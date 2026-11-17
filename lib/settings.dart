import 'imgur_session.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'site_view.dart';

const appVersion = '0.20.9';
const githubRepository = String.fromEnvironment('GITHUB_REPOSITORY');

class AppPreferences extends ChangeNotifier {
  static final instance = AppPreferences();
  static const channel = MethodChannel('dualforum/session');
  ThemeMode mode = ThemeMode.system;
  int accent = 0xff27675d;
  bool autoUpdate = true;
  int startForum = 0;
  int lastUpdateCheck = 0;
  Future<void> load() async {
    try {
      final data =
          await channel.invokeMapMethod<String, dynamic>('getPreferences') ??
              {};
      mode = ThemeMode.values.firstWhere((m) => m.name == data['theme'],
          orElse: () => ThemeMode.system);
      accent = (data['accent'] as int? ?? accent) & 0xffffffff;
      autoUpdate = data['autoUpdate'] as bool? ?? true;
      startForum = data['startForum'] == 1 ? 1 : 0;
      lastUpdateCheck = data['lastUpdateCheck'] as int? ?? 0;
    } on PlatformException {
      /* Use defaults when local storage is unavailable. */
    } on MissingPluginException {
      /* Other platforms require a storage bridge. */
    }
  }

  Future<void> save() async {
    await channel.invokeMethod<void>('setPreferences', {
      'theme': mode.name,
      'accent': accent,
      'autoUpdate': autoUpdate,
      'startForum': startForum,
      'lastUpdateCheck': lastUpdateCheck
    });
    notifyListeners();
  }
}

class ReleaseInfo {
  final String version, notes;
  final Uri page;
  const ReleaseInfo(this.version, this.notes, this.page);
}

class AppUpdates {
  static bool busy = false;
  static bool get configured =>
      RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(githubRepository);
  static bool newer(String candidate, String installed) {
    List<int>? parts(String s) {
      final match =
          RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$').firstMatch(s.trim());
      return match == null
          ? null
          : [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
    }

    final a = parts(candidate), b = parts(installed);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static Future<ReleaseInfo?> latest() async {
    if (!configured) throw Exception('尚未配置发布仓库');
    final response = await http.get(
        Uri.https('api.github.com', '/repos/$githubRepository/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'V2DO/$appVersion',
          'X-GitHub-Api-Version': '2022-11-28'
        }).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) throw Exception('仓库尚无公开正式版本');
    if (response.statusCode == 403 || response.statusCode == 429)
      throw Exception('GitHub 请求受限，请稍后再试');
    if (response.statusCode != 200)
      throw Exception('检查更新失败（${response.statusCode}）');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['draft'] == true || data['prerelease'] == true) return null;
    final version = data['tag_name'] as String? ?? '';
    if (!RegExp(r'^v?\d+\.\d+\.\d+(?:\+\d+)?$').hasMatch(version))
      throw Exception('发布版本号格式无法识别');
    if (!newer(version, appVersion)) return null;
    final page = Uri.tryParse(data['html_url'] as String? ?? '');
    if (page == null ||
        page.scheme != 'https' ||
        page.host != 'github.com' ||
        !page.path.startsWith('/$githubRepository/releases/'))
      throw Exception('发布地址无效');
    return ReleaseInfo(version, data['body'] as String? ?? '', page);
  }

