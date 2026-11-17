import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'check_in.dart';
import 'forum.dart';
import 'session.dart';

class BalanceRecord {
  final String kind, time, amount, balance, description;
  const BalanceRecord(
      this.kind, this.time, this.amount, this.balance, this.description);
  String get signature => '$kind|$time|$amount|$balance|$description';
}

class V2Balance {
  final Map<String, int> coins;
  final List<BalanceRecord> records;
  final int pages;
  const V2Balance(this.coins, this.records, this.pages);
  static V2Balance parse(String body) {
    final doc = html.parse(body);
    final area = doc.querySelector('.balance_area');
    if (area == null) throw const ForumError('无法读取余额，请确认登录状态');
    final coins = <String, int>{'G': 0, 'S': 0, 'B': 0};
    var pending = '';
    var found = false;
    for (final n in area.nodes) {
      if (n is dom.Text) pending += n.text;
      if (n is dom.Element && n.localName == 'img') {
        final key = n.attributes['alt']?.toUpperCase();
        final value = RegExp(r'(\d+)\s*$').firstMatch(pending)?.group(1);
        if (coins.containsKey(key) && value != null) {
          coins[key!] = int.parse(value);
          found = true;
        }
        pending = '';
      }
    }
    if (!found) throw const ForumError('余额格式无法识别');
    final records = <BalanceRecord>[];
    for (final row in doc.querySelectorAll('tr')) {
      if (row.querySelector('td.d') == null) continue;
      final cells = row.querySelectorAll('td.d');
      if (cells.length < 4) continue;
      String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
      final time = clean(cells[0].querySelector('small')?.text ?? '');
      final title = clean(
          cells[0].nodes.whereType<dom.Text>().map((n) => n.text).join(' '));
      records.add(BalanceRecord(title, time, clean(cells[1].text),
          clean(cells[2].text), clean(cells[3].text)));
    }
    final pages = <int>[1];
    for (final a in doc.querySelectorAll('a[href]')) {
      final u = Uri.tryParse(a.attributes['href'] ?? '');
      if (u != null && (u.path == '/balance' || u.path.isEmpty)) {
        final n = int.tryParse(u.queryParameters['p'] ?? '');
        if (n != null && n > 0) pages.add(n);
      }
    }
    pages.sort();
    return V2Balance(coins, records, pages.last);
  }
}

class V2WalletPage extends StatefulWidget {
  final Forum forum;
  const V2WalletPage(this.forum, {super.key});
  @override
  State<V2WalletPage> createState() => _V2WalletPageState();
}

class _V2WalletPageState extends State<V2WalletPage> {
  V2Balance? balance;
  bool? signed;
  bool busy = true, signing = false;
  bool loadingMore = false, hasMore = true, moreFailed = false;
  final records = <BalanceRecord>[];
  final scroll = ScrollController();
  int page = 1;
  int generation = 0;
  String? error;
  Future<void> load({int? target}) async {
    if (busy && balance != null) return;
    final selected = target ?? page;
    final token = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        widget.forum.get('/balance?p=$selected'),
        widget.forum.get('/mission/daily')
      ]);
      for (final r in results) {
        if (r.location.contains('/signin'))
          throw const ForumError('请先登录', needsLogin: true);
        checkResponse(r);
      }
      final next = V2Balance.parse(results[0].body);
      final checked = DailyCheckIn.claimed(results[1].body);
      final canSign =
          RegExp(r'/mission/daily/redeem\?once=\d+').hasMatch(results[1].body);
      if (!mounted || token != generation) return;
      setState(() {
        balance = next;
        records
          ..clear()
          ..addAll(next.records);
        hasMore = next.records.isNotEmpty;
        moreFailed = false;
        signed = checked
            ? true
            : canSign
                ? false
                : null;
        page = selected;
      });
    } catch (e) {
      if (mounted && token == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && token == generation) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) nearEnd();
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    scroll.addListener(nearEnd);
    load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void nearEnd() {
    if (scroll.hasClients &&
        scroll.position.extentAfter < 400 &&
        !busy &&
        !loadingMore &&
        hasMore &&
        !moreFailed) loadMore();
  }

  Future<void> loadMore() async {
    if (busy || loadingMore || !hasMore) return;
    final token = generation;
    setState(() {
      loadingMore = true;
      moreFailed = false;
    });
    try {
      final r = await widget.forum.get('/balance?p=${page + 1}');
      if (r.location.contains('/signin'))
        throw const ForumError('请先登录', needsLogin: true);
      checkResponse(r);
      final next = V2Balance.parse(r.body);
      if (!mounted || token != generation) return;
      final duplicate = next.records.isNotEmpty &&
          records.length >= next.records.length &&
          next.records.asMap().entries.every((e) =>
              records[records.length - next.records.length + e.key].signature ==
              e.value.signature);
      setState(() {
        if (next.records.isEmpty || duplicate) {
          hasMore = false;
        } else {
          records.addAll(next.records);
          page++;
        }
      });
    } catch (e) {
      if (mounted && token == generation)
        setState(() {
          moreFailed = true;
          error = e.toString();
        });
    } finally {
      if (mounted) {
        setState(() => loadingMore = false);
        if (token == generation)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) nearEnd();
          });
      }
    }
  }

  Future<void> sign() async {
    if (signing || signed != false) return;
    setState(() => signing = true);
    try {
      final result = await DailyCheckIn.run();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result ?? '今日已签到')));
      if (mounted) await load(target: 1);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => signing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('V2EX 签到与余额'), actions: [
        IconButton(
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新')
      ]),
      body: busy && balance == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => load(),
              child: ListView(
                  controller: scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    if (balance != null) ...[
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('账户余额',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      for (final coin in [
                                        ('G', 'gold', '金币'),
                                        ('S', 'silver', '银币'),
                                        ('B', 'bronze', '铜币')
                                      ]) ...[
                                        Semantics(
                                            label: coin.$3,
                                            child: Image.asset(
                                                'assets/coins/${coin.$2}.png',
                                                width: 18,
                                                height: 18)),
                                        const SizedBox(width: 5),
                                        Text('${balance!.coins[coin.$1]}'),
                                        const SizedBox(width: 18),
                                      ]
                                    ]),
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      Expanded(
                                          child: Text(signed == true
                                              ? '今日已签到'
                                              : signed == false
                                                  ? '今日尚未签到'
                                                  : '签到状态暂不可用')),
                                      if (signed == false)
                                        FilledButton.tonal(
                                            onPressed: signing ? null : sign,
                                            child:
                                                Text(signing ? '签到中…' : '签到'))
                                    ]),
                                  ]))),
                      const SizedBox(height: 16),
                      const Text('余额记录',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      if (records.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('暂无可显示的记录')),
                      for (final r in records)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                                child: Text(r.kind,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13))),
                                            const SizedBox(width: 8),
                                            Text(r.amount,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        r.amount.startsWith('-')
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .error
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .primary)),
                                          ]),
                                      if (r.description.isNotEmpty)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(r.description,
                                                style: const TextStyle(
                                                    fontSize: 12))),
                                      const SizedBox(height: 5),
                                      Row(children: [
                                        Expanded(
                                            child: Text(r.time,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant))),
                                        Text('余额 ${r.balance}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant))
                                      ]),
                                    ]))),
                      if (loadingMore)
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator())),
                      if (moreFailed)
                        TextButton(
                            onPressed: loadMore,
                            child: const Text('加载失败，点击重试')),
                      if (!hasMore && records.isNotEmpty)
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child:
                                Text('已显示全部记录', textAlign: TextAlign.center)),
                    ],
                  ])));
}
