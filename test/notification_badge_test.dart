import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/account.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/notifications.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/settings.dart';

void main() {
  testWidgets('V2EX home displays the unread count from the signed-in homepage',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    AppPreferences.instance.autoUpdate = false;
    Accounts.states[0].value = const AccountState(
        account: ForumAccount('fixture', ''), verified: true);
    messenger.setMockMethodCallHandler(Session.channel, (call) async {
      if (call.method != 'request') return null;
      final uri = Uri.parse((call.arguments as Map)['url'] as String);
      if (uri.host == 'linux.do')
        return {
          'status': 200,
          'location': '',
          'body': '{"current_user":null,"topic_list":{"topics":[]},"users":[]}'
        };
      return {
        'status': 200,
        'location': '',
        'body':
            '<html><div id="menu-body"><a href="/member/fixture">fixture</a></div><a href="/notifications" class="fade">3 unread</a></html>'
      };
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('消息 · 3 条未读'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    UnreadMessages.counts[0].value = null;
    Accounts.states[0].value = const AccountState();
    messenger.setMockMethodCallHandler(Session.channel, null);
  });
}
