import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'session.dart';
import 'site_view.dart';

class ImgurAccount {
  final int id;
  final String username;
  const ImgurAccount(this.id, this.username);
}

class ImgurSession {
  static String? _webId;
  static Future<String>? _loading;
  // This is Imgur's public website configuration, not an OAuth credential.
  static String websiteId(String script) {
    final export = RegExp(r'hH:\(\)=>[a-zA-Z_$][\w$]*').firstMatch(script);
    if (export == null) throw const ForumError('Imgur 网页接口已变化，暂时无法上传');
    final symbol = export.group(0)!.split('=>').last;
    final part = script.substring(
        export.end, (export.end + 2000).clamp(0, script.length));
    final value = RegExp('(?:var |,)${RegExp.escape(symbol)}="([a-f0-9]{15})"')
        .firstMatch(part)
        ?.group(1);
    if (value == null || !part.contains('imgur.com'))
      throw const ForumError('Imgur 网页接口已变化，暂时无法上传');
    return value;
  }

  static Future<String> configuration() async {
    if (_webId != null) return _webId!;
    if (_loading != null) return _loading!;
    final task = () async {
      final page = await http
          .get(Uri.https('imgur.com', '/upload'))
          .timeout(const Duration(seconds: 20));
      if (page.statusCode != 200) throw const ForumError('无法连接 Imgur，请检查网络');
      final assets = html.parse(page.body).querySelectorAll('script[src]').map(
          (e) => Uri.https('imgur.com', '/').resolve(e.attributes['src']!));
      final asset = assets
          .where((u) =>
              u.scheme == 'https' &&
              u.host == 's.imgur.com' &&
              u.path.startsWith('/desktop-assets/js/main.') &&
              u.path.endsWith('.js'))
          .firstOrNull;
      if (asset == null) throw const ForumError('Imgur 网页接口已变化，暂时无法上传');
      final script = await http.get(asset).timeout(const Duration(seconds: 30));
      if (script.statusCode != 200) throw const ForumError('无法加载 Imgur 上传配置');
      return _webId = websiteId(script.body);
    }();
    _loading = task;
    try {
      return await task;
    } finally {
      _loading = null;
    }
  }

  static Future<Uri> endpoint(String path) async =>
      Uri.https('api.imgur.com', path, {'client_id': await configuration()});
  static Future<void> logout() async {
    await Session.channel.invokeMethod<void>('clearImgurSession');
    if (await current() != null) throw const ForumError('退出状态未确认，请重试');
  }

  static Future<ImgurAccount?> current() async {
    final r = await Session.request(await endpoint('/3/account/me'), headers: {
      'Origin': 'https://imgur.com',
      'Referer': 'https://imgur.com/',
      'Accept': 'application/json'
    });
    if ([401, 403].contains(r.status)) return null;
    final d = decodeResponse(r);
    if (d['success'] != true ||
        d['data']?['id'] is! int ||
        d['data']?['url'] is! String) throw const ForumError('无法确认 Imgur 登录状态');
    return ImgurAccount(d['data']['id'] as int, d['data']['url'] as String);
  }

  static String uploadedLink(ForumResponse r, ImgurAccount account) {
    if ([401, 403, 429].contains(r.status))
      throw const ForumError('Imgur 登录已失效、需要验证或达到上传限制；请打开登录页检查，草稿已保留');
    dynamic data;
    try {
      data = jsonDecode(r.body);
    } catch (_) {
      throw const ForumError('Imgur 返回异常，上传结果未确认，请勿重复上传');
    }
    final image = data['data'];
    if (r.status != 200 || data['success'] != true || image is! Map)
      throw const ForumError('Imgur 上传未成功，可能需要验证或图片不符合要求');
    if (image['account_id'] != account.id)
      throw const ForumError('Imgur 未确认图片归属当前账号，未自动插入；请到网页核对，勿重复上传');
    final link = Uri.tryParse(image['link']?.toString() ?? '');
    if (link == null || link.scheme != 'https' || link.host != 'i.imgur.com')
      throw const ForumError('Imgur 未返回有效图片地址');
    return link.toString();
  }

