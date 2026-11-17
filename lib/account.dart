import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'forum.dart';
import 'session.dart';

class ForumAccount {
  final String username, avatar, logoutPath;
  const ForumAccount(this.username, this.avatar, {this.logoutPath = ''});
}

class AccountService {
  final Forum forum;
  const AccountService(this.forum);

  Future<ForumAccount?> current() async {
    if (forum.discourse) {
      final response = await forum.get('/session/current.json');
      if (response.status == 404 || response.status == 401) return null;
      checkResponse(response);
      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        throw const ForumError('暂时无法读取账号信息，请稍后重试');
      }
      if (data is! Map || !data.containsKey('current_user')) {
        throw const ForumError('账号接口暂未返回有效数据');
      }
      final user = data['current_user'];
      if (user == null) return null;
      if (user is! Map ||
          user['username'] is! String ||
          (user['username'] as String).isEmpty) {
        throw const ForumError('账号接口暂未返回有效数据');
      }
      return ForumAccount(
          user['username'] as String, forum.avatarUrl(user['avatar_template']));
    }
    final response = await forum.get('/');
    checkResponse(response);
    return parseV2(response.body);
  }

  ForumAccount? parseV2(String body) {
    final doc = html.parse(body);
    final member = doc.querySelector(
        '#menu-body a[href^="/member/"], .tools a[href^="/member/"]');
    if (member == null) {
      if (doc.querySelector(
              '#menu-body a[href="/signin"], .tools a[href="/signin"]') !=
          null) return null;
      throw const ForumError('无法确认登录状态，请刷新或完成验证');
    }
    final username =
        Uri.decodeComponent(member.attributes['href']!.split('/').last);
    final avatar = doc.querySelector(
        '#menu-entry img.avatar, #site-header img.avatar, #Right img.avatar, #menu-body img.avatar');
    final logout =
        RegExp(r'''/signout\?once=\d+''').firstMatch(body)?.group(0) ?? '';
    return ForumAccount(username, forum.avatarUrl(avatar?.attributes['src']),
        logoutPath: logout);
  }

  Future<void> logout() async {
    final account = await current();
    if (account == null) return;
    if (forum.discourse) {
      final csrf = decodeResponse(await forum.get('/session/csrf.json'))['csrf']
          as String?;
      if (csrf == null || csrf.isEmpty)
        throw const ForumError('退出失败，请刷新登录状态后重试');
      final response = await forum.transport(
          forum.url('/session/${Uri.encodeComponent(account.username)}'),
          method: 'DELETE',
          headers: {
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': forum.url('/').toString()
          });
      if (![200, 204].contains(response.status))
        throw const ForumError('退出未成功，请重试');
    } else {
      if (account.logoutPath.isEmpty) throw const ForumError('未找到退出入口，请刷新后重试');
      final response = await forum.transport(forum.url(account.logoutPath),
          headers: {'Referer': forum.url('/').toString()});
      if (![200, 302, 303].contains(response.status))
        throw const ForumError('退出未成功，请重试');
    }
    if (await current() != null) throw const ForumError('退出状态未确认，请重试');
  }
}

class AccountState {
  final ForumAccount? account;
  final bool loading;
  final String? error;
  final bool needsLogin, verified;
  const AccountState(
      {this.account,
      this.loading = false,
      this.error,
      this.needsLogin = false,
      this.verified = false});
  String get label =>
      needsLogin ? '登录 / 验证' : account?.username ?? (verified ? '登录' : '账号');
}

class Accounts {
  static final states = [
    ValueNotifier(const AccountState(loading: true)),
    ValueNotifier(const AccountState(loading: true))
  ];
  static final _generation = [0, 0];
  static final List<Future<void>?> _inFlight = [null, null];
  static Future<void> _writes = Future.value();
  static Future<void> load() async {
    try {
      final data = await Session.channel
          .invokeMapMethod<String, dynamic>('getPreferences');
      final cached =
          jsonDecode(data?['knownAccounts'] as String? ?? '{}') as Map;
      for (var i = 0; i < forums.length; i++) {
        final value = cached[forums[i].host];
        if (value is Map && value['username'] is String) {
          states[i].value = AccountState(
              loading: true,
              account: ForumAccount(value['username'] as String,
                  value['avatar'] as String? ?? ''));
        }
      }
    } catch (_) {}
  }

  static Future<void> _save() {
    final payload = jsonEncode({
      for (var i = 0; i < forums.length; i++)
        if (states[i].value.account != null)
          forums[i].host: {
            'username': states[i].value.account!.username,
            'avatar': states[i].value.account!.avatar,
          }
    });
    return _writes = _writes.then((_) async {
      try {
        await Session.channel
            .invokeMethod('setPreferences', {'knownAccounts': payload});
      } catch (_) {}
    });
  }

  static int index(Forum forum) => forum.discourse ? 1 : 0;
  static Future<void> refresh(Forum forum) async {
    final i = index(forum);
    if (_inFlight[i] != null) return _inFlight[i];
    final task = _refresh(forum);
    _inFlight[i] = task;
    try {
      await task;
    } finally {
      if (identical(_inFlight[i], task)) _inFlight[i] = null;
    }
  }

  static Future<void> _refresh(Forum forum) async {
    final i = index(forum), token = ++_generation[index(forum)];
    final previous = states[i].value;
    states[i].value = AccountState(
        account: previous.account,
        loading: true,
        needsLogin: previous.needsLogin,
        verified: previous.verified);
    try {
      final account = await AccountService(forum).current();
      if (token == _generation[i]) {
        states[i].value = AccountState(
            account: account,
            verified: true,
            needsLogin: account == null && previous.account != null);
        await _save();
      }
    } catch (e) {
      if (token == _generation[i])
        states[i].value = AccountState(
            account: previous.account,
            error: e.toString(),
            needsLogin:
                previous.needsLogin || (e is ForumError && e.needsLogin));
    }
  }

  static Future<void> logout(Forum forum) async {
    final i = index(forum);
    ++_generation[i];
    _inFlight[i] = null;
    await AccountService(forum).logout();
    ++_generation[i];
    _inFlight[i] = null;
    states[i].value = const AccountState(verified: true);
    await _save();
  }
}
