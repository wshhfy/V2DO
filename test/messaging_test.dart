import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/notifications.dart';
import 'package:forum_app/account.dart';
import 'package:forum_app/uploads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('LINUX DO list types use their own paginated endpoints', () async {
    final paths = <String>[];
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      paths.add(uri.path);
      expect(uri.queryParameters['page'], '2');
      return const ForumResponse(
          200, '{"users":[],"topic_list":{"topics":[]}}');
    });
    for (final mode in ['latest', 'hot', 'new', 'unread', 'unseen', 'top']) {
      await forum.latest(page: 2, listType: mode);
    }
    expect(paths, [
      '/latest.json',
      '/hot.json',
      '/new.json',
      '/unread.json',
      '/unseen.json',
      '/top.json'
    ]);
  });
  test(
      'V2 mobile notification container loads historical messages with zero unread',
      () {
    final page = NoticeService(forums[0]).parseV2(
        '<div class="content"><div id="notifications"><div class="cell" id="n_7"><a href="/member/alice"><img class="avatar" src="/avatar.png"></a><span class="gray"><a href="/member/alice">alice</a> 回复了 <a href="/t/42#reply3">历史主题</a></span><div class="payload">历史回复</div></div></div><a class="page_normal">2</a></div>',
        initialUnread: 0);
    expect(page.items.single.title, '历史主题');
    expect(page.items.single.author, 'alice');
    expect(page.items.single.unread, false);
    expect(page.hasMore, true);
  });
  test('Nested category redirects preserve the authenticated same-site request',
      () async {
    final paths = <String>[];
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      paths.add(uri.path);
      if (paths.length == 1)
        return const ForumResponse(
            301, '', '/c/develop/develop-lv2/31/l/latest.json?page=0');
      return const ForumResponse(
          200, '{"users":[],"topic_list":{"topics":[]}}');
    });
    await forum.latest(
        section: const ForumSection('31', '开发调优, Lv2', 'category',
            slug: 'develop-lv2'));
    expect(paths, [
      '/c/develop-lv2/31/l/latest.json',
      '/c/develop/develop-lv2/31/l/latest.json'
    ]);
  });
  test('Numeric tag IDs use slug/id route, preserving page and sort', () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/tags.json')
        return const ForumResponse(
            200, '{"tags":[{"id":9,"name":"站务","slug":"9-tag","count":51}]}');
      expect(uri.path, '/tag/9-tag/9/l/top.json');
      expect(uri.queryParameters, {'page': '2', 'period': 'weekly'});
      return const ForumResponse(
          200, '{"users":[],"topic_list":{"topics":[]}}');
    });
    final tag = (await forum.sections('tag')).single;
    expect(tag.name, '站务');
    await forum.latest(page: 2, hot: true, section: tag);
  });
  test('Restricted category errors distinguish permissions from CAPTCHA',
      () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(403, '{"errors":["forbidden"]}'));
    await expectLater(
        forum.latest(
            section: const ForumSection('31', '开发调优, Lv2', 'category',
                slug: 'develop-lv2')),
        throwsA(isA<ForumError>()
            .having((e) => e.needsLogin, 'needsLogin', false)));
  });
  test('Notifications paginate, retain unread state, and mark only explicit ID',
      () async {
    final calls = <String>[];
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      calls.add('$method ${uri.path}');
      if (uri.path == '/notifications.json') {
        expect(uri.queryParameters['offset'], '30');
        return const ForumResponse(200,
            '{"notifications":[{"id":8,"topic_id":42,"post_number":7,"read":false,"notification_type":2,"fancy_title":"A &amp; B","data":{"display_username":"bob"}}],"total_rows_notifications":31}');
      }
      if (uri.path == '/session/csrf.json')
        return const ForumResponse(200, '{"csrf":"fixture"}');
      expect(method, 'PUT');
      expect(jsonDecode(body!), {'id': 8});
      return const ForumResponse(200, '{"success":"OK"}');
    });
    final service = NoticeService(forum),
        page = await NoticeService(forum).list(page: 1);
    expect(page.items.single.title, 'A & B');
    expect(page.items.single.topicId, 42);
    expect(page.items.single.postNumber, 7);
    expect(page.hasMore, false);
    expect(calls.length, 1); // Merely listing never marks read.
    await service.markRead(page.items.single);
    expect(calls.last, 'PUT /notifications/mark-read.json');
  });
  test('V2 HTML notifications include payload and topic target', () {
    const source =
        '<div id="Main"><div class="cell" id="n_4"><img class="avatar" src="//cdn.v2ex.com/a.png"><a href="/member/alice">alice</a><a href="/t/42#reply3">标题</a><span class="ago">2 分钟前</span><div class="payload">回复内容</div></div><a class="page_normal">2</a></div>';
    final page = NoticeService(forums[0]).parseV2(source, initialUnread: 1);
    expect(page.items.single.topicId, 42);
    expect(page.items.single.postNumber, 3);
    expect(page.items.single.detail, '回复内容');
    expect(page.items.single.unread, true);
    expect(page.hasMore, true);
    expect(NoticeService.v2Count('<a href="/notifications">12 条未读提醒</a>'), 12);
  });
  test('V2 unread count uses desktop layout when mobile omits the counter',
      () async {
    final calls = <Map<String, String>>[];
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(uri.path, '/'); // Never open the notification page just to count.
      calls.add(headers);
      return ForumResponse(
          200,
          calls.length == 1
              ? '<html><title>V2EX</title><div id="menu-body"></div></html>'
              : '<div id="Rightbar"><a href="/notifications">12 条未读提醒</a></div>');
    });
    expect(await NoticeService(forum).unreadCount(), 12);
    expect(calls.length, 2);
    expect(calls.last['User-Agent'], contains('Linux x86_64'));
    expect(NoticeService.v2CountOrNull('<html></html>'), isNull);
    expect(NoticeService.v2CountOrNull('<title>(7) V2EX</title>'), 7);
  });
  test('A transient unread refresh failure does not erase a known badge',
      () async {
    final old = Accounts.states[0].value;
    Accounts.states[0].value = const AccountState(
        account: ForumAccount('fixture', ''), verified: true);
    UnreadMessages.counts[0].value = 4;
    addTearDown(() {
      Accounts.states[0].value = old;
      UnreadMessages.counts[0].value = null;
    });
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            throw Exception('offline'));
    await UnreadMessages.refresh(forum);
    expect(UnreadMessages.counts[0].value, 4);
  });
  test('V2 notification time supports snow, compact English, and timestamps',
      () {
    final page = NoticeService(forums[0]).parseV2('''<div id="notifications">
      <div class="cell" id="n_1"><a href="/t/1">One</a><span class="snow">2h 52m ago</span></div>
      <div class="cell" id="n_2"><a href="/t/2">Two</a><span class="fade">3 小时前</span></div>
      <div class="cell" id="n_3"><a href="/t/3">Three</a><time datetime="2026-11-18T02:00:00Z">today</time></div>
    </div>''');
    expect(page.items[0].timeLabel, '2h 52m ago');
    expect(page.items[1].timeLabel, '3 小时前');
    expect(page.items[2].createdAt, DateTime.utc(2026, 11, 18, 2));
  });
  test(
      'Upload sends multipart bytes with CSRF and inserts returned short URL only',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(Session.channel, (call) async {
      expect(call.method, 'request');
      final args = call.arguments as Map;
      expect(args['url'], 'https://linux.do/uploads.json');
      expect(args['headers']['X-CSRF-Token'], 'fixture');
      expect(args['headers']['content-type'],
          startsWith('multipart/form-data; boundary='));
      final body = utf8.decode(args['bodyBytes'] as Uint8List);
      expect(body, contains('name="upload_type"'));
      expect(body, contains('composer'));
      expect(body, contains('name="file"; filename="image.png"'));
      expect(body, contains('IMAGE_FIXTURE'));
      return {
        'status': 200,
        'body': '{"id":42,"short_url":"upload://abc.png"}'
      };
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(Session.channel, null));
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200, '{"csrf":"fixture"}'));
    expect(
        await ImageUploads.upload(
            forum,
            SelectedImage(Uint8List.fromList(utf8.encode('IMAGE_FIXTURE')),
                'image.png', 'image/png')),
        '![图片](upload://abc.png)');
    expect(
        () => ImageUploads.discourseMarkup({'id': 42, 'url': 'javascript:bad'}),
        throwsA(isA<ForumError>()));
  });
}
