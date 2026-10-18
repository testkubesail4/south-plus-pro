import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
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
    expect(find.text('在已加载的 1 页中找到 0 条 · 共 3 页 · 待确认 1 条'), findsOneWidget);
    expect(find.text('已扫描 1/3 页，暂未找到匹配'), findsOneWidget);
    expect(find.text('没有符合条件的内容'), findsNothing);
    expect(find.text('第一页主题'), findsNothing);
    expect(find.text('待确认 (1)'), findsOneWidget);
    expect(find.text('无法确认的主题'), findsNothing);
    await tester.tap(find.text('待确认 (1)'));
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

  testWidgets('a title search narrows the loaded rows and scans nothing',
      (tester) async {
    final rows = [
      listItem('Alpha guide', tid: '1'),
      listItem('Beta notes', tid: '2'),
      listItem('Gamma lo..', tid: '3', truncated: true),
    ];
    // Scrolling to the end still loads the next page, as without a search.
    final repository = FakeProfileRepository(
        topics: rows, onContent: (_) async => contentResult(items: rows));
    await openTab(tester, repository, '主题');
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(find.text('Alpha guide'), findsOneWidget);
    expect(find.text('Beta notes'), findsNothing);
    // A cut title that misses the keyword is undecided, not a miss.
    expect(find.text('待确认 (1)'), findsOneWidget);
    expect(repository.scans, isEmpty);
    expect(repository.queries.every((query) => query.keyword.isEmpty), isTrue);
  });

  testWidgets(
      'every page is read only when asked, from the unfiltered rows, until the keyword changes',
      (tester) async {
    final rows = [
      listItem('Alpha guide', tid: '1'),
      listItem('Beta', tid: '2')
    ];
    final repository = FakeProfileRepository(
        topics: rows, onContent: (_) async => contentResult(items: rows));
    await openTab(tester, repository, '主题');
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索全部页面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始搜索'));
    // A running scan's bar keeps animating.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final asked = repository.scans.single;
    expect(asked.query.keyword, 'alpha');
    expect(asked.loaded, rows, reason: 'scope rows, before the keyword');
    expect(asked.loadedPages, 1);
    asked.scan.finish([
      const UserListItem(
          title: 'Alpha later', url: 'read.php?tid-7.html', sourcePage: 2),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 页'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);

    await tester.enterText(find.byType(TextField), 'alph');
    await tester.pumpAndSettle();
    expect(asked.scan.disposed, isTrue);
    expect(find.text('Alpha guide'), findsOneWidget);
  });

  for (final leave in ['another tab', 'another page']) {
    testWidgets('$leave stops the scan, keeping its rows', (tester) async {
      final rows = [listItem('Alpha guide', tid: '1')];
      final repository = FakeProfileRepository(
          topics: rows, onContent: (_) async => contentResult(items: rows));
      await openTab(tester, repository, '主题');
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索全部页面'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始搜索'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final scan = repository.scans.single.scan;

      if (leave == 'another tab') {
        // As a swipe does; the tab bar may have scrolled away with the header.
        DefaultTabController.of(tester.element(find.byType(TabBarView)))
            .animateTo(UserProfileTab.posts.index);
      } else {
        Navigator.of(tester.element(find.byType(UserProfileScreen))).push(
          MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('a thread'))),
        );
      }
      await tester.pumpAndSettle();
      expect(scan.stopped, isTrue);
      expect(scan.disposed, isFalse);
    });
  }

  testWidgets('typing while a filtered page loads keeps that page',
      (tester) async {
    final page = Completer<UserContentResult>();
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) => page.future,
    );
    await openTab(tester, repository, '主题');
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump();
    page.complete(contentResult(
        items: [listItem('Alpha arrived', tid: '5')], hasMore: true));
    await tester.pumpAndSettle();
    expect(find.text('Alpha arrived'), findsOneWidget);
    expect(find.text('继续查找'), findsOneWidget, reason: 'not stuck loading');
  });

  testWidgets('a page loaded while asking is part of what the scan is given',
      (tester) async {
    final answers = [
      Completer<UserContentResult>(),
      Completer<UserContentResult>(),
    ];
    var asked = 0;
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) => answers[asked++].future,
    );
    await openTab(tester, repository, '主题');
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pump();
    // Loading spinners keep animating: step instead of settling.
    Future<void> step() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    answers[0].complete(contentResult(
        items: [listItem('Alpha one', tid: '5')], scanned: 1, total: 3));
    await step();
    await tester.enterText(find.byType(TextField), 'alpha');
    await step();
    // Page 2 is asked for, by 继续查找 or by scrolling to the end.
    if (asked < 2) {
      await tester.ensureVisible(find.text('继续查找'));
      await tester.tap(find.text('继续查找'));
      await step();
    }
    expect(asked, 2);
    await tester.ensureVisible(find.text('搜索全部页面'));
    await tester.tap(find.text('搜索全部页面'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Page 2 arrives while the confirmation is open.
    answers[1].complete(contentResult(items: [
      listItem('Alpha one', tid: '5'),
      listItem('Alpha two', tid: '6'),
    ], scanned: 2, total: 3));
    await tester.pump();
    await tester.tap(find.text('开始搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final scan = repository.scans.single;
    expect(scan.loadedPages, 2);
    expect(scan.loaded!.map((item) => item.title), ['Alpha one', 'Alpha two']);
  });

  testWidgets('an empty first page the profile counts as all there is',
      (tester) async {
    final repository = FakeProfileRepository(
      pagination: const {
        UserProfileTab.topics: ThreadPagination(currentPage: 1, totalPages: 1),
      },
      onContent: (_) async => contentResult(),
    );
    await openTab(tester, repository, '主题');
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('在已加载的 1 页中找到 0 条'), findsOneWidget);
    expect(find.text('搜索全部页面'), findsNothing);
    expect(find.text('没有符合条件的内容'), findsOneWidget);
  });

  testWidgets('a search category is no board to filter by', (tester) async {
    final repository = FakeProfileRepository(
      favorites: [listItem('Saved', tid: '1')],
      onContent: (_) async => contentResult(),
    )..boards = const [
        ForumSearchBoard(id: 'all', name: '全部版块'),
        // A category id the search form takes; no board has it as fid.
        ForumSearchBoard(id: '2', name: '>> 范围类别'),
        ForumSearchBoard(id: '7', name: '|- 影视区', depth: 1),
      ];
    await openTab(tester, repository, '收藏');
    await tester.tap(find.text('版块：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-filter-group:2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-filter:7')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-filter:2')), findsNothing);
  });

  testWidgets('favourites filter by board and classification, not type',
      (tester) async {
    final repository = FakeProfileRepository(
      favorites: [listItem('Saved', tid: '1')],
      onContent: (_) async => contentResult(),
    );
    await openTab(tester, repository, '收藏');
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('版块：全部'), findsOneWidget);
    expect(find.text('类型：全部'), findsNothing);
    expect(find.widgetWithText(TextField, '搜索收藏标题'), findsOneWidget);
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

    await tester.tap(find.text('待确认 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsOneWidget);

    // The group is expanded while its width and text scale change.
    tester.view.physicalSize = const Size(420, 1400);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('待确认 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsNothing);
    await tester.tap(find.text('待确认 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('无法确认的主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
