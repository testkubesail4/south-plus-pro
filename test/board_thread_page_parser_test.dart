import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/parsers/board_thread_page_parser.dart';

void main() {
  test('BoardThreadPageParser extracts sub boards from desktop board pages',
      () {
    final document = html_parser.parse('''
      <html>
        <body>
          <table>
            <tr><td>子版块</td></tr>
            <tr>
              <td></td>
              <td>论坛</td>
              <td>版主</td>
              <td>文章</td>
              <td>最后发表</td>
            </tr>
            <tr>
              <td>
                <a href="thread.php?fid-213.html">
                  <img src="images/colorImagination/old.gif">
                </a>
              </td>
              <th>
                <a class="bklogo" href="thread.php?fid-213.html"></a>
                <h2>
                  <a href="thread.php?fid-213.html" class="fnamecolor a1">
                    <b>同人志&CG</b>
                  </a>
                </h2>
              </th>
              <td></td>
              <td>26246</td>
              <th><a href="read.php?tid-1.html">Re:(C103)[自购][ ..</a> 8ff82385</th>
            </tr>
            <tr>
              <td>
                <a href="thread.php?fid-214.html">
                  <img src="images/colorImagination/old.gif">
                </a>
              </td>
              <th>
                <a class="bklogo" href="thread.php?fid-214.html"></a>
                <h2>
                  <a href="thread.php?fid-214.html" class="fnamecolor a1">
                    <b>同人志&CG (图墙模式)</b>
                  </a>
                </h2>
              </th>
              <td></td>
              <td>0</td>
              <th></th>
            </tr>
          </table>
          <table>
            <tr><td>全部 精华 文章 作者 回复 / 人气 最后发表</td></tr>
          </table>
        </body>
      </html>
    ''');

    final boards = BoardThreadPageParser().parseDesktopSubBoards(
      document,
      const ForumCategory(
        name: 'C103',
        slug: 'fid-218',
        url: 'https://south-plus.net/thread.php?fid-218.html',
      ),
    );

    expect(boards.map((board) => board.name), [
      '同人志&CG',
      '同人志&CG (图墙模式)',
    ]);
    expect(boards.first.url, 'https://south-plus.net/thread.php?fid-213.html');
    expect(boards.first.postCount, 26246);
    expect(boards.first.subtitle, contains('Re:(C103)'));
  });
}
