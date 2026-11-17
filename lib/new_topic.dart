import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'forum.dart';
import 'session.dart';
import 'account.dart';
import 'profile.dart';

class TopicForm {
  final String token, path;
  final Map<String, String> hidden;
  const TopicForm(this.token, this.path, {this.hidden = const {}});
}

class TopicPublisher {
  final Forum forum;
  const TopicPublisher(this.forum);

  static String? publicationProblem(String body) {
    final doc = html.parse(body);
    final problem = doc.querySelector('.problem')?.text.trim();
    if (problem != null && problem.isNotEmpty) return problem;
    // Some V2EX forms use a message container rather than .problem.
    final messages = doc
        .querySelectorAll('div')
        .map((e) => e.text.trim())
        .where((s) => s.contains('创建新主题过程中遇到一些问题') && s.length < 1000)
        .toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    return messages.firstOrNull;
  }

  Future<(String, Set<int>)?> publicationBaseline() async {
    if (forum.discourse) return null;
    try {
      final account = await AccountService(forum).current();
      if (account == null) return null;
      final before =
          await ProfileService(forum).activity(account.username, 'topics');
      // With no existing topics, absence alone cannot prove a valid baseline.
      if (before.topics.isEmpty) return null;
      return (account.username, before.topics.map((t) => t.id).toSet());
    } catch (_) {
      return null;
    }
  }

  Future<Topic?> verifyPublication(
      (String, Set<int>)? before, String title, ForumSection section) async {
    if (before == null || before.$2.isEmpty) return null;
    try {
      final latest = await ProfileService(forum).activity(before.$1, 'topics');
      final highest = before.$2.reduce((a, b) => a > b ? a : b);
      final matches = latest.topics
          .where((t) => t.id > highest && t.title.trim() == title.trim())
          .toList();
      if (matches.length != 1) return null;
      final candidate = matches.single;
      final response = await forum.get('/t/${candidate.id}');
      if (response.status != 200) return null;
      final doc = html.parse(response.body);
      final author = doc
          .querySelector('.header small a[href^="/member/"]')
          ?.attributes['href'];
      if (doc.querySelector('h1')?.text.trim() != title.trim() ||
          author != '/member/${Uri.encodeComponent(before.$1)}' ||
          doc.querySelector('.header a[href="/go/${section.id}"]') == null ||
          doc.querySelector('.topic_content') == null) return null;
      return Topic(candidate.id, title.trim(),
          author: before.$1, category: section.name);
    } catch (_) {
      return null;
    }
  }

  Future<List<ForumSection>> sections() async {
    if (!forum.discourse) return forum.sections('node');
    final data = decodeResponse(await forum.get('/site.json'));
    final rows = data['categories'] as List? ?? [];
    final allowed = (data['can_create_topic_in_category'] as List?)?.toSet();
    final names = {for (final c in rows) c['id']: c['name']};
    return [
      for (final c in rows)
        if (allowed != null ? allowed.contains(c['id']) : c['permission'] == 1)
          ForumSection('${c['id']}', '${c['name']}', 'category',
              parentName: names[c['parent_category_id']]?.toString() ?? '')
    ];
  }

