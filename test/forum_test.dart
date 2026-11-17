import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/check_in.dart';

void main() {
  test('V2 nested groups and full quotes keep the correct parent', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '''<h1>Topic</h1><div class="reply-threads reply-threads-c"><div class="cell" id="r_11"><span class="no">1</span><strong><a href="/member/root">root</a></strong><div class="reply_content">parent</div><div class="reply-group"><div class="cell reply-group-item" id="r_22"><span class="no">2</span><strong><a href="/member/child">child</a></strong><div class="reply-quote"><div class="reply-quote-head"><a href="/t/123?p=1#r_11">root #1</a></div><div class="reply-quote-text"><b>Full original</b> content</div></div><div class="reply_content">child body</div></div></div></div></div>'''));
    final posts = (await forum.discussion(const Topic(123, 'Topic'))).posts;
    expect(posts.length, 2);
    expect(posts.first.parentId, isNull);
    expect(posts.last.parentId, 11);
    expect(posts.last.parentHtml, '<b>Full original</b> content');
    expect(posts.last.parentLink, '/t/123?p=1#r_11');
  });
  test('V2 quote strip and graph styles parse server parent references',
      () async {
    for (final style in ['a', 'f']) {
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async =>
              ForumResponse(200,
                  '<h1>Topic</h1><div class="reply-threads reply-threads-$style"><div class="cell" id="r_22"><span class="no">2</span><strong><a href="/member/u">u</a></strong><a class="reply-strip" href="#r_11"><span class="reply-strip-who">↩ user #1</span><span class="reply-strip-text">original text</span></a><div class="reply_content">reply</div></div></div>'));
      final post =
          (await forum.discussion(const Topic(123, 'Topic'))).posts.single;
      expect(post.parentId, 11);
      expect(post.threadStyle, style);
      expect(post.parentExcerpt, 'original text');
    }
  });
  test('V2 thread parent uses actual server reply IDs and submits them',
      () async {
    String? sent;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (method == 'POST') {
        sent = body;
        return const ForumResponse(302, '', '/t/123');
      }
      return const ForumResponse(200,
          '<h1>Thread</h1><div class="topic_content">body</div><div class="cell" id="r_99" data-depth="1"><i class="reply-tree-join" data-for="42"></i><span class="no">3</span><strong><a href="/member/a">a</a></strong><div class="reply_content">hello</div></div>');
    });
    final discussion = await forum.discussion(const Topic(123, 'Thread'));
    expect(discussion.posts.single.threadDepth, 1);
    expect(discussion.posts.single.parentId, 42);
    await forum.submit(123, 'hello', const ReplyTicket('123'), replyTo: 99);
    expect(Uri.splitQueryString(sent!)['reply_parent_id'], '99');
  });
  test('English daily mission status is recognized', () {
    expect(DailyCheckIn.claimed('Daily login reward already redeemed'), true);
    expect(DailyCheckIn.claimed('Claim your daily login reward'), false);
  });
  test('Already claimed daily reward never issues redemption', () async {
    final paths = <String>[];
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      paths.add(uri.path);
      return const ForumResponse(200, '每日登录奖励已领取');
    });
    expect(await DailyCheckIn.perform(forum), isNull);
    expect(paths, ['/mission/daily']);
  });
  test('Daily reward redeems once then verifies server state', () async {
    var requests = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      requests++;
      if (requests == 1)
        return const ForumResponse(200,
            '<input onclick="location.href=\'/mission/daily/redeem?once=123\'">');
      if (requests == 2) {
        expect(uri.path, '/mission/daily/redeem');
        expect(uri.queryParameters['once'], '123');
        return const ForumResponse(302, '', '/mission/daily');
      }
      expect(uri.path, '/mission/daily');
      return const ForumResponse(200, '每日登录奖励已领取');
    });
    expect(await DailyCheckIn.perform(forum), 'V2EX 自动签到成功');
    expect(requests, 3);
  });
  test('Discourse section hierarchy and tag route preserve scope on page two',
      () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/site.json')
        return const ForumResponse(200,
            '{"categories":[{"id":1,"name":"Parent","slug":"p"},{"id":2,"name":"Child","slug":"c","parent_category_id":1}]}');
      expect(uri.path, '/tag/flutter/l/latest.json');
      expect(uri.queryParameters['page'], '1');
      return const ForumResponse(
          200, '{"users":[],"topic_list":{"topics":[]}}');
    });
    expect((await forum.sections('category')).last.parentName, 'Parent');
    expect(
        await forum.latest(
            page: 1, section: const ForumSection('flutter', 'flutter', 'tag')),
        isEmpty);
  });
  test('V2EX node page parses forum rows and stops at last page', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/go/python');
      return const ForumResponse(200,
          '<div id="TopicsNode"><div class="cell"><a class="topic-link" href="/t/42#reply2">Python</a><span class="topic_info"><strong><a>a</a></strong><span title="2026-11-10 09:00:00 +08:00">now</span></span><a class="count_livid">2</a></div></div><a class="page_current">1</a>');
    });
    const node = ForumSection('python', 'Python', 'node');
    final rows = await forum.latest(section: node);
    expect(rows.single.id, 42);
    expect(rows.single.createdAt?.toUtc(), DateTime.utc(2026, 11, 10, 1));
    expect(await forum.latest(section: node, page: 1), isEmpty);
  });
  test('Forum avatars normalize relative URLs and timestamps retain UTC', () {
    expect(forums[0].avatarUrl('//cdn.v2ex.com/avatar/a.png'),
        'https://cdn.v2ex.com/avatar/a.png');
    expect(forums[1].avatarUrl('/user_avatar/linux.do/a/{size}/1.png'),
        'https://linux.do/user_avatar/linux.do/a/96/1.png');
    expect(
        parseTime(1700000000)?.toUtc(), DateTime.utc(2023, 11, 14, 22, 13, 20));
    expect(parseTime('2026-11-10T03:20:00Z')?.isUtc, true);
    expect(parseTime(null), null);
  });
  test('V2EX HTML replies include avatar and server time label', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<h1>Topic</h1><div class="cell" id="r_2"><img class="avatar" src="//cdn.v2ex.com/a.png"><strong><a href="/member/a">a</a></strong><span class="ago">2 小时前</span><span class="no">1</span><div class="reply_content">Hello</div></div>'));
    final post = (await forum.discussion(const Topic(1, 'Topic'))).posts.single;
    expect(post.avatar, 'https://cdn.v2ex.com/a.png');
    expect(post.timeLabel, '2 小时前');
  });
  test('V2EX keeps public reply pagination mode after website recovers',
      () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path.startsWith('/t/'))
        return const ForumResponse(200, '<h1>Recovered</h1>');
      expect(uri.path, '/api/replies/show.json');
      expect(uri.queryParameters['page'], '2');
      return const ForumResponse(200,
          '[{"id":21,"member":{"username":"a"},"content_rendered":"next"}]');
    });
    final result = await forum.discussion(
        const Topic(42, 'title', replies: 40, preview: 'body'),
        previous: const Discussion('body', [], pages: 2, publicApi: true));
    expect(result.posts.single.number, 21);
    expect(result.publicApi, true);
  });
  test('Discourse object tags become human readable labels', () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '{"users":[],"topic_list":{"topics":[{"id":1,"title":"Topic","posts_count":2,"tags":[{"id":31,"name":"Announcement"}],"posters":[]}]}}'));
    expect((await forum.latest()).single.category, 'Announcement');
  });
  test('V2EX reply form requires actual editable reply form', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<input name="once" value="123"><textarea name="content"></textarea>'));
    expect((await forum.prepareReply(42)).token, '123');
  });
  test('V2EX login redirect is not a successful submission', () async {
    int posts = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      posts++;
      return const ForumResponse(302, '', '/signin');
    });
    await expectLater(forum.submit(42, 'reply', const ReplyTicket('123')),
        throwsA(isA<ForumError>()));
    expect(posts, 1);
  });
  test('V2EX sends form once and only accepts same topic redirect', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(method, 'POST');
      expect(uri.path, '/t/42');
      final fields = Uri.splitQueryString(body!);
      expect(fields['content'], 'hello & 世界');
      expect(fields['once'], '123');
      return const ForumResponse(302, '', '/t/42?p=2#reply');
    });
    await forum.submit(42, 'hello & 世界', const ReplyTicket('123'));
  });
  test('Discourse JSON errors do not become success', () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(422, '{"errors":["Too short"]}'));
    await expectLater(
        forum.submit(42, 'x', const ReplyTicket('csrf')),
        throwsA(isA<ForumError>()
            .having((e) => e.message, 'message', 'Too short')));
  });
  test('Discourse pagination requests missing IDs and deduplicates', () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.queryParametersAll['post_ids[]'], ['3', '4']);
      return const ForumResponse(200,
          '{"post_stream":{"posts":[{"id":2,"post_number":2,"username":"a","cooked":"old"},{"id":3,"post_number":3,"username":"b","cooked":"new"},{"id":4,"post_number":4,"username":"c","cooked":"last"}]}}');
    });
    final data = await forum.discussion(const Topic(42, 'title'),
        previous: const Discussion('body', [Post(2, 2, 'a', 'old')],
            remaining: [3, 4]));
    expect(data.posts.map((p) => p.id), [2, 3, 4]);
    expect(data.hasMore, false);
  });
  test('verification response raises an actionable auth error', () {
    expect(
        () =>
            decodeResponse(const ForumResponse(403, '<html>challenge</html>')),
        throwsA(
            isA<ForumError>().having((e) => e.needsLogin, 'needsLogin', true)));
  });
}
