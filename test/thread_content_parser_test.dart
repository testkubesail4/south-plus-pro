import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';
import 'package:south_plus_rewrite/services/parsers/thread_content_parser.dart';
import 'package:south_plus_rewrite/services/parsers/user_profile_parser.dart';
import 'package:south_plus_rewrite/services/whats_link_preview_service.dart';

void main() {
  test('extractInlineSegments trims boundary blank lines', () {
    final fragment = html_parser.parseFragment(
      '<div class="card-text"><br><br>\n  正文第一行<br>正文第二行<br><br></div>',
    );
    final content = fragment.querySelector('.card-text')!;

    final segments = ThreadContentParser().extractInlineSegments(content);

    expect(segments, hasLength(1));
    expect(segments.single.text, '正文第一行\n正文第二行');
  });

  test('extractInlineSegments keeps link style scoped to anchor text', () {
    final fragment = html_parser.parseFragment(
      '<div class="card-text">前缀 <a href="https://example.com">链接</a> 后缀</div>',
    );
    final content = fragment.querySelector('.card-text')!;

    final segments = ThreadContentParser().extractInlineSegments(content);

    expect(segments, hasLength(3));
    expect(segments[0].text, '前缀 ');
    expect(segments[0].href, isNull);
    expect(segments[1].text, '链接');
    expect(segments[1].href, 'https://example.com');
    expect(segments[2].text, ' 后缀');
    expect(segments[2].href, isNull);
  });

  test('extractInlineSegments preserves sale box position before images', () {
    final fragment = html_parser.parseFragment('''
      <div class="f14">
        文本说明<br>
        <h6 class="quote jumbotron">
          <span class="s3 f12 fn">此帖售价 5 SP币,已有 8 人购买</span>
          <input type="button"
            onclick="location.href='job.php?action=buytopic&tid=1&pid=1'">
        </h6>
        <blockquote class="blockquote jumbotron">购买风险提示</blockquote>
        <br>
        <img src="https://example.com/1.webp">
      </div>
    ''');
    final content = fragment.querySelector('.f14')!;

    final segments = ThreadContentParser().extractInlineSegments(content);

    expect(segments, hasLength(3));
    expect(segments[0].type, ThreadContentSegmentType.text);
    expect(segments[0].text, contains('文本说明'));
    expect(segments[1].type, ThreadContentSegmentType.saleBox);
    expect(segments[1].saleBox?.buyPath, 'job.php?action=buytopic&tid=1&pid=1');
    expect(segments[1].saleBox?.warning, '购买风险提示');
    expect(segments[2].type, ThreadContentSegmentType.image);
    expect(segments[2].url, 'https://example.com/1.webp');
  });

  test('WhatsLinkPreviewService treats empty api error as success', () {
    final error = WhatsLinkPreviewService.apiErrorMessage({
      'error': '',
      'type': 'FOLDER',
      'file_type': 'folder',
      'name': 'sample',
      'size': 281692258,
      'count': 5,
    });
    final preview = WhatsLinkPreview.fromJson(
      {
        'error': '',
        'type': 'FOLDER',
        'file_type': 'folder',
        'name': 'sample',
        'size': 281692258,
        'count': 5,
        'screenshots': [
          {
            'time': 0,
            'screenshot': 'https://whatslink.info/image/example',
          },
        ],
      },
      sourceUrl: 'magnet:?xt=urn:btih:test',
    );

    expect(error, isNull);
    expect(preview.name, 'sample');
    expect(preview.sizeBytes, 281692258);
    expect(preview.fileCount, 5);
    expect(preview.screenshotUrls, ['https://whatslink.info/image/example']);
  });

  test('ThreadDetailParser extracts desktop posts with avatars and pagination',
      () {
    final document = html_parser.parse('''
      <html>
        <body>
          <a href="read.php?tid-741222-fpage-0-toread--page-1.html">«</a>
          <span>2</span>
          <a href="read.php?tid-741222-fpage-0-toread--page-247.html">»</a>
          <a href="job.php?action-previous-fid-2-tid-741222-fpage-0-goto-previous.html">上一主题</a>
          <a href="job.php?action-previous-fid-2-tid-741222-fpage-0-goto-next.html">下一主题</a>
          <a href="rss.php?tid=741222">Rss订阅本帖最新内容</a>
          Pages: 2/247 Go
          <table class="js-post">
            <tr class="tr1">
              <th class="r_two" rowspan="2">
                <div class="user-pic">
                  <a href="u.php?action-show-uid-123.html">
                    <img src="images/face/a6.gif" alt="a6.gif">
                  </a>
                </div>
                <a href="u.php?action-show-uid-123.html">
                  <strong>Alice</strong>
                </a>
              </th>
              <th class="r_one" id="td_1">
                <div class="tiptop">
                  <span class="fl"><a class="s3">B1F</a></span>
                  <span class="fl gray" title="发表于: 2026-05-29 12:30">
                    2026-05-29 12:30
                  </span>
                  <a href="read.php?tid-741222-uid-123.html">只看该作者</a>
                  <a href="post.php?action-quote-fid-2-tid-741222-pid-1-article-1.html">引用</a>
                </div>
                <div class="tpc_content">
                  <div class="f14" id="read_1">
                    <h6 class="quote jumbotron">
                      <span class="s3 f12 fn">此帖售价 5 SP币,已有 8 人购买</span>
                      <input type="button"
                        onclick="location.href='job.php?action=buytopic&tid=741222&pid=1'">
                    </h6>
                    <blockquote class="blockquote jumbotron">购买风险提示</blockquote>
                    正文 <a href="https://example.com/file.zip">下载</a>
                  </div>
                </div>
              </th>
            </tr>
          </table>
        </body>
      </html>
    ''');

    final parser = ThreadDetailParser();
    final replies = parser.desktopThreadCards(document);
    final pagination = parser.desktopPagination(document, requestedPage: 2);
    final previousThread = parser.previousThread(document);
    final nextThread = parser.nextThread(document);
    final rssFeed = parser.rssFeed(document);

    expect(replies, hasLength(1));
    expect(replies.single.author, 'Alice');
    expect(replies.single.floor, 'B1F');
    expect(replies.single.postedAt, '2026-05-29 12:30');
    expect(
      replies.single.authorUrl,
      'https://south-plus.net/u.php?action-show-uid-123.html',
    );
    expect(
      replies.single.authorAvatarUrl,
      'https://south-plus.net/images/face/a6.gif',
    );
    expect(
      replies.single.authorPostsUrl,
      'https://south-plus.net/read.php?tid-741222-uid-123.html',
    );
    expect(
      replies.single.quoteUrl,
      'https://south-plus.net/post.php?action-quote-fid-2-tid-741222-pid-1-article-1.html',
    );
    expect(replies.single.saleBoxes.single.price, 5);
    expect(replies.single.saleBoxes.single.buyers, 8);
    expect(replies.single.saleBoxes.single.warning, '购买风险提示');
    expect(replies.single.links.single.url, 'https://example.com/file.zip');
    expect(replies.single.content, '正文 下载');
    expect(pagination.currentPage, 2);
    expect(pagination.totalPages, 247);
    expect(previousThread?.label, '上一主题');
    expect(
      previousThread?.url,
      'https://south-plus.net/job.php?action-previous-fid-2-tid-741222-fpage-0-goto-previous.html',
    );
    expect(nextThread?.label, '下一主题');
    expect(rssFeed?.url, 'https://south-plus.net/rss.php?tid=741222');
  });

  test('ThreadDetailParser extracts section title from thread breadcrumbs', () {
    final document = html_parser.parse('''
      <nav class="breadcrumb">
        <a href="index.php">南+ South Plus</a>
        <a href="simple/index.php?f16.html">技术交流</a>
        <span>帖子标题</span>
      </nav>
    ''');

    final section = ThreadDetailParser().sectionTitle(document);

    expect(section, '技术交流');
  });

  test('ThreadDetailParser extracts section title from p-style breadcrumbs',
      () {
    final document = html_parser.parse('''
      <nav class="breadcrumb">
        <a href="index.php">南+ South Plus</a>
        <a href="simple/index.php?p36.html">汉化本发布</a>
        <span>帖子标题</span>
      </nav>
    ''');

    final section = ThreadDetailParser().sectionTitle(document);

    expect(section, '汉化本发布');
  });

  test('ThreadDetailParser prefers desktop document title for section title',
      () {
    final document = html_parser.parse('''
      <html>
        <head>
          <title>试验出售 & 测试图床专用贴| 事务受理 - 南+ South Plus</title>
        </head>
        <body>
          <a href="thread.php?fid-2.html">事务受理</a>
          <a href="thread.php?fid-45.html">例大祭&紅楼夢</a>
        </body>
      </html>
    ''');

    final section = ThreadDetailParser().sectionTitle(document);

    expect(section, '事务受理');
  });

  test(
      'ThreadDetailParser does not treat author filter as canonical thread URL',
      () {
    final document = html_parser.parse('''
      <a href="read.php?tid-741222-uid-123.html">只看该作者</a>
      <a href="read.php?tid-741222.html">试验出售 & 测试图床专用贴</a>
    ''');

    final url = ThreadDetailParser().threadUrl(document);

    expect(url, 'https://south-plus.net/read.php?tid-741222.html');
  });

  test('ThreadDetailParser moves top attachments below read_tpc content', () {
    final document = html_parser.parse('''
      <html>
        <body>
          <table class="js-post">
            <tr class="tr1">
              <th class="r_two" rowspan="2">
                <a href="u.php?action-show-uid-2583629.html">
                  <strong>200a2fc2</strong>
                </a>
              </th>
              <th class="r_one" id="td_tpc">
                <div class="tiptop">
                  <span class="fl"><a class="s3">GF</a></span>
                  <span class="fl gray" title="发表于: 2026-06-19 18:59">
                    2026-06-19 18:59
                  </span>
                </div>
                <div class="tpc_content">
                  <div id="p_tpc" class="c"></div>
                  <div style="margin:5px" id="att_467407">
                    图片：
                    <br>
                    <img
                      src="//south-plus.net/attachment/Mon_2606/9_2583629_bd631ac289fc42b.jpg"
                      loading="lazy"
                      referrerpolicy="no-referrer"
                      border="0"
                      onclick="if(this.width&gt;=680) window.open('//south-plus.net/attachment/Mon_2606/9_2583629_bd631ac289fc42b.jpg');"
                      onload="if(this.width&gt;'680')this.width='680';"
                      width="680">
                  </div>
                  <div class="f14" id="read_tpc">
                    正文内容
                  </div>
                </div>
              </th>
            </tr>
          </table>
        </body>
      </html>
    ''');

    final replies = ThreadDetailParser().desktopThreadCards(document);

    expect(replies, hasLength(1));
    expect(replies.single.segments, hasLength(2));
    expect(replies.single.segments[0].text?.trim(), '正文内容\n 图片：');
    expect(
      replies.single.segments[1].url,
      'https://south-plus.net/attachment/Mon_2606/9_2583629_bd631ac289fc42b.jpg',
    );
    expect(replies.single.content, contains('正文内容'));
    expect(replies.single.content.indexOf('正文内容'),
        lessThan(replies.single.content.indexOf('图片：')));
  });

  test('UserProfileParser strips honor scripts and extracts online status', () {
    final profileDocument = html_parser.parse('''
      <div id="u-sidebar">
        <div id="u-portrait"><img class="pic" src="images/face/none.gif"></div>
        <table><tr><td>等级</td><td>Lv.0</td></tr></table>
        <a href="message.php?action-write-touid-2536715.html">发短消息</a>
        <img title="在线" src="images/colorImagination/u-adf.gif">
        <a title="在线">加为好友</a>
      </div>
      <div id="u-top">
        <h1 class="u-h1">Alice</h1>
        <span id="honor">您还没有设置个性签名</span>
        <script>function honor(){ getObj('honor').innerHTML = 'x'; }</script>
      </div>
      <div id="u-profile">
        <table>
          <tr><td>UID</td><th>2536715</th></tr>
          <tr><td>自我简介</td><th><div><br></div></th></tr>
        </table>
      </div>
      <div id="u-profile-s">
        <table><tr><td>在线时间</td><th>9 小时</th></tr></table>
      </div>
    ''');
    final parser = UserProfileParser();

    final profile = parser.parse(
      uid: '2536715',
      profileUrl: 'https://south-plus.net/u.php?action-show-uid-2536715.html',
      profileDocument: profileDocument,
      homeDocument: html_parser.parse(''),
      topicsDocument: html_parser.parse(''),
      postsDocument: html_parser.parse(''),
      favoritesDocument: html_parser.parse(''),
    );

    expect(profile.tagline, '您还没有设置个性签名');
    expect(profile.tagline, isNot(contains('function honor')));
    expect(profile.isOnline, isTrue);
    expect(profile.statusText, '在线');
    expect(
      profile.messageUrl,
      'https://south-plus.net/message.php?action-write-touid-2536715.html',
    );
    expect(profile.info.map((field) => field.label), isNot(contains('自我简介')));
  });
}
