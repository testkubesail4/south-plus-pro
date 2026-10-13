import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/parsers/forum_pm_parser.dart';
import 'package:south_plus_rewrite/services/parsers/thread_content_parser.dart';
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';

void main() {
  final urls = ForumUrlResolver(baseUri: Uri.https('south-plus.net', '/'));
  test('PM detail preserves formatted HTML and images in shared content AST',
      () {
    final detail = ForumPmParser(baseUri: urls.baseUri).parseDetail(
      html.parse('''<table class="set-table2">
        <tr><td>发件人</td><td>Fixture sender</td></tr>
        <tr><td>标题</td><td>Fixture title</td></tr>
        <tr><td>时间</td><td>2020-01-01</td></tr>
        <tr><td>内容</td><td><b>Bold</b><br>
          <a href="https://blue-plus.net/read.php?tid-701-page-2.html#fixture">Topic</a>
          <img src="https://example.invalid/fixture.png" alt="Fixture image">
          <img src="images/post/smile/1.gif">
          <script>secret executable</script></td></tr>
        <tr><td>选项</td><td></td></tr>
      </table>'''),
      const ForumPmSummary(
          box: ForumPmBox.inbox,
          type: ForumPmType.personal,
          id: '701',
          peer: 'Fixture sender',
          title: 'Fixture title',
          time: '',
          detailPath: 'message.php?action-read-mid-701.html'),
    );
    expect(detail.segments.where((s) => s.isBold).single.text, 'Bold');
    expect(detail.segments.where((s) => s.href != null).single.href,
        'https://south-plus.net/read.php?tid-701-page-2.html#fixture');
    expect(
        detail.segments
            .where((s) => s.type == ThreadContentSegmentType.image)
            .map((s) => (s.url, s.isEmoji)),
        [
          ('https://example.invalid/fixture.png', false),
          ('https://south-plus.net/images/post/smile/1.gif', true),
        ]);
    expect(detail.content, isNot(contains('secret executable')));
    expect(detail.segments.map((s) => s.text).join(),
        isNot(contains('secret executable')));
  });

  test(
      'verified raw WindCode preserves nesting, code, alphabetic list and emoji',
      () {
    final body = html.parseFragment('''<div>[b]Bold [i]nested[/i][/b]
      [color=royalblue][font=Courier New][size=6]Styled[/size][/font][/color]
      [quote][url=https://blue-plus.net/read.php?tid-701.html]Topic[/url][/quote]
      [align=center]Centered[/align]
      [list=a][li]First[/li][li]Second[/li][/list]
      [code]  [img]literal[/img]\n    &lt;b&gt;not HTML&lt;/b&gt;[/code]
      [s:743] [s:543] [s:999999]
      [img]https://example.invalid/fixture.png[/img]
      [wmv=320,240,1]https://example.invalid/fixture.wmv[/wmv]
      [attachment=42] [fly]Still visible[/fly] [sell=5]Locked sample[/sell]
    </div>''').querySelector('div')!;
    final segments =
        ThreadContentParser(urls: urls).extractInlineSegments(body);
    final all = flatten(segments).toList();
    expect(all.where((s) => s.text == 'nested').single.isBold, true);
    expect(all.where((s) => s.text == 'nested').single.isItalic, true);
    final styled = all.singleWhere((s) => s.text == 'Styled');
    expect(styled.colorValue, 0xff4169e1);
    expect(styled.fontFamily, 'Courier New');
    expect(styled.fontScale, 1.5);
    expect(
        all.where((s) => s.type == ThreadContentSegmentType.code).single.text,
        '  [img]literal[/img]\n    <b>not HTML</b>');
    final list =
        all.singleWhere((s) => s.type == ThreadContentSegmentType.list);
    expect(list.isOrdered, true);
    expect(list.listStyle, 'a');
    expect(list.children, hasLength(2));
    expect(
        all.where((s) =>
            s.type == ThreadContentSegmentType.block &&
            s.alignment == ThreadContentAlignment.center),
        hasLength(1));
    expect(all.where((s) => s.isEmoji).map((s) => s.url), [
      'https://south-plus.net/images/post/smile/smallface/face028.jpg',
      'https://south-plus.net/images/post/smile/de/3-2.gif',
    ]);
    expect(all.singleWhere((s) => s.type == ThreadContentSegmentType.media).url,
        'https://example.invalid/fixture.wmv');
    final text = all.map((s) => s.text ?? '').join();
    expect(text, contains('[s:999999]'));
    expect(text, contains('[attachment=42]'));
    expect(text, contains('Still visible'));
    expect(text, contains('[sell=5]Locked sample[/sell]'));
  });

  test('raw code uses its first close and ignores literal opening-tag examples',
      () {
    final body = html
        .parseFragment('<div>[code]literal [code] opening example[/code]</div>')
        .querySelector('div')!;
    final segments = ThreadContentParser().extractInlineSegments(body);
    expect(segments, hasLength(1));
    expect(segments.single.type, ThreadContentSegmentType.code);
    expect(segments.single.text, 'literal [code] opening example');
  });

  test('outer WindCode closing scan treats code as an opaque literal region',
      () {
    final body = html
        .parseFragment(
            '<div>[quote][code]literal [/quote] example[/code][/quote]</div>')
        .querySelector('div')!;
    final segments = ThreadContentParser().extractInlineSegments(body);
    expect(segments, hasLength(1));
    expect(segments.single.type, ThreadContentSegmentType.quote);
    expect(segments.single.children, hasLength(1));
    expect(segments.single.children.single.type, ThreadContentSegmentType.code);
    expect(segments.single.children.single.text, 'literal [/quote] example');
  });

  test('list separators never consume opaque code or nested list items', () {
    const literal = 'literal [*] [li] [/li] [list] [/list] [/align] marker';
    for (final item in [
      '[*][code]$literal[/code]',
      '[li][code]$literal[/code][/li]'
    ]) {
      final body = html
          .parseFragment('<div>[list]$item[/list]</div>')
          .querySelector('div')!;
      final list = ThreadContentParser().extractInlineSegments(body).single;
      expect(list.type, ThreadContentSegmentType.list);
      expect(list.children, hasLength(1));
      final code = list.children.single.children.single;
      expect(code.type, ThreadContentSegmentType.code);
      expect(code.text, literal);
    }
    for (final nested in [
      '[list][*]inner one[*]inner two[/list]',
      '[list][li]inner one[/li][li]inner two[/li][/list]'
    ]) {
      final body = html
          .parseFragment('<div>[list][*]outer$nested[*]last[/list]</div>')
          .querySelector('div')!;
      final list = ThreadContentParser().extractInlineSegments(body).single;
      expect(list.children, hasLength(2));
      final first = list.children.first.children;
      expect(first.first.text, 'outer');
      expect(first.last.type, ThreadContentSegmentType.list);
      expect(first.last.children, hasLength(2));
      expect(first.last.children.map((item) => item.children.single.text),
          ['inner one', 'inner two']);
      expect(list.children.last.children.single.text, 'last');
    }
  });

  test('malformed raw formatting arguments remain visible verbatim', () {
    final body = html
        .parseFragment(
            '<div>[size=huge]plain[/size] [align=up]text[/align] [color=unknown]color[/color]</div>')
        .querySelector('div')!;
    final segments = ThreadContentParser().extractInlineSegments(body);
    expect(segments.map((s) => s.text ?? '').join(),
        '[size=huge]plain[/size] [align=up]text[/align] [color=unknown]color[/color]');
  });

  test('uppercase WWW URLs open as external HTTPS without changing labels', () {
    final body = html
        .parseFragment('<div>WWW.Example.invalid/path</div>')
        .querySelector('div')!;
    final segment = ThreadContentParser().extractInlineSegments(body).single;
    expect(segment.text, 'WWW.Example.invalid/path');
    expect(Uri.parse(segment.href!).scheme, 'https');
    expect(Uri.parse(segment.href!).host.toLowerCase(), 'www.example.invalid');
    expect(Uri.parse(segment.href!).path, '/path');
  });

  test(
      'linked images and smileys preserve safe enclosing HTML and WindCode links',
      () {
    final body = html.parseFragment('''<div>
      <a href="https://example.invalid/file?token=fixture%2Dsignature#fixture%2Danchor"><img src="https://example.invalid/fixture.png"></a>
      [url=https://blue-plus.net/read.php?tid-701.html#42][img]https://example.invalid/another.png[/img][/url]
      [url=https://example.invalid/smile][s:718][/url]
      <a href="javascript:alert(1)"><img src="https://example.invalid/safe.png"></a>
      <a href="job.php?action=buytopic&amp;tid=701"><img src="https://example.invalid/safe.png"></a>
    </div>''').querySelector('div')!;
    final images =
        flatten(ThreadContentParser(urls: urls).extractInlineSegments(body))
            .where((s) => s.type == ThreadContentSegmentType.image)
            .toList();
    expect(images.map((s) => s.href), [
      'https://example.invalid/file?token=fixture%2Dsignature#fixture%2Danchor',
      'https://south-plus.net/read.php?tid-701.html#42',
      'https://example.invalid/smile',
      null,
      null,
    ]);
    expect(images[2].isEmoji, true);
  });

  test('raw fallback wrapper remains outside the clickable URL', () {
    final body = html
        .parseFragment(
            '<div>[sell=5]https://example.invalid/fallback[/sell]</div>')
        .querySelector('div')!;
    final segments = ThreadContentParser().extractInlineSegments(body);
    expect(segments.where((s) => s.href != null).single.href,
        'https://example.invalid/fallback');
    expect(segments.map((s) => s.text ?? '').join(),
        '[sell=5]https://example.invalid/fallback[/sell]');
  });

  test(
      'post anchors match real numeric names outside post wrappers, never fabricate missing names',
      () {
    final document = html.parse('''<form>
      <a name="42"></a><div class="t5 t2"><table class="js-post"><tr>
        <th class="r_two"><strong>Fixture author</strong></th>
        <th class="r_one" id="td_42"><div class="tiptop"><span class="fl"><a class="s3">B11F</a></span></div>
          <div class="tpc_content"><div class="f14" id="read_42">Fixture first</div></div></th>
      </tr></table></div><div class="menu"></div>
      <div class="t5 t2"><table class="js-post"><tr>
        <th class="r_two"><strong>Fixture author</strong></th>
        <th class="r_one" id="td_43"><div class="tpc_content"><div class="f14" id="read_43">Fixture second</div></div></th>
      </tr></table></div>
    </form>''');
    final posts = ThreadDetailParser().desktopThreadCards(document);
    expect(
        posts.first.anchors, containsAll(['42', 'td_42', 'read_42', 'fl-11']));
    expect(posts.last.anchors, containsAll(['td_43', 'read_43']));
    expect(posts.last.anchors, isNot(contains('43')));
    expect(posts.last.anchors, isNot(contains('42')));
  });

  test(
      'excessive WindCode nesting remains visible without unbounded recursive parsing',
      () {
    final body = html
        .parseFragment(
            '<div>${List.filled(80, '[quote]').join()}Fixture${List.filled(80, '[/quote]').join()}</div>')
        .querySelector('div')!;
    final all =
        flatten(ThreadContentParser(urls: urls).extractInlineSegments(body))
            .toList();
    expect(all.where((s) => s.type == ThreadContentSegmentType.quote),
        hasLength(32));
    expect(all.map((s) => s.text ?? '').join(), contains('[quote]'));
    expect(all.map((s) => s.text ?? '').join(), contains('Fixture'));
  });

  test('FAQ email variants and alternate code markup retain literal content',
      () {
    final body = html.parseFragment('''<div>
      [email]reader@example.invalid[/email] [email=reader@example.invalid]Contact[/email]
      <h6 class="quote">Copy code</h6><blockquote id="code1">  [b]literal[/b]\n    &lt;b&gt;still code&lt;/b&gt;</blockquote>
      [iframe]https://example.invalid/media[/iframe]
    </div>''').querySelector('div')!;
    final segments =
        ThreadContentParser(urls: urls).extractInlineSegments(body);
    expect(segments.where((s) => s.href != null).map((s) => (s.text, s.href)), [
      ('reader@example.invalid', 'mailto:reader@example.invalid'),
      ('Contact', 'mailto:reader@example.invalid'),
    ]);
    expect(
        segments
            .singleWhere((s) => s.type == ThreadContentSegmentType.code)
            .text,
        '  [b]literal[/b]\n    <b>still code</b>');
    expect(segments.where((s) => s.type == ThreadContentSegmentType.quote),
        isEmpty);
    expect(
        segments
            .singleWhere((s) => s.type == ThreadContentSegmentType.media)
            .url,
        'https://example.invalid/media');
  });

  test(
      'HTML code-line structure and tables retain text without executing media',
      () {
    final body = html.parseFragment('''<div>
      <div class="blockquote2"><ol><li>  first</li><li>    second</li></ol></div>
      <table><tr><th>Heading</th><td><b>Value</b></td></tr></table>
      <iframe src="javascript:alert(1)">Ignored active fallback</iframe>
    </div>''').querySelector('div')!;
    final segments =
        ThreadContentParser(urls: urls).extractInlineSegments(body);
    expect(
        segments
            .singleWhere((s) => s.type == ThreadContentSegmentType.code)
            .text,
        '  first\n    second');
    final row = segments
        .singleWhere((s) => s.type == ThreadContentSegmentType.table)
        .tableRows
        .single;
    expect(row.first.isHeader, true);
    expect(row.first.segments.single.text, 'Heading');
    expect(row.last.segments.single.isBold, true);
    expect(
        segments
            .singleWhere((s) => s.type == ThreadContentSegmentType.media)
            .url,
        isNull);
    expect(flatten(segments).map((s) => s.text ?? '').join(),
        isNot(contains('Ignored active fallback')));
  });

  test('shared parser links bare URLs while keeping punctuation and blocks',
      () {
    final body = html.parseFragment('''<div>
      <p>First https://blue-plus.net/read.php?tid-701.html#fixture。</p>
      <p>Next https://example.invalid/a_(b)?x=1&amp;y=2, done</p>
      <script>must disappear</script><a href="JaVaScRiPt:alert(1)">Safe label</a>
    </div>''').querySelector('div')!;
    final segments =
        ThreadContentParser(urls: urls).extractInlineSegments(body);
    expect(segments.where((s) => s.href != null).map((s) => s.href), [
      'https://south-plus.net/read.php?tid-701.html#fixture',
      'https://example.invalid/a_(b)?x=1&y=2',
    ]);
    final text = segments.map((s) => s.text ?? '').join();
    expect(text, contains('。\nNext'));
    expect(text, contains(', done'));
    expect(text, isNot(contains('must disappear')));
    expect(text, contains('Safe label'));
  });
}

Iterable<ThreadContentSegment> flatten(
    List<ThreadContentSegment> segments) sync* {
  for (final segment in segments) {
    yield segment;
    yield* flatten(segment.children);
    for (final row in segment.tableRows) {
      for (final cell in row) {
        yield* flatten(cell.segments);
      }
    }
  }
}
