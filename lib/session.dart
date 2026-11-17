import 'dart:convert';
import 'package:flutter/services.dart';

class ForumResponse {
  final int status;
  final String body, location;
  const ForumResponse(this.status, this.body, [this.location = '']);
}

typedef Requester = Future<ForumResponse> Function(Uri uri,
    {String method, Map<String, String> headers, String? body});

class Session {
  static const channel = MethodChannel('dualforum/session');
  static Future<bool>? _linuxRecovery;
  static DateTime? _lastRecovery;
  static bool needsRecovery(Uri uri, String method, ForumResponse r) =>
      uri.host == 'linux.do' &&
      method == 'GET' &&
      (([401, 404].contains(r.status) && uri.path == '/session/current.json') ||
          (r.status == 403 &&
              (r.body.contains('cf-chl-') ||
                  r.body.contains('Just a moment') ||
                  r.body.contains('<html'))));
  static bool linuxGuest(Uri uri, String method, ForumResponse response) {
    if (uri.host != 'linux.do' ||
        uri.path != '/session/current.json' ||
        method != 'GET' ||
        response.status != 200) return false;
    try {
      final value = jsonDecode(response.body);
      return value is Map &&
          value.containsKey('current_user') &&
          value['current_user'] == null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> recoverLinux() async {
    if (_linuxRecovery != null) return _linuxRecovery!;
    if (_lastRecovery != null &&
        DateTime.now().difference(_lastRecovery!).inSeconds < 10) return false;
    _lastRecovery = DateTime.now();
    final task = channel
        .invokeMethod<bool>('refreshLinuxSession')
        .then((v) => v == true)
        .catchError((_) => false);
    _linuxRecovery = task;
    try {
      return await task;
    } finally {
      _linuxRecovery = null;
    }
  }

  static Future<ForumResponse> request(Uri uri,
      {String method = 'GET',
      Map<String, String> headers = const {},
      String? body}) async {
    try {
      Future<ForumResponse> send() async {
        final value = await channel.invokeMapMethod<String, dynamic>(
            'request', {
          'url': uri.toString(),
          'method': method,
          'headers': headers,
          'body': body
        });
        return ForumResponse(value!['status'] as int, value['body'] as String,
            value['location'] as String? ?? '');
      }

      final first = await send();
      if ((needsRecovery(uri, method, first) ||
              linuxGuest(uri, method, first)) &&
          await recoverLinux()) return await send();
      return first;
    } on PlatformException catch (e) {
      throw ForumError(e.message ?? '连接失败');
    }
  }
}

class ForumError implements Exception {
  final String message;
  final bool needsLogin;
  const ForumError(this.message, {this.needsLogin = false});
  @override
  String toString() => message;
}

dynamic decodeResponse(ForumResponse response) {
  checkResponse(response);
  try {
    return jsonDecode(response.body);
  } catch (_) {
    throw const ForumError('网站要求验证，请完成登录/验证后重试', needsLogin: true);
  }
}

void checkResponse(ForumResponse response) {
  if ([401, 403].contains(response.status))
    throw const ForumError('请先完成登录或网站验证', needsLogin: true);
  if (response.status == 429) throw const ForumError('访问频繁，请稍后重试');
  if (response.status < 200 || response.status >= 300)
    throw ForumError('网站返回 ${response.status}');
  if (response.body.contains('cf-chl-') ||
      response.body.contains('<title>Just a moment'))
    throw const ForumError('请先完成网站验证', needsLogin: true);
}
