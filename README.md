# V2DO

V2DO 是一个使用 Flutter 开发的 V2EX 与 LINUX DO 第三方客户端，界面以 Android 为优先。它与两个论坛均无官方关联。

## 界面预览

以下为 Android 开发版实机截图，展示 V2EX 节点和搜索；部分功能可能尚未包含在当前仓库代码或发布包中。

<img src="docs/screenshots/node.png" alt="V2EX 节点列表" width="270"> <img src="docs/screenshots/search.png" alt="V2EX 搜索" width="270">

## 功能

- 浏览主题、节点与分类，查看正文、回复和图片，发帖与回帖。
- 回复排序、只看楼主、楼中楼展示及折叠；支持站点所提供的回复关系。
- 个人资料、收藏、消息、浏览记录；支持 V2EX 签到和余额记录。
- LINUX DO 帖子搜索；V2EX 支持应用内节点和用户建议，暂不支持帖子全文搜索。
- LINUX DO 图片上传；V2EX 编辑器支持登录 Imgur 后上传图片。
- 主题颜色与深浅模式、图片预览与保存、启动论坛选择。

部分功能需要登录或论坛授予相应权限。WebView 用于登录与网站验证；论坛页面解析及非公开接口可能随网站调整失效。Imgur 网页登录不支持 Google 登录，需要使用账号密码。

## 平台状态

Android 已构建并在设备上测试。iOS 尚无工程和平台接口实现，不能运行或发布。

## 构建与测试

已使用 Flutter 3.47.9、Dart 3.13.7 和 Android SDK 36 构建。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Android release 构建从环境变量 `V2DO_KEYSTORE`、`V2DO_STORE_PASSWORD`、`V2DO_KEY_PASSWORD` 和 `V2DO_KEY_ALIAS` 读取签名配置。密钥和密码不得提交到仓库，应由维护者妥善备份。Debug 与正式包使用不同应用 ID 和签名，可以并存；登录状态和本地数据互不共享。

应用内 GitHub Releases 更新检查需要构建时配置 `--dart-define=GITHUB_REPOSITORY=用户名/仓库名`；未配置时不会检查更新。

项目的第三方依赖、论坛标识及图标素材的许可和使用条件需要在公开发布前逐项核实。源代码许可证待项目维护者确定。


