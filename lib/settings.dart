import 'imgur_session.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'site_view.dart';
import 'ui_text.dart';

const appVersion = String.fromEnvironment(
  'V2DO_VERSION_OVERRIDE',
  defaultValue: '0.20.15',
);
const githubRepository = String.fromEnvironment('GITHUB_REPOSITORY');

class AppPreferences extends ChangeNotifier {
  static final instance = AppPreferences();
  static const channel = MethodChannel('dualforum/session');
  ThemeMode mode = ThemeMode.system;
  int accent = 0xff27675d;
  bool autoUpdate = true;
  bool echEnabled = false;
  String language = 'zh';
  int startForum = 0;
  int fontSize = 1;
  double get fontScale => const [0.9, 1.0, 1.15, 1.3][fontSize];
  int lastUpdateCheck = 0;
  Future<void> load() async {
    try {
      final data =
          await channel.invokeMapMethod<String, dynamic>('getPreferences') ??
              {};
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == data['theme'],
        orElse: () => ThemeMode.system,
      );
      accent = (data['accent'] as int? ?? accent) & 0xffffffff;
      autoUpdate = data['autoUpdate'] as bool? ?? true;
      echEnabled = data['echEnabled'] as bool? ?? false;
      language = data['language'] == 'en' ? 'en' : 'zh';
      UiLanguage.current = language;
      startForum = data['startForum'] == 1 ? 1 : 0;
      final size = data['fontSize'];
      fontSize = size is int && size >= 0 && size <= 3 ? size : 1;
      lastUpdateCheck = data['lastUpdateCheck'] as int? ?? 0;
    } on PlatformException {
      /* Use defaults when local storage is unavailable. */
    } on MissingPluginException {
      /* Other platforms require a storage bridge. */
    }
  }

  Future<void> save() async {
    UiLanguage.current = language;
    await channel.invokeMethod<void>('setPreferences', {
      'theme': mode.name,
      'accent': accent,
      'autoUpdate': autoUpdate,
      'echEnabled': echEnabled,
      'language': language,
      'startForum': startForum,
      'fontSize': fontSize,
      'lastUpdateCheck': lastUpdateCheck,
    });
    notifyListeners();
  }
}

