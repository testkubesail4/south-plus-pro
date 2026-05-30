import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';
import 'package:south_plus_rewrite/services/parsers/thread_content_parser.dart';
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
}
