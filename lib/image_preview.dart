import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:collection';
import 'package:html/parser.dart' as html;
import 'avatar.dart';
import 'session.dart';

Map<String, String> imageTargets(String body, Uri base) {
  final result = <String, String>{};
  for (final img in html.parse(body).querySelectorAll('img')) {
    final src = img.attributes['src'];
    if (src == null || src.isEmpty) continue;
    final marker =
        '${img.className} ${img.attributes['alt'] ?? ''} ${img.attributes['title'] ?? ''}'
            .toLowerCase();
    final path = Uri.tryParse(src)?.path.toLowerCase() ?? '';
    final width = double.tryParse(img.attributes['width'] ?? '');
    final height = double.tryParse(img.attributes['height'] ?? '');
    final tiny = width != null &&
        height != null &&
        width > 0 &&
        height > 0 &&
        width <= 32 &&
        height <= 32;
    if (RegExp(r'emoji|emoticon|smiley|twemoji').hasMatch(marker) ||
        RegExp(r'/(?:emoji|emojis|smilies|smileys|emoticons|twemoji)/')
            .hasMatch(path) ||
        RegExp(r'^:[\w+-]+:$').hasMatch(img.attributes['alt'] ?? '') ||
        tiny) continue;
    var full = img.attributes['data-original-src'] ??
        img.attributes['data-original'] ??
        src;
    for (var parent = img.parent; parent != null; parent = parent.parent) {
      if (parent.localName == 'a') {
        final href = parent.attributes['href'];
        if (href != null &&
            (parent.classes.contains('lightbox') ||
                RegExp(r'\.(png|jpe?g|gif|webp|avif)(?:[?#]|$)',
                        caseSensitive: false)
                    .hasMatch(href))) full = href;
        break;
      }
    }
    final target = base.resolve(full);
    if (target.scheme == 'https')
      result[base.resolve(src).toString()] = target.toString();
  }
  return result;
}

Future<void> previewImage(BuildContext context, String url,
    {List<String> images = const []}) {
  final urls = [...images, url].toSet().toList();
  return showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => _Gallery(urls, urls.indexOf(url)));
}

class _Gallery extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const _Gallery(this.urls, this.initial);
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final cache = GalleryImageCache();
  late final PageController pages = PageController(initialPage: widget.initial);
  late int index = widget.initial;
  bool zoomed = false;
  bool saving = false;
  String? saveMessage;
  Future<void> save(String url) async {
    if (saving) return;
    setState(() {
      saving = true;
      saveMessage = null;
    });
    try {
      final bytes = await cache.load(url);
      if (!mounted) return;
      final destination = await Session.channel
          .invokeMethod<String>('saveImage', {'bytes': bytes});
      if (mounted)
        setState(() =>
            saveMessage = destination == null ? '已取消保存' : '图片已保存到$destination');
    } catch (_) {
      if (mounted) setState(() => saveMessage = '保存失败，请检查存储空间后重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> imageMenu(String url) async {
    if (saving) return;
    final accepted = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
            child: ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const UiText('保存原图到本地'),
                onTap: () => Navigator.pop(c, true))));
    if (accepted == true && mounted) await save(url);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
          child: Stack(children: [
        Positioned.fill(
            child: PageView.builder(
                controller: pages,
                itemCount: widget.urls.length,
                physics: zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (i) => setState(() {
                      index = i;
                      zoomed = false;
                    }),
                itemBuilder: (_, i) => _ZoomImage(widget.urls[i],
                    onLongPress: () => imageMenu(widget.urls[i]),
                    cache: cache,
                    key: ValueKey(widget.urls[i]),
                    active: i == index,
                    onZoom: (value) {
                      if (i == index && value != zoomed)
                        setState(() => zoomed = value);
                    }))),
        Positioned(
            top: 8,
            left: 16,
            child: Text('${index + 1} / ${widget.urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15))),
        Positioned(
            top: 0,
            right: 8,
            child: IconButton(
                tooltip: uiTr(context, '关闭图片'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white))),
        Positioned(
            top: 0,
            right: 56,
            child: IconButton(
                tooltip: uiTr(context, saving ? '正在保存' : '保存原图'),
                onPressed: saving ? null : () => save(widget.urls[index]),
                icon: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download_outlined,
                        color: Colors.white))),
        if (saveMessage != null)
          Positioned(
              bottom: 70,
              left: 16,
              right: 16,
              child: Center(
                  child: Container(
                      padding: const EdgeInsets.all(10),
                      color: Colors.black87,
                      child: Text(saveMessage!,
                          style: const TextStyle(color: Colors.white))))),
        Positioned(
            bottom: 12,
            left: 8,
            right: 8,
            child: Row(children: [
              IconButton(
                  tooltip: uiTr(context, '上一张'),
                  onPressed: index == 0
                      ? null
                      : () => pages.previousPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut),
                  icon: Icon(Icons.chevron_left,
                      color: index == 0 ? Colors.white24 : Colors.white)),
              Expanded(
                  child: UiText(zoomed ? '双击还原后可左右滑动' : '左右滑动切换 · 双指或双击缩放',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12))),
              IconButton(
                  tooltip: uiTr(context, '下一张'),
                  onPressed: index == widget.urls.length - 1
                      ? null
                      : () => pages.nextPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut),
                  icon: Icon(Icons.chevron_right,
                      color: index == widget.urls.length - 1
                          ? Colors.white24
                          : Colors.white))
            ]))
      ])));
}

