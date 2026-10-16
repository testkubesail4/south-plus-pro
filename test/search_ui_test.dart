import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
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
    await tapVisible(tester, find.byTooltip('下一页'), settle: false);
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
    await tapVisible(tester, find.byTooltip('上一页'), settle: false);
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

    // Groups start closed; opening one shows its boards but selects nothing.
    expect(find.text('Fixture board'), findsNothing);
    await tester.tap(find.text('示例分区'));
    await tester.pumpAndSettle();
    expect(find.text('示例分区'), findsOneWidget);
    expect(find.text('Fixture board'), findsOneWidget);
    expect(find.textContaining('搜索整个'), findsNothing,
        reason: 'an unsearchable heading has no whole-group scope');

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

  Future<_Repo> pumpProfile(WidgetTester tester) => pump(
        tester,
        screen: (repo) =>
            UserProfileScreen(userUrl: _Repo.profile.url, repository: repo),
      );

  String usernameField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text;

  testWidgets('profile looks up the login name only when asked',
      (tester) async {
    final repo = await pumpProfile(tester);
    expect(repo.loginLookups, isEmpty);

    await tapVisible(tester, find.text('查看登录名'));
    expect(repo.loginLookups, ['1']);
    expect(find.text('登录名 fixture-login'), findsOneWidget);

    // The known name is reused; searching only prefills it.
    await tapVisible(tester, find.text('按人查找'));
    expect(repo.loginLookups, ['1']);
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(usernameField(tester), 'fixture-login');
    expect(repo.queries, isEmpty);
  });

  testWidgets(
      'a failed lookup neither navigates nor falls back to the nickname',
      (tester) async {
    final repo = await pumpProfile(tester);
    repo.loginError =
        const ForumRequestException(ForumRequestKind.rateLimited, 'raw');

    await tapVisible(tester, find.text('按人查找'));
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.textContaining('查询登录名失败'), findsOneWidget);
    expect(find.textContaining('登录名 '), findsNothing);

    // A later tap may retry.
    repo.loginError = null;
    await tapVisible(tester, find.text('按人查找'));
    expect(repo.loginLookups, ['1', '1']);
    expect(usernameField(tester), 'fixture-login');
  });

  testWidgets('one lookup at a time; a session change drops its result',
      (tester) async {
    final repo = await pumpProfile(tester);
    repo.loginGate = Completer();

    await tapVisible(tester, find.text('查看登录名'), settle: false);
    await tester.tap(find.text('按人查找'));
    await tester.pump();
    expect(repo.loginLookups, ['1']);
    expect(
      find.bySemanticsLabel(RegExp('正在查询登录名')),
      findsOneWidget,
    );

    repo.session.value++;
    repo.loginGate!.complete('stale-login');
    await tester.pumpAndSettle();
    expect(find.textContaining('stale-login'), findsNothing);
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.text('登录状态已变化'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('查看登录名'), findsOneWidget);
  });

  testWidgets('a session change hides loaded details at once; reload is fresh',
      (tester) async {
    final repo = await pump(
      tester,
      screen: (repo) => UserProfileScreen(
        userUrl: _Repo.profile.url,
        repository: repo,
        initialTab: UserProfileTab.favorites,
      ),
    );
    expect(find.text('Private favorite'), findsOneWidget);
    expect(repo.detailReloads, [false]);

    repo.session.value++;
    await tester.pump();
    expect(find.text('Private favorite'), findsNothing);
    expect(find.text('fixture-user'), findsNothing);
    expect(find.text('登录状态已变化'), findsOneWidget);
    expect(repo.detailReloads, [false], reason: 'no automatic request');

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repo.detailReloads, [false, true]);
    expect(find.text('Private favorite'), findsOneWidget);
  });

  for (final inFlight in [false, true]) {
    testWidgets(
        'a cached user revalidated as another drops the first login name '
        '(lookup in flight: $inFlight)', (tester) async {
      final repo = await pump(tester, screen: (repo) {
        repo
          ..cached = _Repo.profile
          ..overviewGate = Completer();
        return UserProfileScreen(userUrl: _Repo.profile.url, repository: repo);
      });
      if (inFlight) repo.loginGate = Completer();
      await tapVisible(tester, find.text('查看登录名'), settle: !inFlight);
      expect(repo.loginLookups, ['1']);

      repo.overviewGate!.complete(const UserProfile(
        uid: '2',
        name: 'fixture-other',
        url: 'https://fixture.invalid/u.php?uid-1.html',
      ));
      repo.loginGate?.complete('fixture-login');
      await tester.pumpAndSettle();
      expect(find.textContaining('fixture-login'), findsNothing);
      expect(find.textContaining('fixture-other'), findsWidgets);

      repo.loginGate = null;
      await tapVisible(tester, find.text('查看登录名'));
      expect(repo.loginLookups, ['1', '2']);
    });
  }

  testWidgets('a re-login under the same name clears the shown login name',
      (tester) async {
    final client = _LookupClient();
    final repo = _ProfileOnlyRepo(client);
    Future<void> relogin() async {
      await repo.clearSession();
      await repo.login(
          username: 'Fixture One', password: 'fixture', captcha: '1234');
    }

    await tester.runAsync(() => repo.login(
        username: 'Fixture One', password: 'fixture', captcha: '1234'));
    await pump(
      tester,
      screen: (_) =>
          UserProfileScreen(userUrl: _Repo.profile.url, repository: repo),
    );

    Future<void> reload() async {
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
    }

    await tapVisible(tester, find.text('查看登录名'));
    expect(find.text('登录名 fixture-login'), findsOneWidget);
    await tester.runAsync(relogin);
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture-login'), findsNothing);
    await reload();

    // A lookup answered after the session changed is never shown.
    client.lookupGate = Completer();
    await tapVisible(tester, find.text('查看登录名'), settle: false);
    await tester.runAsync(relogin);
    client.lookupGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture-login'), findsNothing);
    await reload();
    expect(find.text('查看登录名'), findsOneWidget);
    expect(client.lookups, 2);
  });

  testWidgets('a missing user differs from a search without matches',
      (tester) async {
    final repo = await pump(
      tester,
      screen: (repo) =>
          SearchScreen(repository: repo, initialUsername: 'nobody'),
    );
    await tapVisible(tester, _submit, settle: false);
    repo.pending.last.completeError(
      const ForumRequestException(ForumRequestKind.invalidInput, 'raw'),
    );
    await tester.pumpAndSettle();
    expect(find.text('用户不存在'), findsOneWidget);
    expect(find.text('重试'), findsNothing);

    await tapVisible(tester, _submit, settle: false);
    repo.pending.last.complete(const ForumSearchPage(threads: [], total: 0));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关主题'), findsOneWidget);
    expect(find.text('用户不存在'), findsNothing);
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

  group('board hierarchy', () {
    // Synthetic form options: a searchable category, repeated child names
    // under different parents, a locked board and a form-only board.
    const options = [
      ForumSearchBoard(id: 'all', name: '全部版块'),
      ForumSearchBoard(id: '39', name: '>> Fixture zone'),
      ForumSearchBoard(id: '229', name: '|- Event A', depth: 1),
      ForumSearchBoard(id: '230', name: '|- Doujin', depth: 1),
      ForumSearchBoard(id: '226', name: '|- Event B', depth: 1),
      ForumSearchBoard(id: '227', name: '|- Doujin', depth: 1),
      ForumSearchBoard(
          id: '50', name: '|- Locked', depth: 1, selectable: false),
      ForumSearchBoard(id: '51', name: '|- Form only', depth: 1),
    ];
    ForumBoard board(String fid, String name,
            [List<ForumBoard> children = const []]) =>
        ForumBoard(
          name: name,
          url: 'https://south-plus.net/thread.php?fid-$fid.html',
          section: 'Fixture zone',
          children: children,
        );
    final sections = [
      ForumSection(title: 'Fixture zone', items: [
        board('229', 'Event A', [board('230', 'Doujin')]),
        board('226', 'Event B', [board('227', 'Doujin')]),
      ]),
    ];

    Future<_Repo> openPicker(
      WidgetTester tester, {
      ForumSearchBoard? initialBoard,
      Completer<List<ForumSection>>? sectionsGate,
    }) async {
      final repo = await pump(tester, screen: (repo) {
        repo
          ..boards = options
          ..sections = sections
          ..sectionsGate = sectionsGate;
        return SearchScreen(repository: repo, initialBoard: initialBoard);
      });
      await tapVisible(tester, find.text('筛选条件'));
      await tester.ensureVisible(find.text('版块'));
      await tester.tap(find.text('版块'));
      if (sectionsGate == null) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }
      return repo;
    }

    Future<void> search(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, 'kw');
      await tester.pumpAndSettle();
      await tapVisible(tester, _submit, settle: false);
    }

    testWidgets('opening a group differs from searching all of it',
        (tester) async {
      final repo = await openPicker(tester);
      expect(find.text('Event A'), findsNothing, reason: 'starts collapsed');

      await tester.tap(find.text('Fixture zone'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'not chosen');
      expect(find.text('Event A'), findsOneWidget);
      expect(find.text('Doujin'), findsNothing, reason: 'nested closed');
      expect(find.text('Form only'), findsOneWidget);
      expect(
        tester.widget<ListTile>(find.ancestor(
            of: find.text('Locked'), matching: find.byType(ListTile))),
        isA<ListTile>().having((tile) => tile.enabled, 'enabled', false),
      );

      await tester.tap(find.text('搜索整个Fixture zone'));
      await tester.pumpAndSettle();
      expect(find.text('Fixture zone'), findsOneWidget, reason: 'summary');
      await search(tester);
      expect(repo.queries.single.boardId, '39');
      expect(repo.sectionRequests, 1);
    });

    testWidgets('a chosen nested board reopens with its parents expanded',
        (tester) async {
      final repo = await openPicker(
        tester,
        initialBoard: const ForumSearchBoard(id: '227', name: 'Doujin'),
      );
      // Only the chosen board's branch is open.
      final doujin = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Doujin'));
      expect(find.text('Event B'), findsOneWidget);
      expect(doujin, findsOneWidget);
      expect(
        tester.widget<ListTile>(
            find.ancestor(of: doujin, matching: find.byType(ListTile))),
        isA<ListTile>().having((tile) => tile.selected, 'selected', true),
      );

      // Repeated names stay apart when filtered.
      await tester.enterText(find.byType(TextField).last, 'doujin');
      await tester.pumpAndSettle();
      expect(find.text('Fixture zone › Event A'), findsOneWidget);
      expect(find.text('Fixture zone › Event B'), findsOneWidget);
      await tester.tap(find.text('Fixture zone › Event A'));
      await tester.pumpAndSettle();
      await search(tester);
      expect(repo.queries.single.boardId, '230');
    });

    testWidgets('scopes are usable before and without the hierarchy',
        (tester) async {
      final gate = Completer<List<ForumSection>>();
      final repo = await openPicker(tester, sectionsGate: gate);
      expect(find.text('正在加载版块层级…'), findsOneWidget);

      gate.completeError(
          const ForumRequestException(ForumRequestKind.network, 'raw'));
      await tester.pumpAndSettle();
      expect(find.text('未能加载版块层级，按平铺列表显示'), findsOneWidget);
      await tester.tap(find.text('Fixture zone'));
      await tester.pumpAndSettle();
      expect(find.text('Doujin'), findsNWidgets(2), reason: 'flat form list');

      // A retry nests the same scopes.
      repo.sectionsGate = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repo.sectionRequests, 2);
      expect(find.text('Doujin'), findsNothing);
      await tester.tap(find.text('Event B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doujin'));
      await tester.pumpAndSettle();
      await search(tester);
      expect(repo.queries.single.boardId, '227');
    });
  });

  testWidgets('results by a blocked author are hidden, live', (tester) async {
    final repo = await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    repo.pending.last.complete(ForumSearchPage(threads: [
      _thread(1),
      _thread(2).copyWith(
          authorUrl: 'https://south-plus.net/u.php?action-show-uid-1002.html'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsOneWidget);

    repo.blocking.notifier.value = const BlockingRules(users: [
      BlockedUser(
          uid: '1002', name: 'B', userBlocked: true, avatarBlocked: false),
    ]);
    await tester.pump();
    expect(find.text('Result 1'), findsOneWidget);
    expect(find.text('Result 2'), findsNothing);
  });

  testWidgets('results never outlive the session that fetched them',
      (tester) async {
    final repo = await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    repo.pending.last.complete(ForumSearchPage(threads: [_thread(1)]));
    await tester.pumpAndSettle();
    expect(find.text('Result 1'), findsOneWidget);

    repo.session.value++;
    await tester.pump();
    expect(find.text('Result 1'), findsNothing, reason: 'settled result');
    expect(find.text('登录状态已变化'), findsOneWidget);
    expect(_submit, findsOneWidget);

    await tapVisible(tester, _submit, settle: false);
    repo.session.value++;
    repo.pending.last.complete(ForumSearchPage(threads: [_thread(2)]));
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsNothing, reason: 'pending result');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a result is dropped when the account or repository changed',
      (tester) async {
    final current = ValueNotifier<_Repo?>(null);
    final repo = await pump(
      tester,
      screen: (repo) => ValueListenableBuilder<_Repo?>(
        valueListenable: current,
        builder: (_, other, __) => SearchScreen(repository: other ?? repo),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();

    // The account changes before any session notification.
    await tapVisible(tester, _submit, settle: false);
    repo.account = 'fixture-account-b';
    repo.pending.last.complete(ForumSearchPage(threads: [_thread(1)]));
    await tester.pumpAndSettle();
    expect(find.text('Result 1'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The same screen is given another repository mid-request.
    await tapVisible(tester, _submit, settle: false);
    final other = _Repo()..account = 'fixture-account-b';
    current.value = other;
    await tester.pump();
    repo.pending.last.complete(ForumSearchPage(threads: [_thread(2)]));
    await tester.pumpAndSettle();
    expect(find.text('Result 2'), findsNothing);

    // Only the new repository's session now clears results.
    await tapVisible(tester, _submit, settle: false);
    other.pending.last.complete(ForumSearchPage(threads: [_thread(3)]));
    await tester.pumpAndSettle();
    expect(find.text('Result 3'), findsOneWidget);
    repo.session.value++;
    await tester.pump();
    expect(find.text('Result 3'), findsOneWidget);
    other.session.value++;
    await tester.pump();
    expect(find.text('Result 3'), findsNothing);

    // An open picker goes stale when the repository is replaced.
    await tapVisible(tester, find.text('筛选条件'));
    await tapVisible(tester, find.text('版块'));
    expect(find.text('示例分区'), findsOneWidget);
    current.value = repo;
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('登录状态已变化'),
      ),
      findsOneWidget,
    );
    expect(find.text('示例分区'), findsNothing);
  });

  testWidgets('an empty hierarchy is asked for again on retry', (tester) async {
    final repo = await pump(tester, screen: (repo) {
      repo.boards = const [
        ForumSearchBoard(id: 'all', name: '全部版块'),
        ForumSearchBoard(id: '39', name: '>> Zone'),
        ForumSearchBoard(id: '1', name: '|- Parent', depth: 1),
        ForumSearchBoard(id: '2', name: '|- Child', depth: 1),
      ];
      return SearchScreen(repository: repo);
    });
    await tapVisible(tester, find.text('筛选条件'));
    await tapVisible(tester, find.text('版块'));
    expect(find.text('未能加载版块层级，按平铺列表显示'), findsOneWidget);

    repo.sections = [
      ForumSection(title: 'Zone', items: [
        ForumBoard(
          name: 'Parent',
          url: 'https://south-plus.net/thread.php?fid-1.html',
          section: 'Zone',
          children: [
            ForumBoard(
              name: 'Child',
              url: 'https://south-plus.net/thread.php?fid-2.html',
              section: 'Zone',
            ),
          ],
        ),
      ]),
    ];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repo.sectionRequests, 2);
    await tester.tap(find.text('Zone'));
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsNothing, reason: 'nested under Parent');
    await tester.tap(find.text('Parent'));
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsOneWidget);
  });

  testWidgets('an open picker never applies another session\'s choices',
      (tester) async {
    final repo = await pump(tester);
    await tapVisible(tester, find.text('筛选条件'));
    await tapVisible(tester, find.text('版块'));
    await tester.enterText(find.byType(TextField).last, 'unusually');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('存为捷径'));
    await tester.pumpAndSettle();

    // Same name, new session, while the pin dialog is open.
    repo.session.value++;
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Mine');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('登录状态已变化'), findsOneWidget);
    expect((await ForumSearchPreferences.load()).pinnedBoards, isEmpty);
    expect(find.textContaining('unusually'), findsNothing);

    // Reopening loads the new session's list and works.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('全部版块'), findsOneWidget, reason: 'unchanged');
    await tapVisible(tester, find.text('版块'));
    expect(repo.boardRequests, 2);
    await tester.tap(find.text('示例分区'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('unusually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'kw');
    await tester.pumpAndSettle();
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, '11');
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
      // The folded filter summary names the board.
      find.textContaining(
          'An unusually long fictional board name that must wrap nicely'),
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
    expect(find.textContaining('版块 404'), findsOneWidget);
  });

  testWidgets('field help shows only for the focused field', (tester) async {
    await pump(tester);
    const keywordHelp = '多个关键词用空格或 | 分隔';
    const usernameHelp = '填写登录名（非显示昵称），可用 * 通配，例如 abc*';
    expect(find.text(keywordHelp), findsOneWidget);
    expect(find.text(usernameHelp), findsNothing);

    await tester.tap(find.byType(TextField).at(1));
    await tester.pumpAndSettle();
    expect(find.text(keywordHelp), findsNothing);
    expect(find.text(usernameHelp), findsOneWidget);
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
    expect(find.textContaining('Fixture board'), findsOneWidget);

    await tapVisible(tester, find.text('重置筛选'));
    expect(find.text('重置筛选'), findsNothing);
    await tapVisible(tester, _submit, settle: false);
    expect(repo.queries.single.boardId, 'all');
    expect(repo.queries.single.username, 'fixture-user');
  });
}

// Real session and lookup code; only the profile page is canned.
class _ProfileOnlyRepo extends ForumRepository {
  _ProfileOnlyRepo(ForumClient client) : super(client: client);

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async =>
      _Repo.profile;

  @override
  Future<UserProfile> fetchUserProfileDetails(
    UserProfile overview, {
    bool forceReload = false,
  }) async =>
      overview;
}

class _LookupClient extends ForumClient {
  String? username;
  bool loggedIn = false;
  int lookups = 0;
  Completer<void>? lookupGate;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<void> restoreCookies() async {}

  @override
  Future<void> clearSession() async {
    loggedIn = false;
    username = null;
  }

  @override
  Future<String> get(String path) async =>
      username == null ? '' : '<a href="u.php">$username</a>';

  @override
  Future<String> getOnce(String path) async {
    expect(path, 'sendemail.php?uid-1.html');
    lookups++;
    await lookupGate?.future;
    return '<form><input name="sendtoname" value="fixture-login"></form>';
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    username = form['pwuser'];
    loggedIn = true;
    return '<a href="u.php">$username</a>';
  }
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
    ForumBoardFilter? filter,
  }) =>
      Completer<ForumThreadPage>().future;

  UserProfile? cached;
  Completer<UserProfile>? overviewGate;

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => cached;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async {
    if (overviewGate case final gate?) return gate.future;
    return profile;
  }

  @override
  Future<UserProfile> fetchUserProfileDetails(
    UserProfile overview, {
    bool forceReload = false,
  }) async {
    detailReloads.add(forceReload);
    return overview.copyWith(favorites: const [
      UserListItem(title: 'Private favorite', url: 'read.php?tid-9.html'),
    ]);
  }

  final detailReloads = <bool>[];

  String? account;

  @override
  String? get currentUsername => account;

  final session = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get sessionEpoch => session;

  final loginLookups = <String>[];
  Completer<String>? loginGate;
  Object? loginError;

  @override
  Future<String> fetchLoginUsername(String numericUid) async {
    loginLookups.add(numericUid);
    if (loginGate case final gate?) return gate.future;
    if (loginError case final error?) throw error;
    return 'fixture-login';
  }

  final pending = <Completer<ForumSearchPage>>[];
  final queries = <ForumSearchQuery>[];
  final pagePaths = <String>[];
  int boardRequests = 0;

  Completer<List<ForumSearchBoard>>? boardGate;

  List<ForumSearchBoard> boards = _boards;

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async {
    boardRequests++;
    return boardGate?.future ??
        (account == 'fixture-account-a'
            ? [...boards, const ForumSearchBoard(id: '77', name: 'Only for A')]
            : boards);
  }

  List<ForumSection> sections = const [];
  Completer<List<ForumSection>>? sectionsGate;
  int sectionRequests = 0;

  @override
  Future<List<ForumSection>> fetchForumSections() async {
    sectionRequests++;
    if (sectionsGate case final gate?) return gate.future;
    return sections;
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