class ReleaseInfo {
  final String version, notes;
  final Uri page;
  final List<dynamic> assets;
  const ReleaseInfo(this.version, this.notes, this.page, this.assets);
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
      Uri.https(
        'api.github.com',
        '/repos/$githubRepository/releases/latest',
      ),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'V2DO/$appVersion',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 15));
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
    return ReleaseInfo(
      version,
      data['body'] as String? ?? '',
      page,
      data['assets'] as List<dynamic>? ?? [],
    );
  }

  static Map<String, dynamic> selectAsset(
    ReleaseInfo release,
    List<String> abis,
  ) {
    final version = release.version.replaceFirst(RegExp(r'^v'), '');
    for (final abi in [...abis, 'universal']) {
      if (!['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'].contains(abi))
        continue;
      final name = 'V2DO-$version-$abi.apk';
      for (final asset in release.assets) {
        if (asset is! Map || asset['name'] != name) continue;
        final url = Uri.tryParse(
          asset['browser_download_url'] as String? ?? '',
        );
        final digest = asset['digest'] as String? ?? '';
        final size = asset['size'];
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.path !=
                '/$githubRepository/releases/download/${release.version}/$name' ||
            url.hasQuery ||
            url.hasFragment ||
            !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest) ||
            size is! int ||
            size <= 0 ||
            size > 209715200) continue;
        return {
          'url': url.toString(),
          'version': release.version,
          'digest': digest.substring(7),
          'size': size,
        };
      }
    }
    throw Exception('没有找到适合本设备且可校验的更新包');
  }

  static Future<void> check(
    BuildContext context, {
    bool automatic = false,
    @visibleForTesting Future<ReleaseInfo?> Function()? fetchRelease,
  }) async {
    final preferences = AppPreferences.instance;
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (!automatic)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: UiText('应用内更新目前仅支持 Android')));
      return;
    }
    if (busy) return;
    if (automatic &&
        (!configured ||
            !preferences.autoUpdate ||
            DateTime.now().millisecondsSinceEpoch -
                    preferences.lastUpdateCheck <
                const Duration(hours: 6).inMilliseconds)) return;
    if (!configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: UiText('尚未配置 GitHub 发布仓库，发布后即可启用更新提醒')),
      );
      return;
    }
    busy = true;
    try {
      final release = await (fetchRelease ?? latest)();
      preferences.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
      await preferences.save();
      if (!context.mounted) return;
      if (release == null) {
        if (!automatic)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: UiText('当前已是最新正式版本')));
        return;
      }
      final device = await AppPreferences.channel
          .invokeMapMethod<String, dynamic>('updateDevice');
      if (device?['supported'] != true) {
        if (!automatic && context.mounted) throw Exception('仅正式版支持应用内更新');
        return;
      }
      final asset = selectAsset(
        release,
        (device!['abis'] as List).cast<String>(),
      );
      if (!context.mounted) return;
      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: UiText('发现新版本 ${release.version}'),
          content: SingleChildScrollView(
            child: UiText(
              release.notes.trim().isEmpty
                  ? '是否下载并安装新版本？'
                  : '${release.notes.trim()}\n\n是否下载并安装新版本？',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const UiText('暂不更新'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const UiText('下载更新'),
            ),
          ],
        ),
      );
      if (shouldDownload != true || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(minutes: 5),
          content: UiText('正在下载 ${release.version}，请稍候…'),
        ),
      );
      final status = await AppPreferences.channel.invokeMethod<String>(
        'installUpdate',
        asset,
      );
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      if (status == 'permission') {
        final open = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const UiText('允许安装更新'),
            content: const UiText('Android 需要允许 V2DO 安装应用。开启后返回应用，再点击检查更新。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const UiText('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const UiText('前往设置'),
              ),
            ],
          ),
        );
        if (open == true)
          await AppPreferences.channel.invokeMethod<void>(
            'updateInstallPermission',
          );
      } else {
        messenger.showSnackBar(
          const SnackBar(content: UiText('更新包已下载，正在安装；如系统要求，请确认安装。')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      busy = false;
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool checkingEch = false;
  Map<String, dynamic>? echResult;
  DateTime? echCheckedAt;

  Future<void> checkEch() async {
    if (checkingEch) return;
    setState(() => checkingEch = true);
    Map<String, dynamic>? result;
    try {
      result = await AppPreferences.channel
          .invokeMapMethod<String, dynamic>('echCheck')
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    setState(() {
      echResult = result ?? {'www.v2ex.com': false, 'linux.do': false};
      echCheckedAt = DateTime.now();
      checkingEch = false;
    });
  }

  void showEchDetails() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const UiText('检测详情'),
        content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const UiText('检测地址'),
                const SizedBox(height: 6),
                const SelectableText(
                    'https://www.v2ex.com/cdn-cgi/trace\nhttps://linux.do/cdn-cgi/trace'),
                const SizedBox(height: 12),
                const UiText(
                    '安全 DNS：Google、Cloudflare、阿里。查询论坛域名的 HTTPS 和 A 记录，尝试通过 ECH 连接。'),
                const SizedBox(height: 12),
                const UiText(
                    '成功条件：加密握手成功，诊断地址返回 HTTP 200 和 sni=encrypted。检测不使用论坛账号。'),
                const SizedBox(height: 12),
                const UiText('检测成功不代表所有页面均可访问；登录验证网页使用原有网络连接。'),
              ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const UiText('知道了'),
          ),
        ],
      ),
    );
  }

  Widget echCard(BuildContext context, AppPreferences prefs) {
    final scheme = Theme.of(context).colorScheme;
    Widget status(String name, String host) {
      final bool? success = echResult?[host] as bool?;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$name  '),
        Icon(
            success == null
                ? Icons.remove_circle_outline
                : success
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
            size: 16,
            color: success == null
                ? scheme.outline
                : success
                    ? scheme.primary
                    : scheme.error),
        const SizedBox(width: 6),
        UiText(checkingEch
            ? '检测中…'
            : success == null
                ? '未检测'
                : success
                    ? 'ECH 连接成功'
                    : '连接失败'),
      ]);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.security_outlined),
            title: const UiText('ECH 连接'),
            value: prefs.echEnabled,
            onChanged: (value) async {
              prefs.echEnabled = value;
              await persist(context);
              if (value && mounted) checkEch();
            },
          ),
          Wrap(spacing: 16, runSpacing: 4, children: [
            status('V2EX', 'www.v2ex.com'),
            status('LINUX DO', 'linux.do'),
          ]),
          if (echCheckedAt != null) ...[
            const SizedBox(height: 4),
            Text(
                '${uiTr(context, '上次检测')} ${TimeOfDay.fromDateTime(echCheckedAt!).format(context)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          Row(children: [
            TextButton.icon(
                onPressed: checkingEch ? null : checkEch,
                icon: checkingEch
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const UiText('重新检测')),
            TextButton(onPressed: showEchDetails, child: const UiText('检测详情')),
          ]),
        ]),
      ),
    );
  }

  Future<void> resetApplication(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const UiText('重置 V2DO？'),
        content: const UiText(
          '将清除所有应用缓存、本地浏览记录、设置和未发布草稿，并退出 V2EX、LINUX DO 和 Imgur 登录。网站上的帖子、收藏及已保存到相册的图片不受影响。\n\n重置后应用会关闭，请重新打开。此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const UiText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const UiText('重置并退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await AppPreferences.channel.invokeMethod<void>('resetApplication');
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: UiText('重置失败，请重试')));
    }
  }

  static Future<void> configureImgur(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ImgurAccountPage()),
    );
  }

  Future<void> persist(BuildContext context) async {
    try {
      await AppPreferences.instance.save();
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: UiText('设置保存失败，请重试')));
    }
  }

  Widget sectionTitle(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 5),
        child: UiText(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppPreferences.instance,
        builder: (context, _) {
          final prefs = AppPreferences.instance;
          final valueStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              );
          const modes = {
            ThemeMode.system: '跟随系统',
            ThemeMode.light: '浅色',
            ThemeMode.dark: '深色',
          };
          return Scaffold(
            appBar: AppBar(title: const UiText('应用设置')),
            body: ListTileTheme(
              data: const ListTileThemeData(
                minVerticalPadding: 8,
                minLeadingWidth: 24,
                horizontalTitleGap: 12,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  sectionTitle(context, '通用'),
                  ListTile(
                      leading: const Icon(Icons.language),
                      title: const UiText('语言 / Language'),
                      trailing: UiText(
                        prefs.language == 'en' ? 'English' : '简体中文',
                        style: valueStyle,
                      ),
                      onTap: () => showDialog<void>(
                          context: context,
                          builder: (c) => SimpleDialog(
                                  title: const UiText('语言 / Language'),
                                  children: [
                                    for (final entry in const {
                                      'zh': '简体中文',
                                      'en': 'English'
                                    }.entries)
                                      SimpleDialogOption(
                                          onPressed: () async {
                                            prefs.language = entry.key;
                                            Navigator.pop(c);
                                            await persist(context);
                                          },
                                          child: Text(
                                              '${prefs.language == entry.key ? '✓  ' : ''}${entry.value}')),
                                  ]))),
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const UiText('启动时打开'),
                    trailing: Text(prefs.startForum == 0 ? 'V2EX' : 'LINUX DO',
                        style: valueStyle),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (c) => SimpleDialog(
                        title: const UiText('启动论坛'),
                        children: [
                          for (var i = 0; i < 2; i++)
                            SimpleDialogOption(
                              child: Text(
                                '${prefs.startForum == i ? '✓  ' : ''}${i == 0 ? 'V2EX' : 'LINUX DO'}',
                              ),
                              onPressed: () async {
                                prefs.startForum = i;
                                Navigator.pop(c);
                                await persist(context);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  sectionTitle(context, '网络连接'),
                  echCard(context, prefs),
                  ListTile(
                    leading: const Icon(Icons.add_photo_alternate_outlined),
                    title: const UiText('V2EX 图片上传 · Imgur'),
                    onTap: () => configureImgur(context),
                  ),
                  sectionTitle(context, '外观'),
                  ListTile(
                    leading: const Icon(Icons.brightness_6_outlined),
                    title: const UiText('颜色模式'),
                    trailing: UiText(modes[prefs.mode]!, style: valueStyle),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (c) => SimpleDialog(
                        title: const UiText('颜色模式'),
                        children: [
                          for (final entry in modes.entries)
                            SimpleDialogOption(
                              onPressed: () async {
                                prefs.mode = entry.key;
                                Navigator.pop(c);
                                await persist(context);
                              },
                              child: Text(
                                '${prefs.mode == entry.key ? '✓  ' : ''}${uiTr(context, entry.value)}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.format_size),
                    title: const UiText('字体大小'),
                    trailing: UiText(
                      const ['较小', '标准', '较大', '特大'][prefs.fontSize],
                      style: valueStyle,
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (c) => SimpleDialog(
                        title: const UiText('字体大小'),
                        children: [
                          for (var i = 0; i < 4; i++)
                            SimpleDialogOption(
                              onPressed: () async {
                                prefs.fontSize = i;
                                Navigator.pop(c);
                                await persist(context);
                              },
                              child: Text(
                                  '${prefs.fontSize == i ? '✓  ' : ''}${uiTr(context, const [
                                        '较小',
                                        '标准',
                                        '较大',
                                        '特大'
                                      ][i])}'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.palette_outlined),
                        const SizedBox(width: 12),
                        const Expanded(child: UiText('主题色')),
                        Flexible(
                          flex: 2,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 208),
                            child: Row(children: [
                              for (final entry in {
                                0xff27675d: '青绿',
                                0xff355bb3: '蓝色',
                                0xff7954a1: '紫色',
                                0xffa65627: '橙色',
                              }.entries)
                                Expanded(
                                  child: Semantics(
                                    label: uiTr(context, entry.value),
                                    selected: prefs.accent == entry.key,
                                    button: true,
                                    child: InkWell(
                                      onTap: () async {
                                        prefs.accent = entry.key;
                                        await persist(context);
                                      },
                                      child: SizedBox(
                                        height: 48,
                                        child: ExcludeSemantics(
                                          child: Center(
                                            child: CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Color(entry.key),
                                              child: prefs.accent == entry.key
                                                  ? const Icon(Icons.check,
                                                      size: 19,
                                                      color: Colors.white)
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  sectionTitle(context, '更新'),
                  ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const UiText('检查更新'),
                    subtitle: UiText(
                      AppUpdates.configured
                          ? '当前版本 $appVersion · GitHub Releases'
                          : '当前版本 $appVersion · 尚未配置发布仓库',
                    ),
                    onTap: () => AppUpdates.check(context),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_none),
                    title: const UiText('自动检查更新'),
                    value: prefs.autoUpdate,
                    onChanged: (value) async {
                      prefs.autoUpdate = value;
                      await persist(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const UiText('关于 V2DO'),
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'V2DO',
                      applicationVersion: appVersion,
                      applicationIcon: Image.asset(
                        'assets/exdo-icon.png',
                        width: 48,
                        height: 48,
                      ),
                      applicationLegalese: '第三方论坛客户端，与 V2EX、LINUX DO 官方无隶属关系。',
                      children: [
                        const UiText('使用 Flutter 构建，支持原生看帖、回复和多论坛账号管理。'),
                        if (AppUpdates.configured)
                          TextButton(
                            onPressed: () => openExternal(
                              Uri.https('github.com', '/$githubRepository'),
                            ),
                            child: const UiText('项目主页'),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: const UiText('重置应用'),
                    subtitle: const UiText('清空缓存、设置及所有登录状态'),
                    onTap: () => resetApplication(context),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
