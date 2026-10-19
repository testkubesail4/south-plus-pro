import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/forum_link_opener.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';

// Synthetic fixtures only: fictional host, tids, pids and authors.
const _base = 'https://south-plus.net/read.php';
const _notFound = '未找到指定楼层，已显示所在页';
const _viewport = Size(360, 780);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeRepository> pumpThread(
    WidgetTester tester,
    String url, {
    double textScale = 2,
  }) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ThreadDetailScreen(
          repository: repository,
          thread: ForumThread(
            title: 'anchor',
            url: url,
            replies: 0,
            section: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  void expectOnScreen(Finder floor) {
    expect(
      floor.hitTestable(),
      findsOneWidget,
      reason: '$floor should be visible, not just built',
    );
  }

  testWidgets('#fl-N reveals that floor, distinct from a numeric post id', (
    tester,
  ) async {
    await pumpThread(tester, '$_base?tid-7.html#fl-20');
    expectOnScreen(floor('B20F'));
    expect(find.text(_notFound), findsNothing);
  });

  testWidgets('numeric post id reveals the post carrying that DOM anchor', (
    tester,
  ) async {
    // Post id 20 belongs to floor B11F (pid = page * 31 - floor).
    await pumpThread(tester, '$_base?tid-7.html#20');
    expectOnScreen(floor('B11F'));
    expect(floor('B20F').hitTestable(), findsNothing);
  });

  testWidgets('read_PID anchor at 1x scale reveals the reply', (tester) async {
    await pumpThread(tester, '$_base?tid-7.html#read_6', textScale: 1);
    expectOnScreen(floor('B25F'));
  });

  testWidgets('page-e with #a shows the real last page and its anchored row', (
    tester,
  ) async {
    final repository = await pumpThread(tester, '$_base?tid=7&page=e&#a');
    expect(repository.requested.first, contains('page=e'));
    expectOnScreen(floor('B90F'));
    // The page bar under the list shows the page.
    expect(find.textContaining('第 3 /'), findsWidgets);
  });

  testWidgets('resume then 从头看 reveals a detached tpc anchor parsed from HTML',
      (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _MarkupClient();
    final repository = ForumRepository(client: client, historyStore: _History());
    const thread = ForumThread(
        title: 'fixture', url: '$_base?tid-7.html', replies: 40, section: '');
    await repository.saveThreadReadPosition(
        thread, const ThreadReadPosition(page: 2, anchor: '1040'));
    await tester.pumpWidget(MaterialApp(
        home: ThreadDetailScreen(repository: repository, thread: thread)));
    await tester.pumpAndSettle();
    expectOnScreen(floor('B40F'));
    expect(find.text('从头看'), findsOneWidget);
    await tester.tap(find.text('从头看'));
    await tester.pumpAndSettle();
    expect(client.paths, hasLength(2));
    expect(find.text(_notFound), findsNothing);
    expect(find.text('Opening fixture body', findRichText: true).hitTestable(),
        findsOneWidget);
    final detail = await repository.fetchThreadDetail(thread);
    expect(detail.bodyAnchors, contains('tpc'));
    expect(detail.replies.single.anchors, isNot(contains('tpc')));
    final saved = await repository.loadThreadReadPosition(thread);
    expect(saved?.page, 1);
    expect(saved?.anchor, 'tpc', reason: 'a zero-offset reveal may emit no ScrollEnd');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final reopened = ForumRepository(client: client, historyStore: _History());
    await tester.pumpWidget(MaterialApp(
        home: ThreadDetailScreen(repository: reopened, thread: thread)));
    await tester.pumpAndSettle();
    expect(find.text('Opening fixture body', findRichText: true).hitTestable(),
        findsOneWidget);
    expect(find.textContaining('已回到上次阅读位置'), findsNothing);
    expect(find.text(_notFound), findsNothing);
    expect(client.paths.where((path) => path.contains('page-2')), hasLength(1));
  });

  testWidgets('opening post body anchor stays on the opening post', (
    tester,
  ) async {
    final repository = await pumpThread(tester, '$_base?tid-7.html#tpc');
    expectOnScreen(find.text('楼主'));
    expect(find.text(_notFound), findsNothing);
    expect(repository.requested, hasLength(1));
  });

  for (final fragment in ['zzz', 'fl-', 'fl-999', '%E0']) {
    testWidgets('unknown fragment #$fragment falls back on the shown page', (
      tester,
    ) async {
      await pumpThread(tester, '$_base?tid-7.html#$fragment');
      expect(find.text(_notFound), findsOneWidget);
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(list.position.pixels, 0);
    });
  }

  testWidgets('anchor jump runs once, not again on refresh', (tester) async {
    final repository = await pumpThread(tester, '$_base?tid-7.html#zzz');
    expect(find.text(_notFound), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 600),
      1000,
    );
    await tester.pumpAndSettle();
    expect(repository.requested.length, greaterThan(1));
    expect(find.text(_notFound), findsNothing);
  });

  testWidgets('topost link keeps the server endpoint and jumps to its PID',
      (tester) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openForumLink(
              context,
              repository,
              'https://south-plus.net/job.php?action-topost-tid-7-pid-20.html',
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final requested = repository.requested.single;
    expect(requested, contains('job.php?action-topost-tid-7-pid-20.html'));
    expect(Uri.parse(requested).fragment, '20');
    // The server-chosen page 2 holds pid 20 on floor B42F.
    expectOnScreen(floor('B42F'));
    expect(find.text(_notFound), findsNothing);
  });

  testWidgets('no fragment keeps the page at the top', (tester) async {
    await pumpThread(tester, '$_base?tid-7.html');
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(list.position.pixels, 0);
    expect(find.text(_notFound), findsNothing);
  });
}

