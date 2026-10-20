import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic results only.
ForumThread _thread(int i) => ForumThread(
      title: 'Result $i',
      url: 'read.php?tid-$i.html',
      replies: i,
      section: 'Fixture board',
    );

class _Repo extends ForumRepository {
  final paths = <String>[];
  // Every later page repeats page 1, as when results shift while reading.
  bool repeats = false;

  ForumSearchPage _page(int page) => ForumSearchPage(
        threads: [
          for (var i = 0; i < 15; i++)
            _thread((repeats ? 0 : page - 1) * 100 + i),
        ],
        currentPage: page,
        nextPagePath: 'search.php?step=2&page=${page + 1}',
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
