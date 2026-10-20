import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic favourites only: 10 rows a page, 3 pages.
class _Repo extends ForumRepository {
  final epoch = ValueNotifier<int>(0);
  final calls = <String>[];
  final removed = <(FavoriteCollections, List<FavoriteCollectionEntry>)>[];
  // The category's name as each later page reports it.
  String laterLabel = '资料';
  // Later pages repeat page 1's rows.
  bool repeats = false;
  int pageCount = 3;
  // While set, page 3 stays on its way.
  Completer<void>? holdPage3;
  // Categories made here.
  final made = <FavoriteCategory>[];
  final moved =
      <(FavoriteCollections, List<FavoriteCollectionEntry>, String)>[];

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  bool get isLoggedIn => true;

  FavoriteCollections _page(String? category, int page) => FavoriteCollections(
        page: page,
        pageCount: pageCount,
        categoryId: category,
        categories: [
          const FavoriteCategory(id: '0', label: '默认分类'),
          FavoriteCategory(id: '1', label: page == 1 ? '资料' : laterLabel),
          ...made,
        ],
        canCreate: true,
        items: [
          for (var i = 0; i < 10; i++)
            FavoriteCollectionEntry(
              id: '${(repeats ? 1 : page) * 100 + i}',
              categoryId: '0',
              thread: UserListItem(
                  title: 'Fav ${(repeats ? 1 : page) * 100 + i}',
                  url: 'read.php?tid-${page * 100 + i}.html'),
            ),
        ],
      );

  @override
  Future<FavoriteCollections> fetchFavoriteCollections(
      {String? categoryId}) async {
    calls.add('${categoryId ?? 'all'}:1');
    return _page(categoryId, 1);
  }

  @override
  Future<FavoriteCollections> fetchFavoriteCollectionsPage(
      {String? categoryId, int page = 1}) async {
    calls.add('${categoryId ?? 'all'}:$page');
    if (page == 3) await holdPage3?.future;
    return _page(categoryId, page);
  }

  @override
  Future<FavoriteCollectionMutation> removeFavorites(
      FavoriteCollections snapshot,
      List<FavoriteCollectionEntry> entries) async {
    removed.add((snapshot, entries));
    return FavoriteCollectionMutation(
        status: FavoriteMutationStatus.confirmed,
        message: 'ok',
        collections: _page(snapshot.categoryId, snapshot.page));
  }

  // As the forum answers: the list of everything, from its first page.
  @override
  Future<FavoriteCollectionMutation> createFavoriteCategory(
      FavoriteCollections snapshot, String name) async {
    made.add(FavoriteCategory(id: '${2 + made.length}', label: name));
    return FavoriteCollectionMutation(
        status: FavoriteMutationStatus.confirmed,
        message: 'ok',
        collections: _page(null, 1));
  }

