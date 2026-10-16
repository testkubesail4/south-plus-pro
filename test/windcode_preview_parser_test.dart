import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/parsers/thread_content_parser.dart';

void main() {
  final parser = ThreadContentParser(
      urls: ForumUrlResolver(baseUri: Uri.https('blue-plus.net', '/')));

  test('preview toolbar formatting feeds the existing content segments', () {
    final cases = <(String, void Function(ThreadContentSegment))>[
      ('[b]Synthetic[/b]', (s) => expect(s.isBold, isTrue)),
      ('[i]Synthetic[/i]', (s) => expect(s.isItalic, isTrue)),
      ('[u]Synthetic[/u]', (s) => expect(s.isUnderline, isTrue)),
      ('[size=6]Synthetic[/size]', (s) => expect(s.fontScale, 1.5)),
      (
        '[color=royalblue]Synthetic[/color]',
        (s) => expect(s.colorValue, 0xff4169e1)
      ),
      (
        '[font=Courier New]Synthetic[/font]',
        (s) => expect(s.fontFamily, 'Courier New')
      ),
      (
        '[url=https://example.invalid/topic]Synthetic[/url]',
        (s) => expect(s.href, 'https://example.invalid/topic')
      ),
      (
        '[url]https://example.invalid/topic[/url]',
        (s) => expect(s.href, 'https://example.invalid/topic')
      ),
      (
        '[img]/synthetic.png[/img]',
        (s) {
          expect(s.type, ThreadContentSegmentType.image);
          expect(s.url, 'https://blue-plus.net/synthetic.png');
        }
      ),
      (
        '[quote]Synthetic[/quote]',
        (s) {
          expect(s.type, ThreadContentSegmentType.quote);
          expect(s.children.single.text, 'Synthetic');
        }
      ),
      (
        '[align=right]Synthetic[/align]',
        (s) {
          expect(s.type, ThreadContentSegmentType.block);
          expect(s.alignment, ThreadContentAlignment.end);
          expect(s.children.single.text, 'Synthetic');
        }
      ),
      (
        '[list=a][li]First[/li][li]Second[/li][/list]',
        (s) {
          expect(s.type, ThreadContentSegmentType.list);
          expect(s.isOrdered, isTrue);
          expect(s.listStyle, 'a');
          expect(s.children.map((item) => item.children.single.text),
              ['First', 'Second']);
        }
      ),
      (
        '[s:743]',
        (s) {
          expect(s.isEmoji, isTrue);
          expect(s.url,
              'https://blue-plus.net/images/post/smile/smallface/face028.jpg');
        }
      ),
    ];
    for (final (source, check) in cases) {
      check(parser.parseWindCode(source).single);
    }
  });

  test(
      'author preview preserves explicit blank lines through nested formatting',
      () {
    final segments =
        parser.parseWindCode('[b]First\n\n[i]Second[/i][/b]\r\n\r\nThird');
    expect(_text(segments), 'First\n\nSecond\n\nThird');
    final nested = segments.singleWhere((segment) => segment.text == 'Second');
    expect(nested.isBold, isTrue);
    expect(nested.isItalic, isTrue);
  });

  test(
      'sell preview boxes its price and formatted authored contents without buy',
      () {
    for (final price in [0, 5]) {
      final segments = parser.parseWindCode(
          'Before[sell=$price][b]Synthetic paid content[/b]\n[img]/synthetic.png[/img][/sell]After');
      expect(segments.map((s) => s.type), [
        ThreadContentSegmentType.text,
        ThreadContentSegmentType.quote,
        ThreadContentSegmentType.text,
      ]);
      final box = segments[1];
      expect(_text(box.children),
          contains('出售内容 · 售价 $price SP币\nSynthetic paid content'));
      expect(
          box.children
              .singleWhere((s) => s.text == 'Synthetic paid content')
              .isBold,
          isTrue);
      expect(box.children.last.type, ThreadContentSegmentType.image);
      expect(_flatten(segments).any((s) => s.saleBox != null), isFalse);
    }
    final floor = parser.extractInlineSegments(
        dom.Element.tag('div')..append(dom.Text('[sell=5]Synthetic[/sell]')));
    expect(_text(floor), '[sell=5]Synthetic[/sell]',
        reason: 'preview must not change raw server-content fallback');
  });

  test('HTML, unknown tags and invalid arguments stay inert authored text', () {
    for (final source in [
      '<script>synthetic()</script><img src="/unwanted.png">',
      '&lt;b&gt;Synthetic&lt;/b&gt;',
      '[unknown]Synthetic[/unknown]',
      '[hide]Synthetic[/hide]',
      '[sell=-1]Synthetic[/sell]',
      '[sell=5]Synthetic',
      '[size=100]Synthetic[/size]',
      '[url=javascript:synthetic()]Synthetic[/url]',
      '[img]data:image/png,synthetic[/img]',
      '[s:999999]',
    ]) {
      final segments = parser.parseWindCode(source);
      expect(_text(segments), source, reason: source);
      expect(segments.every((s) => s.type == ThreadContentSegmentType.text),
          isTrue,
          reason: source);
    }
    expect(parser.parseWindCode(' \n\n '), isEmpty);
  });

  test('code is opaque to HTML, formatting, sell and emoji expansion', () {
    const body =
        '  [b]Literal[/b]\n\n[sell=5]Literal[/sell] [s:743]\n<img src="/synthetic.png">';
    final segment = parser.parseWindCode('[code]$body[/code]').single;
    expect(segment.type, ThreadContentSegmentType.code);
    expect(segment.text, body);
  });
}

Iterable<ThreadContentSegment> _flatten(
    List<ThreadContentSegment> segments) sync* {
  for (final segment in segments) {
    yield segment;
    yield* _flatten(segment.children);
  }
}

String _text(List<ThreadContentSegment> segments) =>
    _flatten(segments).map((segment) => segment.text ?? '').join();
