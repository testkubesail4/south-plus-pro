import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic boards, users and keywords only.
const _boards = [
  ForumSearchBoard(id: 'all', name: '全部版块'),
  ForumSearchBoard(id: '', name: '>> 示例分区', selectable: false),
  ForumSearchBoard(
    id: '11',
    name: 'An unusually long fictional board name that must wrap nicely',
    depth: 1,
  ),
  ForumSearchBoard(id: '12', name: 'Fixture board', depth: 1),
  ForumSearchBoard(id: '13', name: 'Fixture board', depth: 2),
];

ForumThread _thread(int i) => ForumThread(
      title: 'Result $i',
      url: 'read.php?tid-$i.html',
      replies: i,
      section: 'Fixture board',
    );

final _submit = find.byKey(const ValueKey('search-submit'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pump(
    WidgetTester tester, {
    double textScale = 1,
    Size size = const Size(360, 640),
    Widget Function(_Repo repo)? screen,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: screen?.call(repo) ?? SearchScreen(repository: repo),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  // Requests leave a spinner running, so settle only before tapping.
  Future<void> tapVisible(
    WidgetTester tester,
    Finder finder, {
    bool settle = true,
  }) async {
    if (finder.evaluate().isEmpty) {
      // Slivers past the viewport are not built until scrolled to.
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  for (final scale in [0.9, 1.0, 1.3, 2.3]) {
    testWidgets('every filter is reachable and unclipped at text scale $scale',
        (tester) async {
      final repo =
          await pump(tester, textScale: scale, size: const Size(320, 640));
      await tapVisible(tester, find.text('筛选条件'));
      expect(tester.takeException(), isNull);

      for (final label in ['部分匹配', '完全匹配', '版块', '时间范围', '人气', '升序', '只搜精华帖']) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(320), reason: label);
        expect(rect.top, greaterThanOrEqualTo(0), reason: label);
        expect(rect.bottom, lessThanOrEqualTo(640), reason: label);
        expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
      }

      await tapVisible(tester, find.text('时间范围'));
      await tester.tap(find.text('一周内'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('人气'));
      await tapVisible(tester, find.text('升序'));
      await tapVisible(tester, find.text('只搜精华帖'));
      await tapVisible(tester, find.text('完全匹配'));
      await tester.enterText(find.byType(TextField).first, 'alpha|beta');
      await tester.pumpAndSettle();
      await tapVisible(tester, _submit, settle: false);

      final query = repo.queries.single;
      expect(query.keyword, 'alpha|beta');
      expect(query.time, ForumSearchTime.week);
      expect(query.order, ForumThreadOrder.hits);
      expect(query.ascending, isTrue);
      expect(query.digest, isTrue);
      expect(query.match, ForumSearchMatch.exact);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'results fold the form, page from server links and keep the '
      'submitted query while the form is edited', (tester) async {
    final repo = await pump(tester);
    await tester.enterText(find.byType(TextField).at(1), 'fixture*');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    repo.pending.last.complete(ForumSearchPage(
      threads: [for (var i = 0; i < 12; i++) _thread(i)],
      total: 30,
      nextPagePath: 'search.php?step=2&page=2',
      pageLinks: const [
        ForumSearchPageLink(
            label: '3', path: 'search.php?step=2&page=3', page: 3),
      ],
    ));
    await tester.pumpAndSettle();

    expect(repo.queries.single.username, 'fixture*');
    expect(_submit, findsNothing);
    expect(find.text('用户：fixture*'), findsOneWidget);
    expect(find.text('Result 0'), findsOneWidget);
    expect(find.textContaining('共 30 条结果'), findsOneWidget);

    // Editing the form must not change what the next page fetches.
    await tapVisible(tester, find.text('修改'));
    await tapVisible(tester, find.text('筛选条件'));
    await tester.enterText(find.byType(TextField).at(1), 'other');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('下一页'), settle: false);
    expect(repo.pagePaths, ['search.php?step=2&page=2']);
    expect(repo.queries.last.username, 'fixture*');
    expect(find.text('Result 11'), findsOneWidget,
        reason: 'kept while loading');

    repo.pending.last.completeError(
      const ForumRequestException(ForumRequestKind.rateLimited, 'raw'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Result 11'), findsOneWidget,
        reason: 'kept after failure');
    await tapVisible(tester, find.text('重试'), settle: false);
    expect(repo.pagePaths, [
      'search.php?step=2&page=2',
      'search.php?step=2&page=2',
    ]);
    repo.pending.last.complete(ForumSearchPage(
      threads: [for (var i = 100; i < 112; i++) _thread(i)],
      currentPage: 2,
      previousPagePath: 'search.php?step=2&page=1',
    ));
    await tester.pumpAndSettle();
    // A new page starts at its own first result, even with the form open.
    expect(find.text('Result 100').hitTestable(), findsOneWidget);
    expect(find.textContaining('第 2 页').hitTestable(), findsOneWidget);
    await tapVisible(tester, find.text('上一页'), settle: false);
    expect(repo.pagePaths.last, 'search.php?step=2&page=1');
  });

  testWidgets('match and time defaults save separately and apply next time',
      (tester) async {
    await pump(tester);
    await tapVisible(tester, find.text('筛选条件'));
    expect(find.text('设为默认'), findsNothing);

    await tapVisible(tester, find.text('完全匹配'));
    await tapVisible(tester, find.text('时间范围'));
    await tester.tap(find.text('一个月内'));
    await tester.pumpAndSettle();
    expect(find.text('设为默认'), findsNWidgets(2));

    // Saving the time default must not save the unsaved match choice.
    await tapVisible(tester, find.text('设为默认').last);
    var prefs = await ForumSearchPreferences.load();
    expect(prefs.defaultTime, ForumSearchTime.month);
    expect(prefs.defaultMatch, ForumSearchMatch.partial);
    expect(find.text('设为默认'), findsOneWidget);

    await tapVisible(tester, find.text('设为默认'));
    prefs = await ForumSearchPreferences.load();
    expect(prefs.defaultMatch, ForumSearchMatch.exact);
    expect(find.text('设为默认'), findsNothing);

    final repo = await pump(tester,
        screen: (repo) => SearchScreen(
              key: UniqueKey(),
              repository: repo,
            ));
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.match, ForumSearchMatch.exact);
    expect(repo.queries.single.time, ForumSearchTime.month);
  });

  testWidgets('defaults follow the signed-in account', (tester) async {
    await ForumSearchPreferences.saveDefaultTime(
      ForumSearchTime.day,
      account: 'fixture-account-a',
    );
    final repo = _Repo()..account = 'fixture-account-a';
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(repository: repo),
    ));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('筛选条件'));
    expect(find.text('一天内'), findsOneWidget);

    // Same tab, another login: B's (anonymous-free) defaults apply.
    await tapVisible(tester, find.text('筛选条件'));
    repo.account = 'fixture-account-b';
    await tapVisible(tester, find.text('筛选条件'));
    expect(find.text('一年内'), findsOneWidget);
    expect(find.text('一天内'), findsNothing);
  });

  testWidgets('a quick search after a login switch uses the new defaults',
      (tester) async {
    await ForumSearchPreferences.saveDefaultTime(
      ForumSearchTime.day,
      account: 'fixture-account-a',
    );
    await ForumSearchPreferences.saveDefaultMatch(
      ForumSearchMatch.exact,
      account: 'fixture-account-a',
    );
    final repo = _Repo()..account = 'fixture-account-a';
    await tester.pumpWidget(MaterialApp(home: SearchScreen(repository: repo)));
    await tester.pumpAndSettle();
    repo.account = 'fixture-account-b';

    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    await tester.pump();
    expect(repo.queries.single.time, ForumSearchTime.year);
    expect(repo.queries.single.match, ForumSearchMatch.partial);
  });

  testWidgets('the board list is reloaded for a new login', (tester) async {
    final repo = _Repo()..account = 'fixture-account-a';
    await tester.pumpWidget(MaterialApp(home: SearchScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('筛选条件'));
    await tapVisible(tester, find.text('版块'));
    expect(find.text('Only for A'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    repo.account = 'fixture-account-b';
    await tapVisible(tester, find.text('版块'));
    expect(repo.boardRequests, 2);
    expect(find.text('Only for A'), findsNothing);
  });

  testWidgets('board picker: hierarchy, filter, custom shortcut, stale pin',
      (tester) async {
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '99', label: 'Gone board'),
    ]);
    final repo = await pump(tester);
    await tapVisible(tester, find.text('筛选条件'));
    await tapVisible(tester, find.text('版块'));

    expect(find.text('版块捷径'), findsOneWidget);
    expect(find.text('此版块已不存在，无法搜索'), findsOneWidget);
    await tester.tap(find.text('Gone board'));
    await tester.pumpAndSettle();
    expect(find.text('Gone board'), findsOneWidget,
        reason: 'stale pin not chosen');

    // Section headings are labels, not targets.
    await tester.tap(find.text('>> 示例分区'));
    await tester.pumpAndSettle();
    expect(find.text('>> 示例分区'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'unusually');
    await tester.pumpAndSettle();
    expect(find.text('Fixture board'), findsNothing);
    await tester.tap(find.byTooltip('存为捷径'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Mine');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      (await ForumSearchPreferences.load()).pinnedBoards.map((b) => b.label),
      ['Gone board', 'Mine'],
    );

    await tester.enterText(find.byType(TextField).last, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    expect(find.text('Mine'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, '11');
    expect(repo.boardRequests, 1);
  });

  testWidgets('board header opens a search scoped to that board',
      (tester) async {
    final repo = await pump(
      tester,
      screen: (repo) => BoardThreadListScreen(
        category: const ForumCategory(name: 'Fixture board', slug: 'f12'),
        repository: repo,
      ),
    );
    await tester.tap(find.byTooltip('在本版搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(repo.queries, isEmpty);
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, '12');
  });

  testWidgets('profile opens a username search without submitting it',
      (tester) async {
    final repo = await pump(
      tester,
      screen: (repo) =>
          UserProfileScreen(userUrl: _Repo.profile.url, repository: repo),
    );
    await tapVisible(tester, find.text('搜索主题'));
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('fixture-user'), findsWidgets);
    expect(repo.queries, isEmpty);
  });

  testWidgets('pins stay unselectable until the board list proves them',
      (tester) async {
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '12', label: 'Pinned'),
    ]);
    final repo = await pump(tester);
    repo.boardGate = Completer();
    await tapVisible(tester, find.text('筛选条件'));
    await tester.pump();
    await tester.ensureVisible(find.text('版块'));
    await tester.tap(find.text('版块'));
    await tester.pump(const Duration(milliseconds: 500));
    // Pinned shortcuts load from real async preferences.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('版块列表加载后可选'), findsOneWidget);
    await tester.tap(find.text('Pinned'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('版块列表加载后可选'), findsOneWidget, reason: 'sheet stays');

    repo.boardGate!.completeError(
      const ForumRequestException(ForumRequestKind.network, 'raw'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('版块列表加载失败'), findsOneWidget);
    expect(find.text('版块列表加载后可选'), findsOneWidget);

    repo.boardGate = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('版块列表加载后可选'), findsNothing);
    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, '12');
  });

  testWidgets('a board known only by id shows its id, then its name',
      (tester) async {
    final repo = await pump(
      tester,
      screen: (repo) => SearchScreen(
        repository: repo,
        initialKeyword: 'kw',
        initialBoard: const ForumSearchBoard(id: '11', name: ''),
      ),
    );
    // The board list loads once to name the board; nothing is searched.
    expect(repo.boardRequests, 1);
    expect(repo.queries, isEmpty);
    expect(
      find.text('An unusually long fictional board name that must wrap nicely'),
      findsOneWidget,
    );
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, '11');
  });

  testWidgets('an id-only board missing from the list keeps its id label',
      (tester) async {
    await pump(
      tester,
      screen: (repo) => SearchScreen(
        repository: repo,
        initialBoard: const ForumSearchBoard(id: '404', name: ''),
      ),
    );
    expect(find.text('版块 404'), findsOneWidget);
  });

  testWidgets('prefill from context does not submit; reset restores defaults',
      (tester) async {
    final repo = await pump(
      tester,
      screen: (repo) => SearchScreen(
        repository: repo,
        initialUsername: 'fixture-user',
        initialBoard: const ForumSearchBoard(id: '12', name: 'Fixture board'),
      ),
    );
    expect(repo.queries, isEmpty);
    expect(find.text('fixture-user'), findsOneWidget);
    expect(find.text('Fixture board'), findsOneWidget);

    await tapVisible(tester, find.text('重置筛选'));
    expect(find.text('重置筛选'), findsNothing);
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, 'all');
    expect(repo.queries.single.username, 'fixture-user');
  });
}

class _Repo extends ForumRepository {
  static const profile = UserProfile(
    uid: '1',
    name: 'fixture-user',
    url: 'https://fixture.invalid/u.php?uid-1.html',
  );

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
  }) =>
      Completer<ForumThreadPage>().future;

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => profile;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) async =>
      overview;

  String? account;

  @override
  String? get currentUsername => account;

  final pending = <Completer<ForumSearchPage>>[];
  final queries = <ForumSearchQuery>[];
  final pagePaths = <String>[];
  int boardRequests = 0;

  Completer<List<ForumSearchBoard>>? boardGate;

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async {
    boardRequests++;
    return boardGate?.future ??
        (account == 'fixture-account-a'
            ? [..._boards, const ForumSearchBoard(id: '77', name: 'Only for A')]
            : _boards);
  }

  @override
  Future<ForumSearchPage> searchForum(ForumSearchQuery query) {
    queries.add(query);
    pending.add(Completer());
    return pending.last.future;
  }

  @override
  Future<ForumSearchPage> searchForumPage(
    ForumSearchQuery query,
    String pagePath,
  ) {
    queries.add(query);
    pagePaths.add(pagePath);
    pending.add(Completer());
    return pending.last.future;
  }
}
