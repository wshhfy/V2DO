import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'forum.dart';
import 'social.dart';

class SocialBar extends StatefulWidget {
  final Forum forum;
  final int topicId, postId;
  final bool original;
  final bool liked;
  final int likes;
  final int page;
  const SocialBar(this.forum, this.topicId, this.postId,
      {this.original = false,
      this.liked = false,
      this.likes = 0,
      this.page = 1,
      super.key});
  @override
  State<SocialBar> createState() => _SocialBarState();
}

class _SocialBarState extends State<SocialBar> {
  SocialState? value;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    value = SocialState(liked: widget.liked, likes: widget.likes);
    if (widget.original) refresh();
  }

  Future<void> refresh() async {
    try {
      final s = await SocialService(widget.forum, page: widget.page)
          .state(widget.topicId, widget.postId, original: widget.original);
      if (mounted) setState(() => value = s);
    } catch (_) {/* Action reports authentication errors on tap. */}
  }

  Future<void> act(bool bookmark) async {
    if (busy) return;
    if (!bookmark && !widget.forum.discourse) {
      if (value?.liked == true) return;
      final accepted = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const UiText('发送感谢？'),
                  content: const UiText('V2EX 感谢会按网站规则消耗铜币，发送后不能撤回。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const UiText('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const UiText('感谢'))
                  ]));
      if (accepted != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      final service = SocialService(widget.forum, page: widget.page);
      final result = bookmark
          ? await service.toggleBookmark(widget.topicId, widget.postId,
              original: widget.original)
          : await service.toggleLike(widget.topicId, widget.postId,
              original: widget.original);
      if (mounted) setState(() => value = result);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText(e.toString())));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (widget.original &&
            !widget.forum.discourse &&
            (value?.votes ?? 0) > 0)
          Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UiText('赞同 ${value!.votes}',
                  style: const TextStyle(fontSize: 12))),
        if (widget.original)
          TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: busy ? null : () => act(true),
              icon: Icon(
                  value?.bookmarked == true
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  size: 18),
              label: UiText(value?.bookmarked == true ? '已收藏' : '收藏',
                  style: const TextStyle(fontSize: 12))),
        TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: busy ? null : () => act(false),
            icon: Icon(
                value?.liked == true ? Icons.favorite : Icons.favorite_border,
                size: 16),
            label: UiText(
                busy
                    ? '处理中…'
                    : widget.forum.discourse
                        ? '${value?.liked == true ? '已赞' : '赞'}${(value?.likes ?? 0) > 0 ? ' ${value!.likes}' : ''}'
                        : '${value?.liked == true ? '已感谢' : '感谢'}${(value?.likes ?? 0) > 0 ? ' ${value!.likes}' : ''}',
                style: const TextStyle(fontSize: 12)))
      ]);
}
