import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AvatarLoader {
  // Full-size previews are not retained in the avatar cache.
  static Future<Uint8List> image(String url) => _fetch(Uri.parse(url), 0);
  static final _cache = LinkedHashMap<String, Future<Uint8List>>();
  static void clear() => _cache.clear();
  static Future<Uint8List> load(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return cached;
    }
    if (_cache.length >= 200) _cache.remove(_cache.keys.first);
    // Keep failed futures until evicted so recycled rows don't hammer a broken URL.
    return _cache[url] = _fetch(Uri.parse(url), 0);
  }

  static Future<Uint8List> _fetch(Uri uri, int redirects) async {
    if (redirects > 4 || uri.scheme != 'https')
      throw Exception('Invalid avatar URL');
    if (uri.host == 'linux.do' || uri.host == 'www.v2ex.com') {
      final result = await const MethodChannel('dualforum/session')
          .invokeMapMethod<String, dynamic>('request',
              {'url': uri.toString(), 'method': 'GET', 'binary': true});
      final status = result?['status'] as int? ?? 0;
      if ([301, 302, 303, 307, 308].contains(status)) {
        return _fetch(
            uri.resolve(result!['location'] as String), redirects + 1);
      }
      if (status != 200) throw Exception('Avatar unavailable');
      return result!['bytes'] as Uint8List;
    }
    // Public CDN requests never receive forum cookies or credentials.
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Avatar unavailable');
    return response.bodyBytes;
  }
}
