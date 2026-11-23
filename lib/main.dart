import 'ui_text.dart';
import 'package:html/parser.dart' as html_parser;
import 'imgur_session.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'forum.dart';
import 'avatar.dart';
import 'account.dart';
import 'scrolling.dart';
import 'perf_probe.dart';
import 'check_in.dart';
import 'section_picker.dart';
import 'site_view.dart';
import 'settings.dart';
import 'notifications.dart';
import 'notifications_page.dart';
import 'uploads.dart';
import 'image_preview.dart';
import 'social_bar.dart';
import 'profile_page.dart';
import 'new_topic.dart';
import 'session.dart';
import 'relations_page.dart';
import 'relations.dart';
import 'recent.dart';
import 'v2_wallet.dart';
import 'v2_thread_settings.dart';
import 'v2_search.dart';

class ThreadLines extends CustomPainter {
  final List<({int from, int to, int lane, Color color})> lines;
  final int row;
  const ThreadLines(this.lines, this.row);
  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      if (row < line.from || row > line.to) continue;
      final x = 16.0 + line.lane * 5;
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      final mid = size.height / 2;
      if (row == line.from) {
        final path = Path()
          ..moveTo(42, mid)
          ..lineTo(x + 6, mid)
          ..quadraticBezierTo(x, mid, x, mid + 6)
          ..lineTo(x, size.height);
        canvas.drawPath(path, paint);
      } else if (row == line.to) {
        final path = Path()
          ..moveTo(x, 0)
          ..lineTo(x, mid - 6)
          ..quadraticBezierTo(x, mid, x + 6, mid)
          ..lineTo(42, mid);
        canvas.drawPath(path, paint);
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ThreadLines old) =>
      old.lines != lines || old.row != row;
}

class TreeReplyLines extends CustomPainter {
  final List<Post> posts;
  final int row;
  final Color color;
  const TreeReplyLines(this.posts, this.row, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (var i = 0; i < posts.length; i++) posts[i].id: i};
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var child = 0; child < posts.length; child++) {
      final parent = byId[posts[child].parentId];
      if (parent == null || parent >= child || row < parent || row > child)
        continue;
      final depth = posts[parent].threadDepth.clamp(0, 3);
      final x = 12.0 + depth * 22;
      final y1 =
          row == parent ? (size.height - 10).clamp(0.0, size.height) : 0.0;
      final y2 = row == child ? 18.0.clamp(0.0, size.height) : size.height;
      if (row == child && y2 >= y1 + 8) {
        final path = Path()
          ..moveTo(x, y1)
          ..lineTo(x, y2 - 8)
          ..quadraticBezierTo(x, y2, x + 8, y2)
          ..lineTo(x + 10, y2);
        canvas.drawPath(path, paint);
      } else if (y2 >= y1) {
        canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TreeReplyLines old) =>
      old.posts != posts || old.row != row || old.color != color;
}

List<({int from, int to, int lane, Color color})> threadLines(
    List<Post> posts) {
  final positions = {for (var i = 0; i < posts.length; i++) posts[i].id: i};
  final laneEnds = <int>[];
  final result = <({int from, int to, int lane, Color color})>[];
  for (var i = 0; i < posts.length; i++) {
    final parent = positions[posts[i].parentId];
    if (!['c', 'd', 'f'].contains(posts[i].threadStyle) ||
        parent == null ||
        parent >= i) continue;
    var lane = laneEnds.indexWhere((end) => end < parent);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(i);
    } else {
      laneEnds[lane] = i;
    }
    if (lane >= 5) lane = 4;
    var root = posts[parent].id;
    final seen = <int>{};
    while (seen.add(root)) {
      final index = positions[root];
      final ancestor = index == null ? null : posts[index].parentId;
      if (ancestor == null || !positions.containsKey(ancestor)) break;
      root = ancestor;
    }
    final colors = [
      Colors.teal,
      Colors.blue,
      Colors.deepOrange,
      Colors.purple,
      Colors.indigo
    ];
    result.add((
      from: parent,
      to: i,
      lane: lane,
      color: colors[root.abs() % colors.length]
    ));
  }
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  await RecentStore.instance.load();
  await Accounts.load();
  runApp(const ForumApp());
}

class ForumApp extends StatelessWidget {
  const ForumApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => MaterialApp(
          title: 'V2DO',
          locale: Locale(AppPreferences.instance.language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          themeMode: AppPreferences.instance.mode,
          scrollBehavior: const ExdoScrollBehavior(),
          builder: (context, child) {
            final systemScaler = MediaQuery.textScalerOf(context);
            final content = MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: AppTextScaler(
                    systemScaler, AppPreferences.instance.fontScale),
              ),
              child: child!,
            );
            return const bool.fromEnvironment('PERF_TRACE')
                ? PerfProbe(child: content)
                : content;
          },
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              useMaterial3: true,
              colorSchemeSeed: Color(AppPreferences.instance.accent)),
          darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorSchemeSeed: Color(AppPreferences.instance.accent)),
          home: const HomePage()));
}

class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  @override
  double get textScaleFactor => system.scale(1) * factor;
}

Future<void> authenticate(BuildContext context, Forum forum) async {
  await Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => Scaffold(
              appBar: AppBar(title: UiText('${forum.name} · 登录与验证'), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const UiText('完成'))
              ]),
              body: SafeArea(
                  child: SiteView(
                      forum.url(forum.discourse ? '/login' : '/signin'))))));
  await Accounts.refresh(forum);
  await UnreadMessages.refresh(forum);
  if (!forum.discourse &&
      context.mounted &&
      Accounts.states[0].value.account != null) await showCheckIn(context);
}

Future<void> showCheckIn(BuildContext context) async {
  String? message;
  try {
    message = await DailyCheckIn.run();
  } catch (e) {
    message = 'V2EX 自动签到：$e';
  }
  if (context.mounted && message != null)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: UiText(message), duration: const Duration(seconds: 6)));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> with WidgetsBindingObserver {
  Timer? messageTimer;
  bool accountBusy = false;
  DateTime lastAccountCheck = DateTime.now();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        DateTime.now().difference(lastAccountCheck).inSeconds >= 30 &&
        !accountBusy) {
      lastAccountCheck = DateTime.now();
      for (final forum in forums) {
        Accounts.refresh(forum).then((_) => UnreadMessages.refresh(forum));
      }
    }
  }

  @override
  void dispose() {
    messageTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    messageTimer = Timer.periodic(const Duration(seconds: 90), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        for (final forum in forums) {
          UnreadMessages.refresh(forum);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showCheckIn(context);
      if (mounted) AppUpdates.check(context, automatic: true);
      for (final forum in forums) {
        Accounts.refresh(forum).then((_) => UnreadMessages.refresh(forum));
      }
    });
  }

  late int selected = AppPreferences.instance.startForum;
  final keys = [GlobalKey<_FeedState>(), GlobalKey<_FeedState>()];
  final scaffold = GlobalKey<ScaffoldState>();
  double drawerDrag = 0;
  Future<void> accountMenu(int i) async {
    if (accountBusy) return;
    final forum = forums[i];
    final state = Accounts.states[i].value;
    if (state.needsLogin || (state.account == null && state.verified)) {
      await authenticate(context, forum);
      keys[i].currentState?.reload();
      return;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: UserAvatar(state.account?.avatar ?? '',
                      state.account?.username ?? ''),
                  title: UiText(state.account?.username ?? '账号'),
                  subtitle: UiText(state.verified && state.account != null
                      ? '${forum.name} · 已登录'
                      : forum.name)),
              ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const UiText('刷新登录状态'),
                  onTap: () => Navigator.pop(c, 'refresh')),
              if (state.account != null) ...[
                ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const UiText('我的资料与主题'),
                    onTap: () => Navigator.pop(c, 'profile')),
                if (!forum.discourse)
                  ListTile(
                      leading:
                          const Icon(Icons.account_balance_wallet_outlined),
                      title: const UiText('签到与余额'),
                      onTap: () => Navigator.pop(c, 'wallet')),
                ListTile(
                    leading: const Icon(Icons.bookmark_outline),
                    title: const UiText('我的收藏'),
                    onTap: () => Navigator.pop(c, 'bookmarks')),
                if (!forum.discourse)
                  ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const UiText('我的关注'),
                      onTap: () => Navigator.pop(c, 'relations')),
                ListTile(
                    leading: const Icon(Icons.switch_account_outlined),
                    title: const UiText('切换账号'),
                    subtitle: const UiText('退出当前账号并打开登录页'),
                    onTap: () => Navigator.pop(c, 'switch')),
                ListTile(
                    leading: const Icon(Icons.logout),
                    title: UiText('退出 ${forum.name}'),
                    onTap: () => Navigator.pop(c, 'logout')),
              ] else
                ListTile(
                    leading: const Icon(Icons.login),
                    title: const UiText('登录 / 验证'),
                    onTap: () => Navigator.pop(c, 'login')),
            ])));
    if (action == null || !mounted) return;
    if (action == 'wallet') {
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => V2WalletPage(forum)));
      return;
    }
    if (action == 'relations') {
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const RelationsPage()));
      keys[i].currentState?.reload();
      return;
    }
    if (action == 'profile' || action == 'bookmarks') {
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => ProfilePage(forum, state.account!.username,
                  initial: action == 'bookmarks' ? 'bookmarks' : 'topics')));
      return;
    }
    if (action == 'refresh') {
      await Accounts.refresh(forum);
      if (mounted && Accounts.states[i].value.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Accounts.states[i].value.error!)));
      }
      return;
    }
    if (action == 'login') {
      await authenticate(context, forum);
      keys[i].currentState?.reload();
      return;
    }
    setState(() => accountBusy = true);
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: UiText('正在退出账号…')));
      await Accounts.logout(forum);
      await UnreadMessages.refresh(forum);
      _ComposerState.drafts
          .removeWhere((key, _) => key.startsWith('${forum.host}/'));
      keys[i].currentState?.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (action == 'switch') {
        await authenticate(context, forum);
        keys[i].currentState?.reload();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText('已退出 ${forum.name}')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText(e.toString())));
    } finally {
      if (mounted) setState(() => accountBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      key: scaffold,
      drawer: Drawer(
          width:
              (MediaQuery.sizeOf(context).width * .84).clamp(0, 360).toDouble(),
          child: SafeArea(
              child: RecentPage(forums[selected],
                  key: ValueKey(forums[selected].host),
                  login: () async {
                    await authenticate(context, forums[selected]);
                  },
                  back: () => scaffold.currentState?.closeDrawer(),
                  open: (topic, sequence) {
                    final forum = forums[selected];
                    scaffold.currentState?.closeDrawer();
                    Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                TopicPage(forum, topic, sequence: sequence)));
                  },
                  choose: (section) {
                    scaffold.currentState?.closeDrawer();
                    keys[selected].currentState?.choose(section);
                  }))),
      appBar: AppBar(
          toolbarHeight: 48,
          automaticallyImplyLeading: false,
          title: ForumTitle(forums[selected]),
          actions: [
            ValueListenableBuilder<int?>(
                valueListenable: UnreadMessages.counts[selected],
                builder: (context, count, _) => IconButton(
                    tooltip: uiTr(context,
                        count == null ? '消息 · 未读数待刷新' : '消息 · $count 条未读'),
                    icon: Badge(
                        isLabelVisible: count != null && count > 0,
                        label: Text(count != null && count > 99
                            ? '99+'
                            : '${count ?? 0}'),
                        child:
                            const Icon(Icons.notifications_outlined, size: 22)),
                    onPressed: () async {
                      final forum = forums[selected];
                      if (Accounts.states[selected].value.account == null)
                        await authenticate(context, forum);
                      if (!context.mounted) return;
                      await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => NotificationsPage(forum)));
                      await UnreadMessages.refresh(forum);
                    })),
            ValueListenableBuilder<AccountState>(
                valueListenable: Accounts.states[selected],
                builder: (context, state, _) => TextButton.icon(
                    icon: state.account != null
                        ? UserAvatar(
                            state.account!.avatar, state.account!.username,
                            size: 24)
                        : const Icon(Icons.account_circle_outlined, size: 22),
                    label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 75),
                        child: UiText(state.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    onPressed: () => accountMenu(selected))),
            IconButton(
                tooltip: uiTr(context, '应用设置'),
                icon: const Icon(Icons.settings_outlined, size: 22),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const SettingsPage()))),
          ]),
      body: SafeArea(
          child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => drawerDrag = 0,
              onHorizontalDragUpdate: (event) {
                drawerDrag += event.delta.dx;
                if (drawerDrag > 48) {
                  drawerDrag = -10000;
                  scaffold.currentState?.openDrawer();
                }
              },
              child: IndexedStack(index: selected, children: [
                for (var i = 0; i < 2; i++) Feed(forums[i], key: keys[i])
              ]))),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
            heroTag: 'search',
            tooltip: uiTr(context, '搜索'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => ForumSearchPage(forums[selected]))),
            child: const Icon(Icons.search)),
        const SizedBox(height: 8),
        FloatingActionButton.small(
            heroTag: 'compose',
            tooltip: uiTr(context, '发帖'),
            child: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final forum = forums[selected];
              final result = await Navigator.push<Topic>(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          Composer(forum, const Topic(0, ''), creating: true)));
              if (result != null && context.mounted) {
                keys[selected].currentState?.reload();
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => TopicPage(forum, result)));
              }
            }),
      ]),
      bottomNavigationBar: NavigationBar(
          height: 58,
          selectedIndex: selected,
          onDestinationSelected: (i) => setState(() => selected = i),
          destinations: [
            for (final forum in forums)
              NavigationDestination(
                  icon: ValueListenableBuilder<int?>(
                      valueListenable:
                          UnreadMessages.counts[Accounts.index(forum)],
                      builder: (context, count, _) => Badge(
                          isLabelVisible: count != null && count > 0,
                          child: ForumIcon(forum))),
                  label: forum.name),
          ]));
}

