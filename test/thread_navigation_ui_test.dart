import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/thread_paging_settings.dart';

// Synthetic fixtures only: fictional host, tid, pids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _thread = ForumThread(title: 'nav', url: _url, replies: 0, section: '');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeRepository> pumpThread(
    WidgetTester tester, {
    String url = _url,
    bool autoLoad = true,
    _FakeRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository ??= _FakeRepository();
    if (autoLoad) await ThreadPagingSettings.save(true);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: repository,
        thread: _thread.copyWith(url: url),
      ),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  ScrollPosition list(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(Scrollable).first, Offset(0, -dy));
    await tester.pumpAndSettle();
  }

  testWidgets('auto-loading is off by default, including the bottom shortcut', (
    tester,
  ) async {
    final repository = await pumpThread(tester, autoLoad: false);
    await tester.tap(find.byTooltip('到底部'));
    await tester.pumpAndSettle();
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(Scrollable).first),
        scrollDelta: const Offset(0, 300),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.pages, [1]);
  });

  testWidgets('a wheel turn at the very end appends the next page',
      (tester) async {
    final repository = await pumpThread(tester);
    // Reach the end without the reader scrolling, as a programmatic jump does.
    final position = list(tester);
    for (var i = 0;
        i < 100 && position.pixels != position.maxScrollExtent;
        i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(repository.pages, [1]);
    expect(position.pixels, position.maxScrollExtent);
    // At the end the wheel moves nothing, yet asks for more.
    tester.binding.handlePointerEvent(PointerScrollEvent(
      position: tester.getCenter(find.byType(Scrollable).first),
      scrollDelta: const Offset(0, 300),
    ));
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 2]);
  });

  testWidgets('到底部 appends the next page', (tester) async {
    final repository = await pumpThread(tester);
    await tester.tap(find.byTooltip('到底部'));
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 2]);
  });

  testWidgets('buying on an appended page refreshes that page in place', (
    tester,
  ) async {
    final repository = await pumpThread(tester);
    await tester.tap(find.byTooltip('到底部'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('购买查看').hitTestable(), 300);
    final floorY = tester.getTopLeft(find.text('[B31F]')).dy;
    await tester.tap(find.text('购买查看'));
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 2, 2]);
    expect(find.text('unlocked paid content').hitTestable(), findsOneWidget);
    expect(find.text('购买查看'), findsNothing);
    expect(find.text('[B31F]'), findsOneWidget);
    expect(tester.getTopLeft(find.text('[B31F]')).dy, closeTo(floorY, 1));
    await tester.scrollUntilVisible(find.text('[B1F]'), -300);
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 2, 2], reason: 'page 1 remains loaded');
    expect(find.text('[B1F]').hitTestable(), findsOneWidget);
  });

  for (final reverseResponses in [false, true]) {
    testWidgets('two purchases retain both unlocks (reversed refreshes: $reverseResponses)',
        (tester) async {
      final repository = _FakeRepository(twoSales: true)..delayBuys = true;
      await pumpThread(tester, repository: repository);
      await tester.tap(find.byTooltip('到底部'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('购买查看').first.hitTestable(), 300);
      await tester.tap(find.text('购买查看').first);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('购买查看').hitTestable(), 100);
      await tester.tap(find.text('购买查看'));
      await tester.pump();
      expect(repository.heldPurchases.keys, containsAll(['/buy', '/buy-b']));

      repository.hold = reverseResponses;
      repository.heldPurchases['/buy']!.complete(
          const ReplyResult(success: true, message: 'purchase A'));
      for (var i = 0; i < 3; i++) { await tester.pump(); }
      final earlierResponse = repository.page(2);
      expect(repository.pages, [1, 2, 2]);
      repository.heldPurchases['/buy-b']!.complete(
          const ReplyResult(success: true, message: 'purchase B'));
      for (var i = 0; i < 3; i++) { await tester.pump(); }
      if (reverseResponses) {
        expect(repository.held, hasLength(2));
        repository.held.last.complete(repository.page(2));
        for (var i = 0; i < 3; i++) { await tester.pump(); }
        repository.held.first.complete(earlierResponse);
      }
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('[B31F]'), -200);
      await tester.pumpAndSettle();
      // Scrolling may also append page 3; page 2 is refetched once per buy.
      expect(repository.pages.take(4), [1, 2, 2, 2]);
      expect(repository.pages.where((p) => p == 2), hasLength(3));
      expect(find.text('unlocked both purchases'), findsOneWidget);
      expect(find.text('购买查看'), findsNothing);
    });
  }

  testWidgets('the resume notice auto-hides and closes with the thread',
      (tester) async {
    await _FakeRepository().saveThreadReadPosition(
      _thread,
      const ThreadReadPosition(page: 2, anchor: '1040'),
    );
    await pumpThread(tester);
    expect(find.textContaining('已回到上次阅读位置'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('已回到上次阅读位置'), findsNothing);
  });

  testWidgets(
      'the resume notice stays with its thread, even behind another notice',
      (tester) async {
    await _FakeRepository().saveThreadReadPosition(
      _thread,
      const ThreadReadPosition(page: 2, anchor: '1040'),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('home')),
    ));
    // A long-lived notice from the previous screen is still up.
    ScaffoldMessenger.of(navigator.currentContext!).showSnackBar(
      const SnackBar(content: Text('home notice'), duration: Duration(days: 1)),
    );
    await tester.pumpAndSettle();

    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) =>
          ThreadDetailScreen(repository: _FakeRepository(), thread: _thread),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('已回到上次阅读位置'), findsOneWidget);

    // Leaving at once neither throws nor touches the other notice.
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('elsewhere')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('elsewhere'), findsOneWidget);
    expect(find.textContaining('已回到上次阅读位置'), findsNothing);
    navigator.currentState!.pop();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('home notice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reading to the end appends the following pages', (tester) async {
    final repository = await pumpThread(tester);
    expect(repository.pages, [1], reason: 'opening loads one page');

    for (var i = 0; i < 40 && repository.pages.length < 2; i++) {
      await scrollBy(tester, 2000);
    }
    // A fling may carry on into page 2's own end zone.
    expect(repository.pages.take(2), [1, 2]);
    await tester.scrollUntilVisible(find.text('第 2 页'), -300);
    await tester.scrollUntilVisible(find.text('[B31F]'), 300);

    for (var i = 0; i < 60 && find.text('已到最后一页').evaluate().isEmpty; i++) {
      await scrollBy(tester, 2000);
    }
    expect(repository.pages, [1, 2, 3]);
    expect(find.text('已到最后一页'), findsOneWidget);
  });

  testWidgets('stopping saves the post at the top; reopening resumes there',
      (tester) async {
    final repository = await pumpThread(tester);
    await tester.scrollUntilVisible(find.text('[B12F]'), 300);
    // Align B12F's header with the top edge; its post is the top one.
    await Scrollable.ensureVisible(tester.element(find.text('[B12F]')));
    await tester.pumpAndSettle();
    final saved = await repository.loadThreadReadPosition(_thread);
    expect(saved?.page, 1);
    expect(saved?.anchor, '1012');

    await tester.pumpWidget(const SizedBox());
    final reopened = _FakeRepository();
    await pumpThread(tester, repository: reopened);
    expect(reopened.urls, [_url]);
    expect(find.text('[B12F]').hitTestable(), findsOneWidget);
    expect(find.textContaining('已回到上次阅读位置'), findsOneWidget);
  });

  testWidgets('a saved later page resumes there and 从头看 returns to the start',
      (tester) async {
    await _FakeRepository().saveThreadReadPosition(
      _thread,
      const ThreadReadPosition(page: 2, anchor: '1040'),
    );
    final repository = await pumpThread(tester);
    expect(repository.pages, [2]);
    expect(find.text('[B40F]').hitTestable(), findsOneWidget);

    await tester.tap(find.text('从头看'));
    await tester.pumpAndSettle();
    expect(repository.pages, [2, 1]);
    expect(Uri.parse(repository.urls.last).fragment, 'tpc');
    expect(find.text('[楼主]').hitTestable(), findsOneWidget);
  });

  testWidgets('links to a floor or page ignore the saved position',
      (tester) async {
    await _FakeRepository().saveThreadReadPosition(
      _thread,
      const ThreadReadPosition(page: 2, anchor: '1040'),
    );
    final repository = await pumpThread(tester, url: '$_url#fl-20');
    expect(repository.pages, [1]);
    expect(find.text('[B20F]').hitTestable(), findsOneWidget);
    expect(find.textContaining('已回到上次阅读位置'), findsNothing);

    for (final url in [
      'https://south-plus.net/read.php?tid-7-page-1.html',
      'https://south-plus.net/read.php?tid=7&page=2',
    ]) {
      await tester.pumpWidget(const SizedBox());
      final explicit = await pumpThread(tester, url: url);
      expect(explicit.urls, [url], reason: url);
      expect(find.textContaining('已回到上次阅读位置'), findsNothing);
    }
  });

  testWidgets('a failed reload does not leave the next page stuck',
      (tester) async {
    final repository = await pumpThread(tester);
    repository.hold = true;
    // The in-flight spinner never settles; pump fixed frames instead.
    for (var i = 0; i < 40 && repository.held.isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(repository.pages, [1, 2], reason: 'append of page 2 in flight');

    final staleAppend = repository.held.single;

    // The reader jumps to the latest page while page 2 loads; that fails.
    await tester.tap(find.byTooltip('最新回复'));
    await tester.pump();
    expect(repository.pages.last, 3);
    repository.held.last.completeError(StateError('offline'));
    await tester.pump(const Duration(seconds: 1));
    // The superseded append answers late and is dropped.
    staleAppend.complete(repository.page(2));
    await tester.pump(const Duration(seconds: 1));

    // Appends started since are answered; page 2 arrives again.
    repository.hold = false;
    for (final answer in repository.held.skip(2)) {
      answer.complete(repository.page(2));
    }
    await scrollBy(tester, 400);
    expect(repository.pages.skip(3), contains(2), reason: 'page 2 again');
    await tester.scrollUntilVisible(find.text('第 2 页'), -300);
  });

  testWidgets('the bottom pager returns to the first loaded page',
      (tester) async {
    final repository =
        await pumpThread(tester, repository: _FakeRepository(totalPages: 2));
    for (var i = 0; i < 40 && repository.pages.length < 2; i++) {
      await scrollBy(tester, 2000);
    }
    await tester.scrollUntilVisible(find.byTooltip('上一页'), 300);
    await tester.tap(find.byTooltip('上一页').last);
    await tester.pumpAndSettle();
    expect(list(tester).pixels, 0);
    expect(repository.pages, [1, 2]);
  });

  testWidgets('bottom bar: latest reply, first floor, top and bottom',
      (tester) async {
    final repository = await pumpThread(tester);

    await tester.tap(find.byTooltip('最新回复'));
    await tester.pumpAndSettle();
    expect(repository.urls.last, contains('page-e'));
    expect(find.text('[B90F]').hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip('回到顶部'));
    await tester.pumpAndSettle();
    expect(list(tester).pixels, 0);

    await tester.tap(find.byTooltip('到底部'));
    await tester.pumpAndSettle();
    expect(list(tester).pixels, list(tester).maxScrollExtent);

    await tester.tap(find.byTooltip('首楼'));
    await tester.pumpAndSettle();
    expect(repository.pages.last, 1);
    expect(find.text('[楼主]').hitTestable(), findsOneWidget);
  });
}

