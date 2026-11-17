import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/imgur_session.dart';

void main() {
  testWidgets('Imgur account check shows progress until complete',
      (tester) async {
    final result = Completer<ImgurAccount?>();
    await tester.pumpWidget(
        MaterialApp(home: ImgurAccountPage(checkAccount: () => result.future)));
    expect(find.text('正在检查 Imgur 登录状态…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    result.complete(const ImgurAccount(1, 'tester'));
    await tester.pumpAndSettle();
    expect(find.text('已登录：tester'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('登录 / 验证'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('logging out updates the account action', (tester) async {
    var loggedIn = true;
    await tester.pumpWidget(MaterialApp(
        home: ImgurAccountPage(
      checkAccount: () async =>
          loggedIn ? const ImgurAccount(1, 'tester') : null,
      logout: () async {
        loggedIn = false;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('网页登录上传'), findsOneWidget);
    expect(find.textContaining('无需填写'), findsNothing);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('尚未连接 Imgur 账号'), findsOneWidget);
    expect(find.text('登录 / 验证'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
  });
}
