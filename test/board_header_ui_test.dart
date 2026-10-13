import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/forum_link_opener.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_compose_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic board ids and names only.
const _link = 'https://south-plus.net/thread.php?fid-42.html';

ForumThreadPage _page({String? boardName, int page = 1}) => ForumThreadPage(
      threads: [
        ForumThread(
          title: 'Topic $page',
          url: 'read.php?tid-$page.html',
          replies: 0,
          section: boardName ?? '',
        ),
      ],
      currentPage: page,
      totalPages: 2,
      boardName: boardName,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> openLink(WidgetTester tester) async {
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              openForumLink(context, repo, _link, label: 'click here'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return repo;
  }

  String headerTitle(WidgetTester tester) => tester
      .widget<Text>(find
          .descendant(
            of: find.byType(BoardThreadListScreen),
            matching: find.byType(Text),
          )
          .first)
      .data!;

  testWidgets('a linked board is named by its page, never by the link text',
      (tester) async {
    final repo = await openLink(tester);
    expect(find.text('click here'), findsNothing);
    expect(find.text('版块 42'), findsWidgets, reason: 'neutral until loaded');

    repo.pages.single.complete(_page(boardName: 'Tea room'));
    await tester.pumpAndSettle();
    expect(find.text('Tea room'), findsWidgets);
    expect(find.text('版块 42'), findsNothing);

    // Later pages without a name keep it.
    await tester.ensureVisible(find.text('»'));
    await tester.tap(find.text('»'));
    await tester.pump();
    repo.pages.last.complete(_page(page: 2));
    await tester.pumpAndSettle();
    expect(find.text('Tea room'), findsWidgets);

    await tester.tap(find.byTooltip('发帖'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ThreadComposeScreen>(find.byType(ThreadComposeScreen))
          .category
          .name,
      'Tea room',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('在本版搜索'));
    await tester.pumpAndSettle();
    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialBoard?.id, '42');
    expect(search.initialBoard?.name, 'Tea room');
  });

  testWidgets('a page without a name keeps the known one, or shows the id',
      (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: BoardThreadListScreen(
        category: const ForumCategory(name: 'Known', slug: 'f42', url: _link),
        repository: repo,
      ),
    ));
    repo.pages.single.complete(_page());
    await tester.pumpAndSettle();
    expect(headerTitle(tester), 'Known');

    final unnamed = await openLink(tester);
    unnamed.pages.single.complete(_page());
    await tester.pumpAndSettle();
    expect(headerTitle(tester), '版块 42');
  });
}

class _Repo extends ForumRepository {
  final pages = <Completer<ForumThreadPage>>[];

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
  }) {
    pages.add(Completer());
    return pages.last.future;
  }

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => const [];
}
