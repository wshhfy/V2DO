import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/session.dart';

void main() {
  testWidgets('author filter and reverse order include later V2 pages',
      (tester) async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      final second = uri.queryParameters['p'] == '2';
      return ForumResponse(
          200,
          '<h1>Topic</h1><div class="header"><small><a href="/member/owner">owner</a></small></div><div class="page_normal">2</div>'
          '${second ? '<div class="cell" id="r_33"><span class="no">3</span><strong><a href="/member/owner">owner</a></strong><div class="reply_content">later owner</div></div>' : '<div class="cell" id="r_11"><span class="no">1</span><strong><a href="/member/owner">owner</a></strong><div class="reply_content">first owner</div></div><div class="cell" id="r_22"><span class="no">2</span><strong><a href="/member/other">other</a></strong><div class="reply_content">other reply</div></div>'}');
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(MaterialApp(
        home: TopicPage(forum, const Topic(99, 'Topic', author: 'owner'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看楼主'));
    await tester.pumpAndSettle();
    expect(find.text('other reply', findRichText: true), findsNothing);
    expect(find.text('first owner', findRichText: true), findsOneWidget);
    expect(find.text('later owner', findRichText: true), findsOneWidget);
    await tester.tap(find.text('正序'));
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.text('later owner', findRichText: true)).dy,
        lessThan(tester
            .getTopLeft(find.text('first owner', findRichText: true))
            .dy));
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
  for (final style in ['c', 'a']) {
    testWidgets('V2 $style uses only its intended parent quote display',
        (tester) async {
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async =>
              ForumResponse(200,
                  '<h1>Topic</h1><div class="reply-threads reply-threads-$style"><div class="cell" id="r_11"><span class="no">1</span><strong><a href="/member/root">root</a></strong><div class="reply_content">parent</div><div class="cell reply-group-item" id="r_22"><span class="no">2</span><strong><a href="/member/child">child</a></strong><a class="reply-strip" href="#r_11"><span class="reply-strip-who">引用标记</span></a><div class="reply_content">child body</div></div></div></div>'));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Session.channel, (_) async => null);
      await tester.pumpWidget(
          MaterialApp(home: TopicPage(forum, const Topic(99, 'Topic'))));
      await tester.pumpAndSettle();
      expect(find.text('引用标记'), style == 'c' ? findsNothing : findsOneWidget);
      expect(find.text('child body', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Session.channel, null);
    });
  }
  testWidgets('V2 topic exposes forum reply settings even without replies',
      (tester) async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(
                200, '<h1>Topic</h1><div class="topic_content">body</div>'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(
        MaterialApp(home: TopicPage(forum, const Topic(99, 'Topic'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回复展开选项'));
    await tester.pumpAndSettle();
    expect(find.text('V2EX 回复样式'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
  testWidgets('Missing topic does not falsely prompt login', (tester) async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(404, '{}'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(
        MaterialApp(home: TopicPage(forum, const Topic(99, 'Missing'))));
    await tester.pumpAndSettle();
    expect(find.text('帖子不存在、已删除，或当前账号无权访问'), findsOneWidget);
    expect(find.text('登录 / 验证'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
  testWidgets(
      'Discourse trees follow reply numbers and expand or collapse together',
      (tester) async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/site.json')
        return const ForumResponse(200, '{"categories":[]}');
      return const ForumResponse(200,
          '{"title":"Topic","post_stream":{"stream":[1,2,3],"posts":[{"id":1,"post_number":1,"username":"a","cooked":"body"},{"id":2,"post_number":2,"username":"b","cooked":"root reply"},{"id":3,"post_number":3,"reply_to_post_number":2,"username":"c","cooked":"child reply"}]}}');
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(
        MaterialApp(home: TopicPage(forum, const Topic(99, 'Topic'))));
    await tester.pumpAndSettle();
    expect(find.text('child reply', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('回复展开选项'));
    await tester.pumpAndSettle();
    expect(find.text('V2EX 回复样式'), findsNothing);
    await tester.tap(find.text('全部折叠'));
    await tester.pumpAndSettle();
    expect(find.text('child reply', findRichText: true), findsNothing);
    await tester.tap(find.byTooltip('回复展开选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部展开'));
    await tester.pumpAndSettle();
    expect(find.text('child reply', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
  test('Graph creates an edge for each known parent and preserves root color',
      () {
    const posts = [
      Post(1, 1, 'a', '', threadStyle: 'f'),
      Post(2, 2, 'b', '', threadStyle: 'f', parentId: 1),
      Post(3, 3, 'c', '', threadStyle: 'f', parentId: 2),
    ];
    final lines = threadLines(posts);
    expect(lines.length, 2);
    expect(lines.first.from, 0);
    expect(lines.last.to, 2);
    expect(lines.first.color, lines.last.color);
  });
  testWidgets('Tree folds and unfolds descendants', (tester) async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<h1>Topic</h1><div class="reply-threads reply-threads-d"><div class="cell" id="r_11" data-depth="0"><span class="no">1</span><strong><a href="/member/root">root</a></strong><div class="reply_content">root text</div></div><div class="cell" id="r_22" data-depth="1"><i class="reply-tree-join" data-for="11"></i><span class="no">2</span><strong><a href="/member/child">child</a></strong><div class="reply_content">child text</div></div></div>'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(
        MaterialApp(home: TopicPage(forum, const Topic(99, 'Topic'))));
    await tester.pumpAndSettle();
    expect(find.text('1 条回复'), findsNothing);
    expect(find.text('child text', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('折叠回复'));
    await tester.pumpAndSettle();
    expect(find.text('child text', findRichText: true), findsNothing);
    await tester.tap(find.text('1 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('child text', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
}
