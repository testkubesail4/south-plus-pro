import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic boards and topics only.
const _board = ForumCategory(
  name: 'Fixture board',
  slug: 'fid-901',
  url: 'https://south-plus.net/thread.php?fid-901.html',
);

class _Repo extends ForumRepository {
  final requests = <(int, ForumThreadOrder)>[];
  final gates = <int, Completer<void>>{};
  final failing = <int>{};
  var totalPages = 3;

  /// What the site reports as the page count when it answers a page.
  final totalFor = <int, int>{};

  /// A page the site answers with another page, as (page, page count).
  final answerAs = <int, (int, int)>{};
  var wall = false;
  var subBoards = const <ForumBoard>[];
  var prefix = '';

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async {
    requests.add((page, order));
    // The session a request is sent in, as a client would carry it.
    final sentAs = prefix;
    await gates[page]?.future;
    if (failing.contains(page)) {
      throw const ForumRepositoryException('fixture failure');
    }
    final (shownPage, total) =
        answerAs[page] ?? (page, totalFor[page] ?? totalPages);
    return ForumThreadPage(
      threads: [
        // The same pinned topic heads every page.
        const ForumThread(
          title: 'Pinned notice',
          url: 'https://south-plus.net/read.php?tid-1.html',
          replies: 0,
          section: '',
          isSticky: true,
        ),
        for (var i = 0; i < 14; i++)
          ForumThread(
            title: '$sentAs${order.name} p$shownPage t$i',
            url:
                'https://south-plus.net/read.php?tid-${shownPage * 100 + i}.html',
            replies: i,
            section: '',
          ),
      ],
      currentPage: shownPage,
      totalPages: total,
      boardName: 'Fixture board',
      hasPictureWall: wall,
      subBoards: page == 1 ? subBoards : const [],
    );
  }
}

/// A repository whose signed-in account the test switches.
class _SessionRepo extends _Repo {
  final owner = ValueNotifier<String?>('fixture-a');
  final epoch = ValueNotifier<int>(0);

  @override
  ValueListenable<String?> get sessionUser => owner;

  @override
  ValueListenable<int> get sessionEpoch => epoch;
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: BoardThreadListScreen(category: _board, repository: repo),
  ));
  await tester.pumpAndSettle();
}

/// Frames for what is already due. A held request leaves a spinner running
/// that never settles, so this never waits for quiet.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _toBottom(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
  await _frames(tester);
}

List<int> _pages(_Repo repo) => [for (final r in repo.requests) r.$1];

