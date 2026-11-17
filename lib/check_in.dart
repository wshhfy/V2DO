import 'forum.dart';
import 'session.dart';

class DailyCheckIn {
  static Future<String?>? _running;
  static Future<String?> run() =>
      _running ??= perform(forums.first).whenComplete(() => _running = null);

  static bool claimed(String body) =>
      body.contains('每日登录奖励已领取') ||
      body.contains('已成功领取每日登录奖励') ||
      body.contains('Daily login reward received') ||
      body.contains('Daily login reward already redeemed');

  static Future<String?> perform(Forum forum) async {
    final page = await forum.get('/mission/daily');
    if (page.location.contains('/signin') || page.body.contains('你要查看的页面需要先登录'))
      return null;
    checkResponse(page);
    if (claimed(page.body)) return null;
    final match =
        RegExp(r'/mission/daily/redeem\?once=(\d+)').firstMatch(page.body);
    if (match == null) throw const ForumError('未找到签到入口，请确认 V2EX 登录状态');
    final response = await forum.transport(forum.url(match.group(0)!),
        headers: {'Referer': forum.url('/mission/daily').toString()});
    if (response.status != 302 && response.status != 303)
      checkResponse(response);
    // Never repeat redemption on an uncertain result. Read the server state instead.
    final verified = await forum.get('/mission/daily');
    checkResponse(verified);
    if (!claimed(verified.body)) throw const ForumError('签到结果未确认，请稍后查看签到状态');
    final reward =
        RegExp(r'已成功领取每日登录奖励\s*(\d+)\s*铜币').firstMatch(response.body);
    return reward == null
        ? 'V2EX 自动签到成功'
        : 'V2EX 自动签到成功，获得 ${reward.group(1)} 铜币';
  }
}
