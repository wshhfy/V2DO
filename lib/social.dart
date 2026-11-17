import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'forum.dart';
import 'session.dart';
import 'v2_metrics.dart';

class SocialState {
  final bool liked, bookmarked, canLike;
  final int likes;
  final int votes;
  final int? bookmarkId;
  final String favoritePath, nonce;
  const SocialState(
      {this.liked = false,
      this.bookmarked = false,
      this.canLike = true,
      this.likes = 0,
      this.votes = 0,
      this.bookmarkId,
      this.favoritePath = '',
      this.nonce = ''});
}

class SocialService {
  final Forum forum;
  final int page;
  const SocialService(this.forum, {this.page = 1});
  Future<dynamic> change(String path,
      {String method = 'POST', Map<String, dynamic> values = const {}}) async {
    final token = decodeResponse(await forum.get('/session/csrf.json'))['csrf'];
    if (token is! String || token.isEmpty)
      throw const ForumError('请先登录', needsLogin: true);
    final r = await forum.transport(forum.url(path),
        method: method,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-Token': token,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': forum.url('/').toString()
        },
        body: jsonEncode(values));
    final d = decodeResponse(r);
    if (d is Map && d['errors'] is List && (d['errors'] as List).isNotEmpty)
      throw ForumError((d['errors'] as List).join('；'));
    return d;
  }

  Future<SocialState> state(int topicId, int postId,
      {bool original = false}) async {
    if (forum.discourse) {
      final d = decodeResponse(await forum.get('/posts/$postId.json'));
      final like = (d['actions_summary'] as List? ?? [])
          .where((a) => a['id'] == 2)
          .firstOrNull;
      return SocialState(
          liked: like?['acted'] == true,
          likes: like?['count'] as int? ?? 0,
          canLike: like?['can_act'] == true || like?['can_undo'] == true,
          bookmarked: d['bookmarked'] == true,
          bookmarkId: d['bookmark_id'] as int?);
    }
    final r = await forum.get('/t/$topicId${page > 1 ? '?p=$page' : ''}');
    checkResponse(r);
    return parseV2(r.body, topicId, postId, original: original);
  }

  static SocialState parseV2(String body, int topicId, int postId,
      {bool original = false}) {
    final doc = html.parse(body);
    final favorite = doc.querySelector(
        'a[href^="/favorite/topic/$topicId"],a[href^="/unfavorite/topic/$topicId"]');
    final area =
        doc.querySelector(original ? '#topic_thank' : '#thank_area_$postId');
    final thanked = area?.classes.contains('thanked') == true ||
        area?.querySelector('.topic_thanked') != null ||
        (area?.text.contains('感谢已发送') ?? false);
    final nonce = RegExp(r'''(?:var|let|const)\s+once\s*=\s*["']?(\d+)''')
            .firstMatch(body)
            ?.group(1) ??
        doc.querySelector('input[name="once"]')?.attributes['value'] ??
        '';
    return SocialState(
        liked: thanked,
        likes: original
            ? v2Thanks(doc.documentElement!, original: true)
            : (doc.querySelector('#r_$postId') == null
                ? 0
                : v2Thanks(doc.querySelector('#r_$postId')!)),
        votes: original ? v2Votes(doc.documentElement!, topicId) : 0,
        canLike: !thanked &&
            RegExp('${original ? 'thankTopic' : 'thankReply'}\\(\\s*${original ? topicId : postId}\\s*[,)]')
                .hasMatch(body),
        favoritePath: favorite?.attributes['href'] ?? '',
        bookmarked:
            favorite?.attributes['href']?.startsWith('/unfavorite/') == true,
        nonce: nonce);
  }

  Future<SocialState> toggleBookmark(int topicId, int postId,
      {bool original = true}) async {
    final before = await state(topicId, postId, original: original);
    if (forum.discourse) {
      if (before.bookmarked) {
        if (before.bookmarkId == null)
          throw const ForumError('无法取得收藏标识，请刷新后重试');
        await change('/bookmarks/${before.bookmarkId}.json', method: 'DELETE');
      } else {
        await change('/bookmarks.json',
            values: {'bookmarkable_id': postId, 'bookmarkable_type': 'Post'});
      }
    } else {
      final path = before.favoritePath;
      final uri = forum.url(path);
      if (path.isEmpty ||
          uri.host != forum.host ||
          !RegExp('^/(?:un)?favorite/topic/$topicId\$').hasMatch(uri.path))
        throw const ForumError('当前账号无法收藏，请先登录', needsLogin: true);
      final r = await forum.transport(uri,
          headers: {'Referer': forum.topicUrl(topicId).toString()});
      if (![200, 302, 303].contains(r.status)) checkResponse(r);
    }
    final after = await state(topicId, postId, original: original);
    if (after.bookmarked == before.bookmarked)
      throw const ForumError('收藏状态未确认，请刷新核对，不要连续重复操作');
    return after;
  }

  Future<SocialState> toggleLike(int topicId, int postId,
      {bool original = false}) async {
    final before = await state(topicId, postId, original: original);
    if (!forum.discourse && before.liked) return before;
    if (!before.canLike)
      throw const ForumError('当前账号无法执行此操作，可能是自己的帖子、权限或操作时限限制');
    if (forum.discourse) {
      if (before.liked) {
        await change('/post_actions/$postId.json?post_action_type_id=2',
            method: 'DELETE');
      } else {
        await change('/post_actions.json',
            values: {'id': postId, 'post_action_type_id': 2});
      }
    } else {
      if (before.nonce.isEmpty)
        throw const ForumError('请先登录后感谢', needsLogin: true);
      final r = await forum.transport(
          forum.url(
              '/thank/${original ? 'topic' : 'reply'}/${original ? topicId : postId}?once=${before.nonce}'),
          method: 'POST',
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': forum.topicUrl(topicId).toString()
          });
      final d = decodeResponse(r);
      if (d['success'] != true)
        throw ForumError(d['message']?.toString() ?? '感谢未成功，请刷新核对');
    }
    final after = await state(topicId, postId, original: original);
    if (after.liked == before.liked) throw const ForumError('操作状态未确认，请刷新核对');
    return after;
  }
}
