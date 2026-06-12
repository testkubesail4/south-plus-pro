import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/services/parsers/home_page_parser.dart';

void main() {
  test('HomePageParser parses desktop sections with nested boards', () {
    final document = html_parser.parse('''
      <html>
        <body>
          <table>
            <tr>
              <th><h2><a href="index.php?cateid-39.html">漫区特设</a></h2></th>
            </tr>
            <tr><td>版块</td><td>主题/文章</td><td>最后发表</td></tr>
            <tr>
              <td></td>
              <th>
                <h3><a href="thread.php?fid-226.html">Comic Market 107</a></h3>
                (2) 2025.12.30 - 2025.12.31
                子版：
                <h3>
                  <a href="thread.php?fid-227.html">同人志&CG</a>
                  |
                  <a href="thread.php?fid-228.html">同人志&CG (图墙模式)</a>
                </h3>
              </th>
              <td>594 / 3669</td>
              <th>Re:(C107) sample</th>
            </tr>
            <tr>
              <td></td>
              <th>
                <h3><a href="thread.php?fid-43.html">旧物仓库</a></h3>
                (0) 子版：
                <h3>
                  <a href="thread.php?fid-218.html">C103</a> |
                  <a href="thread.php?fid-215.html">C102</a> |
                  <a href="thread.php?fid-212.html">C101</a>
                </h3>
              </th>
              <td>35097 / 882487</td>
              <th>latest</th>
            </tr>
          </table>
          <table>
            <tr>
              <th><h2><a href="index.php?cateid-3.html">综合交流</a></h2></th>
            </tr>
            <tr><td>版块</td><td>主题/文章</td><td>最后发表</td></tr>
            <tr>
              <td></td>
              <th>
                <h3><a href="thread.php?fid-13.html">免空资源区</a></h3>
                (587) 本区仅接受免费网盘的发布
                子版：
                <h3>
                  <a href="thread.php?fid-14.html">CG资源</a> |
                  <a href="thread_new.php?fid=109">图墙模式</a>
                </h3>
              </th>
              <td>188795 / 8682126</td>
              <th>latest</th>
            </tr>
          </table>
        </body>
      </html>
    ''');

    final sections = HomePageParser().parseDesktopForumSections(document);

    expect(sections.map((section) => section.title), [
      '漫区特设',
      '综合交流',
    ]);
    expect(sections.first.items, hasLength(2));

    final comicMarket = sections.first.items.first;
    expect(comicMarket.name, 'Comic Market 107');
    expect(comicMarket.url, 'https://south-plus.net/thread.php?fid-226.html');
    expect(comicMarket.subtitle, '2025.12.30 - 2025.12.31');
    expect(comicMarket.topicCount, 594);
    expect(comicMarket.postCount, 3669);
    expect(comicMarket.children.map((board) => board.name), [
      '同人志&CG',
      '同人志&CG (图墙模式)',
    ]);

    final archive = sections.first.items.last;
    expect(archive.name, '旧物仓库');
    expect(archive.children.map((board) => board.name), [
      'C103',
      'C102',
      'C101',
    ]);

    final freeStorage = sections.last.items.single;
    expect(freeStorage.name, '免空资源区');
    expect(freeStorage.children.last.url,
        'https://south-plus.net/thread_new.php?fid=109');
  });
}
