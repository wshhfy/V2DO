import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'session.dart';
import 'v2_metrics.dart';

class Topic {
  final int id, replies;
  final String title,
      author,
      category,
      preview,
      avatar,
      activityExcerpt,
      activityTimeLabel;
  final DateTime? createdAt;
  const Topic(this.id, this.title,
      {this.author = '',
      this.category = '',
      this.replies = 0,
      this.preview = '',
      this.activityExcerpt = '',
      this.activityTimeLabel = '',
      this.avatar = '',
      this.createdAt});
}

class Post {
  final DateTime? updatedAt;
  final int version;
  final String editReason;
  final int sourcePage;
  final int threadDepth;
  final int? parentId;
  final int? parentNumber;
  final String threadStyle, parentLabel, parentExcerpt, parentLink, parentHtml;
  final bool liked;
  final int likes;
  final int id, number;
  final String author, html, avatar, timeLabel;
  final DateTime? createdAt;
  const Post(this.id, this.number, this.author, this.html,
      {this.avatar = '',
      this.createdAt,
      this.timeLabel = '',
      this.liked = false,
      this.likes = 0,
      this.sourcePage = 1,
      this.threadDepth = 0,
      this.parentId,
      this.parentNumber,
      this.threadStyle = '',
      this.parentLabel = '',
      this.parentExcerpt = '',
      this.parentLink = '',
      this.parentHtml = '',
      this.updatedAt,
      this.version = 1,
      this.editReason = ''});
}

class Supplement {
  final String body, timeLabel;
  const Supplement(this.body, {this.timeLabel = ''});
}

class Discussion {
  final List<Supplement> supplements;
  final String title, category;
  final Post? original;
  final String body;
  final List<Post> posts;
  final List<int> remaining;
  final int page, pages;
  final bool publicApi;
  const Discussion(this.body, this.posts,
      {this.supplements = const [],
      this.title = '',
      this.category = '',
      this.original,
      this.remaining = const [],
      this.page = 1,
      this.pages = 1,
      this.publicApi = false});
  bool get hasMore => remaining.isNotEmpty || page < pages;
}

class ReplyTicket {
  final String token;
  const ReplyTicket(this.token);
}

class ForumSection {
  final String id, name, kind, slug, parentName;
  final bool restricted;
  final int count;
  const ForumSection(this.id, this.name, this.kind,
      {this.slug = '',
      this.count = 0,
      this.parentName = '',
      this.restricted = false});
}

class Forum {
  static final _categoryNames = <Requester, Map<int, String>>{};
  Future<String> categoryName(dynamic id) async {
    if (id is! int) return '';
    if (!_categoryNames.containsKey(transport)) {
      try {
        await sections('category');
      } catch (_) {
        return '';
      }
    }
    return _categoryNames[transport]?[id] ?? '';
  }

  final String name, host;
  final bool discourse;
  final Requester transport;
  const Forum(this.name, this.host, this.discourse,
      {this.transport = Session.request});
  Uri url(String path) => Uri.https(host, '/').resolve(path);
  Uri topicUrl(int id) => url(discourse ? '/t/topic/$id' : '/t/$id');
  Future<ForumResponse> get(String path) => transport(url(path), headers: {
        'Accept': discourse ? 'application/json' : 'text/html,application/json'
      });

