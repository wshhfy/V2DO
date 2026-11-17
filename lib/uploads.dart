import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'forum.dart';
import 'session.dart';
import 'imgur_session.dart';

class SelectedImage {
  final Uint8List bytes;
  final String name, mime;
  const SelectedImage(this.bytes, this.name, this.mime);
  static Future<SelectedImage?> pick() async {
    try {
      final data =
          await Session.channel.invokeMapMethod<String, dynamic>('pickImage');
      return data == null
          ? null
          : SelectedImage(data['bytes'] as Uint8List, data['name'] as String,
              data['mime'] as String);
    } on PlatformException catch (e) {
      throw ForumError(e.message ?? '无法选择图片');
    }
  }
}

class ImageUploads {
  static Future<String> uploadImgur(SelectedImage image,
      {ImgurAccount? verifiedAccount}) async {
    final account = verifiedAccount ?? await ImgurSession.current();
    if (account == null) throw const ForumError('请先登录 Imgur', needsLogin: true);
    final request =
        http.MultipartRequest('POST', await ImgurSession.endpoint('/3/upload'))
          ..fields['type'] = 'file'
          ..fields['name'] = image.name
          ..files.add(http.MultipartFile.fromBytes('image', image.bytes,
              filename: image.name));
    final bytes = await request.finalize().toBytes();
    try {
      final result =
          await Session.channel.invokeMapMethod<String, dynamic>('request', {
        'url': request.url.toString(),
        'method': 'POST',
        'bodyBytes': bytes,
        'headers': {
          ...request.headers,
          'Accept': 'application/json',
          'Origin': 'https://imgur.com',
          'Referer': 'https://imgur.com/upload'
        }
      });
      return ImgurSession.uploadedLink(
          ForumResponse(result!['status'] as int, result['body'] as String),
          account);
    } on PlatformException {
      throw const ForumError('Imgur 上传结果未确认，请到网页核对，避免重复上传；草稿已保留');
    }
  }

  static Future<String> upload(Forum forum, SelectedImage image,
      {ImgurAccount? imgurAccount}) async {
    if (!forum.discourse)
      return uploadImgur(image, verifiedAccount: imgurAccount);
    final csrf = decodeResponse(await forum.get('/session/csrf.json'))['csrf']
        as String?;
    if (csrf == null || csrf.isEmpty)
      throw const ForumError('请先登录再上传图片', needsLogin: true);
    final request = http.MultipartRequest('POST', forum.url('/uploads.json'));
    request.fields.addAll({'upload_type': 'composer', 'synchronous': 'true'});
    request.files.add(http.MultipartFile.fromBytes('file', image.bytes,
        filename: image.name));
    final bytes = await request.finalize().toBytes();
    try {
      final result =
          await Session.channel.invokeMapMethod<String, dynamic>('request', {
        'url': request.url.toString(),
        'method': 'POST',
        'bodyBytes': bytes,
        'headers': {
          ...request.headers,
          'Accept': 'application/json',
          'X-CSRF-Token': csrf,
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': forum.url('/').origin,
          'Referer': forum.url('/').toString()
        }
      });
      final response =
          ForumResponse(result!['status'] as int, result['body'] as String);
      if (response.status == 413) throw const ForumError('图片超过论坛允许的大小，请压缩后重试');
      if (response.body.trimLeft().startsWith('{')) {
        final data = jsonDecode(response.body);
        if (data['errors'] is List && (data['errors'] as List).isNotEmpty) {
          throw ForumError('上传失败：${(data['errors'] as List).join('；')}');
        }
      }
      return discourseMarkup(decodeResponse(response));
    } on PlatformException catch (e) {
      throw ForumError(e.code == 'NETWORK'
          ? '上传结果未确认；回复草稿已保留，请检查网络后再操作'
          : e.message ?? '上传失败');
    }
  }

  static String discourseMarkup(dynamic data) {
    final short = data['short_url']?.toString() ?? '';
    final url = data['url']?.toString() ?? '';
    final address = short.startsWith('upload://') ? short : url;
    if (data['id'] == null ||
        !(address.startsWith('upload://') ||
            address.startsWith('https://') ||
            address.startsWith('/uploads/'))) {
      throw const ForumError('论坛没有返回可用的图片地址，未插入草稿');
    }
    return '![图片]($address)';
  }
}