  Future<TopicForm> prepare([ForumSection? section]) async {
    if (forum.discourse) {
      final ticket = await forum.prepareReply(0);
      return TopicForm(ticket.token, '/posts.json');
    }
    var path =
        section == null ? '/new' : '/new/${Uri.encodeComponent(section.id)}';
    var response = await forum.get(path);
    for (var i = 0;
        i < 3 && [301, 302, 303, 307, 308].contains(response.status);
        i++) {
      final next = forum.url(response.location);
      if (next.host != forum.host ||
          !RegExp(r'^/(new|write)(/|$)').hasMatch(next.path)) {
        throw const ForumError('请登录后发帖', needsLogin: true);
      }
      path = next.path + (next.hasQuery ? '?${next.query}' : '');
      response = await forum.get(path);
    }
    checkResponse(response);
    final doc = html.parse(response.body);
    final once = doc.querySelector('input[name="once"]')?.attributes['value'];
    if (once == null || doc.querySelector('[name="title"]') == null) {
      final problem = doc.querySelector('.problem')?.text.trim();
      throw ForumError(problem ?? '请登录并确认账号具有发帖权限',
          needsLogin: problem == null);
    }
    var form = doc.querySelector('[name="title"]')!.parent;
    while (form != null && form.localName != 'form') {
      form = form.parent;
    }
    final action = forum.url(form?.attributes['action'] ?? path);
    if (action.host != forum.host ||
        !RegExp(r'^/(?:new(?:/[\w-]+)?|write)$').hasMatch(action.path)) {
      throw const ForumError('网站发帖表单已变化，请稍后重试');
    }
    return TopicForm(once, action.path, hidden: {
      for (final e
          in form?.querySelectorAll('input[type="hidden"][name]') ?? [])
        e.attributes['name']!: e.attributes['value'] ?? ''
    });
  }

  Future<Topic?> publish(String title, String content, ForumSection section,
      {List<String> tags = const []}) async {
    if (title.trim().isEmpty || content.trim().isEmpty)
      throw const ForumError('请填写标题和正文');
    final baseline = await publicationBaseline();
    final form = await prepare(section);
    final fields = forum.discourse
        ? <String, dynamic>{
            'title': title.trim(),
            'raw': content,
            'category': int.parse(section.id),
            'archetype': 'regular',
            'tags': tags,
          }
        : <String, dynamic>{
            ...form.hidden,
            'once': form.token,
            'title': title.trim(),
            'content': content,
            'node_name': section.id,
            'syntax': '1'
          };
    ForumResponse response;
    try {
      response = await forum.transport(forum.url(form.path),
          method: 'POST',
          headers: {
            'Content-Type': forum.discourse
                ? 'application/json'
                : 'application/x-www-form-urlencoded; charset=UTF-8',
            'Origin': 'https://${forum.host}',
            'Referer': forum.url(form.path).toString(),
            if (forum.discourse) 'X-CSRF-Token': form.token,
            if (forum.discourse) 'X-Requested-With': 'XMLHttpRequest',
          },
          body: forum.discourse
              ? jsonEncode(fields)
              : fields.entries
                  .map((e) =>
                      '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
                  .join('&'));
    } catch (_) {
      final verified = await verifyPublication(baseline, title, section);
      if (verified != null) return verified;
      throw const ForumError('发布结果未确认，请先到个人主题列表核对，避免重复发布');
    }
    if (forum.discourse) {
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {}
      if (response.status >= 200 && response.status < 300) {
        if (data is Map &&
            (data['action'] == 'enqueued' || data['pending_post'] != null))
          return null;
        final id = data is Map
            ? (data['topic_id'] ?? data['post']?['topic_id'])
            : null;
        if (id is int) return Topic(id, title.trim(), category: section.name);
      }
      if (data is Map &&
          data['errors'] is List &&
          (data['errors'] as List).isNotEmpty) {
        throw ForumError((data['errors'] as List).join('\n'));
      }
    } else {
      final redirect = forum.url(response.location);
      final match = RegExp(r'^/t/(\d+)/?$').firstMatch(redirect.path);
      if ([301, 302, 303].contains(response.status) &&
          redirect.host == forum.host &&
          match != null) {
        return Topic(int.parse(match.group(1)!), title.trim(),
            category: section.name);
      }
      final problem = publicationProblem(response.body);
      if (problem != null && problem.isNotEmpty) throw ForumError(problem);
      final verified = await verifyPublication(baseline, title, section);
      if (verified != null) return verified;
    }
    throw const ForumError('发布结果未确认，请到个人主题列表核对，避免重复发布');
  }
}
