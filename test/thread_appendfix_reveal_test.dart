import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/thread/thread_render_models.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/features/thread/thread_sale_box_view.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';

// Synthetic fixtures only.
const _path = 'job.php?action-buy-tid-1.html';
const _box = ThreadSaleBox(summary: '售价 1 SP币', buyPath: _path, price: 1);
const _otherBox = ThreadSaleBox(
  summary: '售价 2 SP币',
  buyPath: 'job.php?action-buy-tid-2.html',
  price: 2,
  buyers: 3,
);

ThreadContentSegment _t(String text) => ThreadContentSegment.text(text);
ThreadContentSegment _q(String text) => ThreadContentSegment.quote([_t(text)]);

// The native header the unlocked page keeps: it states the box's own price.
ThreadContentSegment _head() => _q('售价 1 SP币 已有 4 人购买');

ThreadPostRenderModel _model(List<ThreadContentSegment> segments) =>
    ThreadPostRenderModel.fromSegments(segments);

Set<String> _paths(
        List<ThreadContentSegment> before, List<ThreadContentSegment> after) =>
    purchaseRevealPaths(_model(before), _model(after), buyPath: _path);

const _lockedBox = ThreadContentSegment.saleBox(_box);

final _locked = _model([_t('before'), _lockedBox, _t('after')]);
// The unlocked page: the same header, then the paid box, as quotes.
final _unlocked = _model([
  _t('before'),
  _head(),
  _q('paid body'),
  _t('after'),
]);

Widget _host(
  ThreadPostRenderModel model, {
  Set<String>? played,
  Set<String> paths = const {},
  bool reduceMotion = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ThreadPurchaseScope(
          postKey: 'p',
          revealPaths: paths,
          played: played ?? <String>{},
          notices: const {},
          child: ThreadRichContent.renderModel(renderModel: model),
        ),
      ),
    ),
  );
}

