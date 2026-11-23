import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'forum.dart';
import 'notifications.dart';
import 'main.dart'
    show UserAvatar, TimeLabel, ForumIcon, TopicPage, authenticate;

class NotificationsPage extends StatefulWidget {
  final Forum forum;
  const NotificationsPage(this.forum, {super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<ForumNotice> rows = [];
  final readIds = <String>{};
  bool busy = false, hasMore = true;
  int page = 0;
  String? error;
  late final int initialUnread =
      UnreadMessages.counts[widget.forum.discourse ? 1 : 0].value ?? 0;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = reset ? 0 : page + 1;
      final result = await NoticeService(widget.forum)
          .list(page: next, initialUnread: initialUnread);
      if (!mounted) return;
      setState(() {
        if (reset) rows.clear();
        final ids = rows.map((r) => r.id).toSet();
        rows.addAll(result.items.where((r) => !ids.contains(r.id)));
        page = next;
        hasMore = result.hasMore;
      });
      await UnreadMessages.refresh(widget.forum);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(ForumNotice n) async {
    var opened = false;
    if (n.topicId == null) {
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text(n.title),
                  content: UiText('${n.author} ${n.detail}\n\n这条通知没有关联主题。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const UiText('关闭'))
                  ]));
      opened = true;
    } else {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => TopicPage(
                  widget.forum, Topic(n.topicId!, n.title),
                  onLoaded: () => opened = true)));
    }
    if (!mounted || !opened) return;
    try {
      await NoticeService(widget.forum).markRead(n);
      if (mounted) setState(() => readIds.add(n.id));
      await UnreadMessages.refresh(widget.forum);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText('已打开主题，但已读状态同步失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          toolbarHeight: 48,
          title: Row(children: [
            ForumIcon(widget.forum),
            const SizedBox(width: 8),
            const UiText('消息')
          ]),
          actions: [
            IconButton(
                tooltip: uiTr(context, '刷新消息'),
                onPressed: busy ? null : () => load(reset: true),
                icon: const Icon(Icons.refresh))
          ]),
      body: SafeArea(
          child: Column(children: [
        if (!widget.forum.discourse)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: UiText('V2EX 打开消息列表后，网站会清除未读计数。',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                UiText(error!),
                Wrap(children: [
                  TextButton(
                      onPressed: () => load(reset: rows.isEmpty),
                      child: const UiText('重试')),
                  TextButton(
                      onPressed: () async {
                        await authenticate(context, widget.forum);
                        load(reset: true);
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
                    itemBuilder: (c, i) {
                      if (i == rows.length)
                        return Padding(
                            padding: const EdgeInsets.all(20),
                            child: rows.isEmpty
                                ? UiText(
                                    busy
                                        ? '正在加载消息…'
                                        : error == null
                                            ? '暂无消息'
                                            : '',
                                    textAlign: TextAlign.center)
                                : hasMore
                                    ? TextButton(
                                        onPressed: busy ? null : () => load(),
                                        child: const UiText('加载更多消息'))
                                    : const UiText('已显示全部消息',
                                        textAlign: TextAlign.center));
                      final n = rows[i],
                          unread =
                              rows[i].unread && !readIds.contains(rows[i].id);
                      return Material(
                          color: unread
                              ? Theme.of(c)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: .28)
                              : Colors.transparent,
                          child: InkWell(
                              onTap: () => open(n),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Badge(
                                            isLabelVisible: unread,
                                            child: UserAvatar(
                                                n.avatar, n.author,
                                                size: 30)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(n.title,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: unread
                                                          ? FontWeight.w600
                                                          : FontWeight.w400)),
                                              const SizedBox(height: 4),
                                              Text(
                                                  '${n.author} ${widget.forum.discourse ? uiTr(context, n.detail) : n.detail}',
                                                  maxLines: 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                              const SizedBox(height: 4),
                                              TimeLabel(n.createdAt,
                                                  fallback: n.timeLabel)
                                            ])),
                                        if (n.topicId != null)
                                          const Icon(Icons.chevron_right,
                                              size: 18)
                                      ]))));
                    })))
      ])));
}
