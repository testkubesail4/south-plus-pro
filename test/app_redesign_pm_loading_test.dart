import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';
import 'app_redesign_paint_fixture.dart';

const _first = 'message.php?action=chatlog&withuid=901';
const _next = 'message.php?action=chatlog&withuid=901&page=2';
const _paintRoot = ValueKey('chatlog-paint-root');

ForumPmChatRecord _same(String? id) => ForumPmChatRecord(
      id: id,
      sender: '',
      title: 'Identical chat title',
      time: '2026-01-01 10:00',
      content: 'Identical chat body',
    );

class _ChatRepository extends AppRedesignRepository {
  final chatRequests = <String>[];

  @override
  Future<ForumPmChatlog> fetchPmChatlog(String path) async {
    chatRequests.add(path);
    if (path == _first) {
      return ForumPmChatlog(
        currentPage: 1,
        nextPagePath: _next,
        pageLinks: const [ForumPmPageLink(label: '2', path: _next)],
        records: [
          for (var i = 0; i < 14; i++)
            ForumPmChatRecord(
              id: '${100 + i}',
              sender: '',
              title: '$currentUsername private chat $i',
              time: '2026-01-01',
              content: 'Fixture private body $i',
            ),
          _same('1'),
          _same('2'),
        ],
      );
    }
    if (path == _next) {
      return ForumPmChatlog(
        currentPage: 2,
        records: [_same('2'), _same('3'), _same(null), _same(null)],
      );
    }
    throw StateError('The server never supplied this chatlog path: $path');
  }
}

Future<_ChatRepository> _mount(WidgetTester tester, LoadingMode mode) async {
  SharedPreferences.setMockInitialValues({'settings.loading.pm': mode.name});
  await LoadingPreferences.load();
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _ChatRepository();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (_, child) => RepaintBoundary(key: _paintRoot, child: child!),
      home: PmChatlogScreen(repository: repository, path: _first),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _end(WidgetTester tester) async {
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  expect(
    position.maxScrollExtent,
    greaterThan(0),
    reason: 'The first chatlog page must really scroll to trigger continuation',
  );
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'manual chatlogs replace only through an observed explicit next link',
    (tester) async {
      final repository = await _mount(tester, LoadingMode.manual);
      tester.view.physicalSize = const Size(400, 600);
      await tester.pumpAndSettle();
      await _end(tester);
      expect(repository.chatRequests, [_first]);
      final footer = find.byKey(const ValueKey('page-end-next'));
      final next = footer.evaluate().isNotEmpty ? footer : find.text('2');
      await tester.ensureVisible(next);
      final old = find.text('Fixture private body 13');
      expect(
        old.hitTestable(),
        findsOneWidget,
        reason:
            'The outgoing native page must really be visible before switching',
      );
      final semantics = tester.ensureSemantics();
      try {
        expect(next.hitTestable(), findsOneWidget);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        final region = tester.getRect(find.byWidget(scaffold.body!));
        final background = Theme.of(tester.element(find.byType(Scaffold).first))
            .scaffoldBackgroundColor;
        Future<(Uint8List, double)> paint() => captureRedesignPaint(
            tester, find.byKey(_paintRoot), region, background);
        final before = await paint();
        await tester.tap(next);
        await tester.pump();
        await tester.pump();
        final frames = <(Uint8List, double)>[];
        for (var i = 0; i < 16; i++) {
          if (i == 5) {
            expect(old.hitTestable(), findsNothing);
            expect(find.semantics.byLabel(RegExp('Fixture private body 13')),
                findsNothing);
          }
          frames.add(await paint());
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        final after = await paint();
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        debugPrint(
          'CHATLOG_MANUAL pixels=${position.pixels} max=${position.maxScrollExtent} '
          'beforeInk=${before.$2} afterInk=${after.$2} '
          'minimumInk=${frames.map((f) => f.$2).reduce(math.min)}',
        );
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason:
              'Page 2 must scroll too: clamping a short page cannot prove return-to-top',
        );
        expect(
          position.pixels,
          0,
          reason: 'A manual native page replacement starts at the top',
        );
        expect(
            frames.any((frame) =>
                redesignPaintDifference(frame.$1, before.$1) > 0.0001 &&
                redesignPaintDifference(frame.$1, after.$1) > 0.0001),
            isTrue,
            reason: 'The native page turn has a real noninstant middle paint');
        for (final frame in frames) {
          expect(frame.$2,
              greaterThanOrEqualTo(math.min(before.$2, after.$2) * 0.6),
              reason: 'Body ink cannot fade below the weaker endpoint floor');
        }
        expect(repository.chatRequests, [_first, _next]);
        expect(
          find.text('Identical chat body'),
          findsNWidgets(4),
          reason:
              'Manual page2 replaces page1 and does not reuse its seen-ID set',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'chatlog continuation deduplicates native IDs, never equal content or null IDs',
    (tester) async {
      final repository = await _mount(tester, LoadingMode.continuous);
      await _end(tester);
      expect(
        repository.chatRequests,
        [_first, _next],
        reason: 'Only the observed same-peer next path may be requested',
      );
      await _end(tester);
      expect(
        repository.chatRequests,
        [_first, _next],
        reason: 'A missing next link is terminal, not a guessed page 3',
      );
      expect(
        find.text('Identical chat body'),
        findsNWidgets(5),
        reason:
            'IDs 1,2,3 and both unidentified rows survive; only repeated ID 2 is merged',
      );
    },
  );
}
