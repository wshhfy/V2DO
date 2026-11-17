import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:forum_app/forum.dart';
import 'package:forum_app/relations.dart';
import 'package:forum_app/session.dart';

void main() {
  test('Followed nodes exclude navigation and return real node routes',
      () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/my/nodes');
      return const ForumResponse(200,
          '<a href="/go/random">推荐</a><a class="fav-node" href="/go/flutter">Flutter\n42</a>');
    });
    final nodes = await forum.sections('followed');
    expect(nodes.single.name, 'Flutter');
    expect(nodes.single.kind, 'node');
    expect(nodes.single.id, 'flutter');
  });
  test('Followed nodes require login instead of showing an empty list',
      () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(302, '', '/signin?next=/my/nodes'));
    await expectLater(forum.sections('followed'),
        throwsA(isA<ForumError>().having((e) => e.needsLogin, 'login', true)));
  });
  test(
      'Following separates real followed people from authors and last repliers',
      () {
    final result = Relations(forums[0]).parseFollowing(html.parse('''
      <div id="Rightbar"><div class="box"><div class="cell">Account</div><a href="/member/self">self</a></div>
      <div class="box"><div class="cell">Following</div><div class="cell"><a href="/member/alice"><img src="/alice.png"></a><a href="/member/alice">alice</a></div></div></div>
      <div id="Main"><div class="cell"><img class="avatar" src="/alice.png"><span class="item_title"><a class="topic-link" href="/t/23#reply3">文章</a></span><span class="topic_info"><strong><a href="/member/alice">alice</a></strong><a class="node">分享</a><strong><a href="/member/bob">bob</a></strong></span></div><a class="page_normal">2</a></div>'''));
    expect(result.members.map((p) => p.username), ['alice']);
    expect(result.members.single.avatar, 'https://www.v2ex.com/alice.png');
    expect(result.topics.single.author, 'alice');
    expect(result.topics.single.id, 23);
    expect(result.more, true);
  });
  test('Relationship reads server action URLs and current state', () {
    final state = Relations.parseState(html.parse(
        '''<input type="button" onclick="location.href='/unfollow/42?once=token'"/><input type="button" onclick="location.href='/unblock/42?once=token'"/>'''));
    expect(state.following, true);
    expect(state.blocked, true);
  });
  for (final follow in [true, false]) {
    test(
        '${follow ? 'Follow' : 'Block'} verifies server state and is idempotent',
        () async {
      var active = false;
      var count = 0;
      final action = follow ? 'follow' : 'block';
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async {
        if (uri.path.startsWith('/member/'))
          return ForumResponse(200,
              '<input type="button" onclick="location.href=\'/${active ? 'un' : ''}$action/42?once=fresh\'">');
        count++;
        expect(method, 'GET');
        expect(uri.path, '/$action/42');
        expect(uri.queryParameters['once'], 'fresh');
        active = true;
        return const ForumResponse(302, '', '/member/alice');
      });
      final r = Relations(forum);
      await r.set('alice',
          following: follow ? true : null, blocked: follow ? null : true);
      await r.set('alice',
          following: follow ? true : null, blocked: follow ? null : true);
      expect(count, 1);
    });
  }
  test('Missing action never sends a relationship change', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/member/alice');
      return const ForumResponse(200, '<h1>alice</h1>');
    });
    await expectLater(Relations(forum).set('alice', blocked: true),
        throwsA(isA<ForumError>()));
  });
  test('Failed verification reports uncertainty and never repeats mutation',
      () async {
    var count = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path.startsWith('/member/'))
        return const ForumResponse(200,
            '<input type="button" onclick="location.href=\'/block/42?once=fresh\'">');
      count++;
      return const ForumResponse(200, 'blocked?');
    });
    await expectLater(
        Relations(forum).set('alice', blocked: true),
        throwsA(isA<ForumError>()
            .having((e) => e.toString(), 'message', contains('未确认'))));
    expect(count, 1);
  });
  test('Block count is separate from node and topic counts', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<div id="Main">Blocked members 5 Ignored nodes 1 Ignored topics 0</div>'));
    expect(await Relations(forum).blockedCount(), 5);
  });
}