void main() {
  group('purchaseRevealPaths', () {
    test('marks the paid content after the header, not the header', () {
      expect(
        purchaseRevealPaths(_locked, _unlocked, buyPath: _path),
        {'2'},
      );
    });

    test('finds the box nested in a block', () {
      expect(
        _paths([
          _t('a'),
          ThreadContentSegment.block([_t('inner'), _lockedBox]),
        ], [
          _t('a'),
          ThreadContentSegment.block([_t('inner'), _head(), _q('paid')]),
        ]),
        {'1/2'},
      );
    });

    test('nothing while the box is still locked or when nothing changed', () {
      expect(purchaseRevealPaths(_locked, _locked, buyPath: _path), isEmpty);
      expect(
          purchaseRevealPaths(_unlocked, _unlocked, buyPath: _path), isEmpty);
    });

    test('another box, or no such box, reveals nothing', () {
      expect(
        purchaseRevealPaths(_locked, _unlocked, buyPath: 'other'),
        isEmpty,
      );
    });

    test('an unrelated quote added after the paid box is not revealed', () {
      expect(
        _paths([_t('a'), _lockedBox, _t('z')],
            [_t('a'), _head(), _q('paid'), _q('unrelated'), _t('z')]),
        isEmpty,
      );
    });

    test('two ordinary quotes are not the native header and paid box', () {
      expect(
        _paths([_t('a'), _lockedBox, _t('z')],
            [_t('a'), _q('announcement'), _q('unrelated'), _t('z')]),
        isEmpty,
      );
      // A header naming another price is not this box's header either.
      expect(
        _paths([_t('a'), _lockedBox, _t('z')],
            [_t('a'), _q('售价 9 SP币'), _q('paid'), _t('z')]),
        isEmpty,
      );
    });

    test('a changed block before the box makes the diff ambiguous', () {
      expect(
        _paths([_q('old'), _lockedBox, _t('z')],
            [_q('new'), _q('added'), _head(), _q('paid'), _t('z')]),
        isEmpty,
      );
      expect(
        _paths([_t('a'), _lockedBox, _t('z')],
            [_t('b'), _head(), _q('paid'), _t('z')]),
        isEmpty,
      );
    });

    test('a shorter page than the box assumed never throws', () {
      expect(
        _paths([_lockedBox, _q('1'), _q('2')], [_q('replacement')]),
        isEmpty,
      );
      expect(
          _paths([_lockedBox, _q('1'), _q('2')], [_q('h'), _q('p')]), isEmpty);
      expect(_paths([_t('a'), _lockedBox], []), isEmpty);
    });

    test('buying one of two boxes reveals only that one', () {
      expect(
        _paths([
          _lockedBox,
          _t('mid'),
          const ThreadContentSegment.saleBox(_otherBox),
        ], [
          _head(),
          _q('paid'),
          _t('mid'),
          const ThreadContentSegment.saleBox(
            ThreadSaleBox(
              summary: '售价 2 SP币',
              buyPath: 'job.php?action-buy-tid-2.html',
              price: 2,
              buyers: 4,
            ),
          ),
        ]),
        {'1'},
      );
    });
  });

  group('ThreadPurchaseReveal', () {
    FadeTransition fade(WidgetTester tester) => tester.widget<FadeTransition>(
          find.descendant(
            of: find.byType(ThreadPurchaseReveal),
            matching: find.byType(FadeTransition),
          ),
        );

    testWidgets('fades only the paid block, once, at its final size',
        (tester) async {
      final played = <String>{};
      await tester.pumpWidget(_host(_unlocked, played: played, paths: {'2'}));
      expect(find.byType(ThreadPurchaseReveal), findsOneWidget);
      final size = tester.getSize(find.byType(ThreadPurchaseReveal));
      expect(fade(tester).opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 100));
      final middle = fade(tester).opacity.value;
      expect(middle, greaterThan(0));
      expect(middle, lessThan(1));
      // Nothing moves while it fades.
      expect(tester.getSize(find.byType(ThreadPurchaseReveal)), size);
      await tester.pumpAndSettle();
      expect(fade(tester).opacity.value, 1);
      expect(played, contains('p|2|0'));

      // Mounted again (scrolled away and back, or a later refresh): no replay.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(_unlocked, played: played, paths: {'2'}));
      expect(fade(tester).opacity.value, 1);
    });

    testWidgets('is instant when animations are disabled', (tester) async {
      await tester.pumpWidget(
        _host(_unlocked, paths: {'2'}, reduceMotion: true),
      );
      expect(fade(tester).opacity.value, 1);
    });

    testWidgets('wraps nothing in a post without a purchase', (tester) async {
      await tester.pumpWidget(_host(_unlocked));
      expect(find.byType(ThreadPurchaseReveal), findsNothing);
      expect(find.text('paid body', findRichText: true), findsOneWidget);
    });
  });

  group('ThreadSaleBoxView notices', () {
    Widget view(ThreadSaleBoxNotice? notice, {VoidCallback? onBuy}) =>
        MaterialApp(
          home: Scaffold(
            body: ThreadPurchaseScope(
              postKey: 'p',
              revealPaths: const {},
              played: <String>{},
              notices: {if (notice != null) _box.buyPath: notice},
              onRefreshBox: (_) async {},
              child: ThreadSaleBoxView(
                saleBox: _box,
                isBuying: false,
                onBuy: onBuy ?? () {},
              ),
            ),
          ),
        );

    testWidgets('a failed purchase says why and offers a retry',
        (tester) async {
      await tester.pumpWidget(
        view(const ThreadSaleBoxNotice('购买失败：断网', canRetry: true)),
      );
      expect(find.text('购买失败：断网'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('a paid box can only refresh, never buy again', (tester) async {
      var buys = 0;
      await tester.pumpWidget(
        view(const ThreadSaleBoxNotice('请刷新', canRetry: false),
            onBuy: () => buys++),
      );
      expect(find.text('刷新页面'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(buys, 0);
    });
  });
}
