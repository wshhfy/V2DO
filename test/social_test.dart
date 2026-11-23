import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/social.dart';
import 'package:forum_app/profile.dart';
import 'package:forum_app/social_bar.dart';

void main() {
  test('V2 website history selects only Recent Visited Topics sidebar', () {
    const service = ProfileService(Forum('V2EX', 'www.v2ex.com', false));
    final result = service.parseV2Read('''
      <div class="box"><div class="cell">Today Top 10</div><a href="/t/90">Hot</a></div>
      <div class="box"><div class="cell">Recent Visited Topics</div>
        <a href="/t/12#reply3">PC topic &amp; title</a><a href="/t/12">Duplicate</a>
        <a href="/t/11">Earlier topic</a><a href="https://example.com/t/10">External</a>
      </div><div class="box"><div class="cell">Latest</div><a href="/t/99">Latest</a></div>''');
    expect(result.topics.map((t) => t.id), [12, 11]);
    expect(result.topics.first.title, 'PC topic & title');
    expect(result.more, false);
    expect(() => service.parseV2Read('<div class="box">Missing section</div>'),
        throwsA(isA<ForumError>()));
    expect(
        service
            .parseV2Read(
                '<div class="box"><div class="cell">Recent Visited Topics</div></div>')
            .topics,
        isEmpty);
  });
  test('Discourse website reading history uses current user read endpoint',
      () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(method, 'GET');
      if (uri.path == '/session/current.json')
        return const ForumResponse(
            200, '{"current_user":{"username":"owner"}}');
      expect(uri.path, '/read.json');
      expect(uri.queryParameters['page'], '1');
      return const ForumResponse(200,
          '{"topic_list":{"topics":[{"id":9,"title":"Read on PC","posts_count":5}],"more_topics_url":"/read?page=2"}}');
    });
    final result =
        await ProfileService(forum).activity('owner', 'read', page: 1);
    expect(result.topics.single.title, 'Read on PC');
    expect(result.more, true);
    await expectLater(ProfileService(forum).activity('other', 'read'),
        throwsA(isA<ForumError>()));
  });
  testWidgets('V2 already thanked reply still displays its total',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SocialBar(forums[0], 1, 2, liked: true, likes: 53))));
    expect(find.text('已感谢 53'), findsOneWidget);
  });
  test('V2 thanks counts stay separate from topic votes and reply numbers',
      () async {
    const fixtureBody = '''<h1>Topic</h1><div class="topic_content">Body</div>
<script type="application/ld+json">{"@type":"DiscussionForumPosting","interactionStatistic":[{"interactionType":"https://schema.org/LikeAction","userInteractionCount":175}]}</script>
<div id="topic_1_votes"><a onclick="upVoteTopic(1)">45</a></div>
<div class="cell" id="r_2"><span class="no">99</span><span class="ago">2026</span><span class="small fade"><img src="/static/img/heart_20250818.png">53</span><div class="thanked" id="thank_area_2">感谢已发送</div><div class="reply_content">Reply</div></div>''';
    final original = SocialService.parseV2(fixtureBody, 1, 1, original: true);
    expect(original.likes, 175);
    expect(original.votes, 45);
    final reply = SocialService.parseV2(fixtureBody, 1, 2);
    expect(reply.likes, 53);
    expect(reply.liked, true);
    expect(reply.votes, 0);
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200, fixtureBody));
    final discussion = await forum.discussion(const Topic(1, 'Topic'));
    expect(discussion.posts.single.likes, 53);
    expect(discussion.original!.likes, 175);
  });
  test('Discourse like toggles one post with fresh CSRF and verifies state',
      () async {
    var liked = false;
    final mutations = <String>[];
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/session/csrf.json')
        return const ForumResponse(200, '{"csrf":"fixture"}');
      if (uri.path == '/posts/9.json')
        return ForumResponse(
            200,
            jsonEncode({
              'actions_summary': [
                {
                  'id': 2,
                  'acted': liked,
                  'count': liked ? 1 : 0,
                  'can_act': !liked,
                  'can_undo': liked
                }
              ]
            }));
      mutations.add('$method ${uri.path}');
      expect(headers['X-CSRF-Token'], 'fixture');
      if (method == 'POST') {
        expect(jsonDecode(body!), {'id': 9, 'post_action_type_id': 2});
        liked = true;
      } else {
        expect(uri.queryParameters['post_action_type_id'], '2');
        liked = false;
      }
      return const ForumResponse(200, '{"id":9}');
    });
    final service = SocialService(forum);
    expect((await service.toggleLike(2, 9)).liked, true);
    expect((await service.toggleLike(2, 9)).liked, false);
    expect(
        mutations, ['POST /post_actions.json', 'DELETE /post_actions/9.json']);
  });
  test('Discourse bookmark uses returned bookmark ID for removal', () async {
    var saved = false;
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/session/csrf.json')
        return const ForumResponse(200, '{"csrf":"fixture"}');
      if (uri.path == '/posts/9.json')
        return ForumResponse(
            200,
            jsonEncode(
                {'bookmarked': saved, 'bookmark_id': saved ? 77 : null}));
      if (method == 'POST') {
        expect(jsonDecode(body!),
            {'bookmarkable_id': 9, 'bookmarkable_type': 'Post'});
        saved = true;
      }
      if (method == 'DELETE') {
        expect(uri.path, '/bookmarks/77.json');
        saved = false;
      }
      return const ForumResponse(200, '{"id":77,"success":"OK"}');
    });
    final service = SocialService(forum);
    expect((await service.toggleBookmark(2, 9)).bookmarked, true);
    expect((await service.toggleBookmark(2, 9)).bookmarked, false);
  });
  test('V2EX uses server-provided favorite URL and verifies changed state',
      () async {
    var saved = false;
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/t/9')
        return ForumResponse(200,
            '<a href="/${saved ? 'unfavorite' : 'favorite'}/topic/9?once=123">收藏</a>');
      expect(uri.path, '/favorite/topic/9');
      expect(uri.queryParameters['once'], '123');
      saved = true;
      return const ForumResponse(302, '', '/t/9');
    });
    expect((await SocialService(forum).toggleBookmark(9, 9)).bookmarked, true);
  });
  test('V2EX already thanked never issues duplicate paid action', () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      expect(method, 'GET');
      return const ForumResponse(
          200, '<span id="thank_area_8" class="thanked">感谢已发送</span>');
    });
    expect((await SocialService(forum).toggleLike(9, 8)).liked, true);
  });
  test('Profile activity parses V2EX topic and reply references', () {
    final service = ProfileService(forums[0]);
    final r = service.parseV2Activity(
        '<div class="cell"><span class="item_title"><a href="/t/23#reply2">主题</a></span><a class="node">问与答</a></div><a class="page_normal">2</a>');
    expect(r.topics.single.id, 23);
    expect(r.more, true);
  });
  test('V2EX profile topics and bookmarks use topic time, not unrelated titles',
      () {
    const row = '''<div class="cell">
      <div class="fr"><span title="2020-01-01 00:00:00 +08:00">9</span></div>
      <span class="item_title"><a class="topic-link" href="/t/23">主题</a></span>
      <span class="topic_info"><a class="node" href="/go/test">Test</a> •
      <span title="2026-11-19 13:16:44 +08:00">4 days ago</span></span>
    </div>''';
    final topic = ProfileService(forums[0]).parseV2Activity(row).topics.single;
    expect(topic.createdAt, DateTime.parse('2026-11-19T05:16:44Z'));
    expect(topic.activityTimeLabel, '4 days ago');
  });
  test('V2EX profile keeps relative time when no timestamp is available', () {
    const row = '''<div class="cell">
      <span class="item_title"><a href="/t/24">收藏</a></span>
      <span class="topic_info"><span class="ago">3 小时前</span></span>
    </div>''';
    final topic = ProfileService(forums[0]).parseV2Activity(row).topics.single;
    expect(topic.createdAt, isNull);
    expect(topic.activityTimeLabel, '3 小时前');
  });
  test('V2EX thank button accepts current two-argument handler', () {
    final state = SocialService.parseV2(
        '<a onclick="thankTopic(23, 123)">感谢</a><script>var once = 123;</script>',
        23,
        23,
        original: true);
    expect(state.canLike, true);
    expect(state.nonce, '123');
  });
  test('V2EX reply history preserves separate replies to the same topic', () {
    const row =
        '<div class="dock_area"><div class="fr"><span class="fade">17 小时 19 分钟前</span></div><span class="gray"><a href="/t/23">主题</a></span></div><div class="inner"><div class="reply_content">回复内容</div></div>';
    final result = ProfileService(forums[0]).parseV2Activity('$row$row');
    expect(result.topics.length, 2);
    expect(result.topics.first.activityExcerpt, '回复内容');
    expect(result.topics.first.activityTimeLabel, '17 小时 19 分钟前');
  });
}
