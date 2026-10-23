import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/messages/messages_screen.dart';
import 'package:south_plus_rewrite/features/messages/reply_notices_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic boards, titles and tids only.
ForumReplyNotice _notice(int tid) => ForumReplyNotice(
      board: 'Board $tid',
      boardUrl: 'https://south-plus.net/thread.php?fid=$tid',
      title: 'Fixture topic $tid',
      threadUrl: 'https://south-plus.net/read.php?tid=$tid',
      date: '2026-01-0$tid',
      tid: tid,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  bool dotted(WidgetTester tester, Finder near) => tester
      .widget<Badge>(find.descendant(of: near, matching: find.byType(Badge)))
      .isLabelVisible;

  testWidgets(
      '消息 tab holds 短消息 and 回复提醒, each dotted; notices open and '
      'delete', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(const ForumNoticeFlags(replyNotice: true));
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: repo)));
    await tester.pump();
    Finder tab(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(Tab));

    // Either kind of unread dots the 消息 destination.
    expect(dotted(tester, find.byType(NavigationBar)), isTrue);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('消息')));
    await tester.pumpAndSettle();
    expect(dotted(tester, tab('回复提醒')), isTrue);
    expect(dotted(tester, tab('短消息')), isFalse);
    // Screen readers hear which tab has something unread.
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('回复提醒，有未读')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('短消息，有未读')), findsNothing);

    repo.flags.value = const ForumNoticeFlags(unreadPm: true);
    await tester.pump();
    expect(dotted(tester, tab('回复提醒')), isFalse);
    expect(dotted(tester, tab('短消息')), isTrue);
    expect(find.bySemanticsLabel(RegExp('短消息，有未读')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('回复提醒，有未读')), findsNothing);
    semantics.dispose();
    expect(dotted(tester, find.byType(NavigationBar)), isTrue);

    repo.flags.value = const ForumNoticeFlags();
    await tester.pump();
    expect(dotted(tester, find.byType(NavigationBar)), isFalse);

    await tester.tap(tab('回复提醒'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture topic 1'), findsOneWidget);
    expect(find.text('Board 2 · 2026-01-02'), findsOneWidget);

    await tester.tap(find.byTooltip('删除提醒').first);
    await tester.pump();
    expect(repo.deleted, [1]);
    repo.deletion.complete();
    await tester.pumpAndSettle();
    expect(find.text('Fixture topic 1'), findsNothing);
    expect(find.text('Fixture topic 2'), findsOneWidget);

    await tester.tap(find.text('Fixture topic 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .widget<ThreadDetailScreen>(find.byType(ThreadDetailScreen))
          .thread
          .url,
      // A notice names no floor; its new replies are on the latest page.
      'https://south-plus.net/read.php?tid-2-page-e.html',
    );
  });

  testWidgets('a notice that links a page or floor opens exactly that',
      (tester) async {
    ForumReplyNotice at(int tid, String url) => ForumReplyNotice(
          board: 'Board $tid',
          boardUrl: 'https://south-plus.net/thread.php?fid=$tid',
          title: 'Fixture topic $tid',
          threadUrl: url,
          date: '2026-01-0$tid',
          tid: tid,
        );
    const paged = 'https://south-plus.net/read.php?tid-4-page-3.html';
    const floor = 'https://south-plus.net/read.php?tid-5.html#905';
    final repo = _Repo(const ForumNoticeFlags())
      ..notices = [at(4, paged), at(5, floor)];
    await tester
        .pumpWidget(MaterialApp(home: ReplyNoticesScreen(repository: repo)));
    await tester.pumpAndSettle();
    for (final (title, url) in [
      ('Fixture topic 4', paged),
      ('Fixture topic 5', floor),
    ]) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ThreadDetailScreen>(find.byType(ThreadDetailScreen))
              .thread
              .url,
          url);
      Navigator.of(tester.element(find.byType(ThreadDetailScreen))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('swiping between the 消息 tabs keeps both lists loaded',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(const ForumNoticeFlags());
    await tester
        .pumpWidget(MaterialApp(home: MessagesScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(repo.pmFetches, 1);

    for (var i = 0; i < 2; i++) {
      await tester.fling(find.byType(TabBarView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Fixture topic 1'), findsOneWidget);
      await tester.fling(find.byType(TabBarView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
    }
    expect(repo.fetches, 1, reason: '回复提醒 loaded once');
    expect(repo.pmFetches, 1, reason: '短消息 loaded once');
  });

  testWidgets('on a wide window the 消息 tabs and rows keep the list width',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(const ForumNoticeFlags());
    await tester
        .pumpWidget(MaterialApp(home: MessagesScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复提醒'));
    await tester.pumpAndSettle();

    final row = tester.getRect(find.ancestor(
        of: find.text('Fixture topic 1'),
        matching: find.byType(ForumThreadRow)));
    expect(row.width, AppWidths.list);
    expect(row.center.dx, 720);
    expect(tester.getRect(find.byType(TabBar)).width, AppWidths.list);
  });

  testWidgets('a failed delete keeps the notice and says why', (tester) async {
    final repo = _Repo(const ForumNoticeFlags(replyNotice: true));
    await tester
        .pumpWidget(MaterialApp(home: ReplyNoticesScreen(repository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('删除提醒').first);
    repo.deletion.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture topic 1'), findsOneWidget);
    expect(find.textContaining('删除失败'), findsOneWidget);
  });

  testWidgets('no notices shows an empty state that still refreshes',
      (tester) async {
    final repo = _Repo(const ForumNoticeFlags())..notices = [];
    await tester
        .pumpWidget(MaterialApp(home: ReplyNoticesScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('暂无回复提醒'), findsOneWidget);

    repo.notices = [_notice(3)];
    await tester.fling(find.text('暂无回复提醒'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(repo.fetches, 2);
    expect(find.text('Fixture topic 3'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the rows and says why', (tester) async {
    final repo = _Repo(const ForumNoticeFlags())..notices = [_notice(1)];
    await tester
        .pumpWidget(MaterialApp(home: ReplyNoticesScreen(repository: repo)));
    await tester.pumpAndSettle();

    repo.failNext = true;
    await tester.fling(
        find.text('Fixture topic 1'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(repo.fetches, 2);
    expect(find.text('Fixture topic 1'), findsOneWidget);
    expect(find.textContaining('刷新失败'), findsOneWidget);
  });
}

class _Repo extends ForumRepository {
  _Repo(ForumNoticeFlags flags) : flags = ValueNotifier(flags);

  final ValueNotifier<ForumNoticeFlags> flags;
  var notices = [_notice(1), _notice(2)];
  final deleted = <int>[];
  var deletion = Completer<void>();

  @override
  ValueListenable<ForumNoticeFlags> get noticeFlags => flags;

  @override
  Future<List<ForumReplyNotice>> fetchReplyNotices() async {
    fetches++;
    if (failNext) throw StateError('offline');
    return notices;
  }

  var fetches = 0;
  var failNext = false;

  @override
  Future<void> deleteReplyNotice(ForumReplyNotice notice) {
    deleted.add(notice.tid);
    return deletion.future;
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) =>
      Completer<ThreadDetail>().future;

  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    pmFetches++;
    return ForumPmPage(box: box, messages: const []);
  }

  var pmFetches = 0;

  @override
  Future<ForumHomeSnapshot> fetchHome() async => const ForumHomeSnapshot(
        latest: [
          ForumThread(
            title: 'Topic',
            url: 'read.php?tid-9.html',
            replies: 0,
            section: 'Board',
          ),
        ],
        hot: [],
        sections: [],
      );

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}
