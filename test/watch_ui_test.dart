import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/sub_tabs.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/messages/messages_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/watch/watch_rule_sheet.dart';
import 'package:south_plus_rewrite/features/watch/watch_tab.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/native_notice_notifications.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

import 'support/fake_watch.dart';

// Synthetic fixtures only: fictional uids, titles and thread IDs.
WatchRule _rule(
  String id, {
  WatchScope scope = WatchScope.thread,
  String subject = '7',
  String label = 'a thread',
  Set<WatchContentKind> kinds = const {WatchContentKind.replies},
  String? involving,
  String keyword = '',
  WatchKeywordField field = WatchKeywordField.title,
  bool paused = false,
}) =>
    WatchRule(
      id: id,
      scope: scope,
      subjectId: subject,
      label: label,
      kinds: kinds,
      involvingUid: involving,
      keyword: keyword,
      keywordField: field,
      paused: paused,
    );

WatchEvent _event(
  String id, {
  String rule = 'r1',
  WatchContentKind kind = WatchContentKind.replies,
  WatchConfidence confidence = WatchConfidence.certain,
  String reason = '',
  bool unread = true,
}) =>
    WatchEvent(
      id: id,
      ruleId: rule,
      title: 'event $id',
      url: 'https://south-plus.net/read.php?tid-7-page-2.html#90$id',
      kind: kind,
      confidence: confidence,
      reason: reason,
      detectedAt: DateTime(2026, 1, 2, 3, 4),
      unread: unread,
    );