  Future<List<ForumSection>> sections(String kind) async {
    if (!discourse && kind == 'followed') {
      final response = await get('/my/nodes');
      if ([301, 302, 303].contains(response.status) &&
          response.location.contains('/signin')) {
        throw const ForumError('请登录查看关注的节点', needsLogin: true);
      }
      checkResponse(response);
      final doc = html.parse(response.body);
      if (doc.querySelector('input[name="password"]') != null)
        throw const ForumError('请登录查看关注的节点', needsLogin: true);
      return [
        for (final a in doc.querySelectorAll('a.fav-node[href^="/go/"]'))
          ForumSection(url(a.attributes['href']!).pathSegments.last,
              a.text.trim().split('\n').first.trim(), 'node')
      ];
    }
    if (!discourse && kind == 'tab') {
      final response = await get('/');
      checkResponse(response);
      return html
          .parse(response.body)
          .querySelectorAll('#Tabs a[href*="tab="]')
          .map((e) => ForumSection(
              url(e.attributes['href']!).queryParameters['tab']!,
              e.text.trim(),
              'tab'))
          .toList();
    }
    if (!discourse) {
      final rows = decodeResponse(await get('/api/nodes/all.json')) as List;
      return rows
          .map((n) => ForumSection(
              n['name'] as String, n['title'] as String, 'node',
              count: n['topics'] as int? ?? 0))
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));
    }
    if (kind == 'tag') {
      final data = decodeResponse(await get('/tags.json'));
      final rows = [
        ...?data['tags'] as List?,
        for (final group in data['extras']?['categories'] as List? ?? [])
          ...?group['tags'] as List?
      ];
      final unique = <String, ForumSection>{};
      for (final t in rows) {
        final name = t['text']?.toString() ??
            t['name']?.toString() ??
            t['id'].toString();
        unique[name] = ForumSection(t['id']?.toString() ?? name, name, 'tag',
            slug: t['slug']?.toString() ?? '',
            count: t['count'] as int? ?? t['topic_count'] as int? ?? 0);
      }
      return unique.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    }
    final data = decodeResponse(await get('/site.json'));
    // Discourse filters these categories with the current session's Guardian.
    // read_restricted means group-restricted, NOT forbidden to this account.
    final rows = data['categories'] as List? ?? [];
    _categoryNames[transport] = {
      for (final c in rows)
        if (c['id'] is int) c['id'] as int: c['name']?.toString() ?? ''
    };
    final names = {for (final c in rows) c['id']: c['name']};
    return rows
        .map((c) => ForumSection('${c['id']}', '${c['name']}', 'category',
            parentName: names[c['parent_category_id']]?.toString() ?? '',
            restricted: c['read_restricted'] == true,
            slug: c['slug'] as String? ?? '-',
            count: c['topic_count'] as int? ?? 0))
        .toList();
  }

  Future<List<Topic>> latest(
      {int page = 0,
      bool hot = false,
      ForumSection? section,
      String? listType}) async {
    if (!discourse && section == null && !hot)
      section = const ForumSection('recent', '最新', 'recent');
    if (!discourse && section != null) {
      if (section.kind == 'tab' && page > 0) return [];
      final response = await transport(
          url(section.kind == 'recent'
              ? '/recent?p=${page + 1}'
              : section.kind == 'tab'
                  ? '/?tab=${Uri.encodeComponent(section.id)}'
                  : '/go/${Uri.encodeComponent(section.id)}?p=${page + 1}'),
          headers: {
            'Accept': 'text/html',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
          });
      checkResponse(response);
      final doc = html.parse(response.body);
      if (doc.querySelector('.topic-link') == null &&
          doc.querySelector('h1') == null &&
          doc.querySelector('#TopicsNode') == null)
        throw const ForumError('节点需要登录或验证', needsLogin: true);
      final maxPage = doc
          .querySelectorAll('.page_normal, .page_current')
          .map((e) => int.tryParse(e.text.trim()) ?? 1)
          .fold(1, (int a, int b) => a > b ? a : b);
      if (page + 1 > maxPage) return [];
      return doc
          .querySelectorAll('.cell')
          .where((e) => e.querySelector('.topic-link') != null)
          .map((e) {
        final link = e.querySelector('.topic-link')!;
        final id = int.parse(RegExp(r'/t/(\d+)')
            .firstMatch(link.attributes['href']!)!
            .group(1)!);
        return Topic(id, link.text.trim(),
            author: e
                    .querySelector('.topic_info strong a, .small.fade strong')
                    ?.text
                    .trim() ??
                '',
            category: e.querySelector('a.node')?.text.trim() ?? section!.name,
            avatar: avatarUrl(e.querySelector('img.avatar')?.attributes['src']),
            createdAt: parseTime(e
                .querySelector('.topic_info span[title]')
                ?.attributes['title']),
            replies: int.tryParse(
                    e.querySelector('.count_livid')?.text.trim() ?? '') ??
                0);
      }).toList();
    }
    if (!discourse) {
      if (page > 0) return [];
      final data = decodeResponse(await get(
          hot ? '/api/topics/hot.json' : '/api/topics/latest.json')) as List;
      return data
          .map((r) => Topic(r['id'] as int, r['title'] as String,
              author: r['member']['username'] as String? ?? '',
              avatar: avatarUrl(r['member']['avatar_normal']),
              createdAt: parseTime(r['created']),
              category: r['node']?['title'] as String? ?? '',
              replies: r['replies'] as int? ?? 0,
              preview: r['content_rendered'] as String? ?? ''))
          .toList();
    }
    final String path;
    final mode = const {'latest', 'hot', 'top', 'new', 'unread', 'unseen'}
            .contains(listType)
        ? listType!
        : (hot ? 'top' : 'latest');
    final params = 'page=$page${mode == 'top' ? '&period=weekly' : ''}';
    if (section?.kind == 'category') {
      path =
          '/c/${Uri.encodeComponent(section!.slug)}/${section.id}/l/$mode.json?$params';
    } else if (section?.kind == 'tag') {
      path =
          '/tag/${section!.slug.isNotEmpty && int.tryParse(section.id) != null ? '${Uri.encodeComponent(section.slug)}/${section.id}' : Uri.encodeComponent(section.name)}/l/$mode.json?$params';
    } else {
      path = '/$mode.json?$params';
    }
    var response = await get(path);
    // Nested categories and renamed tags redirect to their canonical route.
    for (var i = 0;
        i < 3 && [301, 302, 307, 308].contains(response.status);
        i++) {
      final next = url(response.location);
      if (next.host != host ||
          next.scheme != 'https' ||
          !(next.path.startsWith('/tag/') || next.path.startsWith('/c/')))
        break;
      response = await get(next.toString());
    }
    if (section != null &&
        [403, 404].contains(response.status) &&
        response.body.trimLeft().startsWith('{')) {
      throw const ForumError('该分类或标签不存在，或当前账号没有访问权限。Lv1 / Lv2 等区域以论坛授予的权限为准。');
    }
    final data = decodeResponse(response);
    final users = {for (final u in data['users'] as List? ?? []) u['id']: u};
    final topicRows = data['topic_list']['topics'] as List;
    final firstCategory =
        topicRows.where((t) => t['category_id'] is int).firstOrNull;
    if (firstCategory != null) await categoryName(firstCategory['category_id']);
    return topicRows.map((t) {
      final posters = t['posters'] as List? ?? [];
      return Topic(t['id'] as int, t['title'] as String,
          author: posters.isEmpty
              ? ''
              : users[posters.first['user_id']]?['username'] as String? ?? '',
          avatar: posters.isEmpty
              ? ''
              : avatarUrl(users[posters.first['user_id']]?['avatar_template']),
          createdAt: parseTime(t['created_at']),
          category: _categoryNames[transport]?[t['category_id']] ??
              (t['tags'] as List? ?? [])
                  .take(2)
                  .map((tag) => tag is Map
                      ? tag['name']?.toString() ?? ''
                      : tag.toString())
                  .join(' · '),
          replies: (t['posts_count'] as int? ?? 1) - 1);
    }).toList();
  }

  Future<Discussion> discussion(Topic topic, {Discussion? previous}) async {
    if (discourse) {
      if (previous != null && previous.remaining.isNotEmpty) {
        final ids = previous.remaining.take(20).toList();
        final uri = url('/t/${topic.id}/posts.json').replace(
            queryParameters: {'post_ids[]': ids.map((i) => '$i').toList()});
        final data = decodeResponse(
            await transport(uri, headers: {'Accept': 'application/json'}));
        final newPosts = discoursePosts(data['post_stream']['posts'] as List);
        final existing = previous.posts.map((p) => p.id).toSet();
        return Discussion(
            previous.body,
            [
              ...previous.posts,
              ...newPosts.where((p) => !existing.contains(p.id))
            ]..sort((a, b) => a.number.compareTo(b.number)),
            title: previous.title,
            supplements: previous.supplements,
            category: previous.category,
            original: previous.original,
            remaining: previous.remaining.skip(ids.length).toList());
      }
      final response = await get('/t/${topic.id}.json');
      if (response.status == 404) throw const ForumError('帖子不存在、已删除，或当前账号无权访问');
      final data = decodeResponse(response);
      final posts = discoursePosts(data['post_stream']['posts'] as List);
      final first = posts.where((p) => p.number == 1).firstOrNull;
      if (first == null) throw const ForumError('未取得主题正文，请刷新重试');
      final loaded = posts.map((p) => p.id).toSet();
      final remaining = (data['post_stream']['stream'] as List? ?? [])
          .cast<int>()
          .where((id) => !loaded.contains(id))
          .toList();
      return Discussion(first.html, posts.where((p) => p.number != 1).toList(),
          category: await categoryName(data['category_id']),
          title: data['title'] as String? ?? topic.title,
          original: first,
          remaining: remaining);
    }
    final page = previous == null ? 1 : previous.page + 1;
    final response = await get('/t/${topic.id}?p=$page');
    // Public API is a reading fallback only. It is never used to assume permission to reply.
    if (previous?.publicApi == true ||
        (previous == null && [401, 403].contains(response.status))) {
      final metadata = previous == null
          ? (decodeResponse(await get('/api/topics/show.json?id=${topic.id}'))
                  as List)
              .first as Map
          : const <String, dynamic>{};
      final detail = previous?.body ??
          metadata['content_rendered'] as String? ??
          topic.preview;
      final rows = decodeResponse(await get(
              '/api/replies/show.json?topic_id=${topic.id}&page=$page&page_size=20'))
          as List;
      final posts = rows
          .asMap()
          .entries
          .map((e) => Post(
              e.value['id'] as int,
              (page - 1) * 20 + e.key + 1,
              e.value['member']['username'] as String,
              e.value['content_rendered'] as String? ?? '',
              avatar: avatarUrl(e.value['member']['avatar_normal']),
              createdAt: parseTime(e.value['created'])))
          .toList();
      return Discussion(detail, [...?previous?.posts, ...posts],
          supplements: previous?.supplements ??
              [
                for (final s in metadata['supplements'] as List? ?? [])
                  Supplement(s['content_rendered'] as String? ?? '',
                      timeLabel:
                          parseTime(s['created'])?.toLocal().toString() ?? '')
              ],
          title: metadata['title'] as String? ?? previous?.title ?? topic.title,
          category: metadata['node']?['title'] as String? ??
              previous?.category ??
              topic.category,
          original: previous?.original ??
              Post(
                  topic.id,
                  0,
                  metadata['member']?['username'] as String? ?? topic.author,
                  detail,
                  avatar: metadata['member']?['avatar_normal'] != null
                      ? avatarUrl(metadata['member']['avatar_normal'])
                      : topic.avatar,
                  createdAt: parseTime(metadata['created']) ?? topic.createdAt),
          page: page,
          pages: (topic.replies / 20).ceil().clamp(1, 100000),
          publicApi: true);
    }
    checkResponse(response);
    final doc = html.parse(response.body);
    if (doc.querySelector('h1') == null)
      throw const ForumError('主题需要登录或验证', needsLogin: true);
    final body = doc
        .querySelectorAll('.topic_content')
        .where((e) {
          for (var p = e.parent; p != null; p = p.parent) {
            if (p.classes.contains('subtle')) return false;
          }
          return true;
        })
        .map((e) => e.innerHtml)
        .join('<hr>');
    String? groupParent(dom.Element e) {
      if (!e.classes.contains('reply-group-item')) return null;
      for (var p = e.parent; p != null; p = p.parent) {
        if (p.classes.contains('cell') && p.id.startsWith('r_'))
          return p.id.substring(2);
      }
      return null;
    }

    dom.Element? owned(dom.Element cell, String selector,
        {bool Function(dom.Element)? where}) {
      for (final match in cell.querySelectorAll(selector)) {
        var p = match.parent;
        while (p != null &&
            p != cell &&
            !(p.classes.contains('cell') && p.id.startsWith('r_'))) {
          p = p.parent;
        }
        if (p == cell && (where == null || where(match))) return match;
      }
      return null;
    }

    final style = doc
            .querySelector('.reply-threads')
            ?.className
            .split(' ')
            .firstWhere((c) => c.startsWith('reply-threads-'),
                orElse: () => 'reply-threads-off')
            .replaceFirst('reply-threads-', '') ??
        'off';
    final posts = doc
        .querySelectorAll('.cell[id^="r_"]')
        .map((e) => Post(
            int.tryParse(e.id.replaceFirst('r_', '')) ?? 0,
            int.tryParse(e.querySelector('.no')?.text.trim() ?? '') ?? 0,
            e.querySelector('strong a[href^="/member/"]')?.text.trim() ?? '',
            e.querySelector('.reply_content')?.innerHtml ?? '',
            sourcePage: page,
            threadDepth: int.tryParse(e.attributes['data-depth'] ?? '') ?? 0,
            parentId: int.tryParse(e.attributes['data-parent-id'] ??
                owned(e, '.reply-tree-join')?.attributes['data-for'] ??
                RegExp(r'#r_(\d+)')
                    .firstMatch(
                        (owned(e, '.reply-strip, .reply-quote a[href*="#r_"]') ??
                                    owned(e, '.reply-chip', where: (a) => a.text.trim().startsWith('↩')))
                                ?.attributes['href'] ??
                            '')
                    ?.group(1) ??
                groupParent(e) ??
                ''),
            threadStyle: style,
            parentLink: (owned(e, '.reply-strip, .reply-quote a[href*="#r_"]') ?? owned(e, '.reply-chip', where: (a) => a.text.trim().startsWith('↩')))?.attributes['href'] ?? '',
            parentLabel: (owned(e, '.reply-strip-who, .reply-quote-head') ?? owned(e, '.reply-chip', where: (a) => a.text.trim().startsWith('↩')))?.text.trim() ?? '',
            parentExcerpt: owned(e, '.reply-strip-text, .reply-quote-text, .reply-quote-content, .reply-quote-body')?.text.trim() ?? '',
            parentHtml: owned(e, '.reply-quote-text, .reply-quote-content, .reply-quote-body')?.innerHtml ?? '',
            liked: e.querySelector('.thanked') != null,
            likes: v2Thanks(e),
            avatar: avatarUrl(e.querySelector('img.avatar')?.attributes['src']),
            timeLabel: e.querySelector('.ago')?.text.trim() ?? e.querySelector('span.small.fade')?.text.trim() ?? '',
            createdAt: parseTime(e.querySelector('.ago')?.attributes['title'])))
        .toList();
    final pages = [
      1,
      ...doc
          .querySelectorAll('.page_normal, .page_current')
          .map((e) => int.tryParse(e.text.trim()) ?? 1)
    ]..sort();
    final existing = previous?.posts.map((p) => p.id).toSet() ?? <int>{};
    return Discussion(body.isEmpty ? topic.preview : body,
        [...?previous?.posts, ...posts.where((p) => !existing.contains(p.id))],
        supplements: [
          for (final e in doc.querySelectorAll('.subtle'))
            if (e.querySelector('.topic_content') != null)
              Supplement(e.querySelector('.topic_content')!.innerHtml,
                  timeLabel: e.querySelector('.fade')?.text.trim() ?? '')
        ],
        title: doc.querySelector('h1')?.text.trim() ?? topic.title,
        category: doc.querySelector('.header a[href^="/go/"]')?.text.trim() ??
            previous?.category ??
            topic.category,
        original: Post(
            topic.id,
            0,
            doc
                    .querySelector('.header small a[href^="/member/"]')
                    ?.text
                    .trim() ??
                topic.author,
            body,
            likes: v2Thanks(doc.documentElement!, original: true),
            avatar: avatarUrl(
                doc.querySelector('.header img.avatar')?.attributes['src']),
            createdAt: topic.createdAt,
            timeLabel: (doc.querySelector('.header small')?.text.trim() ?? '')
                .split(' at ')
                .last
                .split(' · ')
                .first),
        page: page,
        pages: pages.last);
  }

  List<Post> discoursePosts(List rows) => rows.map((p) {
        final like = (p['actions_summary'] as List? ?? [])
            .where((a) => a['id'] == 2)
            .firstOrNull;
        return Post(p['id'] as int, p['post_number'] as int,
            p['username'] as String? ?? '', p['cooked'] as String? ?? '',
            parentNumber: p['reply_to_post_number'] as int?,
            liked: like?['acted'] == true,
            updatedAt: parseTime(p['updated_at']),
            version: p['version'] as int? ?? 1,
            editReason: p['edit_reason'] as String? ?? '',
            likes: like?['count'] as int? ?? 0,
            avatar: avatarUrl(p['avatar_template']),
            createdAt: parseTime(p['created_at']));
      }).toList();

  String avatarUrl(dynamic value) {
    if (value is! String || value.isEmpty) return '';
    final uri = url(value.replaceAll('{size}', '96'));
    return uri.replace(scheme: 'https').toString();
  }

  Future<ReplyTicket> prepareReply(int topicId) async {
    if (discourse) {
      final current = await get('/session/current.json');
      if (current.status != 200 ||
          !current.body.contains('current_user') ||
          decodeResponse(current)['current_user'] == null)
        throw const ForumError('请先登录 LINUX DO 后回复', needsLogin: true);
      final csrf =
          decodeResponse(await get('/session/csrf.json'))['csrf'] as String?;
      if (csrf == null || csrf.isEmpty)
        throw const ForumError('无法取得回帖凭据，请重新登录', needsLogin: true);
      return ReplyTicket(csrf);
    }
    final response = await get('/t/$topicId');
    checkResponse(response);
    final doc = html.parse(response.body);
    final once = doc.querySelector('input[name="once"]')?.attributes['value'];
    if (once == null || doc.querySelector('textarea[name="content"]') == null)
      throw const ForumError('请先登录，或该主题暂不允许回复', needsLogin: true);
    return ReplyTicket(once);
  }

  Future<void> submit(int topicId, String content, ReplyTicket ticket,
      {int? replyTo}) async {
    if (content.trim().isEmpty) throw const ForumError('请填写回复内容');
    final fields = discourse
        ? {
            'topic_id': '$topicId',
            'raw': content,
            if (replyTo != null) 'reply_to_post_number': '$replyTo'
          }
        : {
            'once': ticket.token,
            'content': content,
            if (replyTo != null) 'reply_parent_id': '$replyTo'
          };
    final response = await transport(
        url(discourse ? '/posts.json' : '/t/$topicId'),
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Origin': 'https://$host',
          'Referer': topicUrl(topicId).toString(),
          if (discourse) 'X-CSRF-Token': ticket.token,
          if (discourse) 'X-Requested-With': 'XMLHttpRequest'
        },
        body: fields.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'));
    if (discourse) {
      if (response.status >= 200 && response.status < 300) {
        final data = decodeResponse(response);
        if (data['id'] is int && data['topic_id'] == topicId) return;
      }
      try {
        final error = jsonDecode(response.body);
        throw ForumError(
            (error['errors'] as List?)?.join('\n') ?? '回复未确认，请刷新帖子核对后再操作');
      } on FormatException {
        throw const ForumError('回复未确认，请刷新帖子核对后再操作');
      }
    }
    final redirect = url(response.location);
    if ([302, 303].contains(response.status) &&
        redirect.host == host &&
        redirect.path == '/t/$topicId') return;
    final message =
        html.parse(response.body).querySelector('.problem')?.text.trim();
    if (message != null && message.isNotEmpty) throw ForumError(message);
    if ([401, 403].contains(response.status))
      throw const ForumError('登录失效或验证未通过，请重新登录', needsLogin: true);
    throw const ForumError('发送结果未确认，请先刷新帖子核对，避免重复发送');
  }
}

const forums = [
  Forum('V2EX', 'www.v2ex.com', false),
  Forum('LINUX DO', 'linux.do', true)
];

DateTime? parseTime(dynamic value) {
  if (value is num)
    return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(),
        isUtc: true);
  return value is String
      ? DateTime.tryParse(
          value.replaceFirst(RegExp(r' (?=[+-]\d\d:\d\d$)'), ''))
      : null;
}