class ForumSearchPage extends StatefulWidget {
  final Forum forum;
  const ForumSearchPage(this.forum, {super.key});
  @override
  State<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends State<ForumSearchPage> {
  final query = TextEditingController();
  final scroll = ScrollController();
  List<Topic> results = [];
  String activeQuery = '', error = '';
  int page = 0, generation = 0;
  bool loading = false, more = false, searched = false;
  int sovOffset = 0;
  late final Future<List<ForumSection>> nodes;

  @override
  void initState() {
    super.initState();
    nodes = widget.forum.discourse
        ? Future.value([])
        : widget.forum.sections('node');
    scroll.addListener(() {
      if (scroll.position.extentAfter < 500 && more && !loading)
        search(next: true);
    });
  }

  @override
  void dispose() {
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> search({bool next = false}) async {
    final text = next ? activeQuery : query.text.trim();
    if (text.isEmpty || (next && loading)) return;
    if (!widget.forum.discourse) {
      final token = next ? generation : ++generation;
      final offset = next ? sovOffset : 0;
      setState(() {
        loading = true;
        error = '';
        if (!next) {
          activeQuery = text;
          results = [];
          more = false;
          searched = true;
        }
      });
      try {
        final found = await Sov2exSearch.search(text, offset: offset);
        if (!mounted || token != generation) return;
        setState(() {
          final ids = results.map((p) => p.id).toSet();
          results.addAll(found.topics.where((p) => ids.add(p.id)));
          sovOffset = offset + 20;
          more = found.hasMore;
          loading = false;
        });
      } catch (e) {
        if (mounted && token == generation)
          setState(() {
            error = 'SoV2EX 搜索失败：$e';
            loading = false;
            more = false;
          });
      }
      return;
    }
    final token = next ? generation : ++generation;
    final targetPage = next ? page + 1 : 1;
    setState(() {
      loading = true;
      error = '';
      if (!next) {
        activeQuery = text;
        results = [];
        more = false;
        searched = true;
      }
    });
    try {
      final uri = widget.forum
          .url('/search.json')
          .replace(queryParameters: {'q': text, 'page': '$targetPage'});
      final data = decodeResponse(await widget.forum
          .transport(uri, headers: {'Accept': 'application/json'}));
      final topics = <int, Map>{
        for (final t in data['topics'] as List? ?? [])
          if (t['id'] is int) t['id'] as int: t as Map
      };
      final posts = data['posts'] as List? ?? [];
      final rows = <Topic>[];
      final seen = <int>{...results.map((e) => e.id)};
      for (final p in posts) {
        final id = p['topic_id'];
        final topic = topics[id];
        if (id is! int || topic == null || !seen.add(id)) continue;
        rows.add(Topic(id, topic['title']?.toString() ?? '',
            author: p['username']?.toString() ?? '',
            activityExcerpt:
                html_parser.parseFragment(p['blurb']?.toString() ?? '').text ??
                    '',
            createdAt: parseTime(p['created_at']),
            replies: ((topic['posts_count'] as int?) ?? 1) - 1));
      }
      if (!mounted || token != generation) return;
      setState(() {
        results.addAll(rows);
        page = targetPage;
        more = data['grouped_search_result']?['more_full_page_results'] == true;
        loading = false;
      });
    } catch (e) {
      if (mounted && token == generation)
        setState(() {
          error = e.toString();
          loading = false;
          more = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: UiText('${widget.forum.name} 搜索')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
                controller: query,
                autofocus: true,
                onChanged: widget.forum.discourse
                    ? null
                    : (_) => setState(() {
                          generation++;
                          results = [];
                          more = false;
                          searched = false;
                          error = '';
                          loading = false;
                        }),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                    hintText: uiTr(context,
                        widget.forum.discourse ? '搜索帖子' : '搜索节点，或输入 @用户名'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        tooltip: uiTr(context, '搜索'),
                        onPressed: search,
                        icon: const Icon(Icons.arrow_forward)),
                    border: const OutlineInputBorder()))),
        if (error.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: UiText(error)),
        if (!widget.forum.discourse)
          Expanded(
              child: FutureBuilder<List<ForumSection>>(
                  future: nodes,
                  builder: (context, snapshot) {
                    final text = query.text.trim();
                    if (text.isEmpty)
                      return const Center(child: UiText('输入节点名称或 @用户名'));
                    if (text.startsWith('@')) {
                      final name = text.substring(1).trim();
                      if (!RegExp(r'^[A-Za-z0-9_]{1,40}$').hasMatch(name))
                        return const Center(child: UiText('请输入有效的用户名'));
                      return ListView(controller: scroll, children: [
                        ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text('@$name'),
                            subtitle: const UiText('查看用户资料'),
                            onTap: () =>
                                openMember(context, widget.forum, name))
                      ]);
                    }
                    if (snapshot.connectionState != ConnectionState.done)
                      return const Center(child: CircularProgressIndicator());
                    if (snapshot.hasError)
                      return const Center(child: UiText('节点列表加载失败，请稍后重试'));
                    final lower = text.toLowerCase();
                    final matches = (snapshot.data ?? [])
                        .where((s) =>
                            s.id.toLowerCase().contains(lower) ||
                            s.name.toLowerCase().contains(lower))
                        .toList();
                    return ListView(children: [
                      const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                          child: UiText('节点',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      if (matches.isEmpty)
                        const ListTile(title: UiText('没有匹配的节点')),
                      for (final node in matches.take(30))
                        ListTile(
                            leading: const Icon(Icons.tag),
                            title: Text(node.name),
                            subtitle: Text(node.id),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => Scaffold(
                                        appBar: AppBar(title: Text(node.name)),
                                        body: SafeArea(
                                            child: Feed(widget.forum,
                                                initialSection: node)))))),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            FilledButton.tonalIcon(
                                onPressed: loading ? null : () => search(),
                                icon: const Icon(Icons.search, size: 18),
                                label: const UiText('SoV2EX 搜索帖子')),
                          ])),
                      if (searched) ...[
                        const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: UiText('SoV2EX 帖子',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        if (error.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.all(12),
                              child: UiText(error)),
                        for (final topic in results)
                          ListTile(
                              title: Text(topic.title,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  [topic.author, topic.activityExcerpt]
                                      .where((s) => s.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              trailing: TimeLabel(topic.createdAt),
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          TopicPage(widget.forum, topic)))),
                        if (loading)
                          const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator())),
                        if (!loading && error.isEmpty && results.isEmpty)
                          const ListTile(title: UiText('没有找到帖子')),
                        if (more && !loading)
                          TextButton(
                              onPressed: () => search(next: true),
                              child: const UiText('加载更多')),
                      ],
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: UiText('SoV2EX 是第三方搜索服务，搜索结果和索引更新可能有所延迟。',
                              style: TextStyle(fontSize: 12)))
                    ]);
                  }))
        else
          Expanded(
              child: ListView.builder(
                  controller: scroll,
                  itemCount: results.length + 1,
                  itemBuilder: (context, i) {
                    if (i == results.length)
                      return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Center(
                              child: loading
                                  ? const CircularProgressIndicator()
                                  : UiText(searched &&
                                          results.isEmpty &&
                                          error.isEmpty
                                      ? '没有找到结果'
                                      : more
                                          ? '继续下滑加载'
                                          : '')));
                    final topic = results[i];
                    return ListTile(
                        title: Text(topic.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            [topic.author, topic.activityExcerpt]
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        trailing: Text('${topic.replies}'),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    TopicPage(widget.forum, topic))));
                  }))
      ]));
}

