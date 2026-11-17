import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Reset only invokes native clear after explicit confirmation',
      (tester) async {
    var resets = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPreferences.channel, (call) async {
      if (call.method == 'resetApplication') resets++;
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.scrollUntilVisible(find.text('重置应用'), 400);
    await tester.tap(find.text('重置应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(resets, 0);
    await tester.tap(find.text('重置应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置并退出'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppPreferences.channel, null);
  });
  test('Startup forum defaults to V2EX and persists LINUX DO choice', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<dynamic, dynamic> stored = {};
    messenger.setMockMethodCallHandler(AppPreferences.channel, (call) async {
      if (call.method == 'getPreferences') return stored;
      if (call.method == 'setPreferences')
        stored = Map.of(call.arguments as Map);
      return null;
    });
    final prefs = AppPreferences();
    await prefs.load();
    expect(prefs.startForum, 0);
    prefs.startForum = 1;
    await prefs.save();
    final restored = AppPreferences();
    await restored.load();
    expect(restored.startForum, 1);
    stored['startForum'] = 9;
    await restored.load();
    expect(restored.startForum, 0);
    messenger.setMockMethodCallHandler(AppPreferences.channel, null);
  });
  test(
      'GitHub release comparison handles numeric segments and rejects prereleases',
      () {
    expect(AppUpdates.newer('v0.10.0', '0.9.9'), true);
    expect(AppUpdates.newer('v0.6.0', '0.6.0'), false);
    expect(AppUpdates.newer('v0.5.9', '0.6.0'), false);
    expect(AppUpdates.newer('v1.0.0-rc.1', '0.6.0'), false);
    expect(AppUpdates.newer('unexpected', '0.6.0'), false);
  });
  test('Appearance preferences restore Android signed ARGB and theme mode',
      () async {
    const channel = MethodChannel('dualforum/session');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getPreferences')
        return {'theme': 'dark', 'accent': -14194851, 'autoUpdate': false};
      return null;
    });
    final preferences = AppPreferences();
    await preferences.load();
    expect(preferences.mode, ThemeMode.dark);
    expect(preferences.accent, 0xff27675d);
    expect(preferences.autoUpdate, false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
