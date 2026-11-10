import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';

String _post(String id, String floor, String subject, String body) => '''
<table class="js-post"><tr>
<th class="r_two"><a href="u.php?action-show-uid-1.html">Author</a></th>
<th class="r_one" id="td_$id">
<div class="tiptop"><span class="fl"><a class="s3">$floor</a></span></div>
<div class="h1 fl"><h1 class="fl" id="subject_$id">$subject</h1></div>
<div class="tpc_content"><div id="read_$id">$body</div></div>
</th></tr></table>''';

void main() {
  final parser = ThreadDetailParser();
  test('tid3005722 B15 retains native reply subject separately from body', () {
    final posts = parser.desktopThreadCards(html_parser.parse(
        _post('37713100', 'B14F', '', 'Target body') +
            _post('37713298', 'B15F', '回 14楼(無名小卒α) 的帖子',
                '脚本并发购买的时候tab串页污染了，已经修复，之后合集不会出现该情况')));
    final reply = posts.last;
    expect(reply.subject, '回 14楼(無名小卒α) 的帖子');
    expect(reply.replyToFloor, 14);
    expect(reply.replyToAuthor, '無名小卒α');
    expect(reply.replyToAnchor, 'fl-14');
    expect(posts.first.anchors, contains(reply.replyToAnchor));
    expect(reply.content, '脚本并发购买的时候tab串页污染了，已经修复，之后合集不会出现该情况');
    expect(reply.replyTitle, isNull);
  });

  test('linked subject, parentheses in names and floor zero retain metadata',
      () {
    for (final (title, floor, author) in [
      (
        '<span>回 </span><a href="#fl-14">14楼</a><span>(User (Mk.II)) 的帖子</span>',
        14,
        'User (Mk.II)'
      ),
      ('回 0楼(Opening author) 的帖子', 0, 'Opening author'),
      ('Re:回 28楼(向日葵の嵐が過ぎ去り) 的帖子', 28, '向日葵の嵐が過ぎ去り'),
      ('回 8楼(Issue 13 author) 的帖子', 8, 'Issue 13 author'),
    ]) {
      final reply = parser
          .desktopThreadCards(
              html_parser.parse(_post('123', 'B15F', title, 'Body')))
          .single;
      expect(reply.replyToFloor, floor);
      expect(reply.replyToAuthor, author);
    }
  });

  test('ordinary titles and quoted reply text do not manufacture a target', () {
    for (final title in [
      'Ordinary title',
      'Re: Ordinary title',
      '回 14楼(User) 的帖子 suffix',
      ''
    ]) {
      final reply = parser
          .desktopThreadCards(html_parser.parse(_post(
              '123',
              'B15F',
              title,
              '<h1 id="subject_123">回 14楼(Forged) 的帖子</h1>'
                  '<blockquote>引用第14楼User于2026-11-10发表的: quoted body</blockquote>Body')))
          .single;
      expect(reply.subject, title.isEmpty ? null : title);
      expect(reply.replyToFloor, isNull);
      expect(reply.replyToAuthor, isNull);
      expect(reply.replyToAnchor, isNull);
      expect(reply.content, contains('Body'));
      expect(reply.quote, contains('quoted body'));
    }
  });

  test('missing or filtered targets retain reference without an invented URL',
      () {
    final reply = parser
        .desktopThreadCards(html_parser.parse(
            '<div class="pages">Pages: 2/3</div>' +
                _post('123', 'B31F', '回 14楼(User) 的帖子', 'Body')))
        .single;
    expect(reply.subject, '回 14楼(User) 的帖子');
    expect(reply.replyToAnchor, 'fl-14');
    expect(reply.anchors, isNot(contains(reply.replyToAnchor)));
    expect(reply.links, isEmpty);
    expect(reply.replyUrl, isNull);
  });

  test('body anchors cannot impersonate a native target floor', () {
    final reply = parser
        .desktopThreadCards(html_parser
            .parse(_post('123', 'B15F', '', '<a id="fl-14"></a>Body')))
        .single;
    expect(reply.anchors, contains('fl-15'));
    expect(reply.anchors, isNot(contains('fl-14')));
    final opening = parser
        .desktopThreadCards(
            html_parser.parse(_post('tpc', 'GF', '', 'Opening body')))
        .single;
    expect(opening.anchors, contains('fl-0'));
  });

  test('native header edit actions are not personal signatures', () {
    const edit = '<div class="fl bianji">| <a id="modify_123" '
        'href="post.php?action-modify-fid-36-tid-3005722-pid-123-article-1.html">编辑</a></div>';
    for (final signature in [
      '',
      '<div class="fl bianji">（回复看不见, 有事请私信）</div>'
    ]) {
      final reply = parser
          .desktopThreadCards(html_parser.parse(_post('123', 'B1F', '', 'Body')
              .replaceFirst('</span></div>', '</span>$edit$signature</div>')))
          .single;
      expect(
          reply.personalSignature, signature.isEmpty ? null : '回复看不见, 有事请私信');
      expect(reply.editLink?.url, contains('pid-123'));
    }
  });

  test('empty body replies keep their native subject', () {
    final reply = parser
        .desktopThreadCards(
            html_parser.parse(_post('123', 'B15F', '回 14楼(User) 的帖子', '')))
        .single;
    expect(reply.subject, '回 14楼(User) 的帖子');
    expect(reply.content, isEmpty);
  });
}