class _FeedTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  const _FeedTab(this.label, {required this.selected, required this.onPressed});
  @override
  Widget build(BuildContext context) => Center(
      child: SizedBox(
          height: 32,
          child: TextButton(
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: selected
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 9)),
              onPressed: onPressed,
              child: UiText(label))));
}

class Feed extends StatefulWidget {
  final Forum forum;
  final ForumSection? initialSection;
  const Feed(this.forum, {super.key, this.initialSection});
  @override
  State<Feed> createState() => _FeedState();
}

class _FeedState extends State<Feed> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late Future<List<ForumSection>> channels;
  void choose(ForumSection choice) {
    RecentStore.instance.choose(widget.forum, choice);
    setState(() {
      section = choice.kind == 'all' ? null : choice;
      hot = false;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    reload();
  }

  final scroll = ScrollController();
  bool moreFailed = false;
  void nearEnd() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 600 &&
        !loading &&
        !more &&
        !moreFailed &&
        hasMore) loadMore();
  }

  @override
  void dispose() {
    Relations.changes.removeListener(reload);
    scroll.dispose();
    super.dispose();
  }

  ForumSection? section;
  Future<void> pickSection() async {
    final choice = await showModalBottomSheet<ForumSection>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FractionallySizedBox(
            heightFactor: .85, child: SectionPicker(widget.forum)));
    if (choice == null || !mounted) return;
    RecentStore.instance.choose(widget.forum, choice);
    setState(() {
      section = choice.kind == 'all' ? null : choice;
      hot = false;
    });
    await reload();
  }

  List<Topic> topics = [];
  String linuxList = 'latest';
  bool loading = true, more = false, hot = false, hasMore = true;
  int page = 0, generation = 0;
  String? error;
  bool errorNeedsLogin = false;
  @override
  void initState() {
    super.initState();
    channels = widget.forum.discourse
        ? Future.value([])
        : widget.forum.sections('tab');
    if (!widget.forum.discourse)
      section = widget.initialSection ?? const ForumSection('all', '全部', 'tab');
    scroll.addListener(nearEnd);
    if (!widget.forum.discourse) Relations.changes.addListener(reload);
    reload();
  }

  Future<void> reload() async {
    final token = ++generation;
    setState(() {
      loading = true;
      more = false;
      moreFailed = false;
      error = null;
      page = 0;
    });
    try {
      final rows = await widget.forum.latest(
          hot: hot,
          section: section,
          listType: widget.forum.discourse ? linuxList : null);
      if (mounted && token == generation)
        setState(() {
          topics = rows;
          hasMore = rows.isNotEmpty &&
              (widget.forum.discourse ||
                  (section == null ? !hot : section!.kind != 'tab'));
        });
    } catch (e) {
      if (mounted && token == generation)
        setState(() {
          error = e.toString();
          errorNeedsLogin = e is ForumError && e.needsLogin;
        });
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (more || loading || !hasMore) return;
    final token = generation;
    setState(() {
      more = true;
      moreFailed = false;
    });
    try {
      final rows = await widget.forum.latest(
          page: page + 1,
          hot: hot,
          section: section,
          listType: widget.forum.discourse ? linuxList : null);
      if (mounted && token == generation)
        setState(() {
          final ids = topics.map((t) => t.id).toSet();
          final fresh = rows.where((t) => !ids.contains(t.id)).toList();
          topics.addAll(fresh);
          page++;
          hasMore = fresh.isNotEmpty;
        });
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => moreFailed = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText(e.toString())));
      }
    } finally {
      if (mounted && token == generation) setState(() => more = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.forum.discourse)
        SizedBox(
            height: 46,
            child: Row(children: [
              Expanded(
                  child: FutureBuilder<List<ForumSection>>(
                      future: channels,
                      builder: (context, snapshot) {
                        final available = snapshot.data ??
                            const [
                              ForumSection('all', '全部', 'tab'),
                              ForumSection('tech', '技术', 'tab'),
                              ForumSection('creative', '创意', 'tab'),
                              ForumSection('play', '好玩', 'tab'),
                              ForumSection('apple', 'Apple', 'tab'),
                              ForumSection('jobs', '酷工作', 'tab'),
                              ForumSection('deals', '交易', 'tab'),
                              ForumSection('city', '城市', 'tab'),
                              ForumSection('qna', '问与答', 'tab'),
                              ForumSection('hot', '最热', 'tab')
                            ];
                        final choices = [
                          available.where((s) => s.id == 'all').firstOrNull ??
                              const ForumSection('all', '全部', 'tab'),
                          available.where((s) => s.id == 'hot').firstOrNull ??
                              const ForumSection('hot', '最热', 'tab'),
                          ...available
                              .where((s) => s.id != 'all' && s.id != 'hot')
                        ];
                        return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(children: [
                              if (section != null && section!.kind != 'tab')
                                _FeedTab(section!.name,
                                    selected: true, onPressed: pickSection),
                              for (final choice in choices)
                                _FeedTab(choice.name,
                                    selected: section?.kind == 'tab' &&
                                        section?.id == choice.id,
                                    onPressed: () => choose(choice))
                            ]));
                      })),
              TextButton.icon(
                  onPressed: pickSection,
                  icon: const Icon(Icons.apps, size: 17),
                  label: const UiText('全部节点'))
            ])),
      if (widget.forum.discourse)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              Expanded(
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final item in const [
                          ('latest', '最新'),
                          ('hot', '热门'),
                          ('new', '新话题'),
                          ('unread', '追踪未读'),
                          ('unseen', '新帖与未读'),
                          ('top', '热门排行')
                        ])
                          _FeedTab(item.$2, selected: linuxList == item.$1,
                              onPressed: () {
                            setState(() => linuxList = item.$1);
                            if (scroll.hasClients) scroll.jumpTo(0);
                            reload();
                          }),
                      ]))),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 125),
                  child: TextButton.icon(
                      onPressed: pickSection,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: UiText(
                          section?.name ??
                              (widget.forum.discourse ? '分类 / 标签' : '全部节点'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis))),
            ])),
      Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Problem(
                      error!,
                      reload,
                      () => authenticate(context, widget.forum)
                          .then((_) => reload()),
                      needsLogin: errorNeedsLogin)
                  : RefreshIndicator(
                      onRefresh: () async {
                        await Future.wait([
                          reload(),
                          UnreadMessages.refresh(widget.forum),
                        ]);
                      },
                      child: ListView.builder(
                          controller: scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: topics.length + 1,
                          itemBuilder: (context, i) {
                            if (i == topics.length)
                              return Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: hasMore
                                      ? TextButton(
                                          onPressed: more ? null : loadMore,
                                          child: UiText(more
                                              ? '正在加载…'
                                              : moreFailed
                                                  ? '加载失败，点击重试'
                                                  : '加载更多主题'))
                                      : UiText(
                                          topics.isEmpty
                                              ? '暂无主题'
                                              : '已显示本次返回的全部主题',
                                          textAlign: TextAlign.center));
                            final topic = topics[i];
                            final forum = widget.forum;
                            return InkWell(
                                key: ValueKey('${forum.host}/${topic.id}'),
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                        builder: (_) => TopicPage(forum, topic,
                                            sequence: List.of(topics)))),
                                child: Container(
                                    decoration: BoxDecoration(
                                        border: Border(
                                            bottom: BorderSide(
                                                color: Theme.of(context)
                                                    .dividerColor
                                                    .withValues(alpha: .14)))),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 9),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          MemberAvatar(
                                              forum, topic.avatar, topic.author,
                                              size: 30),
                                          const SizedBox(width: 9),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(topic.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.3)),
                                                const SizedBox(height: 5),
                                                Row(children: [
                                                  Expanded(
                                                      child: Text(
                                                          [
                                                            topic.author,
                                                            topic.category
                                                          ]
                                                              .where((s) =>
                                                                  s.isNotEmpty)
                                                              .join(' · '),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      11))),
                                                  const SizedBox(width: 6),
                                                  TimeLabel(topic.createdAt),
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                      Icons.chat_bubble_outline,
                                                      size: 12),
                                                  const SizedBox(width: 3),
                                                  Text('${topic.replies}',
                                                      style: const TextStyle(
                                                          fontSize: 11)),
                                                ]),
                                              ])),
                                        ])));
                          }))),
    ]);
  }
}

class TopicPage extends StatefulWidget {
  final Forum forum;
  final Topic topic;
  final VoidCallback? onLoaded;
  final List<Topic> sequence;
  const TopicPage(this.forum, this.topic,
      {this.onLoaded, this.sequence = const [], super.key});
  @override
  State<TopicPage> createState() => _TopicState();
}

class _TopicState extends State<TopicPage> with TickerProviderStateMixin {
  bool onlyAuthor = false, newestFirst = false, collectingReplies = false;
  int collectionToken = 0;
  bool get flatReplies => onlyAuthor || newestFirst;
  List<Post> get orderedReplies {
    final posts = data?.posts ?? <Post>[];
    final result = posts
        .where((p) => !onlyAuthor || isOriginalPoster(p))
        .toList()
      ..sort((a, b) => newestFirst
          ? b.number.compareTo(a.number)
          : a.number.compareTo(b.number));
    return result;
  }

  Future<void> collectReplies() async {
    final token = ++collectionToken;
    if (!flatReplies || data?.hasMore != true) return;
    setState(() {
      collectingReplies = true;
      moreFailed = false;
    });
    try {
      while (mounted &&
          token == collectionToken &&
          flatReplies &&
          data?.hasMore == true) {
        if (more || loading) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        await loadMore();
        if (moreFailed) break;
      }
    } finally {
      if (mounted && token == collectionToken)
        setState(() => collectingReplies = false);
    }
  }