void main() {
  Future<_Repo> pumpTab(WidgetTester tester, FakeWatch watch,
      {bool rules = false}) async {
    final repository = _Repo(watch);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WatchTab(repository: repository, initialRules: rules),
      ),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  group('动态', () {
    testWidgets('a probable match says why; a certain one says nothing',
        (tester) async {
      await pumpTab(
        tester,
        FakeWatch(rules: [
          _rule('r1')
        ], events: [
          _event('1'),
          _event('2',
              confidence: WatchConfidence.probable,
              reason: '按引用文字匹配，论坛未提供原生目标 ID'),
        ]),
      );
      expect(find.text('可能'), findsOneWidget);
      expect(find.text('按引用文字匹配，论坛未提供原生目标 ID'), findsOneWidget);
      expect(find.text('event 1'), findsOneWidget);
      expect(find.textContaining('新回复 · 01-02 03:04 发现 · a thread'),
          findsNWidgets(2));
    });

    testWidgets('a 动态 claims only what a check could see, and when',
        (tester) async {
      final watch = FakeWatch(
          rules: [_rule('r1')],
          events: [_event('1', kind: WatchContentKind.favorites)]);
      await pumpTab(tester, watch);
      expect(find.text('新可见收藏 · 01-02 03:04 发现 · a thread'), findsOneWidget);
    });

    testWidgets('opening a 动态 does not count as reading it', (tester) async {
      final watch = FakeWatch(rules: [_rule('r1')], events: [_event('1')]);
      await pumpTab(tester, watch);
      await tester.tap(find.text('event 1'));
      await tester.pump();
      expect(watch.read, isEmpty);
      expect(watch.unreadCount, 1);
    });

    testWidgets('标为已读 is the reader asking for it', (tester) async {
      final watch = FakeWatch(rules: [_rule('r1')], events: [_event('1')]);
      await pumpTab(tester, watch);
      await tester.longPress(find.text('event 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(watch.read, ['1']);
      expect(find.byIcon(Icons.circle), findsNothing);
    });

    testWidgets('a failed 标为已读 says so and leaves it unread', (tester) async {
      final watch = FakeWatch(rules: [_rule('r1')], events: [_event('1')])
        ..markReadError = StateError('disk full');
      await pumpTab(tester, watch);
      await tester.longPress(find.text('event 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败，请重试'), findsOneWidget);
      expect(watch.unreadCount, 1);
      expect(find.byIcon(Icons.circle), findsOneWidget);
    });

    testWidgets('a spent request budget reads as waiting, not as nothing new',
        (tester) async {
      final watch = FakeWatch(rules: [_rule('r1')])
        ..pendingUntil = DateTime.now().add(const Duration(minutes: 3));
      await pumpTab(tester, watch);
      expect(find.textContaining('已达请求上限'), findsOneWidget);
      final check = find.widgetWithText(TextButton, '立即检查');
      expect(tester.widget<TextButton>(check).onPressed, isNull);
    });

    testWidgets('立即检查 runs a check', (tester) async {
      final watch = FakeWatch(rules: [_rule('r1')]);
      await pumpTab(tester, watch);
      await tester.tap(find.widgetWithText(TextButton, '立即检查'));
      expect(watch.checks, 1);
    });

    testWidgets('no rules: nothing to check, and 说明 says where to add one',
        (tester) async {
      await pumpTab(tester, FakeWatch());
      expect(find.text('还没有关注'), findsOneWidget);
      expect(find.text('立即检查'), findsNothing);
      await tester.tap(find.byTooltip('说明'));
      await tester.pumpAndSettle();
      expect(find.textContaining('楼层作者菜单'), findsOneWidget);
    });
  });

  group('规则', () {
    testWidgets('each status reads plainly, failures in the error colour',
        (tester) async {
      final watch = FakeWatch(
        rules: [
          _rule('a', label: 'current'),
          _rule('b', label: 'pending'),
          _rule('c', label: 'incomplete'),
          _rule('d', label: 'gone'),
          _rule('e', label: 'paused', paused: true),
        ],
        statuses: {
          'a': WatchStatus(WatchPhase.current, '',
              checkedAt: DateTime(2026, 1, 2, 14, 32)),
          'b': const WatchStatus(WatchPhase.pending, ''),
          'c': const WatchStatus(WatchPhase.incomplete, ''),
          'd': const WatchStatus(WatchPhase.unavailable, '帖子不存在'),
        },
      )..pendingUntil = DateTime.now().add(const Duration(minutes: 2));
      await pumpTab(tester, watch, rules: true);

      expect(find.text('已启用 4/10'), findsOneWidget);
      expect(find.text('14:32 已检查'), findsOneWidget);
      expect(find.text('待继续（已达请求上限）'), findsOneWidget);
      expect(find.text('有内容待确认，下次继续'), findsOneWidget);
      expect(find.text('已暂停'), findsOneWidget);
      final failed = tester.widget<Text>(find.text('无法检查：帖子不存在'));
      expect(failed.style?.color,
          Theme.of(tester.element(find.byType(WatchTab))).colorScheme.error);
      // The limits and what is never checked are one tap away.
      expect(find.textContaining('后台或关闭时不检查'), findsNothing);
      await tester.tap(find.byTooltip('说明'));
      await tester.pumpAndSettle();
      expect(find.text('后台或关闭时不检查'), findsOneWidget);
      expect(find.text('私密收藏、已删除的楼层和图片中的文字无法识别'), findsOneWidget);
    });

    testWidgets('暂停 and 恢复 come from the row menu', (tester) async {
      final watch = FakeWatch(rules: [_rule('a')]);
      await pumpTab(tester, watch, rules: true);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂停'));
      await tester.pumpAndSettle();
      expect(watch.rules.single.paused, isTrue);
      expect(find.text('已启用 0/10'), findsOneWidget);
    });

    testWidgets('删除 asks first', (tester) async {
      final watch = FakeWatch(rules: [_rule('a')]);
      await pumpTab(tester, watch, rules: true);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(watch.rules, hasLength(1));
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(watch.rules, isEmpty);
    });

    testWidgets('a 删除 confirmed after an account switch deletes nothing',
        (tester) async {
      final watch = FakeWatch(rules: [_rule('a')]);
      final repository = await pumpTab(tester, watch, rules: true);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      repository.epoch.value++;
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(watch.rules, hasLength(1));
    });

    testWidgets('打开帖子 opens the watched thread itself', (tester) async {
      final watch = FakeWatch(rules: [_rule('a')]);
      await pumpTab(tester, watch, rules: true);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开帖子'));
      await tester.pumpAndSettle();
      final thread =
          tester.widget<ThreadDetailScreen>(find.byType(ThreadDetailScreen));
      expect(thread.thread.url, endsWith('read.php?tid-7.html'));
    });
  });

  group('rule summary', () {
    test('filters join with 且, kinds with 或, and the field is named', () {
      expect(
          watchRuleSummary(
              _rule('a',
                  scope: WatchScope.user,
                  kinds: {WatchContentKind.topics, WatchContentKind.favorites},
                  keyword: 'RPG'),
              '101'),
          'TA 的新主题或新可见收藏，且标题含「RPG」');
      expect(
          watchRuleSummary(
              _rule('a',
                  scope: WatchScope.user,
                  involving: '101',
                  keyword: 'RPG',
                  field: WatchKeywordField.body),
              '101'),
          'TA 的新回复，且涉及我，且正文含「RPG」');
      expect(watchRuleSummary(_rule('a', involving: '55'), '101'),
          '回复或引用 UID 55 的新回复');
      expect(
          watchRuleSummary(
              _rule('a',
                  scope: WatchScope.board,
                  kinds: {WatchContentKind.topics},
                  keyword: '汉化'),
              '101'),
          '标题含「汉化」的新主题');
    });
  });

  group('editor', () {
    late _Repo sheetRepository;

    Future<FakeWatch> openSheet(
      WidgetTester tester,
      WatchTarget target, {
      List<WatchRule> rules = const [],
    }) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final watch = FakeWatch(rules: rules);
      final repository = sheetRepository = _Repo(watch);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWatchSheet(context,
                  repository: repository, target: target),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return watch;
    }

    testWidgets('涉及 narrows a user rule to replies only', (tester) async {
      final watch = await openSheet(
        tester,
        const WatchTarget(scope: WatchScope.user, subjectId: '55', label: 'u'),
      );
      expect(find.text('TA 的新主题'), findsOneWidget);
      await tester.tap(find.text('我'));
      await tester.pumpAndSettle();
      expect(find.text('涉及只适用于回复'), findsOneWidget);
      expect(find.text('TA 的新回复，且涉及我'), findsOneWidget);
      final topics =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, '新主题'));
      expect(topics.selected, isFalse);
      expect(topics.onSelected, isNull);

      await tester.tap(find.widgetWithText(FilledButton, '关注'));
      await tester.pumpAndSettle();
      final rule = watch.rules.single;
      expect(rule.kinds, {WatchContentKind.replies});
      expect(rule.involvingUid, '101');
      expect(rule.id, matches(RegExp(r'^[A-Za-z0-9_-]{1,128}$')));
    });

    testWidgets('某人 needs a numeric UID; a floor author is one tap',
        (tester) async {
      final watch = await openSheet(
        tester,
        const WatchTarget(
          scope: WatchScope.thread,
          subjectId: '7',
          label: 't',
          people: [('55', 'bob'), ('101', 'me')],
        ),
      );
      await tester.tap(find.text('回复或引用某人的'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, '关注');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('请填写对方的数字 UID'), findsOneWidget);
      // One's own uid is 我, not 某人.
      expect(find.widgetWithText(ChoiceChip, 'me'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'bob'));
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(watch.rules.single.involvingUid, '55');
    });

    testWidgets('a board rule needs a title keyword', (tester) async {
      final watch = await openSheet(
        tester,
        const WatchTarget(scope: WatchScope.board, subjectId: '9', label: 'b'),
      );
      final save = find.widgetWithText(FilledButton, '关注');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '汉化');
      await tester.pumpAndSettle();
      expect(find.text('标题含「汉化」的新主题'), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(watch.rules.single.keywordField, WatchKeywordField.title);
    });

    testWidgets('a watched target lists its rules and can add another (OR)',
        (tester) async {
      await openSheet(
        tester,
        const WatchTarget(scope: WatchScope.thread, subjectId: '7', label: 't'),
        rules: [_rule('a')],
      );
      expect(find.text('所有新回复'), findsOneWidget);
      await tester.tap(find.text('新增关注规则'));
      await tester.pumpAndSettle();
      expect(find.text('关注帖子 · 新规则'), findsOneWidget);
    });

    testWidgets('an account switch closes the sheet unsaved', (tester) async {
      final watch = await openSheet(
        tester,
        const WatchTarget(scope: WatchScope.thread, subjectId: '7', label: 't'),
      );
      expect(find.widgetWithText(FilledButton, '关注'), findsOneWidget);
      sheetRepository.epoch.value++;
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '关注'), findsNothing);
      expect(watch.rules, isEmpty);
    });

    testWidgets('10 active rules leave no room for an 11th', (tester) async {
      await openSheet(
        tester,
        const WatchTarget(scope: WatchScope.thread, subjectId: '7', label: 't'),
        rules: [
          for (var i = 0; i < WatchService.maxActiveRules; i++)
            _rule('r$i', subject: '${100 + i}'),
        ],
      );
      expect(find.text('已启用 10 条，先暂停或删除一条'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '关注'))
              .onPressed,
          isNull);
    });
  });

  testWidgets('a tapped notification turns 消息 to 关注; its dot is announced',
      (tester) async {
    final watch = FakeWatch(rules: [_rule('r1')], events: [_event('1')]);
    final repository = _Repo(watch);
    await tester
        .pumpWidget(MaterialApp(home: MessagesScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == '关注，有未读'),
        findsOneWidget);
    expect(find.text('event 1'), findsNothing);

    watch.tap(_event('1'));
    await tester.pumpAndSettle();
    expect(watch.pendingOpen, isNull);
    // The 动态 opens on its thread; 关注 is the tab under it.
    final thread =
        tester.widget<ThreadDetailScreen>(find.byType(ThreadDetailScreen));
    expect(thread.thread.url, endsWith('read.php?tid-7-page-2.html#901'));
    Navigator.of(tester.element(find.byType(ThreadDetailScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text('event 1'), findsOneWidget);
  });

  group('短消息 and 回复提醒 notifications', () {
    Future<_Repo> pumpMessages(WidgetTester tester, FakeWatch watch,
        {ValueListenable<bool>? shown}) async {
      final repository = _Repo(watch);
      final screen = MessagesScreen(repository: repository);
      await tester.pumpWidget(MaterialApp(
        home: shown == null
            ? screen
            : ValueListenableBuilder(
                valueListenable: shown,
                builder: (_, enabled, child) =>
                    TickerMode(enabled: enabled, child: child!),
                child: screen,
              ),
      ));
      await tester.pumpAndSettle();
      return repository;
    }

    int selectedTab(WidgetTester tester) =>
        tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

    testWidgets('a tap turns to its list and reloads it, even if it is open',
        (tester) async {
      final watch = FakeWatch();
      final repository = await pumpMessages(tester, watch);
      expect(repository.pmLoads, 1);
      await tester.tap(find.text('发件箱'));
      await tester.pumpAndSettle();
      expect(repository.lastBox, ForumPmBox.sendbox);

      watch.tapNotice(NoticeNotificationKind.pm);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      // A fresh 收件箱, whichever box was left open.
      expect(repository.pmLoads, 2);
      expect(repository.lastBox, ForumPmBox.inbox);
      expect(
          tester
              .widget<SubTabs<ForumPmBox>>(find.byType(SubTabs<ForumPmBox>))
              .selected,
          ForumPmBox.inbox);

      watch.tapNotice(NoticeNotificationKind.reply);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      final replies = repository.replyLoads;
      watch.tapNotice(NoticeNotificationKind.reply);
      await tester.pumpAndSettle();
      expect(repository.replyLoads, replies + 1);
      expect(watch.pendingNoticeOpen, isNull);
    });

    testWidgets('a tap shows 消息 from under whatever was open on top',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final watch = FakeWatch();
      final repository = _Repo(watch);
      await tester
          .pumpWidget(MaterialApp(home: HomeShell(repository: repository)));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(HomeShell))).push(
          MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('on top'))));
      await tester.pumpAndSettle();

      watch.tapNotice(NoticeNotificationKind.reply);
      await tester.pumpAndSettle();
      expect(find.text('on top'), findsNothing);
      expect(selectedTab(tester), 1);
      expect(repository.replyLoads, 1);
    });

    testWidgets('a list on screen clears its own system notification',
        (tester) async {
      final shown = ValueNotifier(false);
      final repository = await pumpMessages(tester, FakeWatch(), shown: shown);
      // 消息 off screen clears nothing.
      expect(repository.cancelled, isEmpty);
      shown.value = true;
      await tester.pumpAndSettle();
      expect(repository.cancelled, [NoticeNotificationKind.pm]);
      await tester.tap(find.text('回复提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关注'));
      await tester.pumpAndSettle();
      expect(repository.cancelled,
          [NoticeNotificationKind.pm, NoticeNotificationKind.reply]);
    });

    testWidgets('a clearing the account no longer owns fails quietly',
        (tester) async {
      final watch = FakeWatch();
      final repository = _Repo(watch)
        ..nativeNotifications.error = StateError('stale owner');
      await tester.pumpWidget(
          MaterialApp(home: MessagesScreen(repository: repository)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回复提醒'));
      await tester.pumpAndSettle();
      expect(repository.cancelled,
          [NoticeNotificationKind.pm, NoticeNotificationKind.reply]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('开启 asks; after a refusal only 去设置 opens the settings',
        (tester) async {
      final notifications = _Notifications();
      final watch = FakeWatch(notifications: notifications)
        ..notificationPermission = WatchNotificationPermission.denied
        ..grantOnRequest = false;
      await pumpMessages(tester, watch);
      expect(find.text('系统通知未开启'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '开启'));
      await tester.pumpAndSettle();
      expect(notifications.settingsOpened, 0);
      await tester.tap(find.widgetWithText(TextButton, '去设置'));
      await tester.pumpAndSettle();
      expect(notifications.settingsOpened, 1);

      // Back from the settings with notifications on.
      watch
        ..notificationPermission = WatchNotificationPermission.granted
        ..notifyListeners();
      await tester.pumpAndSettle();
      expect(find.textContaining('系统通知未开启'), findsNothing);
    });

    testWidgets('开启 that is granted needs no settings', (tester) async {
      final watch = FakeWatch()
        ..notificationPermission = WatchNotificationPermission.denied;
      await pumpMessages(tester, watch);
      await tester.tap(find.widgetWithText(TextButton, '开启'));
      await tester.pumpAndSettle();
      expect(find.textContaining('系统通知未开启'), findsNothing);
    });
  });
}

class _Notifications extends WatchNotifications {
  int settingsOpened = 0;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

class _Notices implements NativeNoticeNotifications {
  final cancelled = <NoticeNotificationKind>[];
  Object? error;

  @override
  Future<void> cancelKind(NoticeNotificationKind kind) async {
    cancelled.add(kind);
    if (error case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo extends ForumRepository {
  _Repo(this.fake);

  final FakeWatch fake;

  final epoch = ValueNotifier<int>(0);
  final _notices = _Notices();
  int pmLoads = 0;
  ForumPmBox? lastBox;
  int replyLoads = 0;

  List<NoticeNotificationKind> get cancelled => _notices.cancelled;

  @override
  _Notices get nativeNotifications => _notices;

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  WatchService get watch => fake;

  @override
  bool get isLoggedIn => true;

  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity =>
      ValueNotifier(const ForumAccountIdentity(systemName: 'me', uid: '101'));

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    lastBox = box;
    if (box == ForumPmBox.inbox && pagePath == null) pmLoads++;
    return ForumPmPage(box: box, messages: const []);
  }

  @override
  Future<List<ForumReplyNotice>> fetchReplyNotices() async {
    replyLoads++;
    return const [];
  }

  // An opened 动态's thread never finishes loading here.
  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread, {int page = 1}) =>
      Completer<ThreadDetail>().future;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<ForumHomeSnapshot> fetchHome() async =>
      const ForumHomeSnapshot(latest: [], hot: [], sections: []);

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}
