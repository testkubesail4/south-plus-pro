import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';

import 'app_redesign_fixture.dart';

const _root = ValueKey('redesign-paint-root');

class _BodyFrame {
  _BodyFrame(this.pixels, this.ink);

  final Uint8List pixels;
  final double ink;

  double difference(_BodyFrame other) {
    expect(pixels.length, other.pixels.length);
    var difference = 0.0;
    for (var i = 0; i < pixels.length; i++) {
      difference += (pixels[i] - other.pixels[i]).abs();
    }
    return difference / pixels.length / 255;
  }
}

Future<_BodyFrame> _frame(WidgetTester tester, Color background,
    {double top = 112}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  // Exclude the always-visible navigation and header: they cannot hide a blank body.
  final bottom = tester.getTopLeft(find.byType(NavigationBar)).dy;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 0.5);
    final bytes = (await image.toByteData())!;
    final pixels = <int>[];
    var ink = 0.0;
    for (var y = (top * 0.5).floor(); y < (bottom * 0.5).floor(); y++) {
      for (var x = 0; x < image.width; x++) {
        final offset = (y * image.width + x) * 4;
        final r = bytes.getUint8(offset);
        final g = bytes.getUint8(offset + 1);
        final b = bytes.getUint8(offset + 2);
        pixels.addAll([r, g, b]);
        ink += ((r - background.r * 255).abs() +
                (g - background.g * 255).abs() +
                (b - background.b * 255).abs()) /
            3 /
            255;
      }
    }
    image.dispose();
    return _BodyFrame(Uint8List.fromList(pixels), ink / (pixels.length / 3));
  }))!;
}

Future<AppRedesignRepository> _mount(WidgetTester tester, ThemeMode mode,
    {bool reducedMotion = false}) async {
  final repository = await pumpRedesignShell(tester,
      mode: mode, reducedMotion: reducedMotion, paintKey: _root);
  // Prime real keep-alive tabs, so a skeleton/data future cannot mimic motion.
  for (final tab in ['收藏', '消息', '我的', '首页']) {
    await selectRedesignTab(tester, tab);
  }
  return repository;
}

Future<void> _expectMotion(
  WidgetTester tester,
  Future<void> Function() change, {
  double top = 112,
}) async {
  final background =
      Theme.of(tester.element(find.byType(HomeShell))).scaffoldBackgroundColor;
  final before = await _frame(tester, background, top: top);
  await change();
  await tester.pump();
  final frames = <_BodyFrame>[];
  for (var i = 0; i < 16; i++) {
    frames.add(await _frame(tester, background, top: top));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
  final after = await _frame(tester, background, top: top);
  expect(
    frames.any((frame) =>
        frame.difference(before) > 0.0001 && frame.difference(after) > 0.0001),
    isTrue,
    reason: 'Stable content visibly transitions, not replaces in one frame',
  );
  final minimum = math.min(before.ink, after.ink) * 0.6;
  for (var i = 0; i < frames.length; i++) {
    expect(frames[i].ink, greaterThanOrEqualTo(minimum),
        reason:
            'Body content remains visible at ${i * 16}ms, including dark mode');
  }
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        'primary tab motion has visible intermediate content, not blank ($mode)',
        (tester) async {
      await _mount(tester, mode);
      await _expectMotion(
          tester, () => selectRedesignTab(tester, '收藏', settle: false));
    });

    testWidgets(
        'message box motion keeps content visible between selections ($mode)',
        (tester) async {
      await _mount(tester, mode);
      await selectRedesignTab(tester, '消息');
      await _expectMotion(tester, () => tester.tap(find.text('发件箱')), top: 200);
    });
  }

  testWidgets(
      'rapid tab changes expose only the last tab and replace old owners immediately',
      (tester) async {
    final repository = await _mount(tester, ThemeMode.light);
    final semantics = tester.ensureSemantics();
    try {
      for (final tab in ['收藏', '消息', '我的']) {
        await selectRedesignTab(tester, tab, settle: false);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
      expect(
          find.text('fixture-owner-a favorite 0').hitTestable(), findsNothing);
      expect(find.text('fixture-owner-a inbox message 0').hitTestable(),
          findsNothing);
      expect(find.bySemanticsLabel(RegExp('favorite 0|inbox message 0')),
          findsNothing);
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      expect(find.textContaining('fixture-owner-a', skipOffstage: false),
          findsNothing);
      expect(find.bySemanticsLabel(RegExp('fixture-owner-a')), findsNothing);
      expect(find.text('fixture-owner-b'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reduced motion reaches the selected tab in the first frame',
      (tester) async {
    await _mount(tester, ThemeMode.light, reducedMotion: true);
    final background = Theme.of(tester.element(find.byType(HomeShell)))
        .scaffoldBackgroundColor;
    await selectRedesignTab(tester, '收藏', settle: false);
    await tester.pump();
    final first = await _frame(tester, background);
    await tester.pumpAndSettle();
    expect(
        first.difference(await _frame(tester, background)), lessThan(0.000001));
    expect(
        find.text('fixture-owner-a favorite 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'outgoing PM rows are inert and silent at the 80ms intermediate frame',
      (tester) async {
    await _mount(tester, ThemeMode.light);
    await selectRedesignTab(tester, '消息');
    final semantics = tester.ensureSemantics();
    try {
      await tester.tap(find.text('发件箱'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('fixture-owner-a inbox message 0').hitTestable(),
          findsNothing);
      expect(find.bySemanticsLabel(RegExp('fixture-owner-a inbox message')),
          findsNothing);
      expect(find.text('fixture-owner-a sendbox message 0').hitTestable(),
          findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'rapid message box switches finish in the selected box and isolate account changes',
      (tester) async {
    final repository = await _mount(tester, ThemeMode.light);
    await selectRedesignTab(tester, '消息');
    for (final label in ['发件箱', '跟踪', '收件箱']) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(repository.pmRequests.last, (ForumPmBox.inbox, null));
    expect(find.text('fixture-owner-a inbox message 0').hitTestable(),
        findsOneWidget);
    expect(find.text('fixture-owner-a scout message 0').hitTestable(),
        findsNothing);
    repository.changeOwner('fixture-owner-b');
    await tester.pump();
    expect(find.textContaining('fixture-owner-a', skipOffstage: false),
        findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('fixture-owner-b inbox message 0'), findsOneWidget);
  });
}