  void changeReplyView(String value) {
    setState(() {
      replyKeys.clear();
      if (value == 'author') onlyAuthor = !onlyAuthor;
      if (value == 'order') newestFirst = !newestFirst;
      collectionToken++;
      collectingReplies = false;
    });
    if (flatReplies)
      collectReplies();
    else
      checkViewport();
  }

  final collapsedReplies = <int>{};
  final replyKeys = <int, GlobalKey>{};
  Discussion? threadSource;
  List<Post> threadCache = [];
  List<Post> get threadPosts {
    final posts = data?.posts ?? <Post>[];
    if (!widget.forum.discourse) return posts;
    if (identical(data, threadSource)) return threadCache;
    threadSource = data;
    final byNumber = {for (final p in posts) p.number: p};
    final children = <int, List<Post>>{};
    final roots = <Post>[];
    for (final post in posts) {
      final parent = byNumber[post.parentNumber];
      if (parent == null ||
          parent.id == post.id ||
          parent.number >= post.number) {
        roots.add(post);
      } else {
        (children[parent.id] ??= []).add(post);
      }
    }
    final result = <Post>[];
    void visit(Post p, int depth, int? parent) {
      result.add(Post(p.id, p.number, p.author, p.html,
          avatar: p.avatar,
          createdAt: p.createdAt,
          timeLabel: p.timeLabel,
          liked: p.liked,
          likes: p.likes,
          updatedAt: p.updatedAt,
          version: p.version,
          editReason: p.editReason,
          parentNumber: p.parentNumber,
          parentId: parent,
          threadDepth: depth,
          threadStyle: 'd',
          sourcePage: p.sourcePage));
      for (final child in children[p.id] ?? <Post>[]) {
        visit(child, depth + 1, p.id);
      }
    }

    for (final root in roots) {
      visit(root, 0, null);
    }
    threadCache = result;
    return threadCache;
  }

  List<Post> get visibleReplies {
    if (flatReplies) return data?.hasMore == true ? <Post>[] : orderedReplies;
    final posts = threadPosts;
    final byId = {for (final p in posts) p.id: p};
    return posts.where((post) {
      if (!['c', 'd'].contains(post.threadStyle)) return true;
      var parent = post.parentId;
      final seen = <int>{};
      while (parent != null && seen.add(parent)) {
        if (collapsedReplies.contains(parent)) return false;
        parent = byId[parent]?.parentId;
      }
      return true;
    }).toList();
  }

