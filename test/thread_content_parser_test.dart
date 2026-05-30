import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
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

  test('ThreadDetailParser keeps reply author profile url', () {
    final document = html_parser.parse('''
      <div class="card">
        <div class="card-body">
          <h6>
            <a href="u.php?action-show-uid-123.html">
              <strong>Alice</strong>
            </a>
            <span class="float-right">#2</span>
            2026-05-29 12:30
          </h6>
          <div class="card-text">正文</div>
        </div>
      </div>
    ''');

    final replies = ThreadDetailParser().simpleThreadCards(document);

    expect(replies, hasLength(1));
    expect(replies.single.author, 'Alice');
    expect(
      replies.single.authorUrl,
      'https://south-plus.net/u.php?action-show-uid-123.html',
    );
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
