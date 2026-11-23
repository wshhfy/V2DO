import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'forum.dart';
import 'session.dart';

const threadStyles = <String, String>{
  'off': '经典平铺',
  'a': '引用条',
  'b': '角标与预览',
  'c': '楼中楼',
  'd': '树形缩进',
  'f': '对话连线',
  'h': '引用楼层'
};

class V2ThreadSettings {
  final Forum forum;
  const V2ThreadSettings(this.forum);
  Future<dom.Element> form() async {
    final r = await forum.get('/settings');
    if ([301, 302, 303].contains(r.status) && r.location.contains('signin'))
      throw const ForumError('请先登录 V2EX', needsLogin: true);
    checkResponse(r);
    final doc = html.parse(r.body);
    if (doc.querySelector('input[type="password"]') != null)
      throw const ForumError('请先登录 V2EX', needsLogin: true);
    final input = doc.querySelector('input[name="reply_thread_style"]');
    var f = input?.parent;
    while (f != null && f.localName != 'form') {
      f = f.parent;
    }
    if (f == null ||
        f.attributes['action'] != '/settings' ||
        (f.attributes['method'] ?? '').toLowerCase() != 'post')
      throw const ForumError('网站设置格式发生变化，请稍后重试');
    return f;
  }

  String selected(dom.Element f) {
    final value = f
        .querySelector('input[name="reply_thread_style"][checked]')
        ?.attributes['value'];
    if (!threadStyles.containsKey(value)) throw const ForumError('无法确认当前回复样式');
    return value!;
  }

  Future<String> read() async => selected(await form());
  Future<String> update(String style) async {
    if (!threadStyles.containsKey(style)) throw const ForumError('无效的回复样式');
    final f = await form();
    if (selected(f) == style) return style;
    final fields = <MapEntry<String, String>>[];
    var tokenFound = false, optionFound = false;
    for (final e in f.querySelectorAll('input,textarea,select')) {
      final name = e.attributes['name'];
      if (name == null || e.attributes.containsKey('disabled')) continue;
      final type = (e.attributes['type'] ?? '').toLowerCase();
      if (name == 'reply_thread_style') {
        if (e.attributes['value'] == style) optionFound = true;
        continue;
      }
      if (['submit', 'button', 'file', 'reset', 'image'].contains(type))
        continue;
      if ((type == 'checkbox' || type == 'radio') &&
          !e.attributes.containsKey('checked')) continue;
      if (name == 'once') tokenFound = (e.attributes['value'] ?? '').isNotEmpty;
      if (e.localName == 'select') {
        final options = e.querySelectorAll('option');
        final chosen =
            options.where((o) => o.attributes.containsKey('selected')).toList();
        if (chosen.isEmpty && options.isNotEmpty) chosen.add(options.first);
        for (final o in chosen) {
          if (!o.attributes.containsKey('disabled'))
            fields.add(MapEntry(name, o.attributes['value'] ?? o.text));
        }
      } else {
        fields.add(MapEntry(
            name,
            e.localName == 'textarea'
                ? e.text
                : e.attributes['value'] ??
                    ((type == 'checkbox' || type == 'radio') ? 'on' : '')));
      }
    }
    if (!tokenFound || !optionFound) throw const ForumError('设置表单不完整，请刷新后重试');
    fields.add(MapEntry('reply_thread_style', style));
    final body = fields
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    try {
      final r = await forum.transport(forum.url('/settings'),
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Origin': 'https://${forum.host}',
            'Referer': forum.url('/settings').toString()
          },
          body: body);
      if (![200, 302, 303].contains(r.status)) checkResponse(r);
      final verified = await read();
      if (verified != style) throw const ForumError('网站未确认修改，请刷新后核对');
      return verified;
    } catch (_) {
      // A dropped response may still have saved; only read back, never repeat POST.
      try {
        if (await read() == style) return style;
      } catch (_) {}
      throw const ForumError('修改结果未确认，请刷新后核对');
    }
  }
}

class V2ThreadSettingsPage extends StatefulWidget {
  final Forum forum;
  const V2ThreadSettingsPage(this.forum, {super.key});
  @override
  State<V2ThreadSettingsPage> createState() => _V2ThreadSettingsPageState();
}

class _V2ThreadSettingsPageState extends State<V2ThreadSettingsPage> {
  String? current, error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final v = await V2ThreadSettings(widget.forum).read();
      if (mounted) setState(() => current = v);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(String value) async {
    if (busy || value == current) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final v = await V2ThreadSettings(widget.forum).update(value);
      if (mounted) setState(() => current = v);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const UiText('V2EX 回复样式'), actions: [
        IconButton(
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh),
            tooltip: uiTr(context, '刷新'))
      ]),
      body: ListView(children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: UiText(
                '同步到 V2EX 网站设置；网页端和其他设备也会使用此选项。下方为官网样式示意图，点击图片放大；V2DO 移动端的展示不保证与官网完全相同。')),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: UiText(error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        for (final item in threadStyles.entries)
          Card(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                        title: UiText(item.value),
                        trailing: current == item.key
                            ? Icon(Icons.check,
                                color: Theme.of(context).colorScheme.primary)
                            : null,
                        enabled: !busy && current != null,
                        onTap: () => change(item.key)),
                    if (item.key != 'off')
                      Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: InkWell(
                              onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (c) => Dialog(
                                          child: Stack(children: [
                                        InteractiveViewer(
                                            minScale: 1,
                                            maxScale: 5,
                                            child: Center(
                                                child: Image.asset(
                                                    'assets/reply_styles/${item.key}.png',
                                                    fit: BoxFit.contain))),
                                        Positioned(
                                            right: 0,
                                            top: 0,
                                            child: IconButton(
                                                tooltip: uiTr(context, '关闭图片'),
                                                icon: const Icon(Icons.close),
                                                onPressed: () =>
                                                    Navigator.pop(c)))
                                      ]))),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                      height: 130,
                                      color: Colors.grey.shade200,
                                      child: Image.asset(
                                          'assets/reply_styles/${item.key}.png',
                                          fit: BoxFit.cover,
                                          alignment: Alignment.topCenter,
                                          semanticLabel:
                                              '${item.value}官网示意图'))))),
                  ])),
      ]));
}
