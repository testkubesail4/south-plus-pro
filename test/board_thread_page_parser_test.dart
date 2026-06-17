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

  test('BoardThreadPageParser handles parent boards that only list children',
      () {
    final document = html_parser.parse('''
      <html>
        <body>
          <table>
            <tr><td class="h" colspan="5"><b>子版块</b></td></tr>
            <tr><td></td><td>论坛</td><td>版主</td><td>文章</td><td>最后发表</td></tr>
            <tr class="f_one tr3">
              <td><a href="thread.php?fid-171.html"><img src="new.gif"></a></td>
              <th>
                <a class="bklogo" href="thread.php?fid-171.html"></a>
                <h2><a href="thread.php?fid-171.html" class="fnamecolor a1">CG资源</a></h2>
              </th>
              <td></td><td>190481</td><th>[AI绘画]小舞-斗 ..d06f7a3a</th>
            </tr>
            <tr class="f_one tr3">
              <td><a href="thread.php?fid-172.html"><img src="new.gif"></a></td>
              <th>
                <a class="bklogo" href="thread.php?fid-172.html"></a>
                <h2><a href="thread.php?fid-172.html" class="fnamecolor a1">实用动画</a></h2>
              </th>
              <td></td><td>392656</td><th>Re:[2D动画/无修/ ..31fa71c2</th>
            </tr>
          </table>
          <table id="ajaxtable">
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/anc.gif"></td>
              <td><h3><a href="notice.php?fid-.html#72">Contact / DMCA</a></h3></td>
              <td>论坛公告</td><td>0 / 1</td><td></td>
            </tr>
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topiclock.gif"></td>
              <td>
                <h3><a href="read.php?tid-3373.html">新人报道帖子（回帖已修复）</a></h3>
                <img src="images/colorImagination/file/headtopic_3.gif"
                     title="置顶帖标志">
              </td>
              <td>admin</td><td>64007 / 2018417</td><td></td>
            </tr>
          </table>
        </body>
      </html>
    ''');
    const category = ForumCategory(
      name: '网赚资源区',
      slug: 'fid-170',
      url: 'https://south-plus.net/thread.php?fid-170.html',
    );
    final parser = BoardThreadPageParser();

    final boards = parser.parseDesktopSubBoards(document, category);
    final stickyThreads = parser.parseDesktopStickyThreads(document, category);
    final wallThreads = parser.parseWallThreads(document, category);

    expect(boards.map((board) => board.name), ['CG资源', '实用动画']);
    expect(boards.first.postCount, 190481);
    expect(stickyThreads, isEmpty);
    expect(wallThreads, isEmpty);
  });

  test('BoardThreadPageParser keeps current-board stickies only', () {
    final document = html_parser.parse('''
      <html>
        <body>
          <table id="ajaxtable">
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topiclock.gif"></td>
              <td>
                <h3><a href="read.php?tid-1.html">全局置顶</a></h3>
                <img src="images/colorImagination/file/headtopic_3.gif"
                     title="置顶帖标志">
              </td>
              <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a></td>
              <td>1 / 10</td><td></td>
            </tr>
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topiclock.gif"></td>
              <td>
                <h3><a href="read.php?tid-2.html">分区置顶</a></h3>
                <img src="images/colorImagination/file/headtopic_2.gif"
                     title="置顶帖标志">
              </td>
              <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a></td>
              <td>1 / 10</td><td></td>
            </tr>
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topiclock.gif"></td>
              <td>
                <h3><a href="read.php?tid-3.html">板块置顶</a></h3>
                <img src="images/colorImagination/file/headtopic_1.gif"
                     title="置顶帖标志">
              </td>
              <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a></td>
              <td>1 / 10</td><td></td>
            </tr>
          </table>
        </body>
      </html>
    ''');

    final threads = BoardThreadPageParser().parseDesktopStickyThreads(
      document,
      const ForumCategory(name: '免空资源区', slug: 'fid-13'),
    );

    expect(threads.map((thread) => thread.title), ['板块置顶']);
    expect(threads.single.isSticky, isTrue);
  });

  test('BoardThreadPageParser extracts wall threads with preview images', () {
    final document = html_parser.parse('''
      <html>
        <body>
          <table id="ajaxtable">
            <tr class="tr3 t_one">
              <td>
                <a href="read.php?tid-100.html" target="_blank">
                  <img src="images/colorImagination/thread/topichot.gif">
                </a>
              </td>
              <td id="td_100">
                <h3>
                  <a href="read.php?tid-100.html" id="a_ajax_100">
                    <b>置顶帖</b>
                  </a>
                </h3>
                <img src="images/colorImagination/file/headtopic_3.gif"
                     title="置顶帖标志">
              </td>
              <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a>
                <div>2026-06-01</div>
              </td>
              <td>8 / 100</td>
              <td><a href="read.php?tid-100-page-e-fpage-1.html#a">
                2026-06-02 12:00
              </a></td>
            </tr>
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topichot.gif"></td>
              <td id="td_101">
                <h3><a href="read.php?tid-101.html" id="a_ajax_101">普通表格帖</a></h3>
              </td>
              <td><a class="bl" href="u.php?action-show-uid-2.html">bob</a>
                <div>2026-06-03</div>
              </td>
              <td>3 / 80</td>
              <td></td>
            </tr>
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topichot.gif"></td>
              <td id="td_ad">
                <h3>
                  <a href="https://example.com/ad">
                    <b><font color="#43BFFF">外链广告</font></b>
                  </a>
                </h3>
                <img src="images/colorImagination/file/headtopic_3.gif"
                     title="置顶帖标志">
              </td>
              <td><a class="bl" href="u.php?action-show-uid-1.html">admin</a></td>
              <td>0 / 1</td>
              <td></td>
            </tr>
            <tr class="tr3 t_one">
              <td><img src="images/colorImagination/thread/topiclock.gif"></td>
              <td id="td_102">
                <h3><a href="read.php?tid-102.html" id="a_ajax_102">
                  <b><font color="#FF0000">版块置顶帖</font></b>
                </a></h3>
                <img src="images/colorImagination/file/headtopic_1.gif"
                     title="置顶帖标志">
              </td>
              <td><a class="bl" href="u.php?action-show-uid-5.html">mod</a>
                <div>2026-06-04</div>
              </td>
              <td>2 / 30</td>
              <td></td>
            </tr>
          </table>
          <ul class="stream">
            <li class="dcsns-li dcsns-rss dcsns-feed-0">
              <div class="inner">
                <span class="section-title">
                  <a href="./read.php?tid-200.html">有图帖</a>
                </span>
                <span class="section-text">
                  <span style="float:right">回复/人气：12/&nbsp;345</span>
                  <div>
                    <a href="./read.php?tid-200.html">
                      <img src="/attachment/Mon_2606/9_pic.png">
                    </a>
                  </div>
                </span>
                <span class="section-intro">
                  <table><tr>
                    <td>作者：<a class="bl" href="u.php?action-show-uid-3.html">alice</a></td>
                    <td>2026-06-17</td>
                  </tr></table>
                </span>
              </div>
            </li>
            <li class="dcsns-li dcsns-rss dcsns-feed-0">
              <div class="inner">
                <span class="section-title">
                  <a href="./read.php?tid-201.html">无图帖</a>
                </span>
                <span class="section-text">
                  <span style="float:right">回复/人气：5/&nbsp;20</span>
                  <div>
                    <a href="./read.php?tid-201.html">
                      <img src="/images/noimageavailble_icon.png">
                    </a>
                  </div>
                </span>
                <span class="section-intro">
                  <table><tr>
                    <td>作者：<a class="bl" href="u.php?action-show-uid-4.html">eve</a></td>
                    <td>2026-06-16</td>
                  </tr></table>
                </span>
              </div>
            </li>
          </ul>
          <div class="pages">
            <a href="thread_new.php?fid-9-page-1.html">1</a>
            <a href="thread_new.php?fid-9-page-2.html">2</a>
            <a href="thread_new.php?fid-9-page-12.html">»</a>
          </div>
        </body>
      </html>
    ''');

    final parser = BoardThreadPageParser();
    const category = ForumCategory(name: '茶馆', slug: 'fid-9');
    final sticky = parser.parseDesktopStickyThreads(document, category);
    final ads = parser.parseDesktopAds(document);
    final wall = parser.parseWallThreads(document, category);
    final pages = parser.wallPages(document);

    expect(sticky, hasLength(1));
    expect(sticky.single.title, '版块置顶帖');
    expect(sticky.single.isSticky, isTrue);
    expect(ads, hasLength(1));
    expect(ads.single.title, '外链广告');
    expect(ads.single.url, 'https://example.com/ad');
    expect(wall.map((thread) => thread.title), ['有图帖', '无图帖']);
    expect(wall.first.previewImageUrl,
        'https://south-plus.net/attachment/Mon_2606/9_pic.png');
    expect(wall.last.previewImageUrl, isNull);
    expect(wall.first.replies, 12);
    expect(wall.first.author, 'alice');
    expect(wall.first.authorUrl,
        'https://south-plus.net/u.php?action-show-uid-3.html');
    expect(wall.first.lastPost, '2026-06-17');
    expect(pages, isNotNull);
    expect(pages!.current, 1);
    expect(pages.total, 12);
  });
}
