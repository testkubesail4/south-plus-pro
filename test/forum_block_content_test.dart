import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/services/forum_block_content.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';

void main() {
  test('floor parser exposes a canonical key and the native puremark marker',
      () {
    for (final ignorable in [false, true]) {
      final document = html.parse('''<table class="js-post"><tr>
        <th class="r_two"><a href="u.php?uid-202.html"><strong>Synthetic author</strong></a></th>
        <th class="r_one"><div class="tiptop">${ignorable ? '<span class="js-puremark-content">collapsed</span>' : ''}</div>
          <div class="tpc_content"><div class="f14" id="read_7">Sooo！！</div></div>
        </th></tr></table>''');
      final reply = ThreadDetailParser().desktopThreadCards(document).single;
      expect(threadContentKey(reply), ignorable ? '<IGNORABLE>' : 'so');
    }
  });

  test('short content uses normalized whole-text equality and emoji tokens',
      () {
    String? key(String content) => blockContentKey(
        html.parseFragment('<div>$content</div>').children.single);
    expect(key('Hiiii！！<br> WORLD <img src="images/post/smile/a.gif">'),
        'hi world');
    expect(key('Hi world extra'), 'hi world extra');
    expect(
        key('<img src="images/post/smile/a.gif"><img src="images/post/smile/b.gif">'),
        '<EMOJI>');
    expect(
        key('<img src="data:image/gif;base64,synthetic" data-rinsp-defer-src="images/post/smile/a.gif">'),
        '<EMOJI>');
    expect(key('<img src="https://example.invalid/image.png">'), isNull);
    expect(key('<div><p></p></div>'), '<EMPTY>');
    expect(key('<blockquote class="blockquote3">quoted text</blockquote>'),
        isNull);
    expect(key('<h6 class="jumbotron">paid content</h6>'), isNull);
    expect(key('<video>media caption</video>'), isNull);
    expect(key('a' * 513), isNull);
    expect(key('<span title="${'x' * 2048}">a</span>'), isNull);
  });
}