  int childCount(int id) => threadPosts.where((p) => p.parentId == id).length;
  Future<void> jumpToParent(Post post) async {
    final uri = Uri.tryParse(post.parentLink);
    if (uri != null && uri.hasAuthority && uri.host != widget.forum.host)
      return;
    final target = post.parentId ??
        int.tryParse(RegExp(r'(?:r_|reply)(\d+)')
                .firstMatch(uri?.fragment ?? '')
                ?.group(1) ??
            '');
    final targetPage = int.tryParse(uri?.queryParameters['p'] ?? '');
    if (targetPage != null && targetPage > 0) {
      while (mounted &&
          data != null &&
          data!.page < targetPage &&
          data!.hasMore &&
          !more &&
          !moreFailed) {
        await loadMore();
      }
    }
    if (!mounted) return;
    if (target == null || data?.posts.any((p) => p.id == target) != true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: UiText('未找到可访问的上层回复')));
      return;
    }
    setState(() {
      collapsedReplies.clear();
      onlyAuthor = false;
      collectionToken++;
      collectingReplies = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    final i = visibleReplies.indexWhere((p) => p.id == target);
    if (i < 0 || !scroll.hasClients) return;
    for (var attempt = 0; attempt < 12 && mounted; attempt++) {
      final context = replyKeys[target]?.currentContext;
      if (context != null) {
        await Scrollable.ensureVisible(context,
            duration: const Duration(milliseconds: 250), alignment: .15);
        return;
      }
      final items = visibleReplies.length;
      final guess = scroll.position.maxScrollExtent * ((i + 1) / (items + 1));
      final adjusted = attempt == 0
          ? guess
          : (scroll.offset +
              (i >
                          (visibleReplies.indexWhere(
                              (p) => replyKeys[p.id]?.currentContext != null))
                      ? 1
                      : -1) *
                  scroll.position.viewportDimension *
                  .7);
      scroll.jumpTo(adjusted.clamp(0.0, scroll.position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: UiText('未能定位该回复，请继续滚动查看')));
  }

  late final pageSlide = AnimationController.unbounded(vsync: this);
  late final cardInset = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200));
  bool switchingTopic = false, draggingTopic = false;
  late Topic activeTopic = widget.topic;
  Offset? swipeStart;
  Duration swipeTime = Duration.zero;
  int? swipePointer;
  bool textSelected = false;
  final previewCache = <int, Discussion>{};
  final previewText = <int, String>{};
  Timer? previewTimer;
  void schedulePreviews() {
    previewTimer?.cancel();
    previewTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || draggingTopic || switchingTopic) return;
      warmPreview(adjacent(-1));
      warmPreview(adjacent(1));
    });
  }

  final previewPending = <int>{};
  late final List<Topic> sequence =
      {for (final t in widget.sequence) t.id: t}.values.toList();
  Topic? adjacent(int direction) {
    final items = sequence;
    final index = items.indexWhere((t) => t.id == activeTopic.id);
    final next = index + direction;
    return index < 0 || next < 0 || next >= items.length ? null : items[next];
  }

  Future<void> warmPreview(Topic? topic) async {
    if (topic == null ||
        previewCache.containsKey(topic.id) ||
        !previewPending.add(topic.id)) return;
    try {
      final result = await widget.forum.discussion(topic);
      if (mounted &&
          (adjacent(-1)?.id == topic.id || adjacent(1)?.id == topic.id)) {
        previewCache[topic.id] = result;
        previewText[topic.id] =
            html_parser.parse(result.body).body?.text.trim() ?? '';
        if (!draggingTopic && !switchingTopic) setState(() {});
      }
    } catch (_) {
      // Preview failure must not interrupt reading; normal opening can retry.
    } finally {
      previewPending.remove(topic.id);
    }
  }

  Future<void> settleCards({int? direction}) async {
    if (switchingTopic) return;
    final next = direction == null ? null : adjacent(direction);
    setState(() {
      switchingTopic = true;
      draggingTopic = false;
    });
    final reduced = MediaQuery.disableAnimationsOf(context);
    try {
      if (next == null) {
        await Future.wait([
          pageSlide
              .animateTo(0,
                  duration: Duration(milliseconds: reduced ? 0 : 220),
                  curve: Curves.easeOutCubic)
              .orCancel,
          cardInset
              .animateTo(0,
                  duration: Duration(milliseconds: reduced ? 0 : 220),
                  curve: Curves.easeOutCubic)
              .orCancel,
        ]);
      } else {
        await Future.wait([
          pageSlide
              .animateTo(-direction!.toDouble(),
                  duration: Duration(milliseconds: reduced ? 0 : 220),
                  curve: Curves.easeOutCubic)
              .orCancel,
          cardInset
              .animateTo(0,
                  duration: Duration(milliseconds: reduced ? 0 : 220),
                  curve: Curves.easeOutCubic)
              .orCancel,
        ]);
        if (!mounted) return;
        if (data != null) previewCache[activeTopic.id] = data!;
        setState(() {
          activeTopic = next;
          collectionToken++;
          collectingReplies = false;
          onlyAuthor = false;
          newestFirst = false;
          collapsedReplies.clear();
          replyKeys.clear();
          textSelected = false;
          data = null;
          gallerySource = null;
          galleryImages = [];
        });
        reload(cached: previewCache.remove(next.id));
        if (scroll.hasClients) scroll.jumpTo(0);
        pageSlide.value = 0;

        final keep = {adjacent(-1)?.id, adjacent(1)?.id};
        previewCache.removeWhere((id, _) => !keep.contains(id));
        previewText.removeWhere((id, _) => !keep.contains(id));
      }
    } on TickerCanceled {
      return;
    }
    if (mounted) {
      setState(() => switchingTopic = false);
      schedulePreviews();
    }
  }

  void pointerDown(PointerDownEvent event) {
    if (switchingTopic ||
        swipePointer != null ||
        textSelected ||
        sequence.isEmpty) {
      swipeStart = null;
      return;
    }
    swipePointer = event.pointer;
    swipeStart = event.position;
    swipeTime = event.timeStamp;
  }

  void pointerMove(PointerMoveEvent event) {
    if (event.pointer != swipePointer || swipeStart == null || switchingTopic)
      return;
    final delta = event.position - swipeStart!;
    if (!draggingTopic) {
      if (event.timeStamp - swipeTime >= const Duration(milliseconds: 500) ||
          (delta.dy.abs() > 18 && delta.dy.abs() >= delta.dx.abs())) {
        swipeStart = null;
        return;
      }
      if (delta.dx.abs() < 18 || delta.dx.abs() < delta.dy.abs() * 1.8) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => draggingTopic = true);
      warmPreview(adjacent(-1));
      warmPreview(adjacent(1));
    }
    final travel =
        delta.dx.sign * (delta.dx.abs() - 18).clamp(0.0, double.infinity);
    var distance = travel / MediaQuery.sizeOf(context).width;
    if (adjacent(distance < 0 ? 1 : -1) == null) distance *= .18;
    pageSlide.value = distance.clamp(-1.0, 1.0);
    cardInset.value = (travel.abs() / 100).clamp(0.0, 1.0);
  }

  void pointerUp(PointerUpEvent event) {
    if (event.pointer != swipePointer) return;
    swipeStart = null;
    swipePointer = null;
    if (draggingTopic)
      settleCards(
          direction: pageSlide.value.abs() >= .22
              ? (pageSlide.value < 0 ? 1 : -1)
              : null);
  }

  void cancelSwipe() {
    swipeStart = null;
    swipePointer = null;
    if (draggingTopic) settleCards();
  }

  final scroll = ScrollController();
  bool moreFailed = false;
  final showBackToTop = ValueNotifier<bool>(false);
  int generation = 0;
  void nearEnd() {
    if (mounted && scroll.hasClients) {
      showBackToTop.value =
          scroll.offset > scroll.position.viewportDimension * .75;
    }
    if (mounted &&
        scroll.hasClients &&
        scroll.position.extentAfter < 600 &&
        !loading &&
        error == null &&
        !more &&
        !collectingReplies &&
        !moreFailed &&
        data?.hasMore == true) loadMore();
  }

  void checkViewport() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => nearEnd());
  @override
  void dispose() {
    previewTimer?.cancel();
    pageSlide.dispose();
    cardInset.dispose();
    showBackToTop.dispose();
    scroll.dispose();
    super.dispose();
  }

  Discussion? gallerySource;
  List<String> galleryImages = [];
  List<String> get gallery {
    if (!identical(gallerySource, data) || galleryImages.isEmpty) {
      gallerySource = data;
      galleryImages = <String>{
        ...imageTargets(
                data?.body ?? activeTopic.preview, widget.forum.url('/'))
            .values,
        for (final post in data?.posts ?? <Post>[])
          ...imageTargets(post.html, widget.forum.url('/')).values,
        for (final supplement in data?.supplements ?? <Supplement>[])
          ...imageTargets(supplement.body, widget.forum.url('/')).values
      }.toList();
    }
    return galleryImages;
  }

  String get category =>
      data?.category.isNotEmpty == true ? data!.category : activeTopic.category;
  bool isOriginalPoster(Post post) {
    final author = data?.original?.author.isNotEmpty == true
        ? data!.original!.author
        : activeTopic.author;
    return author.isNotEmpty &&
        post.author.toLowerCase() == author.toLowerCase();
  }

  String get topicTitle =>
      data?.title.isNotEmpty == true ? data!.title : activeTopic.title;
  Discussion? data;
  String? error;
  bool errorNeedsLogin = false;
  bool loading = true, more = false;
  @override
  void initState() {
    super.initState();
    scroll.addListener(nearEnd);
    reload();
  }

  Future<void> reload({Discussion? cached}) async {
    final token = ++generation;
    setState(() {
      loading = true;
      error = null;
      more = false;
      moreFailed = false;
    });
    try {
      final result = cached ?? await widget.forum.discussion(activeTopic);
      if (mounted && token == generation) {
        setState(() => data = result);
        RecentStore.instance.visit(
            widget.forum,
            Topic(activeTopic.id,
                result.title.isEmpty ? activeTopic.title : result.title,
                author: result.original?.author ?? activeTopic.author,
                category: result.category.isEmpty
                    ? activeTopic.category
                    : result.category));
        widget.onLoaded?.call();
        schedulePreviews();
      }
    } catch (e) {
      if (mounted && token == generation)
        setState(() {
          error = e.toString();
          errorNeedsLogin = e is ForumError && e.needsLogin;
        });
    } finally {
      if (mounted && token == generation) {
        setState(() => loading = false);
        if (flatReplies && data?.hasMore == true) collectReplies();
        checkViewport();
      }
    }
  }

  Future<void> loadMore() async {
    if (more || loading || data?.hasMore != true) return;
    final token = generation;
    setState(() {
      more = true;
      moreFailed = false;
    });
    try {
      final result = await widget.forum.discussion(activeTopic, previous: data);
      if (mounted && token == generation) setState(() => data = result);
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => moreFailed = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: UiText(e.toString())));
      }
    } finally {
      if (mounted && token == generation) {
        setState(() => more = false);
        checkViewport();
      }
    }
  }

  Future<void> compose([Post? post]) async {
    final sent = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => Composer(widget.forum, activeTopic, quote: post)));
    if (sent == true && mounted) await reload();
  }

  Widget render(String body) {
    final targets = imageTargets(body, widget.forum.url('/'));
    return SelectionArea(
        key: ValueKey('${activeTopic.id}/$body'),
        onSelectionChanged: (selection) =>
            textSelected = selection?.plainText.isNotEmpty == true,
        child: HtmlWidget(body,
            onTapImage: (image) {
              final sources = image.sources.toList();
              if (sources.isEmpty) return;
              sources.sort((a, b) => (b.width ?? 0).compareTo(a.width ?? 0));
              final source =
                  widget.forum.url('/').resolve(sources.first.url).toString();
              if (targets.containsKey(source))
                previewImage(context, targets[source]!, images: gallery);
            },
            textStyle: const TextStyle(fontSize: 14, height: 1.35),
            customStylesBuilder: (element) =>
                element.localName == 'p' ? {'margin': '4px 0'} : null,
            customWidgetBuilder: (element) {
              if (element.localName == 'blockquote' ||
                  (element.localName == 'aside' &&
                      element.classes.contains('quote'))) {
                return ExpansionTile(
                    dense: true,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(left: 10, bottom: 6),
                    title: const UiText('引用内容', style: TextStyle(fontSize: 12)),
                    children: [render(element.innerHtml)]);
              }
              return null;
            },
            baseUrl: widget.forum.url('/'),
            onTapUrl: (value) async {
              final uri = Uri.tryParse(value);
              if (uri == null) return false;
              final member = RegExp(widget.forum.discourse
                      ? r'^/u/([^/]+)'
                      : r'^/member/([^/]+)')
                  .firstMatch(uri.path);
              if (uri.host == widget.forum.host && member != null) {
                openMember(context, widget.forum,
                    Uri.decodeComponent(member.group(1)!));
                return true;
              }
              if (targets.containsValue(uri.toString()) ||
                  targets.containsKey(uri.toString())) {
                await previewImage(
                    context, targets[uri.toString()] ?? uri.toString(),
                    images: gallery);
                return true;
              }
              final match =
                  RegExp(r'^/t/(?:[^/]+/)?(\d+)').firstMatch(uri.path);
              if (uri.host == widget.forum.host && match != null) {
                Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => TopicPage(widget.forum,
                            Topic(int.parse(match.group(1)!), '主题'))));
                return true;
              }
              return openExternal(uri);
            }));
  }

  Widget neighborCard(Topic topic) {
    final preview = previewCache[topic.id];
    final author = preview?.original?.author ?? topic.author;
    final category = preview?.category.isNotEmpty == true
        ? preview!.category
        : topic.category;
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 48,
            leadingWidth: 44,
            titleSpacing: 0,
            leading: const Icon(Icons.arrow_back),
            title: Row(children: [
              ForumIcon(widget.forum),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      preview?.title.isNotEmpty == true
                          ? preview!.title
                          : topic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.w600)))
            ])),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined),
                    label: const UiText('写回复')))),
        body: SafeArea(
            child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
                children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: .5))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          UserAvatar(
                              preview?.original?.avatar ?? topic.avatar, author,
                              size: 26),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(author,
                                  style: const TextStyle(fontSize: 12))),
                          TimeLabel(
                              preview?.original?.createdAt ?? topic.createdAt,
                              fallback: preview?.original?.timeLabel ?? ''),
                          const SizedBox(width: 8),
                          if (category.isNotEmpty)
                            Flexible(
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        borderRadius: BorderRadius.circular(5)),
                                    child: Text(category,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11))))
                        ]),
                        const Divider(height: 16),
                        if (preview != null)
                          HtmlWidget(preview.body,
                              baseUrl: widget.forum.url('/'),
                              textStyle:
                                  const TextStyle(fontSize: 14, height: 1.35),
                              customStylesBuilder: (e) => e.localName == 'p'
                                  ? {'margin': '4px 0'}
                                  : null)
                        else if (topic.preview.isNotEmpty)
                          HtmlWidget(topic.preview,
                              baseUrl: widget.forum.url('/'),
                              textStyle:
                                  const TextStyle(fontSize: 14, height: 1.35))
                        else
                          const Padding(
                              padding: EdgeInsets.all(20),
                              child: LinearProgressIndicator()),
                        if (preview != null) ...[
                          for (final entry in preview.supplements.indexed)
                            Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                        .withValues(alpha: .4),
                                    border: Border(
                                        left: BorderSide(
                                            width: 3,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary))),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'Supplement ' +
                                              (entry.$1 + 1).toString(),
                                          style: const TextStyle(fontSize: 12)),
                                      HtmlWidget(entry.$2.body,
                                          baseUrl: widget.forum.url('/'),
                                          textStyle: const TextStyle(
                                              fontSize: 14, height: 1.35)),
                                    ])),
                          Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                        style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact),
                                        onPressed: () {},
                                        icon: const Icon(Icons.bookmark_border,
                                            size: 18),
                                        label: const UiText('收藏',
                                            style: TextStyle(fontSize: 12))),
                                    TextButton.icon(
                                        style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact),
                                        onPressed: () {},
                                        icon: const Icon(Icons.favorite_border,
                                            size: 16),
                                        label: UiText(
                                            widget.forum.discourse ? '赞' : '感谢',
                                            style:
                                                const TextStyle(fontSize: 12))),
                                  ])),
                        ],
                      ])),
              if (preview != null) ...[
                const SizedBox(height: 16),
                UiText('回复 · ' + preview.posts.length.toString(),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                for (final post in preview.posts.take(3))
                  Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: .14)))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              UserAvatar(post.avatar, post.author, size: 24),
                              const SizedBox(width: 7),
                              Expanded(
                                  child: Text(post.author,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600))),
                              TimeLabel(post.createdAt,
                                  fallback: post.timeLabel),
                              const SizedBox(width: 6),
                              Text('#' + post.number.toString(),
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 8),
                              Icon(Icons.favorite_border,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              const Icon(Icons.reply, size: 18)
                            ]),
                            Padding(
                                padding:
                                    const EdgeInsets.only(left: 31, bottom: 3),
                                child: HtmlWidget(post.html,
                                    baseUrl: widget.forum.url('/'),
                                    textStyle: const TextStyle(
                                        fontSize: 14, height: 1.35),
                                    customStylesBuilder: (e) =>
                                        e.localName == 'p'
                                            ? {'margin': '4px 0'}
                                            : null)),
                          ])),
              ]
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final previous = adjacent(-1), next = adjacent(1);
    final previousPage = previous == null ? null : neighborCard(previous);
    final nextPage = next == null ? null : neighborCard(next);
    return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: pointerDown,
        onPointerMove: pointerMove,
        onPointerUp: pointerUp,
        onPointerCancel: (_) => cancelSwipe(),
        child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ClipRect(
                child: AnimatedBuilder(
                    animation: Listenable.merge([pageSlide, cardInset]),
                    builder: (context, child) {
                      final inset = cardInset.value;
                      final scale = 1 - .16 * inset;
                      Widget card(Widget page, double position, String key) =>
                          FractionalTranslation(
                              key: ValueKey(key),
                              translation:
                                  Offset(position * (1 - .12 * inset), 0),
                              child: Transform.scale(
                                  scale: scale,
                                  child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(18 * inset),
                                      child: RepaintBoundary(child: page))));
                      return Stack(fit: StackFit.expand, children: [
                        ...[
                          if (previousPage != null)
                            Offstage(
                                offstage: inset == 0,
                                child: IgnorePointer(
                                    child: ExcludeSemantics(
                                        child: card(
                                            previousPage,
                                            pageSlide.value - 1,
                                            'previous-topic-card')))),
                          if (nextPage != null)
                            Offstage(
                                offstage: inset == 0,
                                child: IgnorePointer(
                                    child: ExcludeSemantics(
                                        child: card(
                                            nextPage,
                                            pageSlide.value + 1,
                                            'next-topic-card')))),
                        ],
                        card(child!, pageSlide.value, 'current-topic-card'),
                      ]);
                    },
                    child: AbsorbPointer(
                        absorbing: switchingTopic || draggingTopic,
                        child: buildPage(context))))));
  }

  Widget buildPage(BuildContext context) {
    final replies = visibleReplies;
    final lines = threadLines(replies);
    return Scaffold(
        floatingActionButton: ValueListenableBuilder<bool>(
            valueListenable: showBackToTop,
            builder: (context, visible, _) => visible
                ? FloatingActionButton.small(
                    tooltip: uiTr(context, '回到顶部'),
                    onPressed: () {
                      if (scroll.hasClients)
                        scroll.animateTo(0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut);
                    },
                    child: const Icon(Icons.vertical_align_top))
                : const SizedBox.shrink()),
        appBar: AppBar(
            toolbarHeight: 48,
            leadingWidth: 44,
            titleSpacing: 0,
            actions: [
              if (!widget.forum.discourse ||
                  (!flatReplies &&
                      threadPosts.any((p) =>
                          p.parentId != null &&
                          ['c', 'd'].contains(p.threadStyle))))
                PopupMenuButton<String>(
                    tooltip: uiTr(context, '回复展开选项'),
                    constraints:
                        const BoxConstraints(minWidth: 0, maxWidth: 148),
                    onSelected: (value) async {
                      if (value == 'style') {
                        await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    V2ThreadSettingsPage(widget.forum)));
                        if (mounted) {
                          collapsedReplies.clear();
                          previewCache.clear();
                          previewText.clear();
                          await reload();
                        }
                        return;
                      }
                      setState(() {
                        if (value == 'expand') {
                          collapsedReplies.clear();
                        } else {
                          collapsedReplies.addAll(threadPosts
                              .where((p) =>
                                  p.parentId != null &&
                                  ['c', 'd'].contains(p.threadStyle))
                              .map((p) => p.parentId!));
                        }
                      });
                    },
                    itemBuilder: (_) => [
                          if (!widget.forum.discourse)
                            const PopupMenuItem(
                                value: 'style',
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: UiText('V2EX 回复样式')),
                          if (!flatReplies &&
                              threadPosts.any((p) =>
                                  p.parentId != null &&
                                  ['c', 'd'].contains(p.threadStyle))) ...[
                            const PopupMenuItem(
                                value: 'expand',
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: UiText('全部展开')),
                            const PopupMenuItem(
                                value: 'collapse',
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: UiText('全部折叠')),
                          ]
                        ]),
            ],
            title: Tooltip(
                message: topicTitle,
                child: Row(children: [
                  ForumIcon(widget.forum),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(topicTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.2,
                              fontWeight: FontWeight.w600)))
                ]))),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: FilledButton.icon(
                    onPressed: () => compose(),
                    icon: const Icon(Icons.edit_outlined),
                    label: const UiText('写回复')))),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: reload,
                child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
                    itemCount: replies.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0)
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outlineVariant
                                              .withValues(alpha: .5))),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(children: [
                                          MemberAvatar(
                                              widget.forum,
                                              activeTopic.avatar.isNotEmpty
                                                  ? activeTopic.avatar
                                                  : data?.original?.avatar ??
                                                      '',
                                              data?.original?.author ??
                                                  activeTopic.author,
                                              size: 26),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: InkWell(
                                                  onTap: () => openMember(
                                                      context,
                                                      widget.forum,
                                                      data?.original?.author ??
                                                          activeTopic.author),
                                                  child: Text(
                                                      data?.original?.author ??
                                                          activeTopic.author,
                                                      style: const TextStyle(
                                                          fontSize: 12)))),
                                          TimeLabel(
                                              data?.original?.createdAt ??
                                                  activeTopic.createdAt,
                                              fallback:
                                                  data?.original?.timeLabel ??
                                                      ''),
                                          const SizedBox(width: 8),
                                          if (category.isNotEmpty)
                                            Flexible(
                                                child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 7,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5)),
                                                    child: Text(category,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 11))))
                                        ]),
                                        const Divider(height: 16),
                                        if (data != null)
                                          render(data!.body)
                                        else if (activeTopic.preview.isNotEmpty)
                                          render(activeTopic.preview),
                                        for (final entry
                                            in (data?.supplements ??
                                                    <Supplement>[])
                                                .indexed)
                                          Container(
                                              width: double.infinity,
                                              margin: const EdgeInsets.only(
                                                  top: 16),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .secondaryContainer
                                                      .withValues(alpha: .4),
                                                  border: Border(
                                                      left: BorderSide(
                                                          width: 3,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary))),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                        entry.$2.timeLabel
                                                                .isNotEmpty
                                                            ? entry.$2.timeLabel
                                                            : 'Supplement ${entry.$1 + 1}',
                                                        style: const TextStyle(
                                                            fontSize: 11)),
                                                    const SizedBox(height: 8),
                                                    render(entry.$2.body)
                                                  ])),
                                        if (widget.forum.discourse &&
                                            (data?.original?.version ?? 1) > 1)
                                          Container(
                                              width: double.infinity,
                                              margin: const EdgeInsets.only(
                                                  top: 12),
                                              padding: const EdgeInsets.all(10),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      const Icon(
                                                          Icons.edit_note,
                                                          size: 18),
                                                      const UiText(' 正文已更新 · ',
                                                          style: TextStyle(
                                                              fontSize: 12)),
                                                      TimeLabel(data!
                                                          .original!.updatedAt)
                                                    ]),
                                                    if (data!.original!
                                                        .editReason.isNotEmpty)
                                                      Text(
                                                          data!.original!
                                                              .editReason,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 12))
                                                  ])),
                                        if (data?.original != null)
                                          Align(
                                              alignment: Alignment.centerRight,
                                              child: SocialBar(
                                                  widget.forum,
                                                  activeTopic.id,
                                                  data!.original!.id,
                                                  liked: data!.original!.liked,
                                                  likes: data!.original!.likes,
                                                  original: true,
                                                  key: ValueKey(
                                                      'social/${activeTopic.id}/${data!.original!.id}'))),
                                        if (loading)
                                          const Padding(
                                              padding: EdgeInsets.all(20),
                                              child: LinearProgressIndicator()),
                                        if (error != null)
                                          Problem(
                                              error!,
                                              reload,
                                              () => authenticate(
                                                      context, widget.forum)
                                                  .then((_) => reload()),
                                              needsLogin: errorNeedsLogin),
                                      ])),
                              if (data != null) ...[
                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(
                                      child: UiText(
                                          flatReplies && !data!.hasMore
                                              ? '回复 · ${replies.length}'
                                              : '回复 · ${data!.posts.length}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600))),
                                  TextButton(
                                      style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          minimumSize: const Size(0, 36),
                                          foregroundColor: onlyAuthor
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant),
                                      onPressed: () =>
                                          changeReplyView('author'),
                                      child: UiText(
                                          onlyAuthor ? '✓ 只看楼主' : '只看楼主',
                                          style:
                                              const TextStyle(fontSize: 12))),
                                  TextButton.icon(
                                      style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          minimumSize: const Size(0, 36)),
                                      onPressed: () => changeReplyView('order'),
                                      icon: Icon(
                                          newestFirst
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          size: 14),
                                      label: UiText(newestFirst ? '倒序' : '正序',
                                          style:
                                              const TextStyle(fontSize: 12))),
                                ]),
                              ],
                            ]);
                      if (index == replies.length + 1) {
                        if (data == null) return const SizedBox.shrink();
                        if (flatReplies && data!.hasMore) {
                          if (moreFailed)
                            return TextButton(
                                onPressed: collectReplies,
                                child: const UiText('回复加载失败，点击重试'));
                          return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 8),
                                UiText(
                                    '正在加载全部回复以确保顺序和筛选完整，已加载 ${data!.posts.length} 条')
                              ]));
                        }
                        return data!.hasMore
                            ? moreFailed
                                ? TextButton(
                                    onPressed: loadMore,
                                    child: const UiText('加载失败，点击重试'))
                                : Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                        child: more
                                            ? const CircularProgressIndicator()
                                            : const UiText('继续下滑自动加载回复')))
                            : const Padding(
                                padding: EdgeInsets.all(20),
                                child: UiText('已读完全部回复',
                                    textAlign: TextAlign.center));
                      }
                      final post = replies[index - 1];
                      final isThread = !flatReplies &&
                          ['c', 'd', 'f'].contains(post.threadStyle);
                      return Stack(children: [
                        CustomPaint(
                            painter: flatReplies
                                ? null
                                : post.threadStyle == 'f'
                                    ? ThreadLines(lines, index - 1)
                                    : ['c', 'd'].contains(post.threadStyle)
                                        ? TreeReplyLines(
                                            replies,
                                            index - 1,
                                            Theme.of(context)
                                                .dividerColor
                                                .withValues(alpha: .65))
                                        : null,
                            child: Container(
                                key: replyKeys.putIfAbsent(
                                    post.id, () => GlobalKey()),
                                margin: EdgeInsets.only(
                                    left: flatReplies
                                        ? 0
                                        : post.threadStyle == 'f'
                                            ? 44
                                            : (['c', 'd']
                                                    .contains(post.threadStyle)
                                                ? (post.threadDepth > 0
                                                    ? post.threadDepth
                                                            .clamp(0, 3) *
                                                        22.0
                                                    : (post.parentId != null
                                                        ? 22.0
                                                        : 0.0))
                                                : 0)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Theme.of(context)
                                                .dividerColor
                                                .withValues(alpha: .14)))),
                                child:
                                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  if (!widget.forum.discourse &&
                                      post.threadStyle != 'c' &&
                                      (post.parentId != null ||
                                          post.parentLabel.isNotEmpty))
                                    InkWell(
                                      onTap: () {
                                        if (post.threadStyle != 'b') {
                                          jumpToParent(post);
                                          return;
                                        }
                                        final parent = data!.posts
                                            .where((p) => p.id == post.parentId)
                                            .firstOrNull;
                                        showModalBottomSheet<void>(
                                            context: context,
                                            showDragHandle: true,
                                            builder: (c) => SafeArea(
                                                child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    child:
                                                        SingleChildScrollView(
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                          UiText(
                                                              parent == null
                                                                  ? (post
                                                                          .parentLabel
                                                                          .isEmpty
                                                                      ? '上层回复'
                                                                      : post
                                                                          .parentLabel)
                                                                  : '#' +
                                                                      parent
                                                                          .number
                                                                          .toString() +
                                                                      ' ' +
                                                                      parent
                                                                          .author,
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold)),
                                                          const SizedBox(
                                                              height: 8),
                                                          if (parent != null)
                                                            render(parent.html)
                                                          else
                                                            UiText(post
                                                                    .parentExcerpt
                                                                    .isEmpty
                                                                ? '该回复不在当前已加载页面。'
                                                                : post
                                                                    .parentExcerpt),
                                                          TextButton(
                                                              onPressed: () {
                                                                Navigator.pop(
                                                                    c);
                                                                jumpToParent(
                                                                    post);
                                                              },
                                                              child:
                                                                  const UiText(
                                                                      '跳转到原回复')),
                                                        ])))));
                                      },
                                      child: Container(
                                          decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: .55),
                                              borderRadius:
                                                  BorderRadius.circular(5)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 5),
                                          margin:
                                              const EdgeInsets.only(bottom: 5),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                UiText(
                                                    post.parentLabel.isNotEmpty
                                                        ? post.parentLabel
                                                        : '↳ 回复 ${data!.posts.where((p) => p.id == post.parentId).map((p) => "#${p.number} ${p.author}").firstOrNull ?? "上层回复"}',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary)),
                                                if (post.threadStyle == 'h' &&
                                                    post.parentHtml.isNotEmpty)
                                                  render(post.parentHtml),
                                                if (post.threadStyle != 'h' &&
                                                    post.parentExcerpt
                                                        .isNotEmpty &&
                                                    post.threadStyle != 'b')
                                                  Text(post.parentExcerpt,
                                                      maxLines:
                                                          post.threadStyle ==
                                                                  'h'
                                                              ? 4
                                                              : 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 11)),
                                              ])),
                                    ),
                                  Row(children: [
                                    MemberAvatar(
                                        widget.forum, post.avatar, post.author,
                                        size: 24),
                                    const SizedBox(width: 7),
                                    if (isOriginalPoster(post))
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6),
                                          child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(4)),
                                              child: const UiText('楼主',
                                                  style: TextStyle(
                                                      fontSize: 10)))),
                                    Expanded(
                                        child: InkWell(
                                            onTap: () => openMember(context,
                                                widget.forum, post.author),
                                            child: Text(post.author,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600)))),
                                    TimeLabel(post.createdAt,
                                        fallback: post.timeLabel),
                                    const SizedBox(width: 6),
                                    Text('#${post.number}',
                                        style: const TextStyle(fontSize: 11)),
                                    SocialBar(
                                        widget.forum, activeTopic.id, post.id,
                                        liked: post.liked,
                                        likes: post.likes,
                                        page: post.sourcePage,
                                        key: ValueKey('social/${post.id}')),
                                    IconButton(
                                        tooltip:
                                            uiTr(context, '回复 ${post.author}'),
                                        constraints: const BoxConstraints(
                                            minWidth: 36, minHeight: 36),
                                        padding: const EdgeInsets.all(8),
                                        icon: const Icon(Icons.reply, size: 18),
                                        onPressed: () => compose(post)),
                                  ]),
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          left: 31, bottom: 3),
                                      child: render(post.html)),
                                  if (isThread &&
                                      ['c', 'd'].contains(post.threadStyle) &&
                                      childCount(post.id) > 0)
                                    if (collapsedReplies.contains(post.id))
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(left: 12),
                                          child: InkWell(
                                              onTap: () => setState(() => collapsedReplies
                                                  .remove(post.id)),
                                              child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                        width: 17,
                                                        height: 17,
                                                        decoration: BoxDecoration(
                                                            border: Border(
                                                                left: BorderSide(
                                                                    color: Theme.of(context)
                                                                        .dividerColor),
                                                                bottom: BorderSide(
                                                                    color: Theme.of(
                                                                            context)
                                                                        .dividerColor)),
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .only(
                                                                    bottomLeft:
                                                                        Radius.circular(
                                                                            8)))),
                                                    const SizedBox(width: 5),
                                                    Icon(
                                                        Icons
                                                            .add_circle_outline,
                                                        size: 17,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant),
                                                    const SizedBox(width: 4),
                                                    UiText(
                                                        childCount(post.id)
                                                                .toString() +
                                                            ' 条回复',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .onSurfaceVariant)),
                                                  ])))
                                    else
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: SizedBox(
                                              width: 28,
                                              height: 22,
                                              child: IconButton(
                                                  tooltip:
                                                      uiTr(context, '折叠回复'),
                                                  padding: EdgeInsets.zero,
                                                  onPressed: () => setState(
                                                      () => collapsedReplies
                                                          .add(post.id)),
                                                  icon: Icon(Icons.remove_circle_outline,
                                                      size: 17,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant)))),
                                ]))),
                      ]);
                    }))));
  }
}

