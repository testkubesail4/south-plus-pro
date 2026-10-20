import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic results only; each a valid thread (tid from 1).
ForumThread _thread(int i) => ForumThread(
      title: 'Result $i',
      url: 'read.php?tid-${i + 1}.html',
      replies: i,
      section: 'Fixture board',
    );

class _Repo extends ForumRepository {
  final paths = <String>[];
  // Every later page repeats page 1, as when results shift while reading.
  bool repeats = false;
  // Replaces the pages above when set.
  ForumSearchPage Function(int page)? pages;

  ForumSearchPage _page(int page) =>
      pages?.call(page) ??
      ForumSearchPage(
        threads: [
          for (var i = 0; i < 15; i++)
            _thread((repeats ? 0 : page - 1) * 100 + i),
        ],
        currentPage: page,
        nextPagePath: 'search.php?step=2&page=${page + 1}',
        pageLinks: [
          ForumSearchPageLink(
              label: '${page + 1}',
              path: 'search.php?step=2&page=${page + 1}',
              page: page + 1),
        ],
        totalPages: 9,
      );

  @override
  Future<ForumSearchPage> searchForum(ForumSearchQuery query) async => _page(1);

  @override
  Future<ForumSearchPage> searchForumPage(
      ForumSearchQuery query, String pagePath) async {
    paths.add(pagePath);
    return _page(int.parse(pagePath.split('=').last));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
  });

  Future<_Repo> search(WidgetTester tester, {_Repo? repo}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo ??= _Repo();
    await tester.pumpWidget(MaterialApp(home: SearchScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'fixture');
    await tester.tap(find.byKey(const ValueKey('search-submit')));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> toEnd(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  testWidgets('手动翻页: 下一页 turns to page 2 alone, at its top', (tester) async {
    final repo = await search(tester);
    await toEnd(tester);
    expect(repo.paths, isEmpty, reason: 'reaching the end asks nothing');

    await tester.tap(find.byKey(const ValueKey('page-end-next')));
    await tester.pumpAndSettle();
    expect(repo.paths, ['search.php?step=2&page=2']);
    expect(find.text('Result 100').hitTestable(), findsOneWidget);
    expect(find.text('Result 0', skipOffstage: false), findsNothing);
  });

  testWidgets('自动接续 appends the next page under a 第 N 页 boundary',
      (tester) async {
    await LoadingPreferences.save(LoadingDomain.search, LoadingMode.continuous);
    final repo = await search(tester);
    await toEnd(tester);
    expect(repo.paths.first, 'search.php?step=2&page=2');
    expect(find.text('第 2 页', skipOffstage: false), findsOneWidget);
    expect(find.text('Result 100', skipOffstage: false), findsOneWidget);
  });

  testWidgets('自动接续 pauses after two pages of repeated results',
      (tester) async {
    await LoadingPreferences.save(LoadingDomain.search, LoadingMode.continuous);
    final repo = await search(tester, repo: _Repo()..repeats = true);
    await toEnd(tester);
    expect(repo.paths, [
      'search.php?step=2&page=2',
      'search.php?step=2&page=3',
    ]);
    await tester.scrollUntilVisible(find.text('继续加载第 4 页'), 300,
        scrollable: find.byType(Scrollable).first);
    // A tap on a list still moving only stops it.
    await tester.pumpAndSettle();
    expect(find.text('后续页面的内容已被过滤或重复'), findsOneWidget);
    await tester.tap(find.text('继续加载第 4 页'));
    await tester.pump();
    expect(repo.paths[2], 'search.php?step=2&page=4');
  });

  testWidgets(
      'a page with no rows still turns, to the page the forum links next',
      (tester) async {
    const third = 'search.php?step=2&page=3';
    final repo = await search(tester,
        repo: _Repo()
          ..pages = (page) => page == 1
              ? const ForumSearchPage(
                  threads: [],
                  nextPagePath: third,
                  pageLinks: [
                    ForumSearchPageLink(label: '3', path: third, page: 3),
                  ])
              : ForumSearchPage(threads: [_thread(100)], currentPage: 3));
    expect(find.text('本页没有结果'), findsOneWidget);
    expect(find.text('没有找到相关主题'), findsNothing);
    // Page 2 is not linked: the next is 3, and says so.
    expect(find.text('下一页 · 第 3 页'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-end-next')));
    await tester.pumpAndSettle();
    expect(repo.paths, [third]);
    expect(find.text('Result 100'), findsOneWidget);
    // No next link, and no page count: the end is not claimed.
    expect(find.text('已到最后一页'), findsNothing);
    expect(find.text('论坛未给出下一页，页数未能确认'), findsOneWidget);
  });

  testWidgets('results without a valid thread are never taken for repeats',
      (tester) async {
    await LoadingPreferences.save(LoadingDomain.search, LoadingMode.continuous);
    const unknown = ForumThread(
        title: 'Unknown result',
        url: 'read.php?tid-unknown.html',
        replies: 0,
        section: '');
    final repo = await search(tester,
        repo: _Repo()
          ..pages = (page) => ForumSearchPage(
                threads: [
                  if (page == 1)
                    for (var i = 0; i < 15; i++) _thread(i),
                  unknown,
                  unknown,
                  if (page == 2) _thread(0),
                ],
                currentPage: page,
                nextPagePath: page == 1 ? 'search.php?step=2&page=2' : null,
              ));
    await toEnd(tester);
    await toEnd(tester);
    expect(repo.paths, ['search.php?step=2&page=2']);
    // Both pages' two stay; page 2's repeat of a valid thread does not.
    expect(find.text('Unknown result', skipOffstage: false), findsNWidgets(4));
    expect(find.text('Result 0', skipOffstage: false), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 20000));
    await tester.pumpAndSettle();
    expect(find.text('Result 0'), findsOneWidget);
  });

  testWidgets('a new result list fades in over the spinner', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(MaterialApp(home: SearchScreen(repository: _Repo())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'fixture');
    await tester.tap(find.byKey(const ValueKey('search-submit')));
    await tester.pump();
    await tester.pump();
    double opacity() => tester
        .renderObject<RenderSliverAnimatedOpacity>(
            find.byType(SliverFadeTransition))
        .opacity
        .value;
    expect(opacity(), inInclusiveRange(0.65, 0.99));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });
}
