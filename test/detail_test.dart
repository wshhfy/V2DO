import 'package:flutter_test/flutter_test.dart';
import 'package:forum_app/forum.dart';
import 'package:forum_app/session.dart';
import 'package:forum_app/image_preview.dart';

void main() {
  test(
      'Lightbox uses original image but ordinary linked images keep their source',
      () {
    final targets = imageTargets(
        '<a class="lightbox" href="/original.png"><img src="/thumb.png"></a><a href="https://example.com/article"><img src="https://cdn.example.com/photo.jpg"></a>',
        Uri.parse('https://linux.do/'));
    expect(
        targets['https://linux.do/thumb.png'], 'https://linux.do/original.png');
    expect(targets['https://cdn.example.com/photo.jpg'],
        'https://cdn.example.com/photo.jpg');
  });
  test('List and discussion use the same category, not tag labels', () async {
    final forum = Forum('LINUX DO', 'linux.do', true,
        transport: (uri, {method = 'GET', headers = const {}, body}) async {
      if (uri.path == '/site.json')
        return const ForumResponse(
            200, '{"categories":[{"id":31,"name":"开发调优, Lv2"}]}');
      if (uri.path == '/latest.json')
        return const ForumResponse(200,
            '{"users":[],"topic_list":{"topics":[{"id":42,"title":"test","category_id":31,"tags":["Python"]}]}}');
      return const ForumResponse(200,
          '{"category_id":31,"title":"test","post_stream":{"posts":[{"id":1,"post_number":1,"username":"author","cooked":"body"},{"id":2,"post_number":2,"username":"author","cooked":"reply"}],"stream":[1,2]}}');
    });
    final topic = (await forum.latest()).single;
    final discussion = await forum.discussion(topic);
    expect(topic.category, '开发调优, Lv2');
    expect(discussion.category, topic.category);
    expect(discussion.original!.author, discussion.posts.single.author);
  });
  test('V2EX reads category and original author from the topic header',
      () async {
    final forum = Forum('V2EX', 'www.v2ex.com', false,
        transport: (uri, {method = 'GET', headers = const {}, body}) async =>
            const ForumResponse(200,
                '<div class="header"><a href="/go/qna">问与答</a><h1>title</h1><small><a href="/member/owner">owner</a></small></div><div class="topic_content">body</div>'));
    final d = await forum.discussion(const Topic(1, 'title'));
    expect(d.category, '问与答');
    expect(d.original!.author, 'owner');
  });
}
