import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_sale_box_view.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/thread_paging_settings.dart';

// Synthetic fixtures only: fictional tid, uids and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _box = ThreadSaleBox(
  summary: '售价 1 SP币',
  buyPath: 'job.php?action-buy-tid-7.html',
  price: 1,
);
String _profile(int uid) =>
    'https://south-plus.net/u.php?action-show-uid-$uid.html';

String _lines(String name, int count) =>
    [for (var i = 0; i < count; i++) '$name $i'].join('\n');

class _Repo extends ForumRepository {
  _Repo({this.boxLast = false, this.lines = 30, this.boxOnPage2 = false});

  final bool boxLast;
  final int lines;

  /// The paid floor sits on page 2 of 2 (appended below page 1).
  final bool boxOnPage2;

  /// Whether pages show the paid content (the server unlocked it).
  bool unlocked = false;

  /// What a purchase does to the server's pages.
  bool unlockOnBuy = true;

  /// The unlocked page starts with the native sale header; false: with two
  /// ordinary quotes that merely follow where the box was.
  bool nativeHeader = true;
  bool buyThrows = false;
  int buys = 0;
  final pages = <int>[];

  /// Each queued gate holds the next page fetch made, in call order.
  final fetchGates = <Completer<void>>[];

  /// The last line of the paid floor; read when a fetch starts.
  String tail = 'tail line';

