import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/history/browsing_history_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

// test-audit authoring gate:
// 1) Protects history/thread UI session gates: late fetch must not paint an
//    old account list into filters; clear-confirm must not clear the new
//    account; saved-read resume and revealAnchor must not apply/write across
//    a switch.
// 2) Credible regressions: Completer-held awaits completed after changeOwner.
// 3) Distinct from browsing_history_date_ui_test (filter chrome) and
//    app_redesign_thread_scope_test (page/quote ownership).
// 4) Fake ForumRepository only; real Completer gates — no sleep.

BrowsingHistoryEntry _hist(String title, String owner) => BrowsingHistoryEntry(
      thread: ForumThread(
        title: title,
        url:
            'https://fixture.invalid/read.php?tid-${title.hashCode.abs()}.html',
        replies: 0,
        section: '茶馆',
      ),
      viewedAt: DateTime(2026, 11, 6, 12),
    );

class _HistoryRepo extends ForumRepository {
  _HistoryRepo() {
    _scope.value = 'owner-a';
  }

  final _scope = ValueNotifier<String?>('owner-a');
  final _epoch = ValueNotifier<int>(0);
  Completer<List<BrowsingHistoryEntry>>? historyGate;
  final clearCalls = <String?>[];
  var historyCalls = 0;

  void switchTo(String? scope) {
    _scope.value = scope;
    _epoch.value++;
  }

  @override
  String get localPreferenceAccount => _scope.value ?? 'guest';

  @override
  String? get currentUsername => _scope.value;

  @override
  ValueListenable<String?> get sessionUser => _scope;

  @override
  ValueListenable<int> get sessionEpoch => _epoch;

  @override
  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) async {
    historyCalls++;
    final gate = historyGate;
    if (gate != null) return gate.future;
    return [_hist('live-${_scope.value}', _scope.value ?? 'guest')];
  }

  @override
  Future<void> clearBrowsingHistory() async {
    clearCalls.add(_scope.value);
  }
}

const _thread = ForumThread(
  title: 'Saved-position fixture',
  url: 'https://south-plus.net/read.php?tid-880001.html',
  replies: 4,
  section: '',
);

ThreadDetail _detail(String owner, int page, {String? anchor}) => ThreadDetail(
      thread: _thread,
      body: '$owner body page $page',
      bodyAnchors: anchor == null ? const [] : [anchor],
      pagination: ThreadPagination(currentPage: page, totalPages: 3),
      replies: [
        ThreadReply(
          author: 'peer',
          content: '$owner reply',
          postId: '501',
          floor: 'B1F',
          anchors: const ['501'],
        ),
      ],
    );

class _ThreadRepo extends AppRedesignRepository {
  _ThreadRepo() : super(user: 'owner-a');

  Completer<ThreadReadPosition?>? readGate;
  Completer<ThreadDetail>? detailGate;
  Completer<void>? saveGate;
  final saves = <(String?, ThreadReadPosition)>[];
  final pages = <(String?, int)>[];

