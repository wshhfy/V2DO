import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'forum.dart';
import 'main.dart' show authenticate;

class SectionPicker extends StatefulWidget {
  final Forum forum;
  const SectionPicker(this.forum, {super.key});
  @override
  State<SectionPicker> createState() => _SectionPickerState();
}

class _SectionPickerState extends State<SectionPicker> {
  late String kind = widget.forum.discourse ? 'category' : 'node';
  late Future<List<ForumSection>> future = widget.forum.sections(kind);
  String search = '';
  void change(String next) => setState(() {
        kind = next;
        future = widget.forum.sections(kind);
      });
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(children: [
            Row(children: [
              Expanded(
                  child: UiText(widget.forum.discourse ? '分类与标签' : '频道与节点',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
              TextButton(
                  onPressed: () => Navigator.pop(
                      context, const ForumSection('', '全部', 'all')),
                  child: const UiText('全部帖子')),
              IconButton(
                  tooltip: uiTr(context, '关闭'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            Wrap(children: [
              for (final entry in (widget.forum.discourse
                      ? {'category': '分类', 'tag': '标签'}
                      : {'tab': '首页频道', 'node': '全部节点', 'followed': '关注的节点'})
                  .entries)
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                        label: UiText(entry.value),
                        selected: kind == entry.key,
                        onSelected: (_) => change(entry.key))),
            ]),
            TextField(
                onChanged: (value) =>
                    setState(() => search = value.toLowerCase().trim()),
                decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: uiTr(
                        context,
                        kind == 'node' || kind == 'followed'
                            ? '搜索节点名称 / 英文名'
                            : (kind == 'tag' ? '搜索标签' : '搜索分类')))),
            const SizedBox(height: 8),
            if (widget.forum.discourse && kind == 'category')
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: UiText('仅显示当前账号可见的分类',
                          style: TextStyle(fontSize: 11)))),
            Expanded(
                child: FutureBuilder<List<ForumSection>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.hasError)
                        return Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text(snapshot.error.toString()),
                              TextButton(
                                  onPressed: () => change(kind),
                                  child: const UiText('重试')),
                              if (kind == 'followed')
                                TextButton(
                                    onPressed: () async {
                                      await authenticate(context, widget.forum);
                                      if (mounted) change(kind);
                                    },
                                    child: const UiText('登录 / 验证'))
                            ]));
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final rows = snapshot.data!
                          .where((s) => '${s.parentName} ${s.name} ${s.id}'
                              .toLowerCase()
                              .contains(search))
                          .toList();
                      if (rows.isEmpty)
                        return Center(
                            child: UiText(kind == 'followed' && search.isEmpty
                                ? '还没有关注的节点'
                                : '没有匹配的项目'));
                      return ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final section = rows[i];
                            return ListTile(
                                dense: true,
                                visualDensity:
                                    const VisualDensity(vertical: -2),
                                contentPadding: EdgeInsets.zero,
                                leading: kind == 'category'
                                    ? const Icon(Icons.folder_outlined,
                                        size: 18)
                                    : null,
                                title: Text(section.name,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: kind == 'category' &&
                                                section.parentName.isEmpty
                                            ? FontWeight.w700
                                            : FontWeight.w500)),
                                subtitle: kind == 'node'
                                    ? Text(section.id,
                                        style: const TextStyle(fontSize: 11))
                                    : section.parentName.isNotEmpty
                                        ? Text('↳ ${section.parentName}',
                                            style:
                                                const TextStyle(fontSize: 11))
                                        : null,
                                trailing: section.count > 0
                                    ? Text('${section.count}',
                                        style: const TextStyle(fontSize: 11))
                                    : null,
                                onTap: () => Navigator.pop(context, section));
                          });
                    })),
          ])));
}