/// How many times [text] sits in the whole list. The list builds only what is
/// near the viewport, so this walks it from the top; call it once every page
/// of interest is in. The walk is bounded: a list that keeps growing under it
/// fails the test instead of hanging it.
Future<int> _count(WidgetTester tester, String text) async {
  final position = tester
      .state<ScrollableState>(find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first)
      .position;
  final places = <int>{};
  position.jumpTo(0);
  await tester.pump();
  // The fixtures are a few thousand pixels long; 100 steps of 300 is ample.
  var atEnd = false;
  for (var step = 0; step < 100 && !atEnd; step++) {
    final finder = find.text(text);
    for (var i = 0; i < finder.evaluate().length; i++) {
      places
          .add((tester.getTopLeft(finder.at(i)).dy + position.pixels).round());
    }
    atEnd = position.pixels >= position.maxScrollExtent;
    if (!atEnd) {
      position
          .jumpTo(math.min(position.pixels + 300, position.maxScrollExtent));
      await tester.pump();
    }
  }
  expect(atEnd, isTrue, reason: 'the walk reached the end of the list');
  await tester.pumpAndSettle();
  return places.length;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
  });

  testWidgets('scrolling to the end appends the next pages in order, once',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    expect(_pages(repo), [1], reason: 'nothing loads before the user scrolls');

    await _toBottom(tester);
    expect(_pages(repo), [1, 2]);
    expect(find.text('第 2 页'), findsOneWidget);

    await _toBottom(tester);
    expect(_pages(repo), [1, 2, 3]);

    // The last page's footer and the pager sit below what was just loaded.
    await _toBottom(tester);
    expect(find.text('已到最后一页'), findsOneWidget);
    expect(_pages(repo), [1, 2, 3], reason: 'no request past the last page');
    expect(find.text('第 3 / 3 页'), findsOneWidget);

    expect(await _count(tester, 'Pinned notice'), 1,
        reason: 'a topic repeated on every page is listed once');
    expect(await _count(tester, 'lastPost p1 t0'), 1);
    expect(await _count(tester, 'lastPost p2 t13'), 1);
    expect(_pages(repo), [1, 2, 3]);
  });

  testWidgets('a board that grows while reading keeps loading its new pages',
      (tester) async {
    final repo = _Repo()..totalFor.addAll({1: 2, 2: 3, 3: 3});
    await _pump(tester, repo);
    await _toBottom(tester);
    expect(_pages(repo), [1, 2]);
    expect(find.text('已到最后一页'), findsNothing,
        reason: 'page 2 reported a third page');
    await _toBottom(tester);
    expect(_pages(repo), [1, 2, 3]);
    await _toBottom(tester);
    expect(find.text('已到最后一页'), findsOneWidget);
    expect(find.text('第 3 / 3 页'), findsOneWidget);
  });

  testWidgets('a board that shrinks while reading ends cleanly, not in error',
      (tester) async {
    // Page 3 no longer exists: the site answers with page 2 of 2.
    final repo = _Repo()..answerAs[3] = (2, 2);
    await _pump(tester, repo);
    await _toBottom(tester);
    await _toBottom(tester);
    expect(_pages(repo), [1, 2, 3]);
    expect(find.textContaining('页加载失败'), findsNothing);
    expect(find.text('已到最后一页'), findsOneWidget);
    expect(find.text('第 2 / 2 页'), findsOneWidget);
    await _toBottom(tester);
    expect(_pages(repo), [1, 2, 3], reason: 'no request past the new end');
  });

  testWidgets('a failed page shows an inline retry and stops asking',
      (tester) async {
    final repo = _Repo()..failing.add(2);
    await _pump(tester, repo);
    await _toBottom(tester);
    expect(find.textContaining('页加载失败'), findsOneWidget);
    expect(await _count(tester, 'lastPost p1 t0'), 1,
        reason: 'the loaded page stays; no full-page error');
    await _toBottom(tester);
    expect(_pages(repo), [1, 2], reason: 'no retry loop while failed');

    repo.failing.clear();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(_pages(repo), [1, 2, 2]);
    expect(find.textContaining('页加载失败'), findsNothing);
    expect(await _count(tester, 'lastPost p2 t0'), 1);
  });

  testWidgets('an answer for a replaced list is dropped', (tester) async {
    final repo = _Repo();
    repo.gates[2] = Completer<void>();
    await _pump(tester, repo);
    await _toBottom(tester);
    expect(_pages(repo), [1, 2], reason: 'page 2 is in flight');

    // Page 2 is still held, so its spinner runs: only bounded frames here.
    await tester.tap(find.byKey(const ValueKey('board-order-button')));
    await _frames(tester);
    await tester.tap(find.text('人气'));
    await _frames(tester);
    expect(repo.requests.last, (1, ForumThreadOrder.hits));
    expect(find.text('hits p1 t0'), findsOneWidget);

    repo.gates[2]!.complete();
    await tester.pumpAndSettle();
    expect(
        find.textContaining('lastPost p2', skipOffstage: false), findsNothing);
    expect(find.text('第 2 页'), findsNothing);
  });

  testWidgets('a jump lands on its page and loads earlier pages on request',
      (tester) async {
    // Page 2 is held, so the pager at the end of page 1 still reads 1.
    final repo = _Repo()..gates[2] = Completer<void>();
    await _pump(tester, repo);
    expect(find.textContaining('加载第'), findsNothing);
    await _toBottom(tester);
    expect(_pages(repo), [1, 2], reason: 'page 2 is in flight');
    // The loading row made the list taller than the first drag saw; a second
    // drag brings the pager clear of the 发帖 button.
    await _toBottom(tester);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    expect(_pages(repo), [1, 2, 2], reason: 'the jump asks for page 2 again');
    // Both asks for page 2 are answered; only the jump's answer may apply.
    repo.gates[2]!.complete();
    await tester.pumpAndSettle();
    expect(find.text('lastPost p1 t0'), findsNothing,
        reason: 'a jump replaces the list');
    expect(find.text('lastPost p2 t0'), findsOneWidget);
    expect(find.text('加载第 1 页'), findsOneWidget);

    await tester.tap(find.text('加载第 1 页'));
    await tester.pumpAndSettle();
    expect(repo.requests.last.$1, 1);
    expect(find.textContaining('加载第'), findsNothing);
  });

  testWidgets('the picture wall appends and labels pages too', (tester) async {
    final repo = _Repo()..wall = true;
    await _pump(tester, repo);
    await tester.tap(find.byTooltip('图墙'));
    await tester.pumpAndSettle();
    await _toBottom(tester);
    // A wall is short, so it may already be near the end and ask for more.
    expect(_pages(repo).take(2), [1, 2]);
    expect(await _count(tester, '第 2 页'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('another account drops the loaded pages at once and restarts',
      (tester) async {
    final repo = _SessionRepo()..prefix = 'A ';
    await _pump(tester, repo);
    await _toBottom(tester);
    final asked = _pages(repo).length;
    expect(asked, greaterThan(1), reason: 'A has pages appended');

    repo
      ..prefix = 'B '
      ..gates[1] = Completer<void>();
    repo.owner.value = 'fixture-b';
    repo.epoch.value++;
    await tester.pump();
    expect(
        find.textContaining('A lastPost', skipOffstage: false), findsNothing);

    repo.gates[1]!.complete();
    await tester.pumpAndSettle();
    expect(_pages(repo).skip(asked), [1]);
    expect(find.text('B lastPost p1 t0'), findsOneWidget);
    expect(
        find.textContaining('A lastPost', skipOffstage: false), findsNothing);
  });

  testWidgets('a new session for the same account restarts once it settles',
      (tester) async {
    final repo = _SessionRepo()..prefix = 'A ';
    await _pump(tester, repo);
    await _toBottom(tester);
    final asked = _pages(repo).length;

    // The repository announces the new session before it moves its client.
    repo.epoch.value++;
    repo.prefix = 'B ';
    await tester.pump();
    expect(
        find.textContaining('A lastPost', skipOffstage: false), findsNothing);

    await tester.pumpAndSettle();
    expect(_pages(repo).skip(asked), [1]);
    expect(find.text('B lastPost p1 t0'), findsOneWidget);
    expect(
        find.textContaining('A lastPost', skipOffstage: false), findsNothing);
  });

  testWidgets('a single page never asks for more or claims an end',
      (tester) async {
    final repo = _Repo()..totalPages = 1;
    await _pump(tester, repo);
    await _toBottom(tester);
    expect(_pages(repo), [1]);
    expect(find.text('已到最后一页'), findsNothing);
  });

  testWidgets('the sub-board section folds and remembers it', (tester) async {
    final repo = _Repo()
      ..subBoards = [
        ForumBoard(
          name: 'Child board',
          url: 'https://south-plus.net/thread.php?fid-902.html',
          section: 'Fixture board',
        ),
      ];
    await _pump(tester, repo);
    // The toolbar sits below the sub-boards.
    final before = tester.getTopLeft(find.text('全部主题'));

    await tester.tap(find.text('子版块'));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('全部主题'));
    expect(after.dy, lessThan(before.dy), reason: 'the grid folded away');
    expect((await HomeReadingPreferences.load()).collapsedIds, {'board:901'});

    await tester.tap(find.text('子版块'));
    await tester.pumpAndSettle();
    expect((await HomeReadingPreferences.load()).collapsedIds, isEmpty);
  });

  testWidgets('switching forum origin while open never writes to the old one',
      (tester) async {
    ForumNetworkConfig origin(String host) => ForumNetworkConfig(
          site: ForumSite(host),
          mode: ForumNetworkMode.native,
          dohProvider: ForumNetworkConfig.defaultProvider,
        );
    final repo = _Repo()
      ..subBoards = [
        ForumBoard(
          name: 'Child board',
          url: 'https://south-plus.net/thread.php?fid-902.html',
          section: 'Fixture board',
        ),
      ];
    await repo.updateNetworkConfig(origin('a.example'));
    final scopeA = repo.localPreferenceAccount;
    await HomeReadingPreferences.setCollapsed('board:901', true,
        account: scopeA);
    await _pump(tester, repo);
    final folded = tester.getTopLeft(find.text('全部主题')).dy;

    await repo.updateNetworkConfig(origin('b.example'));
    await tester.pumpAndSettle();
    final scopeB = repo.localPreferenceAccount;
    expect(scopeB, isNot(scopeA));
    expect(tester.getTopLeft(find.text('全部主题')).dy, greaterThan(folded),
        reason: 'origin B has nothing folded, so the sub-boards show');

    await tester.tap(find.text('子版块'));
    await tester.pumpAndSettle();
    expect((await HomeReadingPreferences.load(account: scopeB)).collapsedIds,
        {'board:901'});
    expect((await HomeReadingPreferences.load(account: scopeA)).collapsedIds,
        {'board:901'},
        reason: 'origin A keeps its own fold untouched');
  });
}
