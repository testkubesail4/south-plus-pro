import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/messages/reply_notices_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

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
      .widget<Badge>(find.ancestor(of: near, matching: find.byType(Badge)))
      .isLabelVisible;

  testWidgets('home dots unread notices and PMs; notices open and delete',
      (tester) async {
    final repo =
        _Repo(const ForumNoticeFlags(replyNotice: true, unreadPm: true));
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: repo)));
    await tester.pump();

    expect(
        dotted(tester, find.byIcon(Icons.mark_chat_unread_outlined)), isTrue);
    expect(dotted(tester, find.byIcon(Icons.mail_outline).first), isTrue);
    expect(dotted(tester, find.byIcon(Icons.mail_outline).last), isTrue,
        reason: '消息 tab in the navigation bar');

    repo.flags.value = const ForumNoticeFlags();
    await tester.pump();
    expect(
        dotted(tester, find.byIcon(Icons.mark_chat_unread_outlined)), isFalse);
    expect(dotted(tester, find.byIcon(Icons.mail_outline).last), isFalse);

    await tester.tap(find.text('回复提醒'));
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
      _notice(2).threadUrl,
    );
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
