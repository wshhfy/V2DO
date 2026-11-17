# V2DO

V2DO 是一个使用 Flutter 开发的 V2EX 与 LINUX DO 第三方客户端，界面以 Android 为优先。它与两个论坛均无官方关联。

## 功能

- 浏览主题、节点与分类，查看正文、回复和图片，发帖与回帖。
- 回复排序、只看楼主、楼中楼展示及折叠；支持站点所提供的回复关系。
- 个人资料、收藏、消息、浏览记录；支持 V2EX 签到和余额记录。
- LINUX DO 搜索；V2EX 搜索目前通过浏览器中的 Google 站内搜索。
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

当前 Android release 构建使用开发用 debug 签名，不能视为正式发布签名。公开分发前应配置并妥善保管自己的长期签名密钥；更换签名后不能直接覆盖已安装的旧版测试包。

应用内 GitHub Releases 更新检查需要构建时配置 `--dart-define=GITHUB_REPOSITORY=用户名/仓库名`；未配置时不会检查更新。

项目的第三方依赖、论坛标识及图标素材的许可和使用条件需要在公开发布前逐项核实。源代码许可证待项目维护者确定。
