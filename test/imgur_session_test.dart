import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/imgur_session.dart';
import 'package:forum_app/session.dart';

void main() {
  test('Website configuration fails closed when structure changes', () {
    expect(
        ImgurSession.websiteId(
            'hH:()=>w,var l="imgur.com",w="123456789abcdef"'),
        '123456789abcdef');
    expect(() => ImgurSession.websiteId('unrelated="123456789abcdef"'),
        throwsA(isA<ForumError>()));
    expect(
        () => ImgurSession.websiteId(
            'hH:()=>w,var l="other.example",w="123456789abcdef"'),
        throwsA(isA<ForumError>()));
  });
  test('Upload requires current account ownership and an Imgur HTTPS image',
      () {
    ForumResponse response(dynamic owner, String link) => ForumResponse(
        200,
        jsonEncode({
          'success': true,
          'data': {'account_id': owner, 'link': link}
        }));
    const account = ImgurAccount(42, 'user');
    expect(
        ImgurSession.uploadedLink(
            response(42, 'https://i.imgur.com/a.jpg'), account),
        'https://i.imgur.com/a.jpg');
    expect(
        () => ImgurSession.uploadedLink(
            response(null, 'https://i.imgur.com/a.jpg'), account),
        throwsA(isA<ForumError>()));
    expect(
        () => ImgurSession.uploadedLink(
            response(9, 'https://i.imgur.com/a.jpg'), account),
        throwsA(isA<ForumError>()));
    expect(
        () => ImgurSession.uploadedLink(
            response(42, 'https://example.com/a.jpg'), account),
        throwsA(isA<ForumError>()));
    expect(
        () => ImgurSession.uploadedLink(
            const ForumResponse(403, 'challenge'), account),
        throwsA(isA<ForumError>()));
  });
}
