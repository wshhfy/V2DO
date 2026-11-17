import 'dart:convert';
import 'package:flutter/material.dart';
import 'forum.dart';
import 'session.dart';
import 'profile.dart';
import 'account.dart';

class RecentVisit {
  final Topic topic;
  final DateTime at;
  const RecentVisit(this.topic, this.at);
}

class RecentStore extends ChangeNotifier {
  static final instance = RecentStore();
  final Map<String, List<RecentVisit>> visits = {};
  final Map<String, List<ForumSection>> sections = {};
  Future<void> _writes = Future.value();
  Future<void> load() async {
    try {
      final prefs = await Session.channel
          .invokeMapMethod<String, dynamic>('getPreferences');
      restore(prefs?['recentVisits'] as String? ?? '{}');
      changed();
    } catch (_) {}
  }

  void restore(String raw) {
    try {
      final data = jsonDecode(raw) as Map;
      for (final host in ['www.v2ex.com', 'linux.do']) {
        final entry = data[host] as Map? ?? {};
        visits[host] = [
          for (final t in (entry['topics'] as List? ?? []).take(100))
            RecentVisit(
                Topic(t['id'] as int, t['title'] as String,
                    author: t['author'] as String? ?? '',
                    category: t['category'] as String? ?? ''),
                DateTime.parse(t['at'] as String))
        ];
        sections[host] = host == 'linux.do'
            ? []
            : [
                for (final s in (entry['sections'] as List? ?? []).take(12))
                  ForumSection(s['id'] as String, s['name'] as String,
                      s['kind'] as String,
                      slug: s['slug'] as String? ?? '',
                      parentName: s['parent'] as String? ?? '')
              ];
      }
    } catch (_) {
      visits.clear();
      sections.clear();
    }
  }

  String serialize() => jsonEncode({
        for (final host in ['www.v2ex.com', 'linux.do'])
          host: {
            'topics': [
              for (final v in visits[host] ?? <RecentVisit>[])
                {
                  'id': v.topic.id,
                  'title': v.topic.title,
                  'author': v.topic.author,
                  'category': v.topic.category,
                  'at': v.at.toIso8601String()
                }
            ],
            'sections': [
              for (final s in sections[host] ?? <ForumSection>[])
                {
                  'id': s.id,
                  'name': s.name,
                  'kind': s.kind,
                  'slug': s.slug,
                  'parent': s.parentName
                }
            ],
          }
      });
  void changed() {
    notifyListeners();
    final payload = serialize();
    _writes = _writes.then((_) async {
      try {
        await Session.channel
            .invokeMethod('setPreferences', {'recentVisits': payload});
      } catch (_) {}
    });
  }

  void visit(Forum forum, Topic topic) {
    visits[forum.host] = [
      RecentVisit(topic, DateTime.now()),
      ...(visits[forum.host] ?? <RecentVisit>[])
          .where((v) => v.topic.id != topic.id)
    ].take(100).toList();
    changed();
  }

  void choose(Forum forum, ForumSection section) {
    if (forum.discourse) return;
    sections[forum.host] = [
      section,
      ...(sections[forum.host] ?? <ForumSection>[])
          .where((s) => s.id != section.id || s.kind != section.kind)
    ].take(12).toList();
    changed();
  }

  void remove(Forum forum, int id) {
    visits[forum.host]?.removeWhere((v) => v.topic.id == id);
    changed();
  }

  void clear(Forum forum) {
    visits.remove(forum.host);
    sections.remove(forum.host);
    changed();
  }
}

