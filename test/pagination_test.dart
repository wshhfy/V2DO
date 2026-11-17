import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/recent.dart';

void main() {
  testWidgets(
      'Cards follow held drag, show both neighbors and cancel without visiting them',
      (tester) async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            ForumResponse(200,
                '<h1>Card ${uri.path}</h1><div class="topic_content">Preview body</div>'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(MaterialApp(
        home: TopicPage(forum, const Topic(1002, 'Middle'), sequence: const [
      Topic(1001, 'Previous'),
      Topic(1002, 'Middle'),
      Topic(1003, 'Next')
    ])));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(-65, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('previous-topic-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('next-topic-card')), findsOneWidget);
    final card = tester.widget<FractionalTranslation>(
        find.byKey(const ValueKey('current-topic-card')));
    expect(card.translation.dx, lessThan(0));
    final scale = tester.widget<Transform>(find
        .descendant(
            of: find.byKey(const ValueKey('current-topic-card')),
            matching: find.byType(Transform))
        .first);
    expect(scale.transform.storage[0], lessThan(1));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(
        tester
            .widget<FractionalTranslation>(
                find.byKey(const ValueKey('current-topic-card')))
            .translation
            .dx,
        lessThan(card.translation.dx));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Card /t/1002'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-topic-card')), findsNothing);
    expect(
        RecentStore.instance.visits[forum.host]!
            .any((v) => v.topic.id == 1001 || v.topic.id == 1003),
        false);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
  testWidgets('Long press body text can copy selected text', (tester) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(Session.channel, (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = call.arguments['text'] as String;
      if (call.method == 'Clipboard.hasStrings') return {'value': false};
      return null;
    });
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<h1>Topic</h1><div class="topic_content">Selectable forum paragraph</div>'));
    await tester.pumpWidget(MaterialApp(
        home: TopicPage(forum, const Topic(1, 'Topic'),
            sequence: const [Topic(1, 'Topic'), Topic(2, 'Next')])));
    await tester.pumpAndSettle();
    await tester
        .longPress(find.text('Selectable forum paragraph', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    expect(copied, isNotEmpty);
    expect('Selectable forum paragraph'.contains(copied!), true);
    await tester.pumpWidget(const SizedBox());
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(Session.channel, null);
  });
  testWidgets('Detail swipes within source list and returns to top',
      (tester) async {
    final requested = <String>[];
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      requested.add(uri.path);
      return ForumResponse(200,
          '<h1>Title ${uri.path}</h1><div class="topic_content">${List.filled(80, '<p>Long body</p>').join()}</div>');
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    await tester.pumpWidget(MaterialApp(
        home: TopicPage(forum, const Topic(1, 'First'),
            sequence: const [Topic(1, 'First'), Topic(2, 'Second')])));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(find.byTooltip('回到顶部'), findsNothing);
    list.controller!.jumpTo(500);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('回到顶部'));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, 0);
    expect(find.byTooltip('回到顶部'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(-250, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Title /t/1'), findsOneWidget);
    expect(
        tester
            .widgetList<FractionalTranslation>(
                find.byType(FractionalTranslation))
            .any((w) => w.translation.dx < 0),
        true);
    await tester.pumpAndSettle();
    expect(find.text('Title /t/2'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(250, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Title /t/2'), findsOneWidget);
    expect(
        tester
            .widgetList<FractionalTranslation>(
                find.byType(FractionalTranslation))
            .any((w) => w.translation.dx > 0),
        true);
    await tester.pumpAndSettle();
    expect(find.text('Title /t/1'), findsOneWidget);
    final count = requested.length;
    await tester.drag(find.byType(ListView).first, const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(requested.length, count);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
  for (final fails in [false, true]) {
    testWidgets(
        'Detail loads next page on scroll; failure stops retries ($fails)',
        (tester) async {
      var pageTwo = 0;
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async {
        if (uri.queryParameters['p'] == '2') {
          pageTwo++;
          if (fails) throw Exception('offline');
          return const ForumResponse(200,
              '<h1>Topic</h1><div class="cell" id="r_100"><span class="no">100</span><div class="reply_content">Last reply</div></div>');
        }
        return ForumResponse(
            200,
            '<h1>Topic</h1><div class="topic_content">Body</div><a class="page_normal">2</a>'
            '${List.generate(20, (i) => '<div class="cell" id="r_${i + 1}"><span class="no">${i + 1}</span><div class="reply_content">Reply $i</div></div>').join()}');
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Session.channel, (_) async => null);
      await tester.pumpWidget(
          MaterialApp(home: TopicPage(forum, const Topic(1, 'Topic'))));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(pageTwo, 1);
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(pageTwo, 1);
      if (fails)
        expect(find.text('加载失败，点击重试'), findsOneWidget);
      else
        expect(find.text('Last reply', findRichText: true), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Session.channel, null);
    });
  }
}
