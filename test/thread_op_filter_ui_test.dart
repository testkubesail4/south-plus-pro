import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional host paths, tids, uids and authors.
const _threadUrl = 'https://south-plus.net/read.php?tid-7.html';
const _opProfile = 'https://south-plus.net/u.php?action-show-uid-3.html';
const _unavailable = '无法只看楼主：缺少楼主身份';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpWith(
    WidgetTester tester,
    ForumRepository repository,
    String url,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: ThreadDetailScreen(
        repository: repository,
        thread: ForumThread(title: 'op', url: url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<_FakeRepository> pumpThread(
    WidgetTester tester, {
    String? authorUrl,
  }) async {
    final repository = _FakeRepository(authorUrl);
    await pumpWith(tester, repository, _threadUrl);
    return repository;
  }

  Finder opChip() =>
      find.ancestor(of: find.text('只看楼主'), matching: find.byType(FilterChip));

  Future<void> tapOpChip(WidgetTester tester) async {
    await tester.ensureVisible(opChip());
    await tester.tap(opChip());
    await tester.pumpAndSettle();
  }

  testWidgets(
      'OP without a posts link filters on the server '
      'instead of hiding rows locally', (tester) async {
    final repository = await pumpThread(tester, authorUrl: _opProfile);
    await tester.tap(find.byTooltip('下一页').first);
    await tester.pumpAndSettle();
    expect(
        find.text('others only on page 2', findRichText: true), findsOneWidget);
    // The chip lives on the opening post, which only page 1 shows.
    await tester.tap(find.byTooltip('上一页').first);
    await tester.pumpAndSettle();

    await tapOpChip(tester);

    expect(Uri.parse(repository.requested.last).query, 'tid-7-uid-3.html');
    expect(find.text('没有楼主回复'), findsNothing);
    expect(find.text('第 1 / 1 页 · 本页 2 楼'), findsOneWidget);
    expect(tester.widget<FilterChip>(opChip()).selected, isTrue);
    expect(find.text('»'), findsNothing,
        reason: 'filtered server response has a single page');
  });

  testWidgets('search same title prefills all boards without submitting',
      (tester) async {
    final repository = await pumpThread(tester, authorUrl: _opProfile);

    await tester.tap(find.byTooltip('搜索同名主题'));
    await tester.pumpAndSettle();

    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialKeyword, 'loaded title');
    expect(search.initialBoard, isNull);
    expect(find.widgetWithText(TextField, 'loaded title'), findsOneWidget);
    expect(repository.searches, 0);
  });

  for (final authorUrl in [
    null,
    'https://south-plus.net.evil.invalid/u.php?action-show-uid-3.html',
    'https://south-plus.net/u.php?action-show-uid-0.html',
  ]) {
    testWidgets('OP without a verified identity ($authorUrl) is unavailable',
        (tester) async {
      final repository = await pumpThread(tester, authorUrl: authorUrl);
      final before = repository.requested.length;

      await tapOpChip(tester);

      expect(find.text(_unavailable), findsOneWidget);
      expect(repository.requested, hasLength(before));
      expect(tester.widget<FilterChip>(opChip()).selected, isFalse);
      expect(find.text('没有楼主回复'), findsNothing);
      expect(find.text('reply by other', findRichText: true), findsOneWidget);
    });
  }

  // Real ForumRepository + parser over synthetic HTML: OP identity must come
  // from the unfiltered thread, never from a filtered page's first row.
  group('real repository composition', () {
    late _HtmlClient client;
    late ForumRepository repository;
    setUp(() {
      client = _HtmlClient();
      repository =
          ForumRepository(client: client, historyStore: _NoHistoryStore());
    });

    bool opChipSelected(WidgetTester tester) =>
        tester.widget<FilterChip>(opChip()).selected;

    testWidgets(
        'another author filter never becomes the OP filter; '
        'OP toggle then requests the original OP uid', (tester) async {
      await pumpWith(tester, repository, _threadUrl);
      expect(opChipSelected(tester), isFalse);

      final otherActions =
          find.byKey(const ValueKey('floor-actions-other-B1F'));
      // Centre it so the floating reply button cannot cover the menu.
      Scrollable.ensureVisible(tester.element(otherActions), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(otherActions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('只看该作者'));
      await tester.pumpAndSettle();

      expect(client.paths.last, 'read.php?tid-7-uid-902.html');
      expect(find.text('只看 other'), findsOneWidget);
      expect(opChipSelected(tester), isFalse);

      await tapOpChip(tester);

      expect(client.paths.last, 'read.php?tid-7-uid-901.html');
      expect(opChipSelected(tester), isTrue);

      await tapOpChip(tester);
      expect(client.paths.last, 'read.php?tid-7.html');
      expect(opChipSelected(tester), isFalse);
    });

    testWidgets('uid deep link can be cleared to the unfiltered thread',
        (tester) async {
      await pumpWith(tester, repository,
          'https://south-plus.net/read.php?tid-7-uid-902.html#11');

      final clear = find.byTooltip('取消只看该作者');
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();

      expect(client.paths.last, 'read.php?tid-7.html');
      expect(find.text('opening body', findRichText: true), findsOneWidget);
      expect(clear, findsNothing);
    });

    testWidgets(
        'deep link already filtered by an unknown author never '
        'impersonates the OP', (tester) async {
      await pumpWith(tester, repository,
          'https://south-plus.net/read.php?tid-7-uid-902.html');
      expect(client.paths.single, 'read.php?tid-7-uid-902.html');

      // Either no OP chip or an unselected one that cannot request uid 902.
      if (opChip().evaluate().isNotEmpty) {
        expect(opChipSelected(tester), isFalse);
        await tapOpChip(tester);
        expect(client.paths.where((p) => p.contains('uid-902')), hasLength(1));
      }
    });
  });
}

class _HtmlClient extends ForumClient {
  final paths = <String>[];

  static String _post(
          String uid, String name, String floor, String pid, String body) =>
      '''
<table class="js-post"><tr>
  <th class="r_two"><a href="u.php?action-show-uid-$uid.html"><strong>$name</strong></a></th>
  <th class="r_one" id="td_$pid"><div class="tiptop">
    <span class="fl"><a class="s3">$floor</a></span>
    <a href="read.php?tid-7-uid-$uid.html">只看该作者</a></div>
    <div class="tpc_content"><div class="f14" id="read_$pid">$body</div></div>
  </th></tr></table>''';

  @override
  Future<String> get(String path) async {
    paths.add(path);
    final op = _post('901', 'opuser', '楼主', 'tpc', 'opening body');
    final other = _post('902', 'other', 'B1F', '11', 'reply by other');
    final posts = path.contains('uid-902')
        ? other
        : path.contains('uid-901')
            ? op
            : '$op$other';
    return '''<html><body>Pages: 1/1
<span id="subject_tpc">Fixture thread</span>
<a href="read.php?tid-7.html">Fixture thread</a>
$posts</body></html>''';
  }
}

// The real store opens a database, whose IO never completes in fake async.
class _NoHistoryStore extends BrowsingHistoryStore {
  @override
  Future<void> recordThread(ForumThread thread, {DateTime? viewedAt}) async {}
}

class _FakeRepository extends ForumRepository {
  _FakeRepository(this.authorUrl);

  final String? authorUrl;
  final requested = <String>[];
  var searches = 0;

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => const [];

  @override
  Future<ForumSearchPage> searchForum(ForumSearchQuery query) {
    searches++;
    throw StateError('search must not be submitted');
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread,
      {int page = 1}) async {
    requested.add(thread.url);
    final filtered = thread.url.contains('-uid-3');
    final opThread = ForumThread(
      title: '  loaded title ',
      url: filtered
          ? 'https://south-plus.net/read.php?tid-7-uid-3.html'
          : _threadUrl,
      replies: 2,
      section: 'synthetic',
      author: 'opuser',
      authorUrl: authorUrl,
    );
    if (filtered) {
      return ThreadDetail(
        thread: opThread,
        body: 'opening body',
        pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
        replies: const [
          ThreadReply(author: 'opuser', content: 'op follow-up', floor: 'B9F'),
        ],
      );
    }
    return ThreadDetail(
      thread: opThread,
      body: page == 1 ? 'opening body' : '',
      pagination: ThreadPagination(currentPage: page, totalPages: 2),
      replies: [
        ThreadReply(
          author: 'other',
          content: page == 1 ? 'reply by other' : 'others only on page 2',
          floor: page == 1 ? 'B1F' : 'B31F',
        ),
      ],
    );
  }
}
