import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

const _root = ValueKey('board-motion-paint');
const _board = ForumCategory(name: 'Fixture board', slug: 'fid-900');
const _all = ForumBoardFilter(
    label: '全部',
    kind: ForumBoardFilterKind.all,
    url: 'thread.php?fid-900.html');
const _digest = ForumBoardFilter(
    label: '精华',
    kind: ForumBoardFilterKind.digest,
    url: 'thread.php?fid-900-search-digest.html');

class _BoardRepository extends AppRedesignRepository {
  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) =>
      SynchronousFuture(ForumThreadPage(
        boardName: _board.name,
        currentPage: 1,
        totalPages: 1,
        filters: const [_all, _digest],
        activeFilter: filter ?? _all,
        threads: [
          for (var i = 0; i < 8; i++)
            ForumThread(
              title:
                  'Fixture item $i ${filter?.kind == ForumBoardFilterKind.digest ? 'B' : 'A'}',
              url: 'https://fixture.invalid/read.php?tid-${100 + i}.html',
              replies: i,
              section: '',
              author: 'Fixture author $i',
            ),
        ],
      ));
}

Future<double> _bodyInk(WidgetTester tester, Color background) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_root));
  final chrome = [
    for (final element in find.byType(FloatingActionButton).evaluate())
      tester.getRect(find.byWidget(element.widget)).inflate(8),
  ];
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 0.5);
    final bytes = (await image.toByteData())!;
    var ink = 0.0;
    var count = 0;
    // Exclude the always-visible app bar and filter toolbar.
    for (var y = 80; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (chrome.any((rect) => rect.contains(Offset(x * 2.0, y * 2.0)))) {
          continue;
        }
        final offset = (y * image.width + x) * 4;
        ink += ((bytes.getUint8(offset) - background.r * 255).abs() +
                (bytes.getUint8(offset + 1) - background.g * 255).abs() +
                (bytes.getUint8(offset + 2) - background.b * 255).abs()) /
            3 /
            255;
        count++;
      }
    }
    image.dispose();
    return ink / count;
  }))!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
        'board filter sliver keeps visible body ink through every frame ($mode)',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AppThemeController.notifier.value = mode;
      addTearDown(() => AppThemeController.notifier.value = ThemeMode.system);
      await tester.pumpWidget(RepaintBoundary(
        key: _root,
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: BoardThreadListScreen(
              category: _board, repository: _BoardRepository()),
        ),
      ));
      await tester.pumpAndSettle();
      final background =
          Theme.of(tester.element(find.byType(BoardThreadListScreen)))
              .scaffoldBackgroundColor;
      final before = await _bodyInk(tester, background);
      expect(find.text('Fixture item 0 A'), findsOneWidget);
      await tester.tap(find.text('精华'));
      await tester.pump();
      // Compare equally dense loaded results, not the lower-density waiting skeleton.
      for (var i = 0;
          i < 10 && find.text('Fixture item 0 B').evaluate().isEmpty;
          i++) {
        await tester.pump();
      }
      expect(find.text('Fixture item 0 B'), findsOneWidget);
      final samples = <double>[];
      for (var i = 0; i < 24; i++) {
        samples.add(await _bodyInk(tester, background));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      final after = await _bodyInk(tester, background);
      expect(find.text('Fixture item 0 B'), findsOneWidget);
      expect(math.min(before, after), greaterThan(0.001));
      final reference = math.min(before, after);
      debugPrint('BOARD_FILTER_LOADED_INK $mode before=$before after=$after '
          'minimumRatio=${samples.reduce(math.min) / reference}');
      expect(samples.any((ink) => ink < after * 0.99), isTrue,
          reason:
              'A stable, equally dense filter result must visibly transition');
      for (var i = 0; i < samples.length; i++) {
        expect(samples[i], greaterThanOrEqualTo(reference * 0.6),
            reason:
                'The scroll body must not fade through near-blank at ${i * 16}ms');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
