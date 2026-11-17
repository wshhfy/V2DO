import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'forum.dart';
import 'session.dart';

class V2SearchPage {
  final List<Topic> topics;
  final bool hasMore;
  const V2SearchPage(this.topics, this.hasMore);
}

class Sov2exSearch {
  static V2SearchPage parse(String body, {int offset = 0}) {
    final data = jsonDecode(body);
    if (data is! Map ||
        data['hits'] is! List ||
        data['total'] is! int ||
        data['timed_out'] == true) {
      throw const ForumError('SoV2EX 返回异常，请稍后重试');
    }
    final rows = data['hits'] as List;
    final topics = <Topic>[];
    for (final row in rows) {
      if (row is! Map || row['_source'] is! Map) continue;
      final source = row['_source'] as Map;
      final id = source['id'];
      final title = source['title'];
      if (id is! int || id <= 0 || title is! String) continue;
      final highlights = row['highlight'];
      var excerpt = '';
      if (highlights is Map) {
        for (final key in [
          'content',
          'postscript_list.content',
          'reply_list.content'
        ]) {
          final snippets = highlights[key];
          if (snippets is List &&
              snippets.isNotEmpty &&
              snippets.first is String) {
            excerpt = html.parseFragment(snippets.first as String).text ?? '';
            break;
          }
        }
      }
      final rawCreated = source['created'];
      final created = rawCreated is String &&
              !RegExp(r'(?:Z|[+-]\d\d:?\d\d)$', caseSensitive: false)
                  .hasMatch(rawCreated)
          ? parseTime('${rawCreated}Z')
          : parseTime(rawCreated);
      topics.add(Topic(id, title,
          author: source['member']?.toString() ?? '',
          replies: source['replies'] is int ? source['replies'] as int : 0,
          activityExcerpt: excerpt,
          createdAt: created));
    }
    return V2SearchPage(topics,
        rows.isNotEmpty && offset + rows.length < (data['total'] as int));
  }

  static Future<V2SearchPage> search(String query,
      {int offset = 0, http.Client? client}) async {
    final request = Uri.https('www.sov2ex.com', '/api/search',
        {'q': query, 'from': '$offset', 'size': '20', 'sort': 'sumup'});
    final owned = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c.get(request, headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200)
        throw ForumError('SoV2EX 返回 ${response.statusCode}');
      return parse(utf8.decode(response.bodyBytes), offset: offset);
    } finally {
      if (owned) c.close();
    }
  }
}
