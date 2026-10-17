import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/user_content_query.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

import 'profile_appendfix_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openTab(
    WidgetTester tester,
    FakeProfileRepository repository,
    String tab,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(
        userUrl: profileFixture.url,
        repository: repository,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab));
    await tester.pumpAndSettle();
  }

  testWidgets('unfiltered tab shows the loaded page and scans nothing',
      (tester) async {
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) async => contentResult(),
    );
    await openTab(tester, repository, '主题');

    expect(find.text('第一页主题'), findsOneWidget);
    expect(find.text('加载更多'), findsOneWidget);
    expect(repository.queries, isEmpty);
    expect(repository.boardLoads, 0);
  });

  testWidgets(
      'an incomplete filtered scan is never reported as empty, unresolved rows stay visible',
      (tester) async {
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
    );
    final answers = [
      contentResult(
        unresolved: [listItem('无法确认的主题', tid: '9')],
        checked: 1,
      ),
      contentResult(
        items: [listItem('精华主题', tid: '5')],
        unresolved: [listItem('无法确认的主题', tid: '9')],
        scanned: 3,
        hasMore: false,
        checked: 2,
      ),
    ];
    repository.onContent = (_) async => answers.removeAt(0);
    await openTab(tester, repository, '主题');

    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();

    expect(
        repository.queries.single.articleType, UserContentArticleType.digest);
    expect(find.text('已扫描 1/3 页 · 已核对 1 帖 · 待确认 1 条'), findsOneWidget);
    expect(find.text('已扫描 1/3 页，暂未找到匹配'), findsOneWidget);
    expect(find.text('没有符合条件的内容'), findsNothing);
    expect(find.text('第一页主题'), findsNothing);
    expect(find.text('未确认分类 (1)'), findsOneWidget);
    expect(find.text('无法确认的主题'), findsNothing);
    await tester.tap(find.text('未确认分类 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsOneWidget);

    await tester.ensureVisible(find.text('继续查找'));
    await tester.tap(find.text('继续查找'));
    await tester.pumpAndSettle();
    expect(repository.queries, hasLength(2));
    expect(repository.queries.last.cacheKey, repository.queries.first.cacheKey);
    expect(find.text('精华主题'), findsOneWidget);
    expect(find.text('已查完，另有 1 条无法确认'), findsOneWidget);
    expect(find.text('继续查找'), findsNothing);
  });

  testWidgets('complete scan without matches or unresolved rows says empty',
      (tester) async {
    final repository = FakeProfileRepository(
      posts: [listItem('回复', tid: '1', pid: '10')],
      onContent: (_) async => contentResult(scanned: 3, hasMore: false),
    );
    await openTab(tester, repository, '回复');
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交易'));
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的内容'), findsOneWidget);
    expect(find.text('已到最后一页'), findsOneWidget);
  });

  testWidgets('a result from a superseded selection is dropped',
      (tester) async {
    final first = Completer<UserContentResult>();
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
    );
    repository.onContent = (query) =>
        query.articleType == UserContentArticleType.digest
            ? first.future
            : Future.value(contentResult(items: [listItem('投票主题', tid: '6')]));
    await openTab(tester, repository, '主题');

    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pump();
    expect(find.text('正在查找…'), findsWidgets);

    // The superseded digest query is still pending, so its spinner keeps
    // animating: pump bounded durations instead of settling.
    await tester.tap(find.text('类型：精华'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('投票'), findsOneWidget, reason: 'type menu is open');
    await tester.tap(find.text('投票'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('投票主题'), findsOneWidget);
    first.complete(contentResult(items: [listItem('精华主题', tid: '5')]));
    await tester.pumpAndSettle();

    expect(find.text('投票主题'), findsOneWidget);
    expect(find.text('精华主题'), findsNothing);
  });

  testWidgets('classification needs a board and resets when the board changes',
      (tester) async {
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) async => contentResult(items: [listItem('命中', tid: '2')]),
    );
    await openTab(tester, repository, '主题');

    await tester.tap(find.text('分类：全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部分类'), findsNothing, reason: 'disabled without board');

    await tester.tap(find.text('版块：全部'));
    await tester.pumpAndSettle();
    expect(find.text('综合区'), findsOneWidget);
    expect(find.text('影视区'), findsNothing, reason: 'folded under its section');
    await tester.tap(find.text('综合区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('影视区'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.boardId, '7');

    await tester.tap(find.text('分类：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('求助'));
    await tester.pumpAndSettle();
    expect(repository.queries.last.classificationId, '3');
    expect(find.text('分类：求助'), findsOneWidget);

    await tester.tap(find.text('版块：影视区'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部版块'));
    await tester.pumpAndSettle();
    expect(find.text('分类：全部'), findsOneWidget);
    expect(find.text('第一页主题'), findsOneWidget, reason: 'default list again');
  });

  testWidgets('a failed step keeps earlier matches and offers a retry',
      (tester) async {
    var calls = 0;
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
    );
    repository.onContent = (_) async {
      calls++;
      if (calls == 2) {
        throw const ForumRequestException(ForumRequestKind.network, 'offline');
      }
      return contentResult(items: [listItem('已找到', tid: '2')]);
    };
    await openTab(tester, repository, '主题');
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('继续查找'));
    await tester.tap(find.text('继续查找'));
    await tester.pumpAndSettle();
    expect(find.text('查找失败：网络失败'), findsOneWidget);
    expect(find.text('已找到'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('查找失败：网络失败'), findsNothing);
    expect(calls, 3);
  });

  testWidgets('several replies in one thread stay separate rows',
      (tester) async {
    final repository = FakeProfileRepository(
      posts: [
        listItem('同一帖', tid: '1', pid: '10'),
        listItem('同一帖', tid: '1', pid: '11'),
      ],
      onContent: (_) async => contentResult(),
    );
    await openTab(tester, repository, '回复');
    expect(find.text('同一帖'), findsNWidgets(2));
  });

  testWidgets(
      'every refresh restarts the active query with fresh service state and keeps the selectors',
      (tester) async {
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) async => contentResult(items: [listItem('命中', tid: '2')]),
    );
    await openTab(tester, repository, '主题');
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();
    expect(repository.refreshes, [false]);

    // The cached overview paints at once while the details refresh is slow.
    final hold = repository.holdDetails = Completer<void>();
    final first = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
        .show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    repository.holdDetails = null;
    hold.complete();
    await tester.pumpAndSettle();
    await first;
    expect(repository.queries, hasLength(2));
    expect(repository.refreshes.last, isTrue);
    expect(repository.queries.last.articleType, UserContentArticleType.digest);
    expect(find.text('类型：精华'), findsOneWidget, reason: 'selector kept');
    expect(find.text('命中'), findsOneWidget);

    // A second refresh is a new generation, not the same flag again.
    final second = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator).first)
        .show();
    await tester.pumpAndSettle();
    await second;
    expect(repository.queries, hasLength(3));
    expect(repository.refreshes.last, isTrue);
  });

  testWidgets(
      'reduced motion: resizing and rescaling an expanded unresolved group never mutates a zero-duration AnimatedSize',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) async => contentResult(
        unresolved: [listItem('无法确认的主题', tid: '9')],
        hasMore: false,
      ),
    );
    await openTab(tester, repository, '主题');
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('未确认分类 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsOneWidget);

    // The group is expanded while its width and text scale change.
    tester.view.physicalSize = const Size(420, 1400);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('未确认分类 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsNothing);
    await tester.tap(find.text('未确认分类 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
