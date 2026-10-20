import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_find.dart';
import 'package:south_plus_rewrite/features/thread/thread_floor_actions.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

const _thread = ForumThread(
  title: 'Scoped fixture thread',
  url: 'https://south-plus.net/read.php?tid-990001.html',
  replies: 28,
  section: '',
);

ThreadDetail _detail(String owner, int page) => ThreadDetail(
      thread: _thread,
      body: page == 1 ? '$owner already-readable paid body' : '',
      pagination: ThreadPagination(currentPage: page, totalPages: 3),
      replies: [
        for (var i = 0; i < 14; i++)
          ThreadReply(
            author: 'public-peer-$i',
            content: '$owner private cached page $page reply $i',
            postId: '${page * 100 + i + 1}',
            floor: 'B${(page - 1) * 14 + i + 1}F',
            quoteUrl:
                'https://south-plus.net/post.php?action=quote&tid=990001&pid=${page * 100 + i + 1}',
          ),
      ],
    );

class _ScopedThreadRepository extends AppRedesignRepository {
  final requests = <(String, int)>[];
  final quoteOwners = <String?>[];
  Completer<ThreadDetail>? next;
  final quote = Completer<String?>();

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(
          ForumThread thread) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
      ForumThread thread, ThreadReadPosition position) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread,
      {int page = 1}) async {
    final owner = currentUsername ?? 'guest';
    requests.add((owner, page));
    if (page == 2 && owner == 'fixture-owner-a' && next != null)
      return await next!.future;
    return _detail(owner, page);
  }

  @override
  Future<String?> fetchQuoteDraft(ThreadReply reply) {
    quoteOwners.add(currentUsername);
    return quote.future;
  }
}

Future<void> _open(
    WidgetTester tester, _ScopedThreadRepository repository) async {
  SharedPreferences.setMockInitialValues({'settings.autoLoadNextPage': true});
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
              builder: (_) =>
                  ThreadDetailScreen(repository: repository, thread: _thread))),
          child: const Text('Open scoped thread'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open scoped thread'));
  await tester.pumpAndSettle();
}

Future<void> _recover(WidgetTester tester, {bool pendingQuote = false}) async {
  for (final label in ['Open scoped thread', '重试']) {
    if (find.text(label).hitTestable().evaluate().isNotEmpty) {
      await tester.tap(find.text(label));
      await tester.pump();
      if (pendingQuote) {
        await tester.pump(const Duration(milliseconds: 500));
      } else {
        await tester.pumpAndSettle();
      }
      break;
    }
  }
}

Finder _oldText() => find.textContaining('fixture-owner-a',
    findRichText: true, skipOffstage: false);

void main() {
  testWidgets(
      'logout clears already-readable thread content and an actual docked draft in one frame',
      (tester) async {
    final repository = _ScopedThreadRepository();
    await _open(tester, repository);
    expect(
        find.textContaining('fixture-owner-a already-readable paid body',
            findRichText: true),
        findsWidgets);
    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).last, 'fixture-owner-a unsent draft');
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'fixture-owner-a unsent draft');
    final semantics = tester.ensureSemantics();
    try {
      repository.changeOwner(null);
      await tester.pump();
      expect(_oldText(), findsNothing);
      expect(find.bySemanticsLabel(RegExp('fixture-owner-a')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'a previous-account pending next page cannot refill the pushed thread',
      (tester) async {
    final repository = _ScopedThreadRepository()
      ..next = Completer<ThreadDetail>();
    await _open(tester, repository);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
        repository.requests, [('fixture-owner-a', 1), ('fixture-owner-a', 2)]);
    try {
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      final firstFrameOld = _oldText().evaluate().length;
      repository.next!.complete(_detail('fixture-owner-a', 2));
      await tester.pumpAndSettle();
      await _recover(tester);
      final newBodyAvailable = find
          .textContaining('fixture-owner-b already-readable paid body',
              findRichText: true)
          .evaluate()
          .isNotEmpty;
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lateRows = find
          .textContaining('fixture-owner-a private cached page 2',
              findRichText: true, skipOffstage: false)
          .evaluate()
          .length;
      debugPrint('THREAD_SCOPE firstFrameOld=$firstFrameOld lateRows=$lateRows '
          'newBodyAvailable=$newBodyAvailable requests=${repository.requests}');
      expect(firstFrameOld, 0);
      expect(lateRows, 0);
      expect(_oldText(), findsNothing);
      expect(
          repository.requests
              .where((request) => request.$1 == 'fixture-owner-b')
              .map((request) => request.$2),
          [1]);
      expect(newBodyAvailable, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      if (!repository.next!.isCompleted)
        repository.next!.complete(_detail('fixture-owner-a', 2));
    }
  });

  testWidgets(
      'a rejected old quote cannot append its local fallback into the new account draft',
      (tester) async {
    final repository = _ScopedThreadRepository();
    await _open(tester, repository);
    final footer = find.ancestor(
        of: find.byKey(const ValueKey('floor-actions-public-peer-0-B1F')),
        matching: find.byType(ThreadFloorFooter));
    final quote = find.descendant(
        of: footer, matching: find.byIcon(Icons.format_quote_outlined));
    await tester.ensureVisible(quote);
    await tester.tap(quote);
    await tester.pump(const Duration(milliseconds: 50));
    expect(repository.quoteOwners, ['fixture-owner-a']);
    repository.changeOwner('fixture-owner-b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _recover(tester, pendingQuote: true);
    await tester.tap(find.byTooltip('写回复'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(
        find.byType(TextField).last, 'fixture-owner-b unsent draft');
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'fixture-owner-b unsent draft');
    // Real transport epoch rejection must not activate an old local fallback.
    repository.quote.completeError(StateError('fixture stale quote request'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'fixture-owner-b unsent draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a pushed find sheet forgets its private query before searching the new scope',
      (tester) async {
    const privateQuery = 'fixture-owner-a private find phrase';
    final repository = _ScopedThreadRepository();
    await _open(tester, repository);
    Future<void> openFind() async {
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('帖内查找'));
      await tester.pumpAndSettle();
    }

    await openFind();
    final sheet = find.byType(ThreadFindSheet, skipOffstage: false);
    Finder field() =>
        find.descendant(of: sheet, matching: find.byType(TextField));
    final oldQuery = find.descendant(
        of: sheet,
        matching: find.textContaining(privateQuery,
            findRichText: true, skipOffstage: false),
        skipOffstage: false);
    await tester.enterText(field(), privateQuery);
    await tester.pumpAndSettle();
    expect(oldQuery, findsWidgets);
    final semantics = tester.ensureSemantics();
    try {
      repository.changeOwner('fixture-owner-b');
      await tester.pump();
      expect(oldQuery, findsNothing);
      expect(
          find.descendant(
              of: sheet,
              matching: find.bySemanticsLabel(RegExp(privateQuery)),
              skipOffstage: false),
          findsNothing);
      await tester.pumpAndSettle();
      if (sheet.evaluate().isEmpty) {
        await _recover(tester);
        await openFind();
      }
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      await tester.enterText(field(), 'fixture-owner-b');
      await tester.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.textContaining('第 1 页')),
          findsWidgets);
      expect(oldQuery, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
