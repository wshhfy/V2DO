import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/account.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Malformed session payload is not proof of logout', () async {
    for (final bodyText in ['{}', '<html>Temporary error</html>']) {
      final forum = Forum('LINUX DO', 'linux.do', true,
          transport: (uri, {method = 'GET', headers = const {}, body}) async =>
              ForumResponse(200, bodyText));
      await expectLater(
          AccountService(forum).current(),
          throwsA(isA<ForumError>()
              .having((e) => e.needsLogin, 'needsLogin', false)));
    }
  });
  test('Background account checks keep identity stable and coalesce requests',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(Session.channel, (_) async => null);
    addTearDown(
        () => messenger.setMockMethodCallHandler(Session.channel, null));
    Accounts.states[1].value =
        const AccountState(account: ForumAccount('owner', ''), verified: true);
    var calls = 0;
    final response = Completer<ForumResponse>();
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      calls++;
      return response.future;
    });
    final first = Accounts.refresh(forum);
    final second = Accounts.refresh(forum);
    expect(Accounts.states[1].value.label, 'owner');
    response.completeError(const ForumError('网络请求失败'));
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(Accounts.states[1].value.label, 'owner');
    expect(Accounts.states[1].value.needsLogin, false);
    final guest = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(401, '{}'));
    await Accounts.refresh(guest);
    expect(Accounts.states[1].value.label, '登录 / 验证');
    expect(Accounts.states[1].value.account, isNull);
  });
  test('Cached identity is display only and omits session secrets', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map? saved;
    messenger.setMockMethodCallHandler(Session.channel, (call) async {
      if (call.method == 'getPreferences')
        return {
          'knownAccounts': jsonEncode({
            'linux.do': {'username': 'owner', 'avatar': ''}
          })
        };
      if (call.method == 'setPreferences') saved = call.arguments as Map;
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(Session.channel, null));
    await Accounts.load();
    expect(Accounts.states[1].value.label, 'owner');
    expect(Accounts.states[1].value.verified, false);
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '{"current_user":{"username":"owner","avatar_template":""}}'));
    await Accounts.refresh(forum);
    expect(Accounts.states[1].value.verified, true);
    final cached =
        jsonDecode(saved!['knownAccounts'] as String)['linux.do'] as Map;
    expect(cached.keys.toSet(), {'username', 'avatar'});
  });
  test('V2EX identity comes from session navigation, not a topic author', () {
    final service = AccountService(forums.first);
    final account = service.parseV2(
        '<div id="menu-body"><a href="/member/owner">owner</a></div><button id="menu-entry"><img class="avatar" src="//cdn.v2ex.com/me.png"></button><a href="/member/other">other</a><button onclick="location.href=\'/signout?once=123\'">Sign Out</button>');
    expect(account?.username, 'owner');
    expect(account?.avatar, 'https://cdn.v2ex.com/me.png');
    expect(account?.logoutPath, '/signout?once=123');
    expect(
        service.parseV2(
            '<div id="menu-body"><a href="/signin">登录</a></div><a href="/member/other">other</a>'),
        null);
    expect(() => service.parseV2('<h1>Challenge</h1>'),
        throwsA(isA<ForumError>()));
  });
  test('Discourse logout uses current username and CSRF then verifies guest',
      () async {
    var loggedIn = true;
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/session/current.json')
        return ForumResponse(
            200,
            loggedIn
                ? '{"current_user":{"username":"owner","avatar_template":"/avatar/{size}.png"}}'
                : '{"current_user":null}');
      if (uri.path == '/session/csrf.json')
        return const ForumResponse(200, '{"csrf":"fresh"}');
      expect(uri.path, '/session/owner');
      expect(method, 'DELETE');
      expect(headers['X-CSRF-Token'], 'fresh');
      loggedIn = false;
      return const ForumResponse(200, '{}');
    });
    await AccountService(forum).logout();
    expect(loggedIn, false);
  });
  test('V2EX missing logout nonce cannot guess a logout request', () async {
    var calls = 0;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      calls++;
      return const ForumResponse(
          200, '<div id="menu-body"><a href="/member/me">me</a></div>');
    });
    await expectLater(
        AccountService(forum).logout(), throwsA(isA<ForumError>()));
    expect(calls, 1);
  });
  test('V2EX logout must verify session really ended', () async {
    var loggedIn = true;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/signout') {
        expect(uri.queryParameters['once'], '123');
        loggedIn = false;
        return const ForumResponse(302, '', '/');
      }
      return ForumResponse(
          200,
          loggedIn
              ? '<div id="menu-body"><a href="/member/me">me</a><a href="/signout?once=123">退出</a></div>'
              : '<div id="menu-body"><a href="/signin">登录</a></div>');
    });
    await AccountService(forum).logout();
    expect(loggedIn, false);
  });
}
