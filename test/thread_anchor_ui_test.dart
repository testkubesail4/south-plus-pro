import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/forum_link_opener.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
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
    bool favorited = false,
  }) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository()..favorited = favorited;
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
    final repository =
        ForumRepository(client: client, historyStore: _History());
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
    expect(client.paths, hasLength(3),
        reason: 'page2 also fetches compact OP metadata before 从头看');
    expect(find.text(_notFound), findsNothing);
    expect(find.text('Opening fixture body', findRichText: true).hitTestable(),
        findsOneWidget);
    final detail = await repository.fetchThreadDetail(thread);
    expect(detail.bodyAnchors, contains('tpc'));
    expect(detail.replies.single.anchors, isNot(contains('tpc')));
    final saved = await repository.loadThreadReadPosition(thread);
    expect(saved?.page, 1);
    expect(saved?.anchor, 'tpc',
        reason: 'a zero-offset reveal may emit no ScrollEnd');
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

  group('回 N楼 link', () {
    Future<_FakeRepository> openPage2(WidgetTester tester) =>
        pumpThread(tester, '$_base?tid-7-page-2.html', textScale: 1);

    Future<void> tapLink(WidgetTester tester, String label,
        {bool settle = true}) async {
      // A lookup on its way keeps the progress bar moving.
      Future<void> settled() => settle
          ? tester.pumpAndSettle()
          : tester.pump(const Duration(milliseconds: 500));
      final link = find.text(label);
      await tester.scrollUntilVisible(link, 300,
          scrollable: find.byType(Scrollable).first);
      // Clear of the app bar.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 200));
      await settled();
      await tester.tap(link);
      await settled();
    }

    testWidgets('reveals a target on a loaded page without a request',
        (tester) async {
      final repository = await openPage2(tester);
      final requests = repository.requested.length;
      await tapLink(tester, '回 32楼 user32');
      expectOnScreen(floor('B32F'));
      expect(repository.lookups, isEmpty);
      expect(repository.requested, hasLength(requests));
    });

    testWidgets('opens the page the repository verified for the target',
        (tester) async {
      final repository = await openPage2(tester);
      await tapLink(tester, '回 28楼 user28');
      expect(repository.lookups, [28]);
      expectOnScreen(floor('B28F'));
      expect(find.textContaining('第 1 /'), findsWidgets);
    });

    testWidgets('a missing target says so and keeps the page', (tester) async {
      final repository = await openPage2(tester);
      await tapLink(tester, '回 999楼 user999');
      expect(repository.lookups, [999]);
      expect(find.text('未找到999楼'), findsOneWidget);
      expect(find.textContaining('第 2 /'), findsWidgets);
    });

    testWidgets('a later tap drops the lookup still on its way',
        (tester) async {
      final repository = await openPage2(tester);
      final slow = Completer<void>();
      repository.lookupGate = slow;
      await tapLink(tester, '回 28楼 user28', settle: false);
      repository.lookupGate = null;
      await tapLink(tester, '回 999楼 user999', settle: false);
      slow.complete();
      await tester.pumpAndSettle();
      expect(repository.lookups, [28, 999]);
      expect(find.text('未找到999楼'), findsOneWidget);
      expect(find.textContaining('第 2 /'), findsWidgets);
      expect(floor('B28F'), findsNothing);
    });

    testWidgets('a tap on a loaded floor drops the lookup on its way',
        (tester) async {
      final repository = await openPage2(tester);
      final slow = Completer<void>();
      repository.lookupGate = slow;
      await tapLink(tester, '回 28楼 user28', settle: false);
      await tapLink(tester, '回 32楼 user32', settle: false);
      slow.complete();
      await tester.pumpAndSettle();
      expect(repository.lookups, [28]);
      expectOnScreen(floor('B32F'));
      expect(floor('B28F'), findsNothing);
      expect(find.textContaining('第 2 /'), findsWidgets);
    });

    testWidgets('leaving for another page drops the lookup', (tester) async {
      final repository = await openPage2(tester);
      final slow = Completer<void>();
      repository.lookupGate = slow;
      await tapLink(tester, '回 28楼 user28', settle: false);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('elsewhere'))));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      slow.complete();
      await tester.pump(const Duration(seconds: 1));
      navigator.pop();
      // Settling proves the progress bar is gone.
      await tester.pumpAndSettle();
      expect(find.textContaining('第 2 /'), findsWidgets);
      expect(floor('B28F'), findsNothing);
      expect(find.textContaining('未找到'), findsNothing);
    });

    testWidgets('a search cut short says so, not that the floor is missing',
        (tester) async {
      final repository = await openPage2(tester);
      await tapLink(tester, '回 777楼 user777');
      expect(repository.lookups, [777]);
      expect(find.textContaining('查找超过 20 页'), findsOneWidget);
      expect(find.textContaining('未找到'), findsNothing);
      expect(find.textContaining('第 2 /'), findsWidgets);
    });

    testWidgets('a favorite changed during a lookup survives its page',
        (tester) async {
      final repository = await pumpThread(tester, '$_base?tid-7.html',
          textScale: 1, favorited: true);
      final slow = Completer<void>();
      repository.lookupGate = slow;
      await tapLink(tester, '回 70楼 user70', settle: false);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('已收藏'), -300,
          scrollable: scrollable);
      await tester.tap(find.text('已收藏'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.favoriteCalls, ['remove']);
      slow.complete();
      await tester.pumpAndSettle();
      expectOnScreen(floor('B70F'));
      // Let the notice go, then walk back to the opening post.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('上一页'));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(find.text('收藏'), -300,
          scrollable: scrollable);
      expect(find.text('已收藏'), findsNothing);
      expect(repository.favoriteCalls, ['remove']);
    });
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
  final lookups = <int>[];
  final favoriteCalls = <String>[];
  bool favorited = false;
  Completer<void>? lookupGate;
  static const _replyTo = {5: 70, 31: 28, 33: 999, 35: 32, 37: 777};

  // Stands in for the repository's verified search over the thread's pages.
  @override
  Future<ThreadDetail?> findThreadFloor(
    ForumThread current,
    int floor, {
    required List<ThreadDetail> loaded,
    bool Function()? isCurrent,
  }) async {
    lookups.add(floor);
    await lookupGate?.future;
    if (floor == 777) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '查找超过 20 页，请手动切换页面后重试');
    }
    if (floor > 90) return null;
    return fetchThreadDetail(current.copyWith(url: '$_base?tid-7.html'),
        page: (floor - 1) ~/ 30 + 1);
  }

  @override
  Future<FavoriteResult> removeFavorite(ThreadFavorite favorite) async {
    favoriteCalls.add('remove');
    return const FavoriteResult(
      success: true,
      message: 'fixture removed',
      state: ThreadFavoriteState.notFavorite,
    );
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    requested.add(thread.url);
    final linked = RegExp(r'-page-(\d+)').firstMatch(thread.url)?.group(1);
    if (page == 1 && linked != null) page = int.parse(linked);
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
      favorite: favorited
          ? const ThreadFavorite(
              tid: '7', verify: 'fixture', state: ThreadFavoriteState.favorite)
          : null,
      replies: [
        for (var floor = first + 1; floor <= first + 30; floor++)
          ThreadReply(
            author: 'user$floor',
            content: 'reply body $floor ' * 6,
            floor: 'B${floor}F',
            replyToFloor: _replyTo[floor],
            replyToAuthor:
                _replyTo[floor] == null ? null : 'user${_replyTo[floor]}',
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
  Future<void> recordThreadForScope(
    String scope,
    ForumThread thread, {
    DateTime? viewedAt,
  }) async {}
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
