import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/v2_thread_settings.dart';

void main() {
  testWidgets('Style choices show six official previews and seven options',
      (tester) async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<form action="/settings" method="post"><input type="radio" name="reply_thread_style" value="d" checked></form>'));
    await tester.pumpWidget(MaterialApp(home: V2ThreadSettingsPage(forum)));
    await tester.pumpAndSettle();
    expect(find.text('经典平铺'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    for (final key in ['a', 'b', 'c', 'd', 'f', 'h']) {
      expect(
          (await rootBundle.load('assets/reply_styles/$key.png')).lengthInBytes,
          greaterThan(0));
    }
    await tester.scrollUntilVisible(find.text('引用楼层'), 300);
    expect(find.text('引用楼层'), findsOneWidget);
  });
  test('Updates website style while preserving every unrelated form field',
      () async {
    var value = 'd';
    var posts = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (method == 'POST') {
        posts++;
        final form = Uri.splitQueryString(body!);
        expect(form['website'], 'https://example.org');
        expect(form['bio'], 'hello\nworld');
        expect(form['member_show_my_nodes'], 'on');
        expect(form['timezone'], 'Asia/Shanghai');
        expect(form['once'], '123');
        value = form['reply_thread_style']!;
        return const ForumResponse(302, '', '/settings');
      }
      return ForumResponse(200,
          '<form action="/settings" method="post"><input name="website" value="https://example.org"><textarea name="bio">hello\nworld</textarea><input type="checkbox" name="member_show_my_nodes" checked><select name="timezone"><option value="UTC">UTC</option><option value="Asia/Shanghai" selected>Shanghai</option></select><input type="hidden" name="once" value="123"><input type="radio" name="reply_thread_style" value="d" ${value == 'd' ? 'checked' : ''}><input type="radio" name="reply_thread_style" value="a" ${value == 'a' ? 'checked' : ''}></form>');
    });
    expect(await V2ThreadSettings(forum).update('a'), 'a');
    expect(posts, 1);
  });
  test('Invalid form never posts', () async {
    var posts = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (method == 'POST') posts++;
      return const ForumResponse(200,
          '<form action="/settings" method="post"><input name="reply_thread_style" value="d" checked></form>');
    });
    await expectLater(
        V2ThreadSettings(forum).update('a'), throwsA(isA<ForumError>()));
    expect(posts, 0);
  });
}
