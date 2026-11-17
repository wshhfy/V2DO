import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/image_preview.dart';
import 'package:forum_app/session.dart';

void main() {
  test('Gallery filters emoji and icons but retains normal photographs', () {
    final images = imageTargets('''<img class="emoji-custom" src="/a.png">
      <img src="/images/emoji/twitter/smile.png"><img alt=":smile:" src="/b.png">
      <img width="20" height="20" src="/icon.png"><img src="/photo.jpg">
      <a class="lightbox" href="/full.jpg"><img src="/thumb.jpg"></a>''',
        Uri.parse('https://linux.do/'));
    expect(images.values.toList(),
        ['https://linux.do/photo.jpg', 'https://linux.do/full.jpg']);
  });
  test('Gallery cache bounds bytes and allows failed requests to retry',
      () async {
    var calls = 0;
    final cache = GalleryImageCache(
        maxBytes: 4,
        fetch: (url) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return Uint8List(3);
        });
    await expectLater(cache.load('a'), throwsException);
    await cache.load('a');
    await cache.load('a');
    expect(calls, 2);
    await cache.load('b');
    expect(cache.peek('a'), isNull);
    expect(cache.size, 3);
  });
  testWidgets('Gallery opens tapped image, swipes between images and closes',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String, int>{};
    var saves = 0;
    messenger.setMockMethodCallHandler(Session.channel, (call) async {
      if (call.method == 'saveImage') {
        saves++;
        expect((call.arguments as Map)['bytes'], isA<Uint8List>());
        return '相册 V2DO';
      }
      final url = (call.arguments as Map)['url'] as String;
      calls[url] = (calls[url] ?? 0) + 1;
      return {
        'status': 200,
        'bytes': base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='),
        'location': ''
      };
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(Session.channel, null));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => Scaffold(
                body: TextButton(
                    onPressed: () => previewImage(c, 'https://linux.do/a.png',
                            images: [
                              'https://linux.do/a.png',
                              'https://linux.do/b.png',
                              'https://linux.do/c.png'
                            ]),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一张'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(calls['https://linux.do/a.png'], 1);
    await tester.longPressAt(tester.getCenter(find.byType(PageView)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存原图到本地'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('图片已保存到相册 V2DO'), findsOneWidget);
    expect(calls['https://linux.do/a.png'], 1);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