  @override
  Future<FavoriteCollectionMutation> moveFavorites(FavoriteCollections snapshot,
      List<FavoriteCollectionEntry> entries, String categoryId) async {
    moved.add((snapshot, entries, categoryId));
    return FavoriteCollectionMutation(
        status: FavoriteMutationStatus.confirmed,
        message: 'ok',
        collections: _page(null, snapshot.page));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
  });

  Future<_Repo> pump(WidgetTester tester, {_Repo? repo}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo ??= _Repo();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FavoriteThreadsPage(repository: repo)),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> toEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('手动翻页: 下一页 turns to page 2 alone, at its top', (tester) async {
    final repo = await pump(tester);
    await toEnd(tester);
    expect(repo.calls, ['all:1'], reason: 'reaching the end asks nothing');

    await tester.tap(key('page-end-next'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['all:1', 'all:2']);
    expect(find.text('Fav 200').hitTestable(), findsOneWidget);
    expect(find.text('Fav 100', skipOffstage: false), findsNothing);
    expect(find.textContaining('第 2/3 页'), findsOneWidget);
  });

  testWidgets(
      '自动接续 appends pages; one write takes rows of one page, '
      'sent with that page', (tester) async {
    await LoadingPreferences.save(
        LoadingDomain.favorites, LoadingMode.continuous);
    final repo = await pump(tester);
    await toEnd(tester);
    await toEnd(tester);
    expect(repo.calls, ['all:1', 'all:2', 'all:3']);
    expect(find.text('第 2 页', skipOffstage: false), findsOneWidget);
    expect(find.text('已到最后一页', skipOffstage: false), findsOneWidget);

    await tester.tap(key('favorite-select-start'));
    await tester.pumpAndSettle();
    await tester.tap(key('favorite-select:305'));
    await tester.pumpAndSettle();
    // A row of another page is not added.
    await tester.ensureVisible(key('favorite-select:205'));
    await tester.pumpAndSettle();
    await tester.tap(key('favorite-select:205'));
    await tester.pumpAndSettle();
    expect(find.text('一次只能选择同一页的收藏'), findsOneWidget);
    await tester.tap(key('favorite-select:208'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // The note leaves the selection bar free again.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(key('favorite-remove-selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏').last);
    await tester.pumpAndSettle();
    final (snapshot, entries) = repo.removed.single;
    expect(snapshot.page, 3);
    expect(entries.map((e) => e.id), ['305']);
    expect(entries.every((e) => snapshot.items.any((i) => identical(i, e))),
        isTrue);
  });

  testWidgets('turning to 自动接续 at the end waits for the next scroll',
      (tester) async {
    final repo = await pump(tester);
    await toEnd(tester);
    await LoadingPreferences.save(
        LoadingDomain.favorites, LoadingMode.continuous);
    await tester.pumpAndSettle();
    expect(repo.calls, ['all:1']);

    // The next scroll near the end reads on.
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(repo.calls, ['all:1', 'all:2']);
  });

  testWidgets('a page read before a write is not appended after it',
      (tester) async {
    await LoadingPreferences.save(
        LoadingDomain.favorites, LoadingMode.continuous);
    final hold = Completer<void>();
    final repo = await pump(tester, repo: _Repo()..holdPage3 = hold);
    // Page 3 stays on its way, its spinner turning: no settling from here.
    Future<void> settle() => tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 2; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await settle();
    }
    expect(repo.calls, ['all:1', 'all:2', 'all:3']);

    await tester.tap(key('favorite-select-start'));
    await settle();
    final row = key('favorite-select:205');
    await tester.ensureVisible(row);
    await settle();
    await tester.tap(row);
    await settle();
    await tester.tap(key('favorite-remove-selected'));
    await settle();
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏').last);
    await tester.pumpAndSettle();
    expect(repo.removed.single.$1.page, 2);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('Fav 300', skipOffstage: false), findsNothing);
    expect(find.text('第 3 页', skipOffstage: false), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a row chosen on page 3 moves to a category made on the way',
      (tester) async {
    final repo = await pump(tester);
    for (var i = 0; i < 2; i++) {
      await toEnd(tester);
      await tester.tap(key('page-end-next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(key('favorite-select-start'));
    await tester.pumpAndSettle();
    await tester.tap(key('favorite-select:305'));
    await tester.pumpAndSettle();
    await tester.tap(key('favorite-move'));
    await tester.pumpAndSettle();
    await tester.tap(key('favorite-move-new'));
    await tester.pumpAndSettle();
    await tester.enterText(key('favorite-category-name'), '新分类');
    await tester.pump();
    await tester.tap(key('favorite-category-create'));
    await tester.pumpAndSettle();
    // The answer is page 1 of everything: page 3 is read again for 305.
    expect(repo.calls.last, 'all:3');
    expect(find.text('部分所选主题不在当前页，请重新选择'), findsNothing);

    await tester.tap(key('favorite-move-to:2'));
    await tester.pumpAndSettle();
    final (snapshot, entries, target) = repo.moved.single;
    expect(snapshot.page, 3);
    expect(entries.map((e) => e.id), ['305']);
    expect(identical(entries.single, snapshot.items[5]), isTrue);
    expect(target, '2');
  });

  testWidgets('自动接续 pauses after two pages of repeated rows', (tester) async {
    await LoadingPreferences.save(
        LoadingDomain.favorites, LoadingMode.continuous);
    final repo = await pump(tester,
        repo: _Repo()
          ..repeats = true
          ..pageCount = 9);
    await toEnd(tester);
    expect(repo.calls, ['all:1', 'all:2', 'all:3']);
    expect(find.text('后续页面的内容已被过滤或重复'), findsOneWidget);
    await tester.tap(find.text('继续加载第 4 页'));
    await tester.pump();
    expect(repo.calls[3], 'all:4');
  });

  testWidgets('a later page under another category name is not appended',
      (tester) async {
    await LoadingPreferences.save(
        LoadingDomain.favorites, LoadingMode.continuous);
    final repo = await pump(tester, repo: _Repo()..laterLabel = '其他');
    await tester.tap(key('favorite-folder:1'));
    await tester.pumpAndSettle();
    await toEnd(tester);
    // Page 2 of what is now another category: read everything again.
    final asked = repo.calls.indexOf('1:1');
    expect(repo.calls.sublist(asked, asked + 3), ['1:1', '1:2', 'all:1']);
    await tester.drag(find.byType(ListView), const Offset(0, 20000));
    await tester.pumpAndSettle();
    expect(
        tester.widget<ChoiceChip>(key('favorite-folder:all')).selected, isTrue);
    expect(repo.calls, isNot(contains('1:3')));
  });
}