class _FakeRepository extends ForumRepository {
  final requested = <String>[];

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    requested.add(thread.url);
    final lastPage = thread.url.contains('page=e') || page == 3;
    // Stands in for the server redirecting a topost request to page 2.
    final topost = thread.url.contains('job.php') && page == 1;
    final currentPage = lastPage ? 3 : (topost ? 2 : page);
    final first = (currentPage - 1) * 30;
    return ThreadDetail(
      thread: ForumThread(
        title: 'anchor',
        url: '$_base?tid-7.html',
        replies: 90,
        section: 'synthetic',
        author: 'op',
      ),
      body: currentPage == 1 ? 'opening body' : '',
      bodyAnchors:
          currentPage == 1 ? const ['tpc', 'read_tpc', 'fl-0'] : const [],
      pagination: ThreadPagination(currentPage: currentPage, totalPages: 3),
      replies: [
        for (var floor = first + 1; floor <= first + 30; floor++)
          ThreadReply(
            author: 'user$floor',
            content: 'reply body $floor ' * 6,
            floor: 'B${floor}F',
            anchors: [
              '${currentPage * 31 - floor}',
              'read_${currentPage * 31 - floor}',
              'fl-$floor',
              if (floor == 90) 'a',
            ],
          ),
      ],
    );
  }
}

class _History extends BrowsingHistoryStore {
  @override
  Future<void> recordThread(ForumThread thread, {DateTime? viewedAt}) async {}
}

class _MarkupClient extends ForumClient {
  final paths = <String>[];

  @override
  Future<String> get(String path) async {
    paths.add(path);
    final second = path.contains('page-2');
    String post(String id, String floor, String body) =>
        '<a name="$id"></a><div class="t5 t2"><table class="js-post">'
        '<tr><th class="r_two"><a href="u.php?action-show-uid-42.html">'
        '<strong>Fixture author</strong></a></th><th class="r_one" id="td_$id">'
        '<div class="tiptop"><span class="fl"><a class="s3">$floor</a></span>'
        '</div><div class="tpc_content"><div id="read_$id">$body</div></div>'
        '</th></tr></table></div>';
    return '<div class="pages">Pages: ${second ? 2 : 1}/2</div><form>'
        '${second ? '' : post('tpc', '楼主', 'Opening fixture body')}'
        '${post('1040', 'B40F', 'Reply fixture body')}</form>'
        '<form><a name="foreign"></a></form>';
  }
}

/// A floor by its label in the meta line (`time · B12F`).
Finder floor(String label) => find.textContaining(RegExp('\\b$label\$'));
