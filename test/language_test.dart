import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/settings.dart';
import 'package:forum_app/ui_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Language selector changes interface text and preserves forum text',
      (tester) async {
    final channel =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    channel.setMockMethodCallHandler(AppPreferences.channel, (_) async => null);
    final prefs = AppPreferences.instance;
    prefs.language = 'zh';
    UiLanguage.current = 'zh';
    await tester.pumpWidget(ListenableBuilder(
        listenable: prefs,
        builder: (_, __) => MaterialApp(
            locale: Locale(prefs.language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const SettingsPage())));
    expect(find.text('应用设置'), findsOneWidget);
    await tester.tap(find.text('语言 / Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('ECH connection'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('应用设置', key: Key('forum-content')))));
    expect(tester.widget<Text>(find.byKey(const Key('forum-content'))).data,
        '应用设置');
    prefs.language = 'zh';
    await prefs.save();
    channel.setMockMethodCallHandler(AppPreferences.channel, null);
  });
}