class Composer extends StatefulWidget {
  final bool creating;
  final Forum forum;
  final Topic topic;
  final Post? quote;
  const Composer(this.forum, this.topic,
      {this.quote, this.creating = false, super.key});
  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final title = TextEditingController();
  final tags = TextEditingController();
  ForumSection? section;
  List<ForumSection> sections = [];
  Future<void> pickSection() async {
    String query = '';
    final chosen = await showModalBottomSheet<ForumSection>(
        context: context,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
            builder: (c, update) => SafeArea(
                child: SizedBox(
                    height: MediaQuery.sizeOf(c).height * .75,
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          UiText(widget.forum.discourse ? '选择可发帖分类' : '选择节点'),
                          TextField(
                              decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: uiTr(context, '搜索名称')),
                              onChanged: (s) =>
                                  update(() => query = s.toLowerCase())),
                          Expanded(
                              child: ListView(children: [
                            for (final s in sections.where((s) =>
                                '${s.parentName} ${s.name} ${s.id}'
                                    .toLowerCase()
                                    .contains(query)))
                              ListTile(
                                  dense: true,
                                  title: Text(s.name),
                                  subtitle: s.parentName.isEmpty
                                      ? null
                                      : Text(s.parentName),
                                  onTap: () => Navigator.pop(c, s))
                          ]))
                        ]))))));
    if (chosen != null && mounted) {
      setState(() => section = chosen);
      await prepare();
    }
  }

  bool uploading = false;
  String uploadStage = '';
  String? uploadError;
  void insert(String value) {
    final selection = text.selection;
    final start = selection.isValid ? selection.start : text.text.length;
    final end = selection.isValid ? selection.end : text.text.length;
    final added = '\n$value\n';
    text.value = TextEditingValue(
        text: text.text.replaceRange(start, end, added),
        selection: TextSelection.collapsed(offset: start + added.length));
    drafts[keyName] = text.text;
  }

  Future<void> imageLink() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const UiText('插入图片链接'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (!widget.forum.discourse)
                    const UiText(
                        'V2EX 优先使用 i.imgur.com 或 i.v2ex.co 的图片链接；其他地址可能仅显示为链接。',
                        style: TextStyle(fontSize: 12)),
                  TextField(
                      controller: controller,
                      keyboardType: TextInputType.url,
                      autofocus: true,
                      decoration: InputDecoration(hintText: 'https://…'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const UiText('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, controller.text.trim()),
                      child: const UiText('插入'))
                ]));
    // Dispose after dialog animation has released its TextField.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (value == null || !mounted) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        value.contains(RegExp(r'[\s\[\]()]'))) {
      setState(() => uploadError = '请输入完整的 HTTPS 图片地址');
      return;
    }
    insert(widget.forum.discourse || widget.creating ? '![图片]($value)' : value);
  }

  Future<void> uploadImage() async {
    if (uploading || sending) return;
    setState(() {
      uploadError = null;
      uploading = true;
      uploadStage = widget.forum.discourse ? '正在打开图片选择器…' : '正在检查 Imgur 登录状态…';
    });
    try {
      ImgurAccount? imgurAccount;
      if (!widget.forum.discourse) {
        try {
          imgurAccount =
              await ImgurSession.current().timeout(const Duration(seconds: 40));
        } catch (_) {}
        if (!mounted) return;
        if (imgurAccount == null) {
          setState(() => uploadStage = '请完成 Imgur 登录，完成后继续选图…');
          if (!await ImgurSession.connect(context)) return;
          if (!mounted) return;
          setState(() => uploadStage = '正在确认 Imgur 账号…');
          imgurAccount =
              await ImgurSession.current().timeout(const Duration(seconds: 40));
          if (imgurAccount == null)
            throw const ForumError('尚未取得 Imgur 登录态，请完成登录后重试');
        }
      }
      if (!mounted) return;
      setState(() => uploadStage = '请选择图片…');
      final selected = await SelectedImage.pick();
      if (selected == null || !mounted) return;
      setState(() => uploadStage = '请确认预览并上传…');
      final accepted = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const UiText('上传图片'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Image.memory(selected.bytes,
                        height: 180,
                        cacheWidth: 600,
                        errorBuilder: (_, e, s) =>
                            const Icon(Icons.image, size: 64)),
                    const SizedBox(height: 8),
                    UiText(
                        '上传到 ${widget.forum.discourse ? 'LINUX DO' : 'Imgur'}，成功后插入草稿。\n${(selected.bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
                        style: const TextStyle(fontSize: 12))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const UiText('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const UiText('上传'))
                  ]));
      if (accepted != true || !mounted) return;
      setState(() => uploadStage =
          '正在上传到 ${widget.forum.discourse ? 'LINUX DO' : 'Imgur'}…');
      final markup = await ImageUploads.upload(widget.forum, selected,
          imgurAccount: imgurAccount);
      if (mounted) {
        insert(widget.creating && !widget.forum.discourse
            ? '![图片]($markup)'
            : markup);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: UiText('图片已上传并插入草稿，尚未发布')));
      }
    } catch (e) {
      if (mounted) setState(() => uploadError = e.toString());
    } finally {
      if (mounted)
        setState(() {
          uploading = false;
          uploadStage = '';
        });
    }
  }

  static final drafts = <String, String>{};
  static final draftReplyTargets = <String, Post?>{};
  late final TextEditingController text;
  Post? replyTarget;
  ReplyTicket? ticket;
  bool preparing = true, sending = false, uncertain = false;
  String? error;
  String get keyName => '${widget.forum.host}/${widget.topic.id}';
  @override
  void initState() {
    super.initState();
    replyTarget = widget.quote ?? draftReplyTargets[keyName];
    text = TextEditingController(
        text: drafts[keyName] ??
            (widget.quote != null && !widget.forum.discourse
                ? '@${widget.quote!.author} '
                : ''));
    if (widget.creating) {
      title.text = drafts['$keyName/title'] ?? '';
      tags.text = drafts['$keyName/tags'] ?? '';
    }
    prepare();
  }

  @override
  void dispose() {
    if (text.text.isNotEmpty) {
      drafts[keyName] = text.text;
      draftReplyTargets[keyName] = replyTarget;
    } else {
      drafts.remove(keyName);
      draftReplyTargets.remove(keyName);
    }
    if (widget.creating) {
      drafts['$keyName/title'] = title.text;
      drafts['$keyName/tags'] = tags.text;
    }
    title.dispose();
    tags.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> prepare() async {
    setState(() {
      preparing = true;
      error = null;
    });
    try {
      final ReplyTicket result;
      if (widget.creating) {
        final publisher = TopicPublisher(widget.forum);
        final form = await publisher.prepare(section);
        sections = await publisher.sections();
        if (sections.isEmpty) throw const ForumError('当前账号没有可发帖的分类');
        result = ReplyTicket(form.token);
      } else {
        result = await widget.forum.prepareReply(widget.topic.id);
      }
      if (mounted) setState(() => ticket = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => preparing = false);
    }
  }

  Future<void> send() async {
    if (sending || uploading || uncertain || text.text.trim().isEmpty) return;
    if (widget.creating && (title.text.trim().isEmpty || section == null)) {
      setState(() => error = '请填写标题并选择${widget.forum.discourse ? '分类' : '节点'}');
      return;
    }
    final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: UiText(widget.creating ? '发布这个主题？' : '发布这条回复？'),
                content: UiText(
                    '将发布到 ${widget.forum.name}${widget.creating ? ' · ${section!.name}' : ''}：\n${widget.creating ? title.text.trim() : widget.topic.title}${widget.creating && !widget.forum.discourse ? '\nV2EX 发帖可能消耗铜币，以网站规则为准。' : ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const UiText('继续编辑')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const UiText('发布'))
                ]));
    if (accepted != true || !mounted) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      if (widget.creating) {
        final result = await TopicPublisher(widget.forum).publish(
            title.text, text.text, section!,
            tags: tags.text
                .split(RegExp(r'[,，\s]+'))
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList());
        drafts.remove(keyName);
        text.clear();
        title.clear();
        tags.clear();
        if (mounted) {
          if (result == null)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: UiText('主题已提交审核，请勿重复发布')));
          Navigator.pop(context, result);
        }
        return;
      }
      final fresh = await widget.forum.prepareReply(widget.topic.id);
      await widget.forum.submit(widget.topic.id, text.text, fresh,
          replyTo:
              widget.forum.discourse ? replyTarget?.number : replyTarget?.id);
      drafts.remove(keyName);
      draftReplyTargets.remove(keyName);
      text.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          error = e.toString();
          uncertain = error!.contains('未确认');
        });
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !sending && !uploading,
      child: Scaffold(
          appBar: AppBar(
              title:
                  UiText(widget.creating ? '${widget.forum.name} · 发帖' : '写回复'),
              actions: [
                TextButton(
                    onPressed: ticket != null &&
                            !preparing &&
                            !sending &&
                            !uploading &&
                            !uncertain
                        ? send
                        : null,
                    child: UiText(sending ? '发送中…' : '发送'))
              ]),
          body: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.creating) ...[
                          TextField(
                              controller: title,
                              enabled: !sending && !uploading,
                              maxLines: 2,
                              minLines: 1,
                              decoration: InputDecoration(
                                  hintText: uiTr(context, '标题'),
                                  border: InputBorder.none)),
                          TextButton.icon(
                              onPressed: preparing || sending || uploading
                                  ? null
                                  : pickSection,
                              icon: const Icon(Icons.folder_outlined, size: 18),
                              label: UiText(section?.name ??
                                  (widget.forum.discourse ? '选择分类' : '选择节点'))),
                          if (widget.forum.discourse)
                            TextField(
                                controller: tags,
                                enabled: !sending && !uploading,
                                decoration: InputDecoration(
                                    isDense: true,
                                    hintText: uiTr(context, '标签（逗号分隔，部分分类必填）'),
                                    border: InputBorder.none)),
                          const Divider(height: 8),
                        ],
                        if (!widget.creating && replyTarget != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(children: [
                              const Icon(Icons.reply, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  UiText(
                                      '正在回复 @${replyTarget!.author} · #${replyTarget!.number}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                      html_parser
                                              .parse(replyTarget!.html)
                                              .body
                                              ?.text
                                              .trim()
                                              .replaceAll(
                                                  RegExp(r'\s+'), ' ') ??
                                          '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              )),
                              IconButton(
                                tooltip: uiTr(context, '取消回复目标'),
                                onPressed: sending || uploading
                                    ? null
                                    : () => setState(() => replyTarget = null),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ]),
                          ),
                        if (!widget.creating && replyTarget == null)
                          ExpansionTile(
                              dense: true,
                              tilePadding: EdgeInsets.zero,
                              title: UiText('查看回复主题',
                                  style: const TextStyle(fontSize: 12)),
                              children: [
                                Text(widget.topic.title,
                                    style: const TextStyle(fontSize: 13))
                              ]),
                        if (preparing) const LinearProgressIndicator(),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(children: [
                                UiText(error!),
                                if (!uncertain)
                                  Wrap(children: [
                                    TextButton(
                                        onPressed: preparing ? null : prepare,
                                        child: const UiText('重试')),
                                    TextButton(
                                        onPressed: () async {
                                          await authenticate(
                                              context, widget.forum);
                                          if (mounted) prepare();
                                        },
                                        child: const UiText('登录 / 验证'))
                                  ])
                              ])),
                        Expanded(
                            child: TextField(
                                controller: text,
                                enabled: !sending && !uploading,
                                expands: true,
                                maxLines: null,
                                minLines: null,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                    hintText: uiTr(
                                        context,
                                        widget.creating
                                            ? '正文（支持 Markdown）…'
                                            : '写下你的回复…'),
                                    border: InputBorder.none))),
                        if (uploading) const LinearProgressIndicator(),
                        if (uploadError != null)
                          UiText(uploadError!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error)),
                        Row(children: [
                          TextButton.icon(
                              onPressed:
                                  sending || uploading ? null : uploadImage,
                              icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 20),
                              label: UiText(uploading ? '处理中…' : '上传图片')),
                          TextButton.icon(
                              onPressed:
                                  sending || uploading ? null : imageLink,
                              icon: const Icon(Icons.link, size: 20),
                              label: const UiText('图片链接'))
                        ]),
                        if (uploading) ...[
                          const LinearProgressIndicator(),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(uploadStage,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                        const UiText('发送前会再次确认；失败时保留编辑内容。',
                            style: TextStyle(fontSize: 12)),
                      ])))));
}