class RecentPage extends StatefulWidget {
  final Forum forum;
  final void Function(Topic, List<Topic>) open;
  final ValueChanged<ForumSection> choose;
  final VoidCallback back;
  final Future<void> Function() login;
  const RecentPage(this.forum,
      {super.key,
      required this.open,
      required this.choose,
      required this.back,
      required this.login});
  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  int tab = 0;
  bool cloud = false;
  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          const SizedBox(width: 12),
          Expanded(
              child: Text('${widget.forum.name} · 最近访问',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(
              tooltip: '收起抽屉',
              onPressed: widget.back,
              icon: const Icon(Icons.chevron_left))
        ]),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ChoiceChip(
                            label: Text(['浏览', '我的回复', '收藏'][i]),
                            selected: tab == i,
                            onSelected: (_) => setState(() => tab = i))))
            ])),
        if (tab == 0)
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  child: Row(children: [
                    for (final isCloud in [false, true]) ...[
                      if (isCloud)
                        VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color:
                                Theme.of(context).colorScheme.outlineVariant),
                      Expanded(
                          child: Material(
                              color: cloud == isCloud
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: .09)
                                  : Theme.of(context).colorScheme.surface,
                              child: InkWell(
                                  onTap: () => setState(() => cloud = isCloud),
                                  child: Semantics(
                                      button: true,
                                      selected: cloud == isCloud,
                                      child: Center(
                                          child: Text(isCloud ? '网站记录' : '本地记录',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: cloud == isCloud
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  color: cloud == isCloud
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant))))))),
                    ]
                  ]))),
        Expanded(
            child: tab == 0 && !cloud
                ? _local()
                : ValueListenableBuilder<AccountState>(
                    valueListenable:
                        Accounts.states[Accounts.index(widget.forum)],
                    builder: (_, state, child) => _RemoteActivity(widget.forum,
                        key: ValueKey(
                            '${tab == 0 ? 'read' : tab}/${state.account?.username}'),
                        kind: tab == 0
                            ? 'read'
                            : tab == 1
                                ? 'replies'
                                : 'bookmarks',
                        open: widget.open,
                        login: widget.login))),
      ]);
  Widget _local() => ListenableBuilder(
      listenable: RecentStore.instance,
      builder: (context, _) {
        final store = RecentStore.instance;
        final rows = store.visits[widget.forum.host] ?? [];

        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (rows.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('本机最近读过的帖子会出现在这里。')),
              ])),
          SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final v = rows[i], t = v.topic;
                final at = v.at.toLocal();
                return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(t.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${t.category} · ${t.author} · ${at.month}/${at.day} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () =>
                        widget.open(t, rows.map((v) => v.topic).toList()));
              }),
        ]);
      });
}

class _RemoteActivity extends StatefulWidget {
  final Forum forum;
  final String kind;
  final void Function(Topic, List<Topic>) open;
  final Future<void> Function() login;
  const _RemoteActivity(this.forum,
      {super.key, required this.kind, required this.open, required this.login});
  @override
  State<_RemoteActivity> createState() => _RemoteActivityState();
}

class _RemoteActivityState extends State<_RemoteActivity> {
  final scroll = ScrollController();
  final items = <Topic>[];
  bool busy = false, more = true, needsLogin = false;
  String? error;
  int page = 0, generation = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(nearEnd);
    load();
  }

  void nearEnd() {
    if (scroll.hasClients && scroll.position.extentAfter < 300 && error == null)
      load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    generation++;
    page = 0;
    more = true;
    busy = false;
    items.clear();
    await load();
  }

  Future<void> load() async {
    if (busy || !more) return;
    final token = generation;
    setState(() {
      busy = true;
      error = null;
      needsLogin = false;
    });
    try {
      final account = await AccountService(widget.forum).current();
      if (account == null)
        throw const ForumError('登录后查看网站记录', needsLogin: true);
      final result = await ProfileService(widget.forum)
          .activity(account.username, widget.kind, page: page);
      if (!mounted || token != generation) return;
      setState(() {
        items.addAll(result.topics);
        page++;
        more = result.more && result.topics.isNotEmpty;
      });
    } catch (e) {
      if (mounted && token == generation)
        setState(() {
          error = '$e';
          needsLogin = e is ForumError && e.needsLogin;
        });
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                  child: Text(
                      widget.kind == 'read'
                          ? (widget.forum.discourse
                              ? '网站已记录的阅读 · 同一账号跨设备'
                              : 'V2EX 首页 · Recent Visited Topics')
                          : '读取当前账号的网站记录',
                      style: const TextStyle(fontSize: 11))),
              IconButton(
                  tooltip: '刷新列表',
                  onPressed: busy ? null : reload,
                  icon: const Icon(Icons.refresh, size: 20)),
            ])),
        Expanded(
            child: RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                    controller: scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length + 1,
                    itemBuilder: (context, i) {
                      if (i == items.length)
                        return Padding(
                            padding: const EdgeInsets.all(16),
                            child: busy
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : error != null
                                    ? Column(children: [
                                        Text(error!,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        TextButton(
                                            onPressed: () async {
                                              if (needsLogin)
                                                await widget.login();
                                              if (mounted) await load();
                                            },
                                            child: Text(
                                                needsLogin ? '登录 / 验证' : '重试'))
                                      ])
                                    : more
                                        ? TextButton(
                                            onPressed: load,
                                            child: const Text('加载更多'))
                                        : Text(
                                            items.isEmpty ? '暂无记录' : '已显示全部记录',
                                            textAlign: TextAlign.center));
                      final t = items[i];
                      return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(t.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: t.activityExcerpt.isEmpty
                              ? null
                              : Text(t.activityExcerpt,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => widget.open(t, List.of(items)));
                    }))),
      ]);
}