class _FakeRepository extends ForumRepository {
  _FakeRepository({this.totalPages = 3, this.twoSales = false});

  final int totalPages;
  final bool twoSales;
  bool delayBuys = false;
  final purchased = <String>{};
  final heldPurchases = <String, Completer<ReplyResult>>{};
  final urls = <String>[];
  final pages = <int>[];

  @override
  Future<ReplyResult> buySaleBox(ThreadSaleBox saleBox) async {
    final result = delayBuys
        ? await (heldPurchases[saleBox.buyPath] = Completer<ReplyResult>()).future
        : const ReplyResult(success: true, message: 'purchased');
    if (result.success) purchased.add(saleBox.buyPath);
    return result;
  }

  /// While set, requests wait in [held] until the test answers them.
  bool hold = false;
  final held = <Completer<ThreadDetail>>[];

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    urls.add(thread.url);
    final current = thread.url.contains('page-e') && page == 1 ? 3 : page;
    pages.add(current);
    if (hold) {
      final answer = Completer<ThreadDetail>();
      held.add(answer);
      return answer.future;
    }
    return this.page(current, url: thread.url);
  }

  ThreadDetail page(int current, {String url = _url}) {
    final first = (current - 1) * 30;
    return ThreadDetail(
      thread: ForumThread(
        title: 'nav',
        url: url,
        replies: 90,
        section: 'synthetic',
        author: 'op',
      ),
      body: current == 1 ? 'opening body' : '',
      bodyAnchors: current == 1 ? const ['tpc', 'fl-0'] : const [],
      pagination:
          ThreadPagination(currentPage: current, totalPages: totalPages),
      replies: [
        for (var floor = first + 1; floor <= first + 30; floor++)
          ThreadReply(
            author: 'user$floor',
            content: floor == 31 && purchased.isNotEmpty
                ? twoSales && purchased.length == 2
                    ? 'unlocked both purchases'
                    : 'unlocked paid content'
                : 'reply body $floor ' * 6,
            floor: 'B${floor}F',
            saleBoxes: floor == 31
                ? [
                    if (!purchased.contains('/buy'))
                      const ThreadSaleBox(summary: 'synthetic sale', buyPath: '/buy'),
                    if (twoSales && !purchased.contains('/buy-b'))
                      const ThreadSaleBox(summary: 'second synthetic sale', buyPath: '/buy-b'),
                  ]
                : const [],
            anchors: ['${1000 + floor}', 'read_${1000 + floor}', 'fl-$floor'],
          ),
      ],
    );
  }
}
