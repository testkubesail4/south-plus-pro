import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/services/parsers/thread_image_preview_parser.dart';

void main() {
  test('ThreadImagePreviewParser extracts thread author preview images', () {
    final firstPage = html_parser.parse('''
      <html>
        <body>
          <table>
            <tr>
              <td><a href="u.php?action-show-uid-123.html">Alice</a></td>
              <td>
                <div class="tpc_content">
                  <div class="f14" id="read_1">
                    <img src="images/post/smile/foo.gif">
                    <img data-original="attachment/Mon_2606/1.jpg">
                    <a href="https://ibb.co/example">host page</a>
                    <input value="免费购买" onclick="location.href='job.php?action=buytopic&tid=1'">
                  </div>
                </div>
              </td>
            </tr>
          </table>
        </body>
      </html>
    ''');
    final secondPage = html_parser.parse('''
      <html>
        <body>
          <table>
            <tr>
              <td><a href="u.php?action-show-uid-456.html">Bob</a></td>
              <td><div class="f14" id="read_2"><img src="https://example.com/bob.jpg"></div></td>
            </tr>
            <tr>
              <td><a href="u.php?action-show-uid-123.html">Alice</a></td>
              <td><div class="f14" id="read_3">https://catbox.moe/sample.webp</div></td>
            </tr>
          </table>
        </body>
      </html>
    ''');

    final preview = ThreadImagePreviewParser().parsePages([
      (document: firstPage, url: 'https://south-plus.net/read.php?tid-1.html'),
      (document: secondPage, url: 'https://south-plus.net/read.php?tid-1-page-2.html'),
    ]);

    expect(preview.images.map((image) => image.url), [
      'https://south-plus.net/attachment/Mon_2606/1.jpg',
      'https://catbox.moe/sample.webp',
    ]);
    expect(preview.hostPages, ['https://ibb.co/example']);
    expect(preview.hasBuyBlock, isTrue);
  });

  test('ThreadImagePreviewParser extracts host page og image', () {
    final document = html_parser.parse('''
      <html>
        <head>
          <meta property="og:image" content="/images/full.jpg">
        </head>
      </html>
    ''');

    final images = ThreadImagePreviewParser().parseHostPage(
      document,
      'https://postimg.cc/abc123',
    );

    expect(images.single.url, 'https://postimg.cc/images/full.jpg');
  });
}
