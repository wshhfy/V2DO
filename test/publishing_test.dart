import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/new_topic.dart';

void main() {
  test('V2 rate limit message is a rejection rather than uncertain success',
      () {
    expect(
        TopicPublisher.publicationProblem(
            '<div class="message"><strong>创建新主题过程中遇到一些问题：</strong><ul><li>距离创建上一个新主题还不到 30 分钟，请稍等 1191 秒之后再试</li></ul></div>'),
        contains('1191 秒'));
    expect(TopicPublisher.publicationProblem('<div>主题已创建</div>'), isNull);
  });
  for (final transportLost in [false, true]) {
    test(
        'Duplicate title then corrected publication verifies new topic (lost=$transportLost)',
        () async {
      var posts = 0;
      var published = false;
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async {
        if (method == 'POST') {
          posts++;
          if (posts == 1)
            return const ForumResponse(200, '<div class="problem">标题重复</div>');
          expect(Uri.splitQueryString(body!)['title'], 'New title');
          published = true;
          if (transportLost) throw Exception('response lost');
          return const ForumResponse(
              200, '<html><body>Submitted</body></html>');
        }
        if (uri.path == '/')
          return const ForumResponse(200,
              '<div class="tools"><a href="/member/tester">tester</a></div>');
        if (uri.path == '/member/tester/topics')
          return ForumResponse(200,
              '<div class="cell"><span class="item_title"><a href="/t/100">Old title</a></span></div>${published ? '<div class="cell"><span class="item_title"><a href="/t/101">New title</a></span></div>' : ''}');
        if (uri.path == '/t/101')
          return const ForumResponse(200,
              '<div class="header"><h1>New title</h1><small><a href="/member/tester">tester</a></small><a href="/go/sandbox">沙盒</a></div><div class="topic_content">body</div>');
        return const ForumResponse(200,
            '<form><input name="title"><input name="once" value="fresh"></form>');
      });
      const section = ForumSection('sandbox', '沙盒', 'node');
      final publisher = TopicPublisher(forum);
      await expectLater(
          publisher.publish('Old title', 'body', section),
          throwsA(
              isA<ForumError>().having((e) => e.message, 'message', '标题重复')));
      expect((await publisher.publish('New title', 'body', section))!.id, 101);
      expect(posts,
          2); // One request per explicit send; never resubmit automatically.
    });
  }
  test('Verification rejects old matches and mismatched author or node',
      () async {
    for (final scenario in ['old', 'author', 'node', 'unavailable']) {
      final forum = Forum('V2EX', 'www.v2ex.com', false,
          transport: (uri, {method = 'GET', headers = const {}, body}) async {
        expect(method, 'GET');
        if (uri.path.contains('/member/'))
          return ForumResponse(200,
              '<div class="cell"><span class="item_title"><a href="/t/${scenario == 'old' ? 100 : 101}">Title</a></span></div>');
        if (scenario == 'unavailable') throw Exception('offline');
        return ForumResponse(200,
            '<div class="header"><h1>Title</h1><small><a href="/member/${scenario == 'author' ? 'other' : 'tester'}">user</a></small><a href="/go/${scenario == 'node' ? 'other' : 'sandbox'}">node</a></div><div class="topic_content">body</div>');
      });
      expect(
          await TopicPublisher(forum).verifyPublication(('tester', {100}),
              'Title', const ForumSection('sandbox', '沙盒', 'node')),
          isNull);
    }
  });
  test('V2 supplements remain ordered and separate from original', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<h1>标题</h1><div class="topic_content">正文</div><div class="subtle"><span class="fade">第 1 条附言 · 昨天</span><div class="topic_content"><p>补充一</p></div></div><div class="subtle"><span class="fade">今天</span><div class="topic_content">补充二</div></div>'));
    final d = await forum.discussion(const Topic(1, '标题'));
    expect(d.body, '正文');
    expect(d.supplements.length, 2);
    expect(d.supplements.first.body, '<p>补充一</p>');
    expect(d.supplements.first.timeLabel, contains('昨天'));
  });
  test('Discourse preserves editing metadata and updated cooked content', () {
    final p = forums[1].discoursePosts([
      {
        'id': 1,
        'post_number': 1,
        'username': 'a',
        'cooked': '<p>最新内容</p>',
        'version': 3,
        'updated_at': '2026-11-11T00:00:00Z',
        'edit_reason': '补充说明'
      }
    ]).single;
    expect(p.version, 3);
    expect(p.editReason, '补充说明');
    expect(p.updatedAt, isNotNull);
    expect(p.html, contains('最新内容'));
  });
  test('V2 create follows form action and retains hidden fields', () async {
    var mutations = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (method == 'GET')
        return const ForumResponse(200,
            '<form action="/new/test"><input name="title"><textarea name="content"></textarea><input type="hidden" name="once" value="fixture"><input type="hidden" name="extra" value="retained"></form>');
      mutations++;
      final fields = Uri.splitQueryString(body!);
      expect(uri.path, '/new/test');
      expect(fields['once'], 'fixture');
      expect(fields['syntax'], '1');
      expect(fields['extra'], 'retained');
      expect(fields['node_name'], 'test');
      return const ForumResponse(302, '', '/t/234#reply0');
    });
    final topic = await TopicPublisher(forum)
        .publish('标题', '正文', const ForumSection('test', '测试', 'node'));
    expect(topic!.id, 234);
    expect(mutations, 1);
  });
  for (final queued in [false, true]) {
    test(
        'Discourse publication handles ${queued ? 'moderation queue' : 'created topic'}',
        () async {
      final forum = Forum('LINUX DO', 'linux.do', true,
          transport: (uri, {method = 'GET', headers = const {}, body}) async {
        if (uri.path == '/session/current.json')
          return const ForumResponse(200, '{"current_user":{"username":"a"}}');
        if (uri.path == '/session/csrf.json')
          return const ForumResponse(200, '{"csrf":"fixture"}');
        expect(method, 'POST');
        expect(headers['X-CSRF-Token'], 'fixture');
        final fields = jsonDecode(body!);
        expect(fields['category'], 4);
        expect(fields['tags'], ['flutter']);
        expect(fields.containsKey('topic_id'), false);
        return ForumResponse(
            200, queued ? '{"action":"enqueued"}' : '{"topic_id":33,"id":44}');
      });
      final topic = await TopicPublisher(forum).publish(
          '标题', '正文', const ForumSection('4', '开发', 'category'),
          tags: ['flutter']);
      expect(topic?.id, queued ? null : 33);
    });
  }
  test('Network uncertainty never retries POST', () async {
    var count = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (method == 'GET')
        return const ForumResponse(200,
            '<form><input name="title"><input name="once" value="fixture"></form>');
      count++;
      throw Exception('timeout');
    });
    await expectLater(
        TopicPublisher(forum)
            .publish('标题', '正文', const ForumSection('test', '测试', 'node')),
        throwsA(isA<ForumError>()
            .having((e) => e.toString(), 'message', contains('未确认'))));
    expect(count, 1);
  });
  test('Only full category permissions allow creating topics', () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '{"categories":[{"id":1,"name":"可发帖","permission":1},{"id":2,"name":"仅回复","permission":2},{"id":3,"name":"只读","permission":3}]}'));
    expect((await TopicPublisher(forum).sections()).map((s) => s.id), ['1']);
  });
}
