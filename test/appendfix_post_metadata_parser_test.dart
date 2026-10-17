import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:south_plus_rewrite/services/parsers/thread_detail_parser.dart';

void main() {
  for (final sample in [
    (title: '发表于: 昨天', text: '2026-10-16 21:26', time: '2026-10-16 21:26'),
    (title: '发表于: 2026-10-15 12:34', text: '昨天', time: '2026-10-15 12:34'),
    (title: '发表于: 昨天', text: '昨天', time: null),
  ]) {
    test('post metadata uses a full date: ${sample.title}/${sample.text}', () {
      final document = html_parser.parse('''
        <table class="js-post"><tr>
          <th class="r_two"><a href="u.php?action-show-uid-12.html"><strong>Author</strong></a></th>
          <th class="r_one">
            <div class="tiptop"><span class="fl"><span class="s3">楼主</span></span>
              <span class="fl gray" title="${sample.title}">${sample.text}</span>
              <div class="fl bianji">（短签名）</div>
            </div>
            <div class="tpc_content" id="read_tpc">Opening body</div>
            <div class="signature">Footer signature is not floor metadata</div>
          </th>
        </tr></table>
        <table class="js-post"><tr>
          <th class="r_two"><a href="u.php?action-show-uid-13.html"><strong>Reply author</strong></a></th>
          <th class="r_one">
            <div class="tiptop"><span class="fl"><span class="s3">B1F</span></span>
              <span class="gray" title="发表于: 昨天">2026-10-16 22:30</span>
            </div>
            <div class="tpc_content" id="read_42">Reply body</div>
            <div class="signature">Never use this footer</div>
          </th>
        </tr></table>
      ''');
      final posts = ThreadDetailParser().desktopThreadCards(document);

      expect(posts, hasLength(2));
      expect(posts.first.postedAt, sample.time);
      expect(posts.first.personalSignature, '短签名');
      expect(posts.last.postedAt, '2026-10-16 22:30');
      expect(posts.last.personalSignature, isNull);
    });
  }
}
