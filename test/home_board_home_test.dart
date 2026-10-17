import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';

// Synthetic boards and titles only.
const _account = 'fixture_login';
const _firstSection = 'Boards with a rather long section title';

ForumThread _thread(String title) => ForumThread(
    title: title, url: 'read.php?tid-1.html', replies: 0, section: '');

class _Repo extends ForumRepository {
  var loggedIn = true;

  /// False lets the real session and origin decide the storage scope.
  var fixedAccount = true;
  Future<ForumTaskSnapshot?> Function()? cachedTasks;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  String? get currentUsername =>
      fixedAccount ? _account : super.currentUsername;

  @override
  String? get localPreferenceAccount =>
      fixedAccount ? _account : super.localPreferenceAccount;

  @override
  final accountIdentity = ValueNotifier(const ForumAccountIdentity(
      systemName: _account, nickname: 'Fixture user'));

  @override
  Future<ForumHomeSnapshot> fetchHome() async => ForumHomeSnapshot(
        latest: [_thread('Latest 1')],
        quickLists: [
          ForumQuickList(title: '最新讨论', threads: [
            for (var i = 1; i <= 8; i++) _thread('Latest $i'),
          ]),
        ],
        hot: const [ForumCategory(name: 'Hot board', slug: 'fid-7')],
        sections: [
          ForumSection(title: _firstSection, items: [
            for (var i = 2; i <= 3; i++)
              ForumBoard(
                name: 'Board $i',
                url: 'https://south-plus.net/thread.php?fid-4$i.html',
                section: 'Boards',
              ),
          ]),
          const ForumSection(title: 'More', items: [
            ForumBoard(
              name: 'Board 5',
              url: 'https://south-plus.net/thread.php?fid-45.html',
              section: 'More',
            ),
          ]),
        ],
      );

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async =>
      cachedTasks == null ? null : cachedTasks!();

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pump(
    WidgetTester tester, {
    bool guest = false,
    double textScale = 1,
    _Repo? repo,
  }) async {
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo ??= _Repo();
    repo.loggedIn = !guest;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeShell(key: UniqueKey(), repository: repo),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  // 速览 rows are 48 high at 1x, split by 1px hairlines.
  double rowsHeight(int rows) => rows * 48.0 + rows - 1;
  // The list area is the nearest tall fixed-height box around its rows.
  double listHeight(WidgetTester tester) => tester
      .getSize(find
          .ancestor(
            of: find.text('Latest 1'),
            matching: find.byWidgetPredicate(
                (w) => w is SizedBox && (w.height ?? 0) > 100),
          )
          .first)
      .height;

  group('速览 row count', () {
    testWidgets('a saved count sets how many rows show and the list height',
        (tester) async {
      await HomeReadingPreferences.saveQuickRowCount(3, account: _account);
      await pump(tester);
      expect(find.text('Latest 3'), findsOneWidget);
      expect(find.text('Latest 4'), findsNothing);
      expect(listHeight(tester), rowsHeight(3));
    });

    testWidgets('the 显示行数 sheet changes it at once and keeps it',
        (tester) async {
      await pump(tester);
      expect(find.text('Latest 8'), findsOneWidget, reason: 'default is 8');
      expect(listHeight(tester), rowsHeight(8));

      await tester.tap(find.byTooltip('显示行数'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '5'));
      await tester.pumpAndSettle();
      expect(find.text('Latest 5'), findsOneWidget);
      expect(find.text('Latest 6'), findsNothing);
      expect(listHeight(tester), rowsHeight(5));
      expect(
        (await HomeReadingPreferences.load(account: _account)).quickRowCount,
        5,
      );
    });

    testWidgets('large text keeps the rows within bounds', (tester) async {
      await HomeReadingPreferences.saveQuickRowCount(3, account: _account);
      await pump(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Latest 3'), findsOneWidget);
      expect(find.text('Latest 4'), findsNothing);
    });
  });

  group('section folds', () {
    testWidgets('a section folds, stays folded on reopening, and unfolds',
        (tester) async {
      await pump(tester);
      final key = find.byKey(const ValueKey('home-section-1'));
      final open = tester.getTopLeft(key).dy;

      await tester.tap(find.text(_firstSection));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(key).dy, lessThan(open - 40),
          reason: 'the boards folded away');
      expect(
        (await HomeReadingPreferences.load(account: _account)).collapsedIds,
        {'section:$_firstSection'},
      );

      await pump(tester);
      expect(tester.getTopLeft(key).dy, lessThan(open - 40),
          reason: 'remembered after reopening');

      await tester.tap(find.text(_firstSection));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(key).dy, open);
      expect(
        (await HomeReadingPreferences.load(account: _account)).collapsedIds,
        isEmpty,
      );
    });

    testWidgets('a folded section hides its boards from taps and readers',
        (tester) async {
      await HomeReadingPreferences.setCollapsed('section:$_firstSection', true,
          account: _account);
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(find.text('Board 2').hitTestable(), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Board 2')), findsNothing);
      expect(find.text('Board 5').hitTestable(), findsOneWidget,
          reason: 'other sections stay open');
      semantics.dispose();
    });
  });

  testWidgets("a guest switching forum origin gets that origin's own folds",
      (tester) async {
    ForumNetworkConfig origin(String host) => ForumNetworkConfig(
          site: ForumSite(host),
          dohEnabled: false,
          dohProvider: ForumNetworkConfig.defaultProvider,
        );
    final repo = _Repo()..fixedAccount = false;
    await repo.updateNetworkConfig(origin('a.example'));
    final scopeA = repo.localPreferenceAccount;
    await pump(tester, guest: true, repo: repo);
    final key = find.byKey(const ValueKey('home-section-1'));
    final open = tester.getTopLeft(key).dy;

    await tester.tap(find.text(_firstSection));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(key).dy, lessThan(open - 40));

    // Same shell, same (null) user: only the origin changes.
    await repo.updateNetworkConfig(origin('b.example'));
    await tester.pumpAndSettle();
    final scopeB = repo.localPreferenceAccount;
    expect(scopeB, isNot(scopeA));
    expect(tester.getTopLeft(key).dy, open,
        reason: 'origin B starts with nothing folded');
    expect((await HomeReadingPreferences.load(account: scopeA)).collapsedIds,
        {'section:$_firstSection'});
    expect((await HomeReadingPreferences.load(account: scopeB)).collapsedIds,
        isEmpty);

    await tester.tap(find.text(_firstSection));
    await tester.pumpAndSettle();
    expect((await HomeReadingPreferences.load(account: scopeA)).collapsedIds,
        {'section:$_firstSection'},
        reason: 'a fold made under B is not written to A');
    expect((await HomeReadingPreferences.load(account: scopeB)).collapsedIds,
        {'section:$_firstSection'});
  });

