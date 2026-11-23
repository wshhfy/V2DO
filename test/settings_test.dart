import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Settings keep startup in general and fit large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: const SettingsPage(),
    ));
    expect(tester.getTopLeft(find.text('启动时打开')).dy,
        lessThan(tester.getTopLeft(find.text('网络连接')).dy));
    await tester.scrollUntilVisible(find.text('重置应用'), 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
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
  test('Font size persists and invalid values restore the default', () async {
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
    expect(prefs.fontScale, 1);
    prefs.fontSize = 2;
    await prefs.save();
    final restored = AppPreferences();
    await restored.load();
    expect(restored.fontScale, 1.15);
    stored['fontSize'] = 99;
    await restored.load();
    expect(restored.fontScale, 1);
    messenger.setMockMethodCallHandler(AppPreferences.channel, null);
  });
  test('ECH is disabled by default and the choice persists', () async {
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
    expect(prefs.echEnabled, false);
    prefs.echEnabled = true;
    await prefs.save();
    final restored = AppPreferences();
    await restored.load();
    expect(restored.echEnabled, true);
    messenger.setMockMethodCallHandler(AppPreferences.channel, null);
  });
  test('Language defaults to Chinese and persists English', () async {
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
    expect(prefs.language, 'zh');
    prefs.language = 'en';
    await prefs.save();
    final restored = AppPreferences();
    await restored.load();
    expect(restored.language, 'en');
    prefs.language = 'zh';
    await prefs.save();
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
  test('Selects a matching APK and rejects an untrusted download URL', () {
    final base =
        'https://github.com/$githubRepository/releases/download/v1.2.3';
    final digest = 'sha256:${'a' * 64}';
    final assets = [
      {
        'name': 'V2DO-1.2.3-universal.apk',
        'browser_download_url': '$base/V2DO-1.2.3-universal.apk',
        'digest': digest,
        'size': 100
      },
      {
        'name': 'V2DO-1.2.3-arm64-v8a.apk',
        'browser_download_url': '$base/V2DO-1.2.3-arm64-v8a.apk',
        'digest': digest,
        'size': 50
      },
    ];
    final release = ReleaseInfo('v1.2.3', '', Uri.parse(base), assets);
    expect(AppUpdates.selectAsset(release, ['arm64-v8a'])['size'], 50);
    expect(AppUpdates.selectAsset(release, ['unknown'])['size'], 100);
    final invalid = ReleaseInfo('v1.2.3', '', Uri.parse(base), [
      {...assets.first, 'browser_download_url': 'https://evil.example/file.apk'}
    ]);
    expect(() => AppUpdates.selectAsset(invalid, ['unknown']), throwsException);
  });
  for (final automatic in [false, true]) {
    testWidgets('Update download requires confirmation (automatic: $automatic)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final prefs = AppPreferences.instance;
      prefs.autoUpdate = true;
      prefs.lastUpdateCheck = 0;
      var downloads = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AppPreferences.channel, (call) async {
        if (call.method == 'updateDevice')
          return {
            'supported': true,
            'abis': ['arm64-v8a']
          };
        if (call.method == 'installUpdate') {
          downloads++;
          return 'started';
        }
        return null;
      });
      final release = ReleaseInfo(
          'v1.2.3',
          '更新内容',
          Uri.parse('https://github.com/$githubRepository/releases/tag/v1.2.3'),
          [
            {
              'name': 'V2DO-1.2.3-arm64-v8a.apk',
              'browser_download_url':
                  'https://github.com/$githubRepository/releases/download/v1.2.3/V2DO-1.2.3-arm64-v8a.apk',
              'digest': 'sha256:${'a' * 64}',
              'size': 100
            }
          ]);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => AppUpdates.check(context,
                          automatic: automatic,
                          fetchRelease: () async => release),
                      child: const Text('检查'))))));
      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.2.3'), findsOneWidget);
      expect(downloads, 0);
      await tester.tap(find.text('暂不更新'));
      await tester.pumpAndSettle();
      expect(downloads, 0);
      prefs.lastUpdateCheck = 0;
      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(downloads, 1);
      messenger.setMockMethodCallHandler(AppPreferences.channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
  }
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
