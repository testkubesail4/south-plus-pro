import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

const _category = ForumCategory(name: 'Fixture board', slug: 'fid-901');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (kind, suffix) in [
    (ForumBoardFilterKind.digest, '-search-digest'),
    (ForumBoardFilterKind.topicType, '-type-2'),
    (ForumBoardFilterKind.special, '-special-1'),
    (ForumBoardFilterKind.all, ''),
  ]) {
    test(
      'filtered $kind fetch composes paging/order and keeps active filter',
      () async {
        final client = _BoardClient('''$_boardHtml
        <div class="pages"><b>2</b>
          <a href="thread_new.php?fid-901$suffix-orderway-hits-asc-DESC-page-9.html">9</a>
        </div>''');
        final filter = ForumBoardFilter(
          label: 'Fixture selection',
          kind: kind,
          url: 'https://south-plus.net/thread.php?fid-901$suffix.html#c',
        );
        final page = await ForumRepository(client: client).fetchBoardThreadPage(
          _category,
          page: 2,
          order: ForumThreadOrder.hits,
          filter: filter,
        );
        expect(client.paths, [
          'thread_new.php?fid-901$suffix-orderway-hits-asc-DESC-page-2.html',
        ]);
        expect(page.activeFilter?.kind, kind);
        expect(page.currentPage, 2);
        expect(page.totalPages, 9);
      },
    );
  }

  test(
    'board filter deep links preserve their type instead of loading all',
    () async {
      final client = _BoardClient(_boardHtml);
      final page = await ForumRepository(client: client).fetchBoardThreadPage(
        const ForumCategory(
          name: 'Fixture board',
          slug: 'fid-901',
          url: 'https://south-plus.net/thread.php?fid=901&type=2',
        ),
      );
      expect(client.paths, [
        'thread_new.php?fid-901-type-2-orderway-lastpost-asc-DESC-page-1.html',
      ]);
      expect(page.activeFilter?.kind, ForumBoardFilterKind.topicType);
    },
  );

  test(
    'empty filtered wall returns an empty page instead of a parse error',
    () async {
      final client = _BoardClient(
        '''<div class="hthread"><ul class="threadlist">
      <li><a href="thread_new.php?fid-901.html">全部</a></li>
      <li><a href="thread_new.php?fid-901-search-digest.html">精华</a></li>
      </ul></div><ul class="stream"></ul>''',
      );
      final page = await ForumRepository(client: client).fetchBoardThreadPage(
        _category,
        filter: const ForumBoardFilter(
          label: '精华',
          url: 'thread.php?fid-901-search-digest.html',
          kind: ForumBoardFilterKind.digest,
        ),
      );
      expect(page.threads, isEmpty);
      expect(page.activeFilter?.label, '精华');
      expect(page.hasNext, isFalse);
      expect(page.currentPage, 1);
      expect(page.totalPages, 1);
    },
  );

  test(
    'untrusted or malformed filters reject before making a request',
    () async {
      for (final (url, kind) in [
        (
          'https://example.invalid/thread.php?fid-901-type-2.html',
          ForumBoardFilterKind.topicType,
        ),
        ('post.php?fid-901-type-2.html', ForumBoardFilterKind.topicType),
        ('thread.php?fid-999-type-2.html', ForumBoardFilterKind.topicType),
        ('thread.php?fid=901&type=2&type=3', ForumBoardFilterKind.topicType),
        (
          'thread.php?fid-901-type-2-special-1.html',
          ForumBoardFilterKind.topicType,
        ),
        ('thread.php?fid-901-type-2.html', ForumBoardFilterKind.digest),
        ('thread.php?fid-901-search-unknown.html', ForumBoardFilterKind.digest),
        ('thread.php?fid-901-special-6.html', ForumBoardFilterKind.special),
        (
          'thread.php?fid-901-type-2-action-delete.html',
          ForumBoardFilterKind.topicType,
        ),
      ]) {
        final client = _BoardClient(_boardHtml);
        await expectLater(
          ForumRepository(client: client).fetchBoardThreadPage(
            _category,
            filter: ForumBoardFilter(
              label: 'Fixture invalid',
              url: url,
              kind: kind,
            ),
          ),
          throwsA(isA<ForumRepositoryException>()),
          reason: url,
        );
        expect(client.paths, isEmpty, reason: url);
      }
    },
  );

  test(
    'board filters expose safe URLs, site order and server-selected type',
    () async {
      final page = await ForumRepository(
        client: _BoardClient(_boardHtml),
      ).fetchBoardThreadPage(_category);
      expect(page.filters.map((filter) => filter.label), [
        '全部',
        '精华',
        'Fixture type',
        '投票',
        '活动',
        '悬赏',
        '商品',
        '辩论',
      ]);
      expect(page.filters.map((filter) => filter.kind), [
        ForumBoardFilterKind.all,
        ForumBoardFilterKind.digest,
        ForumBoardFilterKind.topicType,
        ...List.filled(5, ForumBoardFilterKind.special),
      ]);
      expect(
        page.filters[1].url,
        'https://south-plus.net/thread_new.php?fid-901-search-digest.html#c',
      );
      expect(
        page.filters[3].url,
        'https://south-plus.net/thread.php?fid-901-special-1.html',
      );
      expect(page.activeFilter?.label, 'Fixture type');
    },
  );

  test(
    'picture-wall aliases become view flags and preserve child metadata',
    () async {
      final client = _BoardClient(_boardHtml);
      final page = await ForumRepository(
        client: client,
      ).fetchBoardThreadPage(_category);

      expect(page.subBoards.map((board) => board.name), ['Fixture child']);
      final child = page.subBoards.single;
      expect(child.hasPictureWall, isTrue);
      expect(child.postCount, 12);
      expect(child.subtitle, 'Fixture description');
      expect(child.lastPostTitle, 'Fixture last topic');
      expect(child.lastPostTime, '2026-01-02 03:04');
      expect(page.hasPictureWall, isTrue);
      expect(page.parents.map((parent) => parent.name), ['Fixture parent']);
      expect(page.parents.single.slug, 'fid-900');
      expect(
        page.threads.single.previewImageUrl,
        'https://south-plus.net/attachment/fixture.jpg',
      );
      expect(
        page.threads.single.url,
        'https://south-plus.net/read.php?tid-701.html',
      );
    },
  );
}

