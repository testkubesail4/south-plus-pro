import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/messages/live_notice_banner.dart';
import 'package:south_plus_rewrite/features/messages/messages_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_live_sync.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';

// Synthetic titles, boards and tids only.
ForumThread _thread(String title) => ForumThread(
      title: title,
      url: 'read.php?tid-1.html',
      replies: 0,
      section: 'Board',
    );

ForumReplyNotice _notice(int tid) => ForumReplyNotice(
      board: 'Board $tid',
      boardUrl: 'https://south-plus.net/thread.php?fid=$tid',
      title: 'Fixture topic $tid',
      threadUrl: 'https://south-plus.net/read.php?tid=$tid',
      date: '2026-01-0$tid',
      tid: tid,
    );

ForumPmSummary _pm(String id) => ForumPmSummary(
      id: id,
      title: 'Message $id',
      peer: 'Peer',
      time: '2026-01-01',
      box: ForumPmBox.inbox,
      type: ForumPmType.personal,
      detailPath: 'message.php?action-read-mid-$id.html',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: repo)));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  group('home', () {
    testWidgets('a new revision swaps fresh rows in, keeping the open tab',
        (tester) async {
      final repo = await pumpShell(tester);
      expect(find.text('Latest 1'), findsOneWidget);
      await tester.tap(find.text('最新回复'));
      await tester.pumpAndSettle();

      repo.latestTitle = 'Latest 2';
      repo.sync.bumpHome();
      await tester.pumpAndSettle();
      expect(repo.homeReads, 2);
      // Still on 最新回复, with no placeholders in between.
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      await tester.tap(find.text('最新讨论'));
      await tester.pumpAndSettle();
      expect(find.text('Latest 2'), findsOneWidget);
    });

    testWidgets('a revision while home is hidden waits for its return',
        (tester) async {
      final repo = await pumpShell(tester);
      await selectTab(tester, '搜索');
      repo.sync.bumpHome();
      await tester.pumpAndSettle();
      expect(repo.homeReads, 1);
      await selectTab(tester, '首页');
      expect(repo.homeReads, 2);
    });

    testWidgets('a failed quiet refresh keeps the page', (tester) async {
      final repo = await pumpShell(tester);
      repo.failHome = true;
      repo.sync.bumpHome();
      await tester.pumpAndSettle();
      expect(find.text('Latest 1'), findsOneWidget);
      expect(find.text('主页加载失败'), findsNothing);
    });

    testWidgets('pulling down brings 消息 along; its failure offers 重试',
        (tester) async {
      final repo = await pumpShell(tester);
      repo.sync.fail = true;
      await tester.fling(
          find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(repo.homeReads, 2);
      expect(repo.sync.userSyncs, 1);
      expect(find.text('消息同步失败'), findsOneWidget);

      repo.sync.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repo.sync.userSyncs, 2);
    });

    testWidgets('消息 failing while a slow home still loads is handled',
        (tester) async {
      final repo = await pumpShell(tester);
      repo.sync.fail = true;
      repo.homeGate = Completer<void>();
      await tester.fling(
          find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The sync has failed; the home has not answered.
      expect(repo.sync.userSyncs, 1);
      repo.homeGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('消息同步失败'), findsOneWidget);
    });

    testWidgets('a shell gone before its banner mounts leaves no entry',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester
          .pumpWidget(MaterialApp(home: HomeShell(repository: _Repo())));
      // The banner is inserted after the first frame, built in the next.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LiveNoticeBanner), findsNothing);
    });
  });

  group('消息', () {
    testWidgets('showing 消息 checks quietly, with a hairline under the tabs',
        (tester) async {
      final repo = await pumpShell(tester);
      repo.sync.hold = Completer<void>();
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('消息')));
      await tester.pump();
      await tester.pump();
      expect(repo.sync.quietSyncs, 1);
      expect(find.byKey(const ValueKey('messages-syncing')), findsOneWidget);
      // The lists stay up meanwhile.
      expect(find.text('Message 1'), findsOneWidget);

      repo.sync.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('messages-syncing')), findsNothing);

      await selectTab(tester, '首页');
      await selectTab(tester, '消息');
      expect(repo.sync.quietSyncs, 2);
    });

    testWidgets('fresher lists read elsewhere show in place', (tester) async {
      final repo = await pumpShell(tester);
      await selectTab(tester, '消息');
      repo.inbox.value =
          ForumPmPage(box: ForumPmBox.inbox, messages: [_pm('2'), _pm('1')]);
      await tester.pumpAndSettle();
      expect(find.text('Message 2'), findsOneWidget);

      await tester.tap(find.text('回复提醒'));
      await tester.pumpAndSettle();
      expect(find.text('Fixture topic 1'), findsOneWidget);
      repo.replies.value = [_notice(2), _notice(1)];
      await tester.pumpAndSettle();
      expect(find.text('Fixture topic 2'), findsOneWidget);
    });
  });

  group('in-app notice', () {
    testWidgets('shows over any page; a tap opens its list', (tester) async {
      final repo = await pumpShell(tester);
      // A page pushed over the shell.
      Navigator.of(tester.element(find.byType(NavigationBar))).push(
          MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Pushed page'))));
      await tester.pumpAndSettle();

      repo.sync.notify(NoticeNotificationKind.reply, 2, 'Fixture topic 7');
      await tester.pumpAndSettle();
      expect(find.text('Fixture topic 7'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Fixture topic 7'));
      await tester.pumpAndSettle();
      expect(find.text('Pushed page'), findsNothing);
      expect(find.byType(MessagesScreen), findsOneWidget);
      final tabs = tester.widget<TabBar>(find.descendant(
          of: find.byType(MessagesScreen), matching: find.byType(TabBar)));
      expect(tabs.controller!.index, 1);
      expect(find.text('Fixture topic 7'), findsNothing);
    });

    testWidgets('without a title it names its kind, and leaves by itself',
        (tester) async {
      final repo = await pumpShell(tester);
      repo.sync.notify(NoticeNotificationKind.pm, 1, null);
      await tester.pumpAndSettle();
      expect(find.text('新短消息'), findsOneWidget);
      await tester.pump(LiveNoticeBanner.shownFor);
      await tester.pumpAndSettle();
      expect(find.text('新短消息'), findsNothing);
    });

    testWidgets('an upward swipe puts it away', (tester) async {
      final repo = await pumpShell(tester);
      repo.sync.notify(NoticeNotificationKind.pm, 1, 'New peer');
      await tester.pumpAndSettle();
      await tester.fling(find.text('New peer'), const Offset(0, -80), 800);
      await tester.pumpAndSettle();
      expect(find.text('New peer'), findsNothing);
    });

    testWidgets('nothing shows over the list it would open', (tester) async {
      final repo = await pumpShell(tester);
      await selectTab(tester, '消息');
      repo.sync.notify(NoticeNotificationKind.pm, 1, 'New peer');
      await tester.pumpAndSettle();
      expect(find.text('New peer'), findsNothing);

      repo.sync.notify(NoticeNotificationKind.reply, 1, 'Fixture topic 9');
      await tester.pumpAndSettle();
      expect(find.text('Fixture topic 9'), findsOneWidget);
    });
  });
}

class _Sync extends ForumLiveSync {
  _Sync() : super(checkMessages: () async {});

  final _home = ValueNotifier(0);
  final _notice = ValueNotifier<LiveNotice?>(null);
  final _busy = ValueNotifier(false);
  var quietSyncs = 0;
  var userSyncs = 0;
  var fail = false;
  Completer<void>? hold;
  var _serial = 0;

  void bumpHome() => _home.value++;

  void notify(NoticeNotificationKind kind, int count, String? title) =>
      _notice.value =
          LiveNotice(serial: ++_serial, kind: kind, count: count, title: title);

  @override
  ValueListenable<int> get homeRevision => _home;

  @override
  ValueListenable<LiveNotice?> get latestNotice => _notice;

  @override
  ValueListenable<bool> get messagesSyncing => _busy;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<void> syncMessages({bool user = false}) async {
    user ? userSyncs++ : quietSyncs++;
    _busy.value = true;
    try {
      await hold?.future;
      if (fail && user) throw StateError('offline');
    } finally {
      _busy.value = false;
    }
  }
}

class _Repo extends ForumRepository {
  final sync = _Sync();
  final inbox = ValueNotifier<ForumPmPage?>(null);
  final replies = ValueNotifier<List<ForumReplyNotice>?>(null);
  var latestTitle = 'Latest 1';
  var homeReads = 0;
  var failHome = false;
  Completer<void>? homeGate;

  @override
  ForumLiveSync get liveSync => sync;

  @override
  ValueListenable<ForumPmPage?> get pmInbox => inbox;

  @override
  ValueListenable<List<ForumReplyNotice>?> get replyNotices => replies;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => 'fixture_login';

  @override
  final accountIdentity = ValueNotifier(const ForumAccountIdentity(
      systemName: 'fixture_login', nickname: 'Fixture user'));

  @override
  Future<ForumHomeSnapshot> fetchHome() async {
    homeReads++;
    await homeGate?.future;
    if (failHome) throw StateError('offline');
    return ForumHomeSnapshot(
      latest: [_thread(latestTitle)],
      quickLists: [
        ForumQuickList(title: '最新讨论', threads: [_thread(latestTitle)]),
        ForumQuickList(title: '最新回复', threads: [_thread('Reply 1')]),
      ],
      hot: const [],
      sections: const [],
    );
  }

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async =>
      ForumPmPage(box: box, messages: [_pm('1')]);

  @override
  Future<List<ForumReplyNotice>> fetchReplyNotices() async => [_notice(1)];

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;
}
