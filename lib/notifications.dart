import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'account.dart';
import 'forum.dart';
import 'session.dart';

class ForumNotice {
  final String id, title, detail, author, avatar, timeLabel;
  final int? topicId;
  final int postNumber;
  final bool unread;
  final DateTime? createdAt;
  const ForumNotice(
      {required this.id,
      required this.title,
      this.detail = '',
      this.author = '',
      this.avatar = '',
      this.timeLabel = '',
      this.topicId,
      this.postNumber = 0,
      this.unread = false,
      this.createdAt});
}

class NoticePage {
  final List<ForumNotice> items;
  final bool hasMore;
  const NoticePage(this.items, this.hasMore);
}

class NoticeService {
  final Forum forum;
  const NoticeService(this.forum);
  Future<int> unreadCount() async {
    if (forum.discourse) {
      final r = await forum.get('/session/current.json');
      if ([401, 404].contains(r.status)) return 0;
      final user = decodeResponse(r)['current_user'];
      if (user == null) return 0;
      // The ordinary total and high-priority total are separate in Discourse.
      return (user['unread_notifications'] as int? ?? 0) +
          (user['unread_high_priority_notifications'] as int? ?? 0);
    }
    final r = await forum.get('/');
    checkResponse(r);
    return v2Count(r.body);
  }

  static int v2Count(String body) {
    final doc = html.parse(body);
    for (final link in doc.querySelectorAll('a[href^="/notifications"]')) {
      final match = RegExp(r'\d[\d,]*').firstMatch(link.text);
      if (match != null)
        return int.tryParse(match.group(0)!.replaceAll(',', '')) ?? 0;
    }
    return 0;
  }

  Future<NoticePage> list({int page = 0, int initialUnread = 0}) async {
    if (forum.discourse) {
      final d = decodeResponse(
          await forum.get('/notifications.json?offset=${page * 30}&limit=30'));
      final rows = (d['notifications'] as List? ?? []).map((n) {
        final data = n['data'] as Map? ?? {};
        const labels = {
          1: '提到了你',
          2: '回复了你',
          3: '引用了你',
          4: '编辑了帖子',
          5: '赞了你的帖子',
          6: '发送了私信',
          9: '邀请你参与主题',
          12: '授予徽章',
          14: '关注的主题有新回复',
          17: '点赞了你的帖子'
        };
        final title = html
                .parse(n['fancy_title']?.toString() ??
                    data['topic_title']?.toString() ??
                    data['badge_name']?.toString() ??
                    '论坛通知')
                .body
                ?.text ??
            '论坛通知';
        return ForumNotice(
            id: '${n['id']}',
            title: title,
            detail: labels[n['notification_type']] ?? '有一条新动态',
            author: data['display_username']?.toString() ??
                data['original_username']?.toString() ??
                '',
            avatar: forum.avatarUrl(n['acting_user_avatar_template']),
            topicId: n['topic_id'] as int?,
            postNumber: n['post_number'] as int? ?? 0,
            unread: n['read'] == false,
            createdAt: parseTime(n['created_at']));
      }).toList();
      final total = d['total_rows_notifications'] as int?;
      return NoticePage(
          rows, total != null ? (page + 1) * 30 < total : rows.length == 30);
    }
    final r = await forum.get('/notifications?p=${page + 1}');
    checkResponse(r);
    return parseV2(r.body, page: page, initialUnread: initialUnread);
  }

  NoticePage parseV2(String body, {int page = 0, int initialUnread = 0}) {
    final d = html.parse(body);
    if (d.querySelector('a[href="/signin"]') != null &&
        d.querySelector('#notifications .cell[id], #Main .cell[id]') == null) {
      throw const ForumError('请先登录查看消息', needsLogin: true);
    }
    final rows = <ForumNotice>[];
    for (final cell
        in d.querySelectorAll('#notifications .cell, #Main .cell')) {
      final link = cell.querySelector('a[href*="/t/"]');
      if (link == null) continue;
      final uri = forum.url(link.attributes['href'] ?? '');
      final id = RegExp(r'^/t/(\d+)').firstMatch(uri.path);
      if (id == null) continue;
      final author = cell
          .querySelectorAll('a[href^="/member/"]')
          .where((a) => a.text.trim().isNotEmpty)
          .firstOrNull;
      rows.add(ForumNotice(
          id: cell.id.isEmpty ? '${page}_${rows.length}' : cell.id,
          title: link.text.trim(),
          topicId: int.parse(id.group(1)!),
          postNumber: int.tryParse(RegExp(r'(?:reply|r_)(\d+)')
                      .firstMatch(uri.fragment)
                      ?.group(1) ??
                  '') ??
              0,
          author: author?.text.trim() ?? '',
          avatar: forum
              .avatarUrl(cell.querySelector('img.avatar')?.attributes['src']),
          detail: cell.querySelector('.payload')?.text.trim() ??
              cell.querySelector('.fade')?.text.trim() ??
              '',
          timeLabel: cell.querySelector('.ago')?.text.trim() ?? '',
          createdAt: parseTime(cell.querySelector('.ago')?.attributes['title']),
          unread: page == 0 && rows.length < initialUnread));
    }
    final last = d
        .querySelectorAll('.page_normal,.page_current')
        .map((e) => int.tryParse(e.text.trim()) ?? 1)
        .fold(1, (a, b) => a > b ? a : b);
    return NoticePage(rows, page + 1 < last);
  }

  Future<void> markRead(ForumNotice notice) async {
    if (!forum.discourse || !notice.unread) return;
    final csrf = decodeResponse(await forum.get('/session/csrf.json'))['csrf'];
    final r = await forum.transport(forum.url('/notifications/mark-read.json'),
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': '$csrf',
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: jsonEncode({'id': int.parse(notice.id)}));
    checkResponse(r);
  }
}

class UnreadMessages {
  static final counts = [ValueNotifier<int?>(null), ValueNotifier<int?>(null)];
  static final _generation = [0, 0];
  static Future<void> refresh(Forum forum) async {
    final i = Accounts.index(forum),
        token = ++_generation[Accounts.index(forum)];
    if (Accounts.states[i].value.account == null) {
      counts[i].value = 0;
      return;
    }
    try {
      final count = await NoticeService(forum).unreadCount();
      if (token == _generation[i]) counts[i].value = count;
    } catch (_) {
      if (token == _generation[i]) counts[i].value = null;
    }
  }
}