class Problem extends StatelessWidget {
  final String message;
  final VoidCallback retry, login;
  final bool needsLogin;
  const Problem(this.message, this.retry, this.login,
      {this.needsLogin = false, super.key});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            UiText(message),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: retry, child: const UiText('重试')),
              if (needsLogin)
                FilledButton(onPressed: login, child: const UiText('登录 / 验证'))
            ])
          ])));
}

class ForumIcon extends StatelessWidget {
  final Forum forum;
  const ForumIcon(this.forum, {super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.asset(
          forum.discourse ? 'assets/linuxdo.png' : 'assets/v2ex.png',
          width: 24,
          height: 24));
}

class ForumTitle extends StatelessWidget {
  final Forum forum;
  const ForumTitle(this.forum, {super.key});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        ForumIcon(forum),
        const SizedBox(width: 8),
        Flexible(
            child: Text(forum.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))
      ]);
}

class UserAvatar extends StatelessWidget {
  final String url, name;
  final double size;
  const UserAvatar(this.url, this.name, {this.size = 28, super.key});
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Center(
            child: Text(
                name.isEmpty ? '·' : name.characters.first.toUpperCase(),
                style: TextStyle(fontSize: size * .45))));
    return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
            width: size,
            height: size,
            child: url.isEmpty
                ? fallback
                : FutureBuilder(
                    future: AvatarLoader.load(url),
                    builder: (context, snapshot) => snapshot.hasData
                        ? Image.memory(snapshot.data!,
                            cacheWidth: 96,
                            cacheHeight: 96,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.low,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stack) => fallback)
                        : fallback)));
  }
}

class TimeLabel extends StatelessWidget {
  final DateTime? date;
  final String fallback;
  const TimeLabel(this.date, {this.fallback = '', super.key});
  @override
  Widget build(BuildContext context) {
    String label = fallback.split('·').first.trim();
    String full = label;
    if (date != null) {
      final local = date!.toLocal();
      full = local.toString().split('.').first;
      final delta = DateTime.now().difference(local);
      if (delta.isNegative || delta.inMinutes < 1) {
        label = '刚刚';
      } else if (delta.inHours < 1) {
        label = '${delta.inMinutes}分钟前';
      } else if (delta.inDays < 1) {
        label = '${delta.inHours}小时前';
      } else if (delta.inDays < 7) {
        label = '${delta.inDays}天前';
      } else {
        label =
            '${local.year == DateTime.now().year ? '' : '${local.year}/'}${local.month}/${local.day}';
      }
    }
    return Tooltip(
        message: full.isEmpty ? '时间未提供' : full,
        child: UiText(label.isEmpty ? '时间未知' : label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)));
  }
}