  static Future<bool> connect(BuildContext context) async {
    return await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => const _ImgurLoginPage())) ??
        false;
  }
}

class _ImgurLoginPage extends StatefulWidget {
  const _ImgurLoginPage();
  @override
  State<_ImgurLoginPage> createState() => _ImgurLoginPageState();
}

class _ImgurLoginPageState extends State<_ImgurLoginPage> {
  bool checking = false;
  String? error;
  Future<void> finish() async {
    setState(() {
      checking = true;
      error = null;
    });
    try {
      final account = await ImgurSession.current();
      if (!mounted) return;
      if (account != null) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => error = '尚未确认 Imgur 登录成功。请完成账号密码登录；Google 登录暂不支持。');
    } catch (e) {
      if (mounted) setState(() => error = '账号验证失败：$e');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Imgur · 登录'), actions: [
          TextButton(
              onPressed: checking ? null : finish,
              child: Text(checking ? '验证中…' : '完成')),
        ]),
        body: SafeArea(
            child: Column(children: [
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Google 不允许在应用内嵌网页（WebView）中登录，因此这里无法直接使用 Google 登录。请使用 Imgur 账号和密码登录；外部浏览器的登录状态无法同步到 V2DO。')),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          Expanded(
              child: SiteView(Uri.https('imgur.com', '/signin'),
                  imgurLogin: true)),
        ])),
      );
}

class ImgurAccountPage extends StatefulWidget {
  final Future<ImgurAccount?> Function()? checkAccount;
  final Future<void> Function()? logout;
  const ImgurAccountPage({super.key, this.checkAccount, this.logout});
  @override
  State<ImgurAccountPage> createState() => _ImgurAccountPageState();
}

class _ImgurAccountPageState extends State<ImgurAccountPage> {
  Future<ImgurAccount?> check() =>
      (widget.checkAccount?.call() ?? ImgurSession.current()).timeout(
          const Duration(seconds: 40),
          onTimeout: () => throw const ForumError('Imgur 登录状态检查超时，请刷新重试'));
  late Future<ImgurAccount?> state = check();
  bool signingOut = false;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Imgur 图片上传')),
      body: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('网页登录上传',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                    '请使用 Imgur 账号和密码登录。Google 不允许在应用内嵌网页（WebView）中进行 Google 登录，因此这里无法直接使用“使用 Google 登录”。登录成功后可在原生编辑器选图并确认上传。网站改版或要求验证时可能不可用。'),
                const SizedBox(height: 20),
                FutureBuilder<ImgurAccount?>(
                    future: state,
                    builder: (c, s) {
                      final waiting = s.connectionState != ConnectionState.done;
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (waiting)
                              const Row(children: [
                                SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                SizedBox(width: 10),
                                Expanded(child: Text('正在检查 Imgur 登录状态…'))
                              ])
                            else
                              Text(s.hasError
                                  ? '${s.error}'
                                  : s.data == null
                                      ? '尚未连接 Imgur 账号'
                                      : '已登录：${s.data!.username}'),
                            const SizedBox(height: 12),
                            FilledButton(
                                onPressed: waiting || signingOut
                                    ? null
                                    : () async {
                                        if (s.data != null && !s.hasError) {
                                          setState(() => signingOut = true);
                                          try {
                                            await (widget.logout?.call() ??
                                                ImgurSession.logout());
                                          } catch (e) {
                                            if (context.mounted)
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                      content:
                                                          Text('退出失败：$e')));
                                          } finally {
                                            if (mounted)
                                              setState(() {
                                                signingOut = false;
                                                state = check();
                                              });
                                          }
                                          return;
                                        }
                                        try {
                                          await ImgurSession.connect(context);
                                        } catch (_) {}
                                        if (mounted)
                                          setState(() => state = check());
                                      },
                                child: Text(signingOut
                                    ? '正在退出…'
                                    : s.data != null && !s.hasError
                                        ? '退出登录'
                                        : '登录 / 验证')),
                            TextButton(
                                onPressed: waiting || signingOut
                                    ? null
                                    : () => setState(() => state = check()),
                                child: const Text('刷新状态')),
                          ]);
                    }),
              ]))));
}