class _ZoomImage extends StatefulWidget {
  final VoidCallback onLongPress;
  final GalleryImageCache cache;
  final bool active;
  final String url;
  final ValueChanged<bool> onZoom;
  const _ZoomImage(this.url,
      {super.key,
      required this.onLongPress,
      required this.cache,
      required this.onZoom,
      required this.active});
  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  bool zoomed = false;
  late Future<Uint8List> bytes = widget.cache.load(widget.url);
  final transform = TransformationController();
  @override
  void initState() {
    super.initState();
    transform.addListener(changed);
  }

  void changed() {
    final next = transform.value.getMaxScaleOnAxis() > 1.01;
    if (next != zoomed) {
      setState(() => zoomed = next);
      widget.onZoom(next);
    }
  }

  @override
  void didUpdateWidget(covariant _ZoomImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active)
      transform.value = Matrix4.identity();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
      future: bytes,
      initialData: widget.cache.peek(widget.url),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const UiText('图片加载失败', style: TextStyle(color: Colors.white)),
            TextButton(
                onPressed: () =>
                    setState(() => bytes = widget.cache.load(widget.url)),
                child: const UiText('重试'))
          ]));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return GestureDetector(
            onLongPress: widget.onLongPress,
            onDoubleTap: () => transform.value =
                transform.value.getMaxScaleOnAxis() > 1.01
                    ? Matrix4.identity()
                    : (Matrix4.identity()..scaleByDouble(2, 2, 1, 1)),
            child: InteractiveViewer(
                transformationController: transform,
                minScale: 1,
                maxScale: 6,
                panEnabled: transform.value.getMaxScaleOnAxis() > 1.01,
                child: Center(
                    child: Image.memory(snapshot.data!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, e, s) => const UiText('无法解码图片',
                            style: TextStyle(color: Colors.white))))));
      });
}

/// Scoped to one open gallery. Bound retained compressed bytes to 64 MiB.
class GalleryImageCache {
  final Future<Uint8List> Function(String) fetch;
  final int maxBytes;
  GalleryImageCache(
      {Future<Uint8List> Function(String)? fetch,
      this.maxBytes = 64 * 1024 * 1024})
      : fetch = fetch ?? AvatarLoader.image;
  final _ready = LinkedHashMap<String, Uint8List>();
  final _pending = <String, Future<Uint8List>>{};
  int size = 0;
  Uint8List? peek(String url) => _ready[url];
  Future<Uint8List> load(String url) {
    final bytes = _ready.remove(url);
    if (bytes != null) {
      _ready[url] = bytes;
      return Future.value(bytes);
    }
    return _pending[url] ??= _load(url);
  }

  Future<Uint8List> _load(String url) async {
    try {
      final bytes = await Future.sync(() => fetch(url));
      _ready[url] = bytes;
      size += bytes.length;
      while (_ready.length > 1 && (size > maxBytes || _ready.length > 24)) {
        size -= _ready.remove(_ready.keys.first)!.length;
      }
      return bytes;
    } finally {
      _pending.remove(url);
    }
  }
}
