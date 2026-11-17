import 'package:html/parser.dart' as html;
import 'forum.dart';
import 'session.dart';
import 'account.dart';

class MemberProfile {
  final String username, name, avatar, bio, website;
  final DateTime? joined;
  final int? level, id;
  const MemberProfile(this.username,
      {this.name = '',
      this.avatar = '',
      this.bio = '',
      this.website = '',
      this.joined,
      this.level,
      this.id});
}

class MemberActivity {
  final List<Topic> topics;
  final bool more;
  const MemberActivity(this.topics, this.more);
}

class ProfileService {
  final Forum forum;
  const ProfileService(this.forum);
  Future<MemberProfile> member(String username) async {
    if (forum.discourse) {
      final r = await forum.get('/u/${Uri.encodeComponent(username)}.json');
      if ([403, 404].contains(r.status))
        throw const ForumError('用户不存在，或资料设置为不可见');
      final u = decodeResponse(r)['user'];
      return MemberProfile(u['username'] as String,
          name: u['name'] as String? ?? '',
          avatar: forum.avatarUrl(u['avatar_template']),
          bio: html.parse(u['bio_cooked'] as String? ?? '').body?.text.trim() ??
              '',
          website: u['website'] as String? ?? '',
          joined: parseTime(u['created_at']),
          level: u['trust_level'] as int?,
          id: u['id'] as int?);
    }
    final d = decodeResponse(await forum.get(
        '/api/members/show.json?username=${Uri.encodeComponent(username)}'));
    if (d['status'] == 'error' || d['username'] == null)
      throw const ForumError('用户不存在或资料不可见');
    return MemberProfile(d['username'] as String,
        name: d['tagline'] as String? ?? '',
        avatar: forum.avatarUrl(d['avatar_large']),
        bio: d['bio'] as String? ?? '',
        website: d['website'] as String? ?? '',
        joined: parseTime(d['created']),
        id: d['id'] as int?);
  }

