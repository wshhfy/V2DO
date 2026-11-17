import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Only explicit anonymous Linux session triggers quiet recovery', () {
    final uri = Uri.https('linux.do', '/session/current.json');
    expect(
        Session.linuxGuest(
            uri, 'GET', const ForumResponse(200, '{"current_user":null}')),
        true);
    expect(
        Session.linuxGuest(uri, 'GET',
            const ForumResponse(200, '{"current_user":{"username":"a"}}')),
        false);
    expect(Session.linuxGuest(uri, 'GET', const ForumResponse(200, 'not json')),
        false);
    expect(
        Session.linuxGuest(
            uri, 'POST', const ForumResponse(200, '{"current_user":null}')),
        false);
  });
  test('Only Linux read challenges and current-session expiry request recovery',
      () {
    const challenge = ForumResponse(403, '<html>Just a moment</html>');
    expect(
        Session.needsRecovery(
            Uri.https('linux.do', '/latest.json'), 'GET', challenge),
        true);
    expect(
        Session.needsRecovery(
            Uri.https('linux.do', '/posts.json'), 'POST', challenge),
        false);
    expect(
        Session.needsRecovery(Uri.https('www.v2ex.com', '/'), 'GET', challenge),
        false);
    expect(
        Session.needsRecovery(Uri.https('linux.do', '/t/1.json'), 'GET',
            const ForumResponse(403, '{"error":"forbidden"}')),
        false);
    expect(
        Session.needsRecovery(Uri.https('linux.do', '/session/current.json'),
            'GET', const ForumResponse(404, '{}')),
        true);
  });
  test(
      'Concurrent reads share one recovery and retry once; cooldown prevents loops',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final gate = Completer<bool>();
    var recoveries = 0;
    var ready = false;
    var calls = 0;
    messenger.setMockMethodCallHandler(Session.channel, (call) async {
      if (call.method == 'refreshLinuxSession') {
        recoveries++;
        return gate.future;
      }
      calls++;
      return {
        'status': ready ? 200 : 403,
        'body': ready ? '{}' : '<html>Just a moment</html>',
        'location': ''
      };
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(Session.channel, null));
    final a = Session.request(Uri.https('linux.do', '/latest.json'));
    final b = Session.request(Uri.https('linux.do', '/session/current.json'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(recoveries, 1);
    ready = true;
    gate.complete(true);
    expect((await a).status, 200);
    expect((await b).status, 200);
    expect(calls, 4);
    ready = false;
    expect(
        (await Session.request(Uri.https('linux.do', '/latest.json'))).status,
        403);
    expect(recoveries, 1);
    expect(calls, 5);
  });
}
