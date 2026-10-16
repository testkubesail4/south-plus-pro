import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/reply/reply_sheet.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('search blocks resubmits and separates failures from no results',
      (tester) async {
    final repository = _FakeRepository();
    final searchButton = find.byKey(const ValueKey('search-submit'));
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(repository: repository)),
    );

    await tester.enterText(find.byType(TextField).first, 'sample');
    await tester.tap(searchButton);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(repository.searches, hasLength(1));
    expect(
      tester.widget<ButtonStyleButton>(searchButton).onPressed,
      isNull,
    );

    repository.searches.single.completeError(
      const ForumRequestException(ForumRequestKind.rateLimited, 'raw'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('请求过于频繁'), findsOneWidget);
    expect(find.text('没有找到相关主题'), findsNothing);

    await tester.tap(searchButton);
    await tester.pump();
    repository.searches.last.complete(const ForumSearchPage(threads: []));
    await tester.pump();
    await tester.pump();
    expect(repository.searches, hasLength(2));
    expect(find.text('没有找到相关主题'), findsOneWidget);
  });

  testWidgets('search sends username only and follows the server next page',
      (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(repository: repository)),
    );

    await tester.tap(find.text('筛选条件'));
    await tester.pumpAndSettle();
    expect(repository.boardRequests, 1);

    await tester.enterText(find.byType(TextField).at(1), 'someone');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('search-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-submit')));
    await tester.pump();
    final query = repository.queries.single;
    expect(query.keyword, isEmpty);
    expect(query.username, 'someone');
    expect(query.boardId, 'all');
    expect(query.order, ForumThreadOrder.postedAt);
    expect(query.ascending, isFalse);

    repository.searches.single.complete(const ForumSearchPage(
      threads: [_FakeRepository.thread],
      total: 42,
      nextPagePath: 'search.php?step=2&page=2',
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 42 条结果'), findsOneWidget);

    await tester.scrollUntilVisible(find.byTooltip('下一页'), 100,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pump();
    expect(repository.pagePaths, ['search.php?step=2&page=2']);
    expect(repository.queries.last, same(query));
  });

  testWidgets('reply failure shows short text and re-enables submit once',
      (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReplyComposer(
              thread: _FakeRepository.thread,
              repository: repository,
              onSubmitted: (_) {},
            ),
          ),
        ),
      ),
    );
    final submit = find.byKey(const ValueKey('reply-submit-button'));

    await tester.enterText(find.byType(TextField).last, 'body');
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    expect(repository.replies, 1);
    expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNull);

    repository.reply.completeError(
      const ForumRequestException(ForumRequestKind.network, 'raw'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('网络失败'), findsOneWidget);
    expect(repository.replies, 1);
    expect(tester.widget<ButtonStyleButton>(submit).onPressed, isNotNull);
  });
}

class _FakeRepository extends ForumRepository {
  static const thread = ForumThread(
    title: 'title',
    url: 'https://example.invalid/read.php?tid-1.html',
    replies: 0,
    section: 'section',
  );

  final searches = <Completer<ForumSearchPage>>[];
  final queries = <ForumSearchQuery>[];
  final pagePaths = <String>[];
  final reply = Completer<ReplyResult>();
  int replies = 0;
  int boardRequests = 0;

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async {
    boardRequests++;
    return const [
      ForumSearchBoard(id: 'all', name: 'all boards'),
      ForumSearchBoard(id: '1', name: 'board one'),
    ];
  }

  @override
  Future<ForumSearchPage> searchForum(ForumSearchQuery query) {
    queries.add(query);
    searches.add(Completer());
    return searches.last.future;
  }

  @override
  Future<ForumSearchPage> searchForumPage(
    ForumSearchQuery query,
    String pagePath,
  ) {
    queries.add(query);
    pagePaths.add(pagePath);
    searches.add(Completer());
    return searches.last.future;
  }

  @override
  Future<ReplyResult> submitReply({
    required ForumThread thread,
    required String title,
    required String content,
  }) {
    replies++;
    return reply.future;
  }
}
