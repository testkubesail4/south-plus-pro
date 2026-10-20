import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

const _board = ForumCategory(
  name: 'Fixture paging board',
  slug: 'fixture-board',
  url: 'https://fixture.invalid/thread.php?fid-900.html',
);

ForumThreadPage _page(int page, {bool repeated = false}) => ForumThreadPage(
      currentPage: page,
      totalPages: 6,
      boardName: _board.name,
      threads: [
        for (var i = 0; i < 20; i++)
          ForumThread(
            title: 'Fixture page ${repeated ? 1 : page} topic $i',
            url:
                'https://fixture.invalid/read.php?tid-${(repeated ? 1 : page) * 100 + i}.html',
            replies: 0,
            section: _board.name,
          ),
      ],
    );

class _BoardRepository extends ForumRepository {
  final requests = <int>[];
  final repeatedPages = <int>{};
  Completer<ForumThreadPage>? secondPage;

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) {
    requests.add(page);
    if (page == 2 && secondPage != null) return secondPage!.future;
    return Future.value(_page(page, repeated: repeatedPages.contains(page)));
  }
}

Future<void> _mount(
    WidgetTester tester, _BoardRepository repository, LoadingMode mode) async {
  SharedPreferences.setMockInitialValues({'settings.loading.board': mode.name});
  await LoadingPreferences.load();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: BoardThreadListScreen(category: _board, repository: repository),
  ));
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> _end(WidgetTester tester, {bool settle = true}) async {
  final position = _position(tester);
  position.jumpTo(position.maxScrollExtent);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
      'manual board paging never fetches on scroll and replaces on explicit next',
      (tester) async {
    final repository = _BoardRepository();
    await _mount(tester, repository, LoadingMode.manual);
    await _end(tester);
    expect(repository.requests, [1],
        reason: 'The board must consume its saved manual preference');
    final next = find.textContaining('下一页');
    await tester.ensureVisible(next.first);
    await tester.tap(next.first);
    await tester.pumpAndSettle();
    expect(repository.requests, [1, 2]);
    expect(find.text('Fixture page 2 topic 0'), findsOneWidget);
    expect(find.text('Fixture page 1 topic 0'), findsNothing);
    expect(_position(tester).pixels, 0);
  });

  testWidgets(
      'two duplicate pages pause automatic board loading without claiming the end',
      (tester) async {
    final repository = _BoardRepository()..repeatedPages.addAll([2, 3]);
    await _mount(tester, repository, LoadingMode.continuous);
    await _end(tester);
    expect(repository.requests, [1, 2, 3],
        reason: 'No-progress must stop network requests even when total=6');
    expect(find.textContaining(RegExp('过滤|重复')), findsWidgets);
    expect(find.text('已到最后一页'), findsNothing);
    final resume = find.textContaining(RegExp(r'继续加载.*4'));
    await tester.ensureVisible(resume.first);
    await tester.tap(resume.first);
    await tester.pumpAndSettle();
    expect(repository.requests, [1, 2, 3, 4]);
    expect(find.text('Fixture page 4 topic 0'), findsOneWidget);
  });

  testWidgets(
      'switching a board to manual accepts only the already-started next page',
      (tester) async {
    final repository = _BoardRepository()
      ..secondPage = Completer<ForumThreadPage>();
    await _mount(tester, repository, LoadingMode.continuous);
    await _end(tester, settle: false);
    expect(repository.requests, [1, 2]);
    await LoadingPreferences.save(LoadingDomain.board, LoadingMode.manual);
    await tester.pump();
    repository.secondPage!.complete(_page(2));
    await tester.pumpAndSettle();
    expect(repository.requests, [1, 2]);
    await _end(tester);
    expect(repository.requests, [1, 2],
        reason:
            'Completing an in-flight append cannot restart automatic loading');
    expect(find.text('Fixture page 2 topic 19'), findsOneWidget,
        reason:
            'The already-started page is accepted once, not silently dropped');
    final next = find.textContaining('下一页');
    await tester.ensureVisible(next.first);
    await tester.tap(next.first);
    await tester.pumpAndSettle();
    expect(repository.requests, [1, 2, 3]);
    expect(find.text('Fixture page 3 topic 0'), findsOneWidget);
    expect(find.text('Fixture page 1 topic 0'), findsNothing);
  });
}
