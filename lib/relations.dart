import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'forum.dart';
import 'session.dart';
import 'profile.dart';

class RelationState {
  final String followPath, blockPath;
  const RelationState({this.followPath = '', this.blockPath = ''});
  bool get following => followPath.startsWith('/unfollow/');
  bool get blocked => blockPath.startsWith('/unblock/');
}

class FollowingPage {
  final List<Topic> topics;
  final List<MemberProfile> members;
  final bool more;
  const FollowingPage(this.topics, this.members, this.more);
}

class Relations {
  static final changes = ValueNotifier<int>(0);
  final Forum forum;
  const Relations(this.forum);
  Future<Document> page(String path) async {
    final r = await forum.transport(forum.url(path), headers: {
      'Accept': 'text/html',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
    });
    if ([301, 302, 303].contains(r.status) && r.location.contains('/signin'))
      throw const ForumError('请先登录 V2EX', needsLogin: true);
    checkResponse(r);
    final doc = html.parse(r.body);
    if (doc.querySelector('input[type="password"]') != null)
      throw const ForumError('请先登录 V2EX', needsLogin: true);
    return doc;
  }

  static RelationState parseState(Document doc) {
    String follow = '', block = '';
    for (final button in doc.querySelectorAll(
        'input[type="button"][onclick], a.button[href], button[onclick]')) {
      final raw =
          button.attributes['onclick'] ?? button.attributes['href'] ?? '';
      final match =
          RegExp(r'''/(unfollow|follow|unblock|block)/\d+\?once=[^'"\s;&]+''')
              .firstMatch(raw);
      if (match == null) continue;
      final path = match.group(0)!;
      if (match.group(1)!.contains('follow')) {
        follow = path;
      } else {
        block = path;
      }
    }
    return RelationState(followPath: follow, blockPath: block);
  }

  Future<RelationState> state(String username) async =>
      parseState(await page('/member/${Uri.encodeComponent(username)}'));

  Future<RelationState> set(String username,
      {bool? following, bool? blocked}) async {
    final before = await state(username);
    final want = following ?? blocked!;
    final current = following != null ? before.following : before.blocked;
    final path = following != null ? before.followPath : before.blockPath;
    if (path.isEmpty)
      throw const ForumError('当前无法管理此用户，请确认已登录且不是自己的账号', needsLogin: true);
    if (want == current) return before;
    final uri = forum.url(path);
    if (uri.host != forum.host ||
        !RegExp(r'^/(unfollow|follow|unblock|block)/\d+$').hasMatch(uri.path) ||
        (uri.queryParameters['once'] ?? '').isEmpty)
      throw const ForumError('无法确认操作地址');
    try {
      final response = await forum.transport(uri, headers: {
        'Referer':
            forum.url('/member/${Uri.encodeComponent(username)}').toString()
      });
      if (![200, 302, 303].contains(response.status)) checkResponse(response);
      final after = await state(username);
      final verifiedPath =
          following != null ? after.followPath : after.blockPath;
      if (verifiedPath.isEmpty ||
          (following != null ? after.following : after.blocked) != want)
        throw const ForumError('操作结果未确认，请刷新核对，不要连续重复操作');
      changes.value++;
      return after;
    } catch (e) {
      throw ForumError('操作结果未确认，请刷新核对：$e');
    }
  }

  Future<FollowingPage> following({int pageNumber = 1}) async =>
      parseFollowing(await page('/my/following?p=$pageNumber'),
          pageNumber: pageNumber);
  FollowingPage parseFollowing(Document doc, {int pageNumber = 1}) {
    final topics = <Topic>[];
    final root = doc.querySelector('#Main') ?? doc.body!;
    for (final cell in root.querySelectorAll('.cell')) {
      final a = cell.querySelector('.topic-link, .item_title a[href^="/t/"]');
      if (a == null) continue;
      final id = int.tryParse(RegExp(r'/t/(\d+)')
              .firstMatch(a.attributes['href'] ?? '')
              ?.group(1) ??
          '');
      if (id == null) continue;
      topics.add(Topic(id, a.text.trim(),
          author: cell
                  .querySelector('.topic_info strong a, .small.fade strong a')
                  ?.text
                  .trim() ??
              '',
          avatar: forum
              .avatarUrl(cell.querySelector('img.avatar')?.attributes['src']),
          category: cell.querySelector('a.node')?.text.trim() ?? '',
          createdAt:
              parseTime(cell.querySelector('span[title]')?.attributes['title']),
          replies: int.tryParse(
                  cell.querySelector('.count_livid')?.text.trim() ?? '') ??
              0));
    }
    final members = <String, MemberProfile>{};
    // The sidebar lists each followed user as direct cell/inner links.
    // Account links are nested in a table/span; topic authors live in #Main.
    for (final a in doc.querySelectorAll(
        '#Rightbar .box > .cell > a[href^="/member/"], #Rightbar .box > .inner > a[href^="/member/"]')) {
      final name = forum.url(a.attributes['href']!).pathSegments.last;
      final avatar = forum.avatarUrl(a.querySelector('img')?.attributes['src']);
      members[name] = MemberProfile(name,
          avatar: avatar.isNotEmpty ? avatar : members[name]?.avatar ?? '');
    }
    final last = doc
        .querySelectorAll('.page_normal,.page_current')
        .map((e) => int.tryParse(e.text.trim()) ?? 1)
        .fold(1, (a, b) => a > b ? a : b);
    return FollowingPage(topics, members.values.toList(), pageNumber < last);
  }

  Future<int?> blockedCount() async {
    final d = await page('/settings/block');
    final text = (d.querySelector('#Main') ?? d.body!)
        .text
        .replaceAll(RegExp(r'\s+'), ' ');
    return int.tryParse(
        RegExp(r'(?:Blocked members|屏蔽的用户|已屏蔽用户)\s*(\d+)', caseSensitive: false)
                .firstMatch(text)
                ?.group(1) ??
            '');
  }
}

// Only names discovered/managed in this app. This is not the complete server list.
class KnownBlocks {
  static Future<Map<String, dynamic>> _read() async {
    final prefs = await Session.channel
            .invokeMapMethod<String, dynamic>('getPreferences') ??
        {};
    try {
      return Map<String, dynamic>.from(
          jsonDecode(prefs['v2exKnownBlocks'] as String? ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  static Future<List<String>> names(String account) async =>
      List<String>.from((await _read())[account] ?? []);
  static Future<void> remember(
      String account, String username, bool blocked) async {
    final all = await _read();
    final names = List<String>.from(all[account] ?? []);
    names.removeWhere((n) => n.toLowerCase() == username.toLowerCase());
    if (blocked) names.add(username);
    all[account] = names;
    await Session.channel
        .invokeMethod('setPreferences', {'v2exKnownBlocks': jsonEncode(all)});
  }
}