  final epoch = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
    ForumThread t,
    ThreadReadPosition p,
  ) async {}

  @override
  Future<ReplyResult> buySaleBox(ThreadSaleBox saleBox) async {
    buys++;
    if (buyThrows) throw StateError('断网');
    if (unlockOnBuy) unlocked = true;
    return const ReplyResult(success: true, message: '购买完成');
  }

  ThreadReply _floor(
    String floor,
    int uid,
    List<ThreadContentSegment> segments, {
    List<ThreadSaleBox> boxes = const [],
  }) =>
      ThreadReply(
        author: '用户$uid',
        authorUrl: _profile(uid),
        content: 'content',
        segments: segments,
        saleBoxes: boxes,
        floor: floor,
        postedAt: '2026-10-12 10:20',
        quoteUrl: 'post.php?action-quote-tid-7-pid-$floor.html',
      );

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    pages.add(page);
    final tailLine = tail;
    if (fetchGates.isNotEmpty) await fetchGates.removeAt(0).future;
    final tall = [ThreadContentSegment.text(_lines('floor', 25))];
    final paid = _floor(
      'B2F',
      5,
      [
        ThreadContentSegment.text(_lines('intro', lines)),
        if (unlocked) ...[
          ThreadContentSegment.quote([
            ThreadContentSegment.text(
              nativeHeader ? '售价 1 SP币 header line' : 'announcement',
            ),
          ]),
          ThreadContentSegment.quote(
            [ThreadContentSegment.text(_lines('paid', 12))],
          ),
        ] else
          const ThreadContentSegment.saleBox(_box),
        ThreadContentSegment.text(tailLine),
      ],
      boxes: unlocked ? const [] : const [_box],
    );
    final replies = boxOnPage2
        ? (page == 1
            ? [_floor('B1F', 4, tall)]
            : [_floor('B3F', 6, tall), paid])
        : [
            _floor('B1F', 4, tall),
            if (!boxLast) paid,
            _floor('B3F', 6, tall),
            if (boxLast) paid,
          ];
    return ThreadDetail(
      thread: thread.copyWith(
        title: '合成主题',
        author: '楼主甲',
        authorUrl: _profile(3),
      ),
      body: 'opening body',
      replies: replies,
      pagination: ThreadPagination(
        currentPage: page,
        totalPages: boxOnPage2 ? 2 : 1,
      ),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpThread(WidgetTester tester, _Repo repo) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
        repository: repo,
        thread:
            const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final boxView = find.byType(ThreadSaleBoxView);
  final header = find.textContaining('header line', findRichText: true);

  Future<void> bringBoxIntoView(WidgetTester tester,
      {bool bottom = false}) async {
    if (bottom) {
      // Rows are built lazily, so the extent grows while scrolling: drag
      // until the end stops moving.
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      for (var i = 0; i < 10; i++) {
        final before = position.pixels;
        await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
        await tester.pumpAndSettle();
        if (position.pixels == before) break;
      }
    } else {
      await tester.dragUntilVisible(
        boxView,
        find.byType(ListView).first,
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
    }
    expect(boxView, findsOneWidget);
    expect(tester.getTopLeft(boxView).dy, lessThan(800));
  }

  /// Buys and returns the header's top at the first, a middle and the last
  /// frame of the reveal.
  Future<List<double>> buyAndTrack(WidgetTester tester) async {
    await tester.tap(find.text('购买查看'));
    for (var i = 0; i < 20 && header.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(header, findsOneWidget);
    final first = tester.getTopLeft(header).dy;
    await tester.pump(const Duration(milliseconds: 100));
    final middle = tester.getTopLeft(header).dy;
    await tester.pumpAndSettle();
    return [first, middle, tester.getTopLeft(header).dy];
  }

  for (final bottom in [false, true]) {
    testWidgets(
        'the unlocked box keeps its place on screen '
        '(${bottom ? 'list end' : 'mid list'})', (tester) async {
      // At the end the paid floor is short, so the box sits near the bottom.
      final repo = _Repo(boxLast: bottom, lines: bottom ? 3 : 30);
      await pumpThread(tester, repo);
      await bringBoxIntoView(tester, bottom: bottom);
      final boxTop = tester.getTopLeft(boxView).dy;

      final tops = await buyAndTrack(tester);

      for (final top in tops) {
        // The header takes the box's place (its own padding is a few px).
        expect(top, closeTo(boxTop, 14));
        expect(top, closeTo(tops.first, 0.5));
      }
      expect(repo.buys, 1);
      expect(boxView, findsNothing);
      expect(find.byType(ThreadPurchaseReveal), findsOneWidget);
    });
  }

  testWidgets('two ordinary quotes after the box are not a reveal',
      (tester) async {
    final repo = _Repo()..nativeHeader = false;
    await pumpThread(tester, repo);
    await bringBoxIntoView(tester);

    await tester.tap(find.text('购买查看'));
    await tester.pumpAndSettle();

    expect(boxView, findsNothing);
    expect(find.text('announcement', findRichText: true), findsOneWidget);
    expect(find.byType(ThreadPurchaseReveal), findsNothing);
  });

  testWidgets('a paid box whose page still shows it locked cannot buy again',
      (tester) async {
    final repo = _Repo()..unlockOnBuy = false;
    await pumpThread(tester, repo);
    await bringBoxIntoView(tester);

    await tester.tap(find.text('购买查看'));
    await tester.pumpAndSettle();
    expect(repo.buys, 1);
    expect(find.text('购买查看'), findsNothing);
    expect(find.text('刷新页面'), findsOneWidget);

    // The only action left is a read-only refresh.
    repo.pages.clear();
    await tester.tap(find.text('刷新页面'));
    await tester.pumpAndSettle();
    expect(repo.pages, [1]);
    expect(repo.buys, 1);
    expect(find.text('购买查看'), findsNothing);
  });

  testWidgets('an unconfirmed purchase stays read-only, even after a refresh',
      (tester) async {
    final repo = _Repo()..buyThrows = true;
    await pumpThread(tester, repo);
    await bringBoxIntoView(tester);

    await tester.tap(find.text('购买查看'));
    await tester.pumpAndSettle();
    expect(repo.buys, 1);
    expect(find.text('购买查看'), findsNothing);

    repo.pages.clear();
    await tester.tap(find.text('刷新页面'));
    await tester.pumpAndSettle();
    expect(repo.pages, [1]);
    // The page still shows the box: say so, and never offer a purchase.
    expect(find.textContaining('页面仍显示未购买'), findsOneWidget);
    expect(find.text('购买查看'), findsNothing);
    expect(repo.buys, 1);
  });

  testWidgets('a box on an appended page refreshes that page, not page 1',
      (tester) async {
    await ThreadPagingSettings.save(true);
    final repo = _Repo(boxOnPage2: true)..buyThrows = true;
    await pumpThread(tester, repo);
    // 自动加载下一页 appends page 2 by itself near the end of page 1.
    await tester.drag(find.byType(ListView).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(repo.pages, [1, 2]);
    await bringBoxIntoView(tester);

    await tester.tap(find.text('购买查看'));
    await tester.pumpAndSettle();
    repo.pages.clear();
    await tester.tap(find.text('刷新页面'));
    await tester.pumpAndSettle();

    expect(repo.pages, [2]);
    expect(repo.buys, 1);
    expect(find.text('购买查看'), findsNothing);
  });

  testWidgets('a purchased page that arrives after a session switch is dropped',
      (tester) async {
    final repo = _Repo();
    await pumpThread(tester, repo);
    await bringBoxIntoView(tester);

    final gate = Completer<void>();
    repo.fetchGates.add(gate);
    await tester.tap(find.text('购买查看'));
    await tester.pump();
    await tester.pump();
    expect(repo.buys, 1);

    // Another account takes over while the paid page is still loading.
    repo.epoch.value++;
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();

    expect(header, findsNothing);
    expect(find.byType(ThreadPurchaseReveal), findsNothing);
  });

  testWidgets('a purchased page overtaken by a pull-to-refresh is dropped',
      (tester) async {
    final repo = _Repo();
    await pumpThread(tester, repo);
    await bringBoxIntoView(tester);

    // The paid page is requested and held; its content is fixed right now.
    final gate = Completer<void>();
    repo.fetchGates.add(gate);
    await tester.tap(find.text('购买查看'));
    await tester.pump();
    await tester.pump();
    expect(repo.buys, 1);

    // The reader pulls to refresh from the top; that answer comes first.
    repo.tail = 'newer tail';
    await tester.drag(find.byType(ListView).first, const Offset(0, 20000));
    // The held purchase keeps its spinner turning: pump, never settle.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(repo.pages.length, 3);

    // The overtaken answer arrives late and must change nothing.
    gate.complete();
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('newer tail', findRichText: true),
      find.byType(ListView).first,
      const Offset(0, -150),
    );
    expect(find.text('newer tail', findRichText: true), findsOneWidget);
    expect(find.text('tail line', findRichText: true), findsNothing);
    expect(find.byType(ThreadPurchaseReveal), findsNothing);
  });
}
