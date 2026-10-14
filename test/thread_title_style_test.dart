import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/parsers/board_thread_page_parser.dart';
import 'package:south_plus_rewrite/services/parsers/home_page_parser.dart';
import 'package:south_plus_rewrite/services/parsers/search_result_parser.dart';

void main() {
  const title =
      '<b><i><u><font color="#FF00FF">Fixture title</font></u></i></b>';
  const link = '<a href="read.php?tid-123.html">$title</a>';
  const category = ForumCategory(name: 'Fixture board', slug: 'fid-42');

  test('all fetched list paths preserve title highlighting and plain text', () {
    final threads = [
      HomePageParser().parseLatestThreads(html.parse(link)).single,
      HomePageParser()
          .parseLatestThreadsFromScript('document.write("$link");')
          .single,
      SearchResultParser()
          .parse(html.parse('<title>搜索结果</title><table><tr><td>$link</td>'
              '</tr></table>'))
          .single,
      BoardThreadPageParser()
          .parseWallThreads(
              html.parse('<ul class="stream"><li class="dcsns-li">'
                  '<div class="section-title">$link</div></li></ul>'),
              category)
          .single,
      BoardThreadPageParser()
          .parseDesktopStickyThreads(
              html.parse('<table id="ajaxtable"><tr class="tr3">'
                  '<td><img src="headtopic_1.gif"><h3>$link</h3></td>'
                  '<td>2 / 10</td></tr></table>'),
              category)
          .single,
    ];
    for (final thread in threads) {
      expect(thread.title, 'Fixture title');
      final style = thread.copyWith(replies: 3).titleStyle!;
      expect(style.bold, isTrue);
      expect(style.italic, isTrue);
      expect(style.underline, isTrue);
      expect(style.colorValue, 0xffff00ff);
    }
  });

  test('plain titles stay unstyled and invalid colors are ignored', () {
    final parser = HomePageParser();
    final plain = parser
        .parseLatestThreads(
            html.parse('<a href="read.php?tid-124.html">Plain title</a>'))
        .single;
    expect(plain.titleStyle, isNull);
    final invalid = parser
        .parseLatestThreads(html.parse(
            '<a href="read.php?tid-125.html"><b><font color="url(javascript:x)">'
            'Safe title</font></b></a>'))
        .single;
    expect(invalid.titleStyle!.bold, isTrue);
    expect(invalid.titleStyle!.colorValue, isNull);
  });
}
