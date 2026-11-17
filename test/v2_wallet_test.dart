import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/v2_wallet.dart';

void main() {
  testWidgets('Automatically loads next balance pages and stops on empty',
      (tester) async {
    final calls = <int>[];
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/mission/daily')
        return const ForumResponse(200, '每日登录奖励已领取');
      final p = int.parse(uri.queryParameters['p'] ?? '1');
      calls.add(p);
      final row = p <= 2
          ? '<table><tr><td class="d">交易$p<small>日期</small></td><td class="d">+1</td><td class="d">$p</td><td class="d">说明</td></tr></table>'
          : '';
      return ForumResponse(
          200, '<div class="balance_area">1<img alt="B"></div>$row');
    });
    await tester.pumpWidget(MaterialApp(home: V2WalletPage(forum)));
    await tester.pumpAndSettle();
    expect(calls, [1, 2, 3]);
    expect(find.text('交易1'), findsOneWidget);
    expect(find.text('交易2'), findsOneWidget);
    expect(find.text('已显示全部记录'), findsOneWidget);
  });
  test('Reads coin denominations, records and pagination', () {
    final v = V2Balance.parse(
        '''<div class="balance_area bigger">2 <img alt="G"> 13 <img alt="S"> 45 <img alt="B"></div><table><tr><td class="d">每日登录奖励<small>2026-11-16</small></td><td class="d">+20</td><td class="d">123</td><td class="d">每日奖励</td></tr></table><a href="/balance?p=3">3</a>''');
    expect(v.coins, {'G': 2, 'S': 13, 'B': 45});
    expect(v.records.single.kind, '每日登录奖励');
    expect(v.records.single.amount, '+20');
    expect(v.records.single.time, '2026-11-16');
    expect(v.pages, 3);
  });
  test('Missing balance is an error rather than zero', () {
    expect(
        () => V2Balance.parse('<html>登录</html>'), throwsA(isA<ForumError>()));
  });
}