  static Future<void> check(BuildContext context,
      {bool automatic = false}) async {
    final preferences = AppPreferences.instance;
    if (busy) return;
    if (automatic &&
        (!configured ||
            !preferences.autoUpdate ||
            DateTime.now().millisecondsSinceEpoch -
                    preferences.lastUpdateCheck <
                const Duration(hours: 6).inMilliseconds)) return;
    if (!configured) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('尚未配置 GitHub 发布仓库，发布后即可启用更新提醒')));
      return;
    }
    busy = true;
    try {
      preferences.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
      await preferences.save();
      final release = await latest();
      if (!context.mounted) return;
      if (release == null) {
        if (!automatic)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('当前已是最新正式版本')));
        return;
      }
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text('发现新版本 ${release.version}'),
                  content: SingleChildScrollView(
                      child: Text(release.notes.isEmpty
                          ? '可前往 GitHub 查看并下载新版。'
                          : release.notes)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('稍后')),
                    FilledButton(
                        onPressed: () {
                          Navigator.pop(c);
                          openExternal(release.page);
                        },
                        child: const Text('查看并下载'))
                  ]));
    } catch (e) {
      if (!automatic && context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      busy = false;
    }
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  Future<void> resetApplication(BuildContext context) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('重置 V2DO？'),
                content: const Text(
                    '将清除所有应用缓存、本地浏览记录、设置和未发布草稿，并退出 V2EX、LINUX DO 和 Imgur 登录。网站上的帖子、收藏及已保存到相册的图片不受影响。\n\n重置后应用会关闭，请重新打开。此操作无法撤销。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('重置并退出')),
                ]));
    if (confirmed != true || !context.mounted) return;
    try {
      await AppPreferences.channel.invokeMethod<void>('resetApplication');
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('重置失败，请重试')));
    }
  }

  static Future<void> configureImgur(BuildContext context) async {
    await Navigator.push(context,
        MaterialPageRoute<void>(builder: (_) => const ImgurAccountPage()));
  }

  Future<void> persist(BuildContext context) async {
    try {
      await AppPreferences.instance.save();
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置保存失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) {
        final prefs = AppPreferences.instance;
        const modes = {
          ThemeMode.system: '跟随系统',
          ThemeMode.light: '浅色',
          ThemeMode.dark: '深色'
        };
        return Scaffold(
            appBar: AppBar(title: const Text('应用设置')),
            body: ListView(children: [
              ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('启动时打开'),
                  subtitle: Text(prefs.startForum == 0 ? 'V2EX' : 'LINUX DO'),
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (c) =>
                          SimpleDialog(title: const Text('启动论坛'), children: [
                            for (var i = 0; i < 2; i++)
                              SimpleDialogOption(
                                  child: Text(
                                      '${prefs.startForum == i ? '✓  ' : ''}${i == 0 ? 'V2EX' : 'LINUX DO'}'),
                                  onPressed: () async {
                                    prefs.startForum = i;
                                    Navigator.pop(c);
                                    await persist(context);
                                  })
                          ]))),
              ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('V2EX 图片上传 · Imgur'),
                  subtitle: const Text('登录后原生上传'),
                  onTap: () => configureImgur(context)),
              ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('颜色模式'),
                  subtitle: Text(modes[prefs.mode]!),
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (c) =>
                          SimpleDialog(title: const Text('颜色模式'), children: [
                            for (final entry in modes.entries)
                              SimpleDialogOption(
                                  onPressed: () async {
                                    prefs.mode = entry.key;
                                    Navigator.pop(c);
                                    await persist(context);
                                  },
                                  child: Text(
                                      '${prefs.mode == entry.key ? '✓  ' : ''}${entry.value}'))
                          ]))),
              const ListTile(
                  leading: Icon(Icons.palette_outlined), title: Text('主题色')),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, children: [
                    for (final entry in {
                      0xff27675d: '青绿',
                      0xff355bb3: '蓝色',
                      0xff7954a1: '紫色',
                      0xffa65627: '橙色'
                    }.entries)
                      ChoiceChip(
                          label: Text(entry.value),
                          avatar: CircleAvatar(
                              radius: 8, backgroundColor: Color(entry.key)),
                          selected: prefs.accent == entry.key,
                          onSelected: (_) async {
                            prefs.accent = entry.key;
                            await persist(context);
                          })
                  ])),
              const Divider(),
              ListTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: const Text('检查更新'),
                  subtitle: Text(AppUpdates.configured
                      ? '当前版本 $appVersion · GitHub Releases'
                      : '当前版本 $appVersion · 尚未配置发布仓库'),
                  onTap: () => AppUpdates.check(context)),
              SwitchListTile(
                  secondary: const Icon(Icons.notifications_none),
                  title: const Text('自动检查更新'),
                  subtitle: const Text('打开应用时检查，每 6 小时最多一次'),
                  value: prefs.autoUpdate,
                  onChanged: (value) async {
                    prefs.autoUpdate = value;
                    await persist(context);
                  }),
              const Divider(),
              ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 V2DO'),
                  subtitle: const Text('版本 $appVersion'),
                  onTap: () => showAboutDialog(
                          context: context,
                          applicationName: 'V2DO',
                          applicationVersion: appVersion,
                          applicationIcon: Image.asset('assets/exdo-icon.png',
                              width: 48, height: 48),
                          applicationLegalese:
                              '第三方论坛客户端，与 V2EX、LINUX DO 官方无隶属关系。',
                          children: [
                            const Text('使用 Flutter 构建，支持原生看帖、回复和多论坛账号管理。'),
                            if (AppUpdates.configured)
                              TextButton(
                                  onPressed: () => openExternal(Uri.https(
                                      'github.com', '/$githubRepository')),
                                  child: const Text('项目主页'))
                          ])),
              ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('重置应用'),
                  subtitle: const Text('清空缓存、设置及所有登录状态'),
                  onTap: () => resetApplication(context)),
            ]));
      });
}