  Future<MemberActivity> activity(String username, String kind,
      {int page = 0}) async {
    if (kind == 'read') {
      final current = await AccountService(forum).current();
      if (current == null)
        throw const ForumError('请先登录查看网站阅读记录', needsLogin: true);
      if (current.username.toLowerCase() != username.toLowerCase())
        throw const ForumError('账号已切换，请刷新列表');
      if (!forum.discourse) {
        if (page > 0) return const MemberActivity([], false);
        final r = await forum.transport(forum.url('/'), headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36',
          'Accept': 'text/html',
        });
        checkResponse(r);
        return parseV2Read(r.body);
      }
      final d = decodeResponse(await forum.get('/read.json?page=$page'));
      final list = d['topic_list'];
      if (list is! Map || list['topics'] is! List)
        throw const ForumError('网站暂未提供阅读记录，请稍后重试');
      return MemberActivity([
        for (final t in list['topics'] as List)
          if (t['id'] is int && t['title'] is String)
            Topic(t['id'] as int, t['title'] as String,
                replies:
                    ((t['posts_count'] as int? ?? 1) - 1).clamp(0, 1000000))
      ], list['more_topics_url'] != null);
    }
    if (kind == 'bookmarks') {
      final current = await AccountService(forum).current();
      if (current == null) throw const ForumError('请先登录查看收藏', needsLogin: true);
      if (current.username.toLowerCase() != username.toLowerCase())
        throw const ForumError('账号已切换，请从当前账号入口查看收藏');
    }
    if (forum.discourse) {
      if (kind == 'bookmarks') {
        final d = decodeResponse(await forum.get(
            '/u/${Uri.encodeComponent(username)}/bookmarks.json?page=$page'));
        final list = d['user_bookmark_list'] ?? {};
        final rows = (list['bookmarks'] as List? ?? [])
            .where((r) => r['topic_id'] is int)
            .map((r) => Topic(r['topic_id'] as int,
                r['title'] as String? ?? r['name'] as String? ?? '收藏的主题',
                author: r['username'] as String? ?? '',
                createdAt: parseTime(r['created_at'])))
            .toList();
        return MemberActivity(rows, list['more_bookmarks_url'] != null);
      }
      final d = decodeResponse(await forum.get(
          '/user_actions.json?username=${Uri.encodeComponent(username)}&filter=${kind == 'topics' ? 4 : 5}&offset=${page * 30}&limit=30'));
      final rows = d['user_actions'] as List? ?? [];
      final topics = <Topic>[];
      for (final r in rows) {
        if (r['topic_id'] is! int) continue;
        topics.add(Topic(r['topic_id'] as int,
            html.parse(r['title'] as String? ?? '主题').body?.text ?? '主题',
            author: username,
            activityExcerpt: kind == 'replies'
                ? html.parse(r['excerpt'] as String? ?? '').body?.text.trim() ??
                    ''
                : '',
            avatar: forum.avatarUrl(r['avatar_template']),
            createdAt: parseTime(r['created_at'])));
      }
      return MemberActivity(topics, rows.length == 30);
    }
    final path = kind == 'bookmarks'
        ? '/my/topics?p=${page + 1}'
        : '/member/${Uri.encodeComponent(username)}/$kind?p=${page + 1}';
    final r = await forum.transport(forum.url(path), headers: {
      'Accept': 'text/html',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
    });
    if ([301, 302, 303].contains(r.status) && r.location.contains('/signin'))
      throw const ForumError('请先登录查看收藏', needsLogin: true);
    checkResponse(r);
    return parseV2Activity(r.body, page: page, username: username);
  }

  MemberActivity parseV2Read(String body) {
    final doc = html.parse(body);
    final boxes = doc.querySelectorAll('.box');
    final matching = boxes.where((box) => RegExp(
            r'Recent\s+Visited\s+Topics|最近访问的主题|最近浏览的主题',
            caseSensitive: false)
        .hasMatch(box.querySelector('.cell, .header')?.text ?? ''));
    if (matching.isEmpty) {
      throw const ForumError('首页暂未返回 Recent Visited Topics，请确认网站已有访问记录');
    }
    final seen = <int>{};
    final topics = <Topic>[];
    for (final a in matching.first.querySelectorAll('a[href]')) {
      final uri = forum.url(a.attributes['href']!);
      final match = RegExp(r'^/t/(\d+)/?$').firstMatch(uri.path);
      if (uri.host != forum.host || match == null) continue;
      final id = int.parse(match[1]!);
      final title = a.text.trim();
      if (title.isNotEmpty && seen.add(id)) topics.add(Topic(id, title));
    }
    return MemberActivity(topics, false);
  }

  MemberActivity parseV2Activity(String body,
      {int page = 0, String username = ''}) {
    final doc = html.parse(body);
    if (doc.querySelector('input[name="password"]') != null)
      throw const ForumError('请先登录', needsLogin: true);
    final topics = <Topic>[];
    final seen = <int>{};
    for (final cell in doc.querySelectorAll('.cell, .dock_area')) {
      final a = cell.querySelector(
          '.topic-link, .item_title a[href*="/t/"], span.gray a[href*="/t/"], .gray a[href*="/t/"]');
      if (a == null) continue;
      final id = int.tryParse(RegExp(r'/t/(\d+)')
              .firstMatch(a.attributes['href'] ?? '')
              ?.group(1) ??
          '');
      if (id == null) continue;
      if (!cell.classes.contains('dock_area') && !seen.add(id)) continue;
      topics.add(Topic(id, a.text.trim(),
          author: username,
          activityExcerpt: cell.classes.contains('dock_area')
              ? cell.nextElementSibling
                      ?.querySelector('.reply_content')
                      ?.text
                      .trim() ??
                  ''
              : '',
          activityTimeLabel: cell.classes.contains('dock_area')
              ? (cell.querySelector('.fr .fade')?.text.trim() ?? '')
              : '',
          category:
              cell.querySelector('.node, a[href^="/go/"]')?.text.trim() ?? '',
          avatar: forum
              .avatarUrl(cell.querySelector('img.avatar')?.attributes['src']),
          replies: int.tryParse(
                  cell.querySelector('.count_livid')?.text.trim() ?? '') ??
              0,
          createdAt: parseTime(
              cell.querySelector('.fr [title]')?.attributes['title'] ??
                  cell.querySelector('.ago[title]')?.attributes['title'])));
    }
    final last = doc
        .querySelectorAll('.page_normal,.page_current')
        .map((e) => int.tryParse(e.text.trim()) ?? 1)
        .fold(1, (a, b) => a > b ? a : b);
    if (topics.isEmpty &&
        (doc.body?.text.contains('隐私') == true ||
            doc.body?.text.contains('不公开') == true))
      throw const ForumError('该用户未公开此项内容');
    return MemberActivity(topics, page + 1 < last);
  }
}
