import 'ui_text.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<bool> openExternal(Uri uri) async {
  if (!['http', 'https'].contains(uri.scheme)) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class SiteView extends StatefulWidget {
  final Uri initialUrl;
  final bool imgurLogin;
  const SiteView(this.initialUrl, {super.key, this.imgurLogin = false});
  @override
  State<SiteView> createState() => _SiteViewState();
}

class _SiteViewState extends State<SiteView> {
  late final WebViewController controller;
  int progress = 0;
  String? error;
  late Uri currentUrl = widget.initialUrl;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => error = null);
        },
        onUrlChange: (change) {
          final uri = Uri.tryParse(change.url ?? '');
          if (mounted && uri != null && ['http', 'https'].contains(uri.scheme))
            setState(() => currentUrl = uri);
        },
        onWebResourceError: (failure) {
          if (mounted && failure.isForMainFrame == true)
            setState(() => error = '网页加载失败，请重试或用浏览器打开');
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || !['https', 'http'].contains(uri.scheme))
            return NavigationDecision.prevent;
          if (widget.imgurLogin && uri.host == 'accounts.google.com') {
            if (mounted)
              setState(() => error =
                  '当前网页登录方案不支持 Google 登录。请返回使用 Imgur 账号密码；在外部浏览器登录也不能同步账号到 V2DO。');
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(widget.initialUrl);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Row(children: [
              IconButton(
                  tooltip: uiTr(context, '网页后退'),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (await controller.canGoBack()) await controller.goBack();
                  }),
              Expanded(
                  child:
                      Text(currentUrl.host, overflow: TextOverflow.ellipsis)),
              IconButton(
                  tooltip: uiTr(context, '网页首页'),
                  icon: const Icon(Icons.home_outlined),
                  onPressed: () => controller.loadRequest(widget.initialUrl)),
              IconButton(
                  tooltip: uiTr(context, '刷新网页'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() => error = null);
                    controller.reload();
                  }),
              IconButton(
                  tooltip: uiTr(context, '用浏览器打开'),
                  icon: const Icon(Icons.open_in_browser),
                  onPressed: () => openExternal(currentUrl)),
            ])),
        if (progress < 100) LinearProgressIndicator(value: progress / 100),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: UiText(error!)),
        Expanded(child: WebViewWidget(controller: controller)),
      ]);
}

void openSite(BuildContext context, String title, Uri uri) {
  Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => Scaffold(
                appBar: AppBar(title: Text(title)),
                body: SafeArea(child: SiteView(uri)),
              )));
}
