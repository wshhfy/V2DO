import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/session.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
        'V2 reply target is shown and submitted unless cancelled: $cancel',
        (tester) async {
      String? posted;
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async {
        if (method == 'POST') {
          posted = body;
          return ForumResponse(302, '', '/t/${uri.pathSegments.last}');
        }
        return const ForumResponse(200,
            '<input name="once" value="123"><textarea name="content"></textarea>');
      });
      final topic = Topic(cancel ? 612 : 611, 'Topic');
      await tester.pumpWidget(MaterialApp(
          home: Composer(forum, topic,
              quote: const Post(901, 7, 'alice', '<p>Original reply</p>'))));
      await tester.pumpAndSettle();
      expect(find.text('正在回复 @alice · #7'), findsOneWidget);
      expect(find.text('Original reply'), findsOneWidget);
      if (cancel) {
        await tester.tap(find.byTooltip('取消回复目标'));
        await tester.pumpAndSettle();
        expect(find.text('正在回复 @alice · #7'), findsNothing);
      }
      await tester.enterText(find.byType(TextField), '@alice Thanks');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      final fields = Uri.splitQueryString(posted!);
      expect(fields['reply_parent_id'], cancel ? isNull : '901');
      expect(fields['content'], '@alice Thanks');
    });
  }
}
