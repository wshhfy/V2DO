import 'package:flutter/material.dart';

import 'forum.dart';
import 'main.dart' show TopicPage, UserAvatar, TimeLabel, authenticate;
import 'profile.dart';
import 'profile_page.dart' show ProfilePage;
import 'relations.dart';

class RelationButtons extends StatefulWidget {
  final String username;
  const RelationButtons(this.username, {super.key});
  @override
  State<RelationButtons> createState() => _RelationButtonsState();
}

class _RelationButtonsState extends State<RelationButtons> {
  RelationState? value;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await Relations(forums[0]).state(widget.username);
      if (mounted) setState(() => value = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(bool follow) async {
    if (busy || value == null) return;
    if ((follow ? value!.followPath : value!.blockPath).isEmpty) {
      await authenticate(context, forums[0]);
      if (mounted) await refresh();
      return;
    }
    final desired = !(follow ? value!.following : value!.blocked);
    final verb = follow ? (desired ? '关注' : '取消关注') : (desired ? '屏蔽' : '解除屏蔽');
    final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('$verb ${widget.username}？'),
                content: Text(!follow && desired
                    ? '屏蔽后，V2EX 将过滤该用户的主题、回复及提醒。'
                    : '此操作将同步到 V2EX 账号。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(verb))
                ]));
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await Relations(forums[0]).set(widget.username,
          following: follow ? desired : null, blocked: follow ? null : desired);
      if (mounted) setState(() => value = result);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已$verb')));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: busy || value == null || error != null
                  ? null
                  : () => act(true),
              icon: Icon(
                  value?.following == true
                      ? Icons.person_remove_outlined
                      : Icons.person_add_outlined,
                  size: 18),
              label: Text(value?.following == true ? '取消关注' : '关注')),
          TextButton.icon(
              onPressed: busy || value == null || error != null
                  ? null
                  : () => act(false),
              icon: const Icon(Icons.block, size: 18),
              label: Text(value?.blocked == true ? '解除屏蔽' : '屏蔽')),
          IconButton(
              onPressed: busy ? null : refresh,
              tooltip: '刷新关注和屏蔽状态',
              icon: const Icon(Icons.refresh, size: 18)),
        ]),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.error)),
      ]);
}

class RelationsPage extends StatefulWidget {
  const RelationsPage({super.key});
  @override
  State<RelationsPage> createState() => _RelationsPageState();
}

class _RelationsPageState extends State<RelationsPage> {
  int selected = 0, page = 0, generation = 0;
  bool loading = false, more = false;
  String? error;
  List<Topic> topics = [];
  List<MemberProfile> members = [];
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    if (next && loading) return;
    final token = ++generation;
    final target = next ? page + 1 : 1;
    setState(() {
      loading = true;
      error = null;
      if (!next) {
        topics = [];
        members = [];
        more = false;
      }
    });
    try {
      final result = await Relations(forums[0]).following(pageNumber: target);
      if (mounted && token == generation)
        setState(() {
          topics = [...topics, ...result.topics];
          members = result.members;
          more = result.more;
          page = target;
        });
    } catch (e) {
      if (mounted && token == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  Future<void> member(String name) async {
    if (name.trim().isEmpty) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ProfilePage(forums[0], name.trim())));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('V2EX · 我的关注'), toolbarHeight: 48),
      body: SafeArea(
          child: Column(children: [
        Row(children: [
          for (final entry in ['关注动态', '关注的人'].indexed)
            Expanded(
                child: TextButton(
                    style: TextButton.styleFrom(
                        backgroundColor: selected == entry.$1
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null),
                    onPressed: () {
                      setState(() => selected = entry.$1);
                      load();
                    },
                    child: Text(entry.$2)))
        ]),
        if (selected != 0)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                  controller: search,
                  decoration: InputDecoration(
                      isDense: true,
                      hintText: '输入 V2EX 用户名，查看并管理',
                      suffixIcon: IconButton(
                          tooltip: '打开用户资料',
                          onPressed: () => member(search.text),
                          icon: const Icon(Icons.search))),
                  onSubmitted: member)),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(error!),
                Wrap(children: [
                  TextButton(
                      onPressed: loading ? null : load,
                      child: const Text('重试')),
                  TextButton(
                      onPressed: () async {
                        await authenticate(context, forums[0]);
                        if (mounted) load();
                      },
                      child: const Text('登录 / 验证'))
                ])
              ])),
        Expanded(
            child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (selected == 0) ...[
                        for (final t in topics)
                          ListTile(
                              dense: true,
                              leading: InkWell(
                                  onTap: () => member(t.author),
                                  child:
                                      UserAvatar(t.avatar, t.author, size: 28)),
                              title: Text(t.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Row(children: [
                                Expanded(
                                    child: Text('${t.author} · ${t.category}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11))),
                                TimeLabel(t.createdAt)
                              ]),
                              trailing: Text('${t.replies}',
                                  style: const TextStyle(fontSize: 11)),
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => TopicPage(forums[0], t,
                                          sequence: List.of(topics))))),
                        if (more)
                          TextButton(
                              onPressed:
                                  loading ? null : () => load(next: true),
                              child: const Text('加载更多')),
                      ],
                      if (selected == 1)
                        for (final p in members)
                          ListTile(
                              dense: true,
                              leading:
                                  UserAvatar(p.avatar, p.username, size: 32),
                              title: Text(p.username),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => member(p.username)),
                      if (!loading &&
                          error == null &&
                          (selected == 0 ? topics.isEmpty : members.isEmpty))
                        Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                                child: Text(
                                    selected == 1 ? '暂无关注的用户' : '暂无关注动态'))),
                    ]))),
      ])));
}
