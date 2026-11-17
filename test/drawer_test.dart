import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/session.dart';

void main() {
  testWidgets('History is a narrow overlay drawer and outside tap dismisses it',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(Session.channel, (call) async {
      if (call.method != 'request') return null;
      final uri = Uri.parse((call.arguments as Map)['url'] as String);
      return {
        'status': 200,
        'location': '',
        'body': uri.host == 'linux.do'
            ? '{"current_user":null,"topic_list":{"topics":[]},"users":[],"notifications":[]}'
            : '<div class="tools"><a href="/signin">登录</a></div><div id="Tabs"><a href="/?tab=all">全部</a></div>每日登录奖励已领取'
      };
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('最近访问'), findsNothing);
    await tester.dragFrom(const Offset(100, 450), const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Drawer)).width, 336);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('V2EX · 最近访问'), findsOneWidget);
    expect(find.text('我的回复'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    await tester.tap(find.text('我的回复'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(Drawer), matching: find.text('登录 / 验证')),
        findsOneWidget);
    await tester.tapAt(const Offset(390, 400));
    await tester.pumpAndSettle();
    expect(find.text('V2EX · 最近访问'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    messenger.setMockMethodCallHandler(Session.channel, null);
  });
}
