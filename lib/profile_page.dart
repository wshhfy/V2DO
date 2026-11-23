import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'account.dart';
import 'forum.dart';
import 'profile.dart';
import 'main.dart'
    show TopicPage, UserAvatar, ForumIcon, TimeLabel, authenticate;
import 'site_view.dart';
import 'relations_page.dart';

void openMember(BuildContext context, Forum forum, String username) {
  if (username.isEmpty) return;
  Navigator.push(context,
      MaterialPageRoute<void>(builder: (_) => ProfilePage(forum, username)));
}

class MemberAvatar extends StatelessWidget {
  final Forum forum;
  final String url, name;
  final double size;
  const MemberAvatar(this.forum, this.url, this.name,
      {this.size = 28, super.key});
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: name.isEmpty ? null : () => openMember(context, forum, name),
      child: UserAvatar(url, name, size: size));
}

class ProfilePage extends StatefulWidget {
  final Forum forum;
  final String username, initial;
  const ProfilePage(this.forum, this.username,
      {this.initial = 'topics', super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<MemberProfile> profile =
      ProfileService(widget.forum).member(widget.username);
  late String kind = widget.initial;
  final rows = <Topic>[];
  int page = 0, generation = 0;
  bool busy = false, more = false;
  String? error;
  bool get own =>
      Accounts.states[Accounts.index(widget.forum)].value.account?.username
          .toLowerCase() ==
      widget.username.toLowerCase();
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (!reset && busy) return;
    final token = ++generation;
    final next = reset ? 0 : page + 1;
    setState(() {
      busy = true;
      error = null;
      if (reset) rows.clear();
    });
    try {
      final result = await ProfileService(widget.forum)
          .activity(widget.username, kind, page: next);
      if (mounted && token == generation)
        setState(() {
          rows.addAll(result.topics);
          more = result.more;
          page = next;
        });
    } catch (e) {
      if (mounted && token == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && token == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          toolbarHeight: 48,
          title: Row(children: [
            ForumIcon(widget.forum),
            const SizedBox(width: 8),
            Expanded(
                child: UiText(own ? '我的资料' : widget.username,
                    maxLines: 1, overflow: TextOverflow.ellipsis))
          ])),
      body: SafeArea(
          child: Column(children: [
        FutureBuilder<MemberProfile>(
            future: profile,
            builder: (context, s) {
              if (s.hasError)
                return ListTile(
                    title: UiText(s.error.toString()),
                    trailing: IconButton(
                        onPressed: () => setState(() => profile =
                            ProfileService(widget.forum)
                                .member(widget.username)),
                        icon: const Icon(Icons.refresh)));
              if (!s.hasData) return const LinearProgressIndicator();
              final p = s.data!;
              return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          UserAvatar(p.avatar, p.username, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(p.username,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700)),
                                if (p.name.isNotEmpty)
                                  Text(p.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                UiText(
                                    [
                                      if (p.level != null) 'Lv${p.level}',
                                      if (p.id != null) '#${p.id}',
                                      if (p.joined != null)
                                        '${p.joined!.year}/${p.joined!.month} 加入'
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 11))
                              ]))
                        ]),
                        if (!widget.forum.discourse && !own)
                          RelationButtons(widget.username),
                        if (p.bio.isNotEmpty || p.website.isNotEmpty)
                          ExpansionTile(
                              dense: true,
                              tilePadding: EdgeInsets.zero,
                              title: const UiText('个人简介',
                                  style: TextStyle(fontSize: 12)),
                              children: [
                                if (p.bio.isNotEmpty) Text(p.bio),
                                if (p.website.isNotEmpty)
                                  TextButton(
                                      onPressed: () {
                                        final uri = Uri.tryParse(p.website);
                                        if (uri != null) openExternal(uri);
                                      },
                                      child: Text(p.website))
                              ])
                      ]));
            }),
        Row(children: [
          for (final entry in {
            'topics': '主题',
            'replies': '回复',
            if (own) 'bookmarks': '我的收藏'
          }.entries)
            Expanded(
                child: TextButton(
                    style: TextButton.styleFrom(
                        backgroundColor: kind == entry.key
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null),
                    onPressed: () {
                      setState(() => kind = entry.key);
                      load(reset: true);
                    },
                    child: UiText(entry.value)))
        ]),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                UiText(error!),
                Wrap(children: [
                  TextButton(
                      onPressed: () => load(reset: true),
                      child: const UiText('重试')),
                  TextButton(
                      onPressed: () async {
                        await authenticate(context, widget.forum);
                        if (mounted) load(reset: true);
                      },
                      child: const UiText('登录 / 验证'))
                ])
              ])),
        Expanded(
            child: RefreshIndicator(
                onRefresh: () => load(reset: true),
                child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, i) {
                      if (i == rows.length)
                        return Padding(
                            padding: const EdgeInsets.all(20),
                            child: busy
                                ? const SizedBox.shrink()
                                : more
                                    ? TextButton(
                                        onPressed: () => load(),
                                        child: const UiText('加载更多'))
                                    : UiText(
                                        rows.isEmpty ? '暂无公开内容' : '已显示全部内容',
                                        textAlign: TextAlign.center));
                      final t = rows[i];
                      return ListTile(
                          dense: true,
                          title: Text(t.title,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (t.activityExcerpt.isNotEmpty)
                                  Text(t.activityExcerpt,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis),
                                Row(children: [
                                  if (t.category.isNotEmpty)
                                    Expanded(
                                        child: Text(t.category, maxLines: 1)),
                                  TimeLabel(t.createdAt,
                                      fallback: t.activityTimeLabel)
                                ])
                              ]),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => TopicPage(widget.forum, t,
                                      sequence: List.of(rows)))));
                    })))
      ])));
}
