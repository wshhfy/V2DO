import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/main.dart';
import 'package:forum_app/session.dart';

void main() {
  testWidgets('LINUX DO search renders matching topics', (tester) async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/search.json');
      expect(uri.queryParameters['q'], 'flutter');
      return const ForumResponse(200, '{"topics":[{"id":12,"title":"Flutter topic","posts_count":4}],"posts":[{"topic_id":12,"username":"alice","blurb":"test"}],"grouped_search_result":{"more_full_page_results":false}}');
    });
    await tester.pumpWidget(MaterialApp(home: ForumSearchPage(forum)));
    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Flutter topic'), findsOneWidget);
    expect(find.text('alice · test'), findsOneWidget);
  });
}