  testWidgets(
      'an open edit sheet closes without writing when the scope '
      'changes', (tester) async {
    ForumNetworkConfig origin(String host) => ForumNetworkConfig(
          site: ForumSite(host),
          dohEnabled: false,
          dohProvider: ForumNetworkConfig.defaultProvider,
        );
    final repo = _Repo()..fixedAccount = false;
    await repo.updateNetworkConfig(origin('a.example'));
    final scopeA = repo.localPreferenceAccount;
    await ForumSearchPreferences.savePinnedBoards(
      const [ForumSearchPinnedBoard(id: '42', label: 'Pinned board')],
      account: scopeA,
    );
    final semantics = tester.ensureSemantics();
    await pump(tester, repo: repo);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑常用版块'), findsOneWidget);

    await repo.updateNetworkConfig(origin('b.example'));
    // One frame in, the sheet may still be animating out, but empty.
    await tester.pump();
    expect(find.text('Pinned board'), findsNothing,
        reason: "origin A's pins never show under origin B");
    expect(find.byTooltip('移除 Pinned board'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Pinned board')), findsNothing);
    expect(find.text('编辑常用版块'), findsNothing);
    await tester.pumpAndSettle();
    semantics.dispose();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      [
        for (final pin in (await ForumSearchPreferences.load(account: scopeA))
            .pinnedBoards)
          pin.id,
      ],
      ['42'],
    );
    expect(
      (await ForumSearchPreferences.load(account: repo.localPreferenceAccount))
          .pinnedBoards,
      isEmpty,
    );
  });

  group('board shortcuts', () {
    testWidgets('hot boards stay; 我的版块 shows the pins beneath them',
        (tester) async {
      await ForumSearchPreferences.savePinnedBoards(
        const [ForumSearchPinnedBoard(id: '42', label: 'Pinned board')],
        account: _account,
      );
      await pump(tester);
      expect(find.text('热门版块'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Hot board'), findsOneWidget);
      expect(find.text('我的版块'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Pinned board'), findsOneWidget);
      expect(tester.getTopLeft(find.text('我的版块')).dy,
          greaterThan(tester.getTopLeft(find.text('热门版块')).dy));
    });

    testWidgets('guests have no 我的版块', (tester) async {
      await pump(tester, guest: true);
      expect(find.text('热门版块'), findsOneWidget);
      expect(find.text('我的版块'), findsNothing);
    });

    testWidgets('最近 lists visits newest first, without repeats',
        (tester) async {
      await pump(tester);
      expect(find.widgetWithText(ActionChip, '添加常用版块'), findsOneWidget);
      await tester.tap(find.text('最近'));
      await tester.pumpAndSettle();
      expect(find.text('还没有浏览过的版块'), findsOneWidget);

      for (final (fid, name) in [
        (55, 'Visited A'),
        (56, 'Visited B'),
        (55, 'Visited A'),
      ]) {
        await HomeReadingPreferences.recordBoardVisit(
          ForumCategory(name: name, slug: 'fid-$fid'),
          account: _account,
        );
      }
      await tester.pumpAndSettle();
      final a = find.widgetWithText(ActionChip, 'Visited A');
      final b = find.widgetWithText(ActionChip, 'Visited B');
      expect(a, findsOneWidget);
      expect(b, findsOneWidget);
      expect(tester.getTopLeft(a).dx, lessThan(tester.getTopLeft(b).dx));
    });

    testWidgets(
        'the edit sheet removes, adds and clears recent, writing the '
        'search screen\'s own store', (tester) async {
      await ForumSearchPreferences.savePinnedBoards(
        const [ForumSearchPinnedBoard(id: '42', label: 'Pinned board')],
        account: _account,
      );
      await HomeReadingPreferences.recordBoardVisit(
        const ForumCategory(name: 'Visited A', slug: 'fid-55'),
        account: _account,
      );
      await pump(tester);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('编辑常用版块'), findsOneWidget);
      final sheet = find.byType(BottomSheet);
      await tester.tap(find.descendant(
          of: sheet, matching: find.widgetWithText(ActionChip, 'Hot board')));
      await tester.pumpAndSettle();
      var pins =
          (await ForumSearchPreferences.load(account: _account)).pinnedBoards;
      expect([for (final pin in pins) pin.id], ['42', '7']);

      await tester.tap(find.byTooltip('移除 Pinned board'));
      await tester.pumpAndSettle();
      pins =
          (await ForumSearchPreferences.load(account: _account)).pinnedBoards;
      expect([for (final pin in pins) pin.id], ['7']);

      await tester.tap(find.text('清除最近访问'));
      await tester.pumpAndSettle();
      expect(
        (await HomeReadingPreferences.load(account: _account)).recentBoards,
        isEmpty,
      );
      expect(find.text('清除最近访问'), findsNothing);
    });
  });

  group('任务奖励 shortcut', () {
    ForumTaskSnapshot snapshot(ForumTaskState daily, ForumTaskState weekly) =>
        ForumTaskSnapshot(tasks: [daily, weekly], updatedAt: DateTime.now());

    testWidgets('a claimed task reads 已领取, is disabled and names no countdown',
        (tester) async {
      final repo = _Repo()
        ..cachedTasks = () async => snapshot(
              const ForumTaskState(
                name: '日常奖励',
                availability: ForumTaskAvailability.coolingDown,
                cooldownThreshold: Duration(hours: 24),
                cooldownRemaining: Duration(hours: 5),
              ),
              const ForumTaskState(
                name: '周常奖励',
                availability: ForumTaskAvailability.coolingDown,
                cooldownThreshold: Duration(hours: 168),
              ),
            );
      await pump(tester, repo: repo);
      expect(find.text('已领取'), findsOneWidget);
      expect(find.textContaining('h 后'), findsNothing);
      final button = tester.widget<TextButton>(find.ancestor(
          of: find.text('已领取'), matching: find.bySubtype<TextButton>()));
      expect(button.onPressed, isNull);
      expect(find.byTooltip('上次领取未超过 168 小时'), findsOneWidget);
    });

    testWidgets('a task whose state is unknown keeps the button usable',
        (tester) async {
      for (final other in [
        const ForumTaskState(
          name: '周常奖励',
          availability: ForumTaskAvailability.unknown,
        ),
        null,
      ]) {
        final repo = _Repo()
          ..cachedTasks = () async => ForumTaskSnapshot(
                tasks: [
                  const ForumTaskState(
                    name: '日常奖励',
                    availability: ForumTaskAvailability.coolingDown,
                    cooldownThreshold: Duration(hours: 18),
                  ),
                  if (other != null) other,
                ],
                updatedAt: DateTime.now(),
              );
        await pump(tester, repo: repo);
        expect(find.text('已领取'), findsNothing, reason: '$other');
        final button = tester.widget<TextButton>(find.ancestor(
            of: find.text('任务奖励'), matching: find.bySubtype<TextButton>()));
        expect(button.onPressed, isNotNull);
      }
    });

    testWidgets('a claimable task stays enabled', (tester) async {
      final repo = _Repo()
        ..cachedTasks = () async => snapshot(
              const ForumTaskState(
                name: '日常奖励',
                availability: ForumTaskAvailability.claimable,
              ),
              const ForumTaskState(
                name: '周常奖励',
                availability: ForumTaskAvailability.coolingDown,
                cooldownThreshold: Duration(hours: 168),
              ),
            );
      await pump(tester, repo: repo);
      expect(find.text('可领取'), findsOneWidget);
      final button = tester.widget<TextButton>(find.ancestor(
          of: find.text('可领取'), matching: find.bySubtype<TextButton>()));
      expect(button.onPressed, isNotNull);
    });
  });
}
