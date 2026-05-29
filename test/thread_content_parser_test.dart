import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/services/parsers/thread_content_parser.dart';
import 'package:south_plus_rewrite/services/whats_link_preview_service.dart';

void main() {
  test('extractInlineSegments trims boundary blank lines', () {
    final fragment = html_parser.parseFragment(
      '<div class="card-text"><br><br>\n  正文第一行<br>正文第二行<br><br></div>',
    );
    final content = fragment.querySelector('.card-text')!;

    final segments = const ThreadContentParser().extractInlineSegments(content);

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
      },
      sourceUrl: 'magnet:?xt=urn:btih:test',
    );

    expect(error, isNull);
    expect(preview.name, 'sample');
    expect(preview.sizeBytes, 281692258);
    expect(preview.fileCount, 5);
  });
}
