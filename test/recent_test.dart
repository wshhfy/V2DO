import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/recent.dart';
import 'package:forum_app/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'History is isolated by forum, capped, reordered and survives serialization',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, (_) async => null);
    final store = RecentStore();
    for (var i = 1; i <= 102; i++) {
      store.visit(forums[0], Topic(i, 'title $i'));
    }
    store.visit(forums[1], const Topic(1, 'Linux topic'));
    store.choose(forums[1], const ForumSection('news', '新闻', 'category'));
    expect(store.sections[forums[1].host], isNull);
    store.visit(forums[0], const Topic(10, 'Updated title'));
    store.choose(forums[0], const ForumSection('tech', '技术', 'tab'));
    store.choose(forums[0], const ForumSection('qna', '问与答', 'node'));
    store.choose(forums[0], const ForumSection('tech', '技术', 'tab'));
    final restored = RecentStore()..restore(store.serialize());
    expect(restored.visits[forums[0].host]!.length, 100);
    expect(restored.visits[forums[0].host]!.first.topic.title, 'Updated title');
    expect(
        restored.sections[forums[0].host]!.map((s) => s.id), ['tech', 'qna']);
    restored.clear(forums[0]);
    expect(restored.visits[forums[0].host], isNull);
    expect(restored.visits[forums[1].host]!.single.topic.title, 'Linux topic');
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Session.channel, null);
  });
}
