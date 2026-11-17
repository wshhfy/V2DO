import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/v2_search.dart';

void main() {
  test('SoV2EX parses topic results and pagination', () {
    final page = Sov2exSearch.parse(
        '{"total":21,"hits":[{"_source":{"id":123,"title":"Flutter","member":"alice","replies":3,"created":"2024-01-01T00:00:00Z"},"highlight":{"content":["hello <em>Flutter</em>"]}}]}');
    expect(page.topics.single.id, 123);
    expect(page.topics.single.activityExcerpt, 'hello Flutter');
    expect(page.topics.single.author, 'alice');
    expect(page.topics.single.createdAt, DateTime.utc(2024));
    expect(page.hasMore, true);
  });
  test('SoV2EX timezone-free dates are UTC', () {
    final page = Sov2exSearch.parse(
        '{"total":1,"hits":[{"_source":{"id":123,"title":"Topic","created":"2024-01-01T00:00:00"}}]}');
    expect(page.topics.single.createdAt, DateTime.utc(2024));
  });
  testWidgets('V2EX searches node suggestions without opening a browser',
      (tester) async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/api/nodes/all.json');
      return const ForumResponse(200,
          '[{"name":"python","title":"Python","topics":42},{"name":"linux","title":"Linux","topics":15}]');
    });
    await tester.pumpWidget(MaterialApp(home: ForumSearchPage(forum)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pyth');
    await tester.pumpAndSettle();
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('Linux'), findsNothing);
    await tester.enterText(find.byType(TextField), '@alice');
    await tester.pumpAndSettle();
    expect(find.text('查看用户资料'), findsOneWidget);
  });
  testWidgets('LINUX DO search renders matching topics', (tester) async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/search.json');
      expect(uri.queryParameters['q'], 'flutter');
      return const ForumResponse(200,
          '{"topics":[{"id":12,"title":"Flutter topic","posts_count":4}],"posts":[{"topic_id":12,"username":"alice","blurb":"test"}],"grouped_search_result":{"more_full_page_results":false}}');
    });
    await tester.pumpWidget(MaterialApp(home: ForumSearchPage(forum)));
    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Flutter topic'), findsOneWidget);
    expect(find.text('alice · test'), findsOneWidget);
  });
}