  @override
  String get localPreferenceAccount => currentUsername ?? 'guest';

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread thread) async {
    final gate = readGate;
    if (gate != null) return gate.future;
    return null;
  }

  @override
  Future<void> saveThreadReadPosition(
    ForumThread thread,
    ThreadReadPosition position,
  ) async {
    saves.add((currentUsername, position));
    final gate = saveGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    pages.add((currentUsername, page));
    final gate = detailGate;
    if (gate != null) return gate.future;
    return _detail(currentUsername ?? 'guest', page, anchor: 'tpc');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'late history fetch after switch does not keep old-account rows for filters',
      (tester) async {
    final repo = _HistoryRepo();
    final gate = Completer<List<BrowsingHistoryEntry>>();
    repo.historyGate = gate;

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrowsingHistoryScreen(repository: repo),
      ),
    );
    await tester.pump();
    expect(repo.historyCalls, 1);

    // Drop the gate before switching so the post-switch refresh reads the new
    // account immediately; the in-flight first fetch still holds [gate].
    repo.historyGate = null;
    repo.switchTo('owner-b');
    await tester.pump();
    await tester.pump();

    gate.complete([_hist('old-a-only', 'owner-a')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('old-a-only'), findsNothing);
    expect(find.textContaining('live-owner-b'), findsWidgets);
  });

  for (final datePickerOpen in [false, true]) {
    testWidgets(
        'shown history disappears while the next account loads (date picker=$datePickerOpen)',
        (tester) async {
      final repo = _HistoryRepo();
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: BrowsingHistoryScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('live-owner-a'), findsOneWidget);
      if (datePickerOpen) {
        await tester.tap(find.byTooltip('按日期筛选'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('history-date:年2026')),
          findsOneWidget,
        );
      }

      final nextHistory = Completer<List<BrowsingHistoryEntry>>();
      repo.historyGate = nextHistory;
      repo.switchTo('owner-b');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('history-date:年2026')),
        findsNothing,
      );
      expect(find.text('live-owner-a'), findsNothing);
      expect(find.text('live-owner-b'), findsNothing);
      nextHistory.complete([_hist('live-owner-b', 'owner-b')]);
      await tester.pumpAndSettle();
      if (datePickerOpen) {
        expect(find.text('账号已切换'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '返回'));
        await tester.pumpAndSettle();
      }
      expect(find.text('live-owner-b'), findsOneWidget);
      expect(find.text('live-owner-a'), findsNothing);
    });
  }

  testWidgets(
      'clear confirm after switch aborts and does not clear new account',
      (tester) async {
    final repo = _HistoryRepo();

    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BrowsingHistoryScreen(repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('live-owner-a'), findsWidgets);

    await tester.tap(find.byTooltip('清空浏览历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空浏览历史？'), findsOneWidget);

    repo.switchTo('owner-b');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(repo.clearCalls, isEmpty);
    expect(find.text('浏览历史已清空'), findsNothing);
  });

  testWidgets(
      'saved read position completed after switch does not load old page',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'settings.autoLoadNextPage': false});
    await LoadingPreferences.load();

    final repo = _ThreadRepo();
    final gate = Completer<ThreadReadPosition?>();
    repo.readGate = gate;

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: ThreadDetailScreen(repository: repo, thread: _thread),
    ));
    await tester.pump();
    expect(repo.pages, isEmpty);

    repo.changeOwner('owner-b');
    await tester.pump();

    gate.complete(const ThreadReadPosition(page: 3, anchor: '501'));
    await tester.pumpAndSettle();

    expect(
      repo.pages.where((e) => e.$2 == 3),
      isEmpty,
      reason: 'old saved page must not load after switch',
    );
    expect(
      repo.pages.where((e) => e.$1 == 'owner-b').map((e) => e.$2),
      isNot(contains(3)),
    );
  });

  testWidgets('an admitted saved anchor never carries into a new account page',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'settings.autoLoadNextPage': false});
    await LoadingPreferences.load();

    final repo = _ThreadRepo();
    final oldPage = Completer<ThreadDetail>();
    repo.readGate = Completer<ThreadReadPosition?>()
      ..complete(const ThreadReadPosition(page: 3, anchor: '501'));
    repo.detailGate = oldPage;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: ThreadDetailScreen(repository: repo, thread: _thread),
    ));
    await tester.pump();
    await tester.pump();
    expect(repo.pages, contains(('owner-a', 3)));

    repo.detailGate = null;
    repo.changeOwner('owner-b');
    await tester.pumpAndSettle();
    expect(repo.pages, contains(('owner-b', 1)));
    expect(
      repo.saves.where((saved) => saved.$1 == 'owner-b'),
      isEmpty,
      reason: 'A pending resume must not scroll or save a position for B',
    );

    oldPage.complete(_detail('owner-a', 3, anchor: 'tpc'));
    await tester.pumpAndSettle();
    expect(find.text('owner-a body page 3'), findsNothing);
    expect(repo.saves.where((saved) => saved.$1 == 'owner-b'), isEmpty);
  });

  testWidgets(
      'revealAnchor save uses capture-at-entry; switch before save skips write',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'settings.autoLoadNextPage': false});
    await LoadingPreferences.load();

    final repo = _ThreadRepo();
    // Non-tpc anchor forces resume + _revealAnchor (page 1 + tpc would skip).
    repo.readGate = Completer<ThreadReadPosition?>()
      ..complete(const ThreadReadPosition(page: 1, anchor: '501'));

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: ThreadDetailScreen(repository: repo, thread: _thread),
    ));
    // Let openAtSaved load page and start reveal frames, then switch.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    repo.changeOwner('owner-b');
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      repo.saves.where((e) => e.$1 == 'owner-b'),
      isEmpty,
      reason: 'late reveal must not write read pos under the new account',
    );
  });
}
