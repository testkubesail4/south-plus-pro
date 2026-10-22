import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/messages/messages_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/watch/watch_rule_sheet.dart';
import 'package:south_plus_rewrite/features/watch/watch_tab.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
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

    testWidgets('no rules says where to add one', (tester) async {
      await pumpTab(tester, FakeWatch());
      expect(find.text('还没有关注'), findsOneWidget);
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
      // The limits and what is never checked are disclosed.
      expect(find.textContaining('App 在后台或被关闭时不检查，不保证即时通知'), findsOneWidget);
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

    testWidgets('denied notifications offer 开启', (tester) async {
      final watch = FakeWatch(rules: [_rule('a')])
        ..notificationPermission = WatchNotificationPermission.denied;
      await pumpTab(tester, watch, rules: true);
      await tester.tap(find.widgetWithText(TextButton, '开启'));
      await tester.pumpAndSettle();
      expect(find.textContaining('系统通知未开启'), findsNothing);
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
}

class _Repo extends ForumRepository {
  _Repo(this.fake);

  final FakeWatch fake;

  final epoch = ValueNotifier<int>(0);

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
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async =>
      ForumPmPage(box: box, messages: const []);

  @override
  Future<List<ForumReplyNotice>> fetchReplyNotices() async => const [];

  // An opened 动态's thread never finishes loading here.
  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread, {int page = 1}) =>
      Completer<ThreadDetail>().future;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;
}
