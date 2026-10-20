import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

const _board = ForumCategory(name: 'Scoped fixture board', slug: 'fid-900');

class _ScopedBoardRepository extends AppRedesignRepository {
  final requests = <(String, int)>[];
  final requestMarkers = <String>[];
  String marker = '';
  Completer<void>? oldNext;

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async {
    final owner = currentUsername!;
    final realm = marker;
    final prefix = realm.isEmpty ? owner : '$owner $realm';
    requests.add((owner, page));
    requestMarkers.add(realm);
    if (page == 2 && realm == 'realm-before') await oldNext!.future;
    return ForumThreadPage(
      currentPage: page,
      totalPages: 3,
      boardName: _board.name,
      threads: [
        for (var i = 0; i < 14; i++)
          ForumThread(
            title: '$prefix page $page row $i',
            url: 'https://fixture.invalid/read.php?tid-${page * 100 + i}.html',
            replies: i,
            section: '',
          ),
      ],
    );
  }
}

Future<void> _open(
    WidgetTester tester, _ScopedBoardRepository repository) async {
  SharedPreferences.setMockInitialValues(
      {'settings.loading.board': 'continuous'});
  await LoadingPreferences.load();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => BoardThreadListScreen(
                  category: _board, repository: repository))),
          child: const Text('Open scoped board'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open scoped board'));
  await tester.pumpAndSettle();
}

Future<void> _recover(WidgetTester tester) async {
  // Both route removal and explicit retry are valid account-change UX.
  for (final label in ['Open scoped board', '重试']) {
    if (find.text(label).hitTestable().evaluate().isNotEmpty) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      break;
    }
  }
}

void _end(WidgetTester tester) {
  final position =
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  position.jumpTo(position.maxScrollExtent);
}

void main() {
  testWidgets(
      'a pushed board replaces its owner before accepting the new account next page',
      (tester) async {
    final repository = _ScopedBoardRepository();
    await _open(tester, repository);
    expect(find.text('fixture-owner-a page 1 row 0'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      final firstFrameOld = find
          .textContaining('fixture-owner-a', skipOffstage: false)
          .evaluate()
          .length;
      final firstFrameSemantics =
          find.bySemanticsLabel(RegExp('fixture-owner-a')).evaluate().length;
      await tester.pumpAndSettle();
      await _recover(tester);
      final startsAtB1 = find
          .text('fixture-owner-b page 1 row 0')
          .hitTestable()
          .evaluate()
          .isNotEmpty;
      _end(tester);
      await tester.pumpAndSettle();
      final bPages = repository.requests
          .where((request) => request.$1 == 'fixture-owner-b')
          .map((request) => request.$2)
          .toList();
      debugPrint('BOARD_SCOPE firstFrameOld=$firstFrameOld '
          'semantics=$firstFrameSemantics startsAtB1=$startsAtB1 requestsB=$bPages');
      expect(firstFrameOld, 0,
          reason:
              'Backend late-response guards cannot remove already-rendered pages');
      expect(firstFrameSemantics, 0);
      expect(startsAtB1, isTrue);
      expect(bPages, [1, 2]);
      expect(find.textContaining('fixture-owner-a', skipOffstage: false),
          findsNothing);
      expect(find.text('fixture-owner-b page 2 row 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'a single epoch clears a pushed board before client adoption and rejects its old next',
      (tester) async {
    final repository = _ScopedBoardRepository()
      ..marker = 'realm-before'
      ..oldNext = Completer<void>();
    await _open(tester, repository);
    expect(
        find.text('fixture-owner-a realm-before page 1 row 0'), findsOneWidget);
    _end(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(repository.requests.map((request) => request.$2), [1, 2]);
    try {
      repository.epoch.value++;
      // Repository notifications precede synchronous client adoption.
      repository.marker = 'realm-after';
      await tester.pump();
      final firstFrameOld = find
          .textContaining('realm-before', skipOffstage: false)
          .evaluate()
          .length;
      repository.oldNext!.complete();
      await tester.pumpAndSettle();
      await _recover(tester);
      debugPrint('BOARD_EPOCH firstFrameOld=$firstFrameOld '
          'requestRealms=${repository.requestMarkers} requests=${repository.requests}');
      expect(firstFrameOld, 0);
      expect(repository.requestMarkers.skip(2), isNotEmpty);
      expect(repository.requestMarkers.skip(2), everyElement('realm-after'),
          reason: 'New-epoch page1 cannot start through the previous client');
      expect(repository.requests.skip(2).map((request) => request.$2), [1]);
      expect(find.textContaining('realm-before', skipOffstage: false),
          findsNothing);
      expect(find.text('fixture-owner-a realm-after page 1 row 0'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      if (!repository.oldNext!.isCompleted) repository.oldNext!.complete();
    }
  });
}