// Synthetic structure from round4 thread-fid13/thread-fid36/thread_new-fid36.
const _boardHtml = '''
<html><body>
<div id="breadcrumbs"><a href="index.php">Fixture site</a>
  <a href="thread.php?fid-900.html">Fixture parent</a>
  <a href="https://example.invalid/thread.php?fid-999.html">Foreign</a>
  <a href="thread.php?fid-901.html">Fixture board</a></div>
<a href="thread_new.php?fid-901-page-1.html">[点击进入图墙模式]</a>
<table><tr><td>子版块</td></tr>
  <tr><td>论坛</td><td>文章</td><td>最后发表</td></tr>
  <tr><th><h2><a href="thread.php?fid-904.html">图墙模式</a></h2></th><td>0</td><th></th></tr>
  <tr><th><h2><a href="thread.php?fid-903.html">Fixture child (图墙模式)</a></h2></th><td>0</td><th></th></tr>
  <tr><th><h2><a href="thread.php?fid-902.html">Fixture child</a></h2>
    <span class="smalltxt">Fixture description</span></th><td>12</td>
    <th title="2026-01-02 03:04"><h3><a href="read.php?tid-702.html">Fixture last topic</a></h3>
      Fixture last author</th></tr>
</table>
<div id="menu_special"><ul>
  <li><a href="thread.php?fid-901.html">全 部</a></li>
  <li><a href="thread.php?fid-901-special-1.html">投 票</a></li>
  <li><a href="thread.php?fid-901-special-2.html">活 动</a></li>
  <li><a href="thread.php?fid-901-special-3.html">悬 赏</a></li>
  <li><a href="thread.php?fid-901-special-4.html">商 品</a></li>
  <li><a href="thread.php?fid-901-special-5.html">辩 论</a></li>
  <li><a href="post.php?fid-901-special-1.html">Fixture action</a></li>
</ul></div>
<div class="hthread"><ul class="threadlist">
  <li id="thread_type_all" class="current"><a href="thread_new.php?fid-901.html#c">全部</a></li>
  <li id="thread_type_digest"><a href="thread_new.php?fid-901-search-digest.html#c">精华</a></li>
  <li id="thread_type_2"><a href="thread_new.php?fid-901-type-2.html#c">Fixture type</a></li>
  <li><a href="https://example.invalid/thread.php?fid-901-type-3.html">Foreign</a></li>
  <li><a href="thread.php?fid-999-type-4.html">Other board</a></li>
</ul></div>
<script>setCurrent('thread_type_2','thread_type_all','current');</script>
<ul class="stream"><li class="dcsns-li">
  <span class="section-title"><a href="read.php?tid-701.html">Fixture topic</a></span>
  <span class="section-text">回复/人气：3/42
    <a href="read.php?tid-701.html"><img src="/attachment/fixture.jpg"></a></span>
  <span class="section-intro"><a class="bl" href="u.php?action-show-uid-801.html">Fixture author</a>2026-01-02</span>
</li></ul>
</body></html>
''';

class _BoardClient extends ForumClient {
  _BoardClient(this.body);
  final String body;
  final paths = <String>[];

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<String> get(String path) async {
    paths.add(path);
    return body;
  }
}
