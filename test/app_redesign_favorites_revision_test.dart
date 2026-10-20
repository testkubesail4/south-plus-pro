import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

class _RevisionRepository extends AppRedesignRepository {
  final requests = <int>[];
  final writes = <(FavoriteCollections, List<FavoriteCollectionEntry>)>[];
  final nativeRevisions = <FavoriteCollections, int>{};
  final third = Completer<FavoriteCollections>();
  FavoriteCollections? oldThird;
  int revision = 0;

  FavoriteCollections _native(int page) {
    final fresh = revision > 0;
    final count = fresh
        ? 1
        : page == 1
            ? 36
            : page == 2
                ? 5
                : 10;
    final snapshot = FavoriteCollections(
      page: fresh ? 1 : page,
      pageCount: fresh ? 1 : 3,
      categories: const [FavoriteCategory(id: '0', label: '默认分类')],
      items: [
        for (var i = 1; i <= count; i++)
          FavoriteCollectionEntry(
            id: fresh ? '901' : '${page * 100 + i}',
            categoryId: '0',
            thread: UserListItem(
              title: fresh
                  ? 'Fresh authoritative row'
                  : page == 3
                      ? 'retired page 3 row $i'
                      : 'Initial page $page row $i',
              url: 'read.php?tid-${fresh ? 901 : page * 100 + i}.html',
            ),
          ),
      ],
    );
    nativeRevisions[snapshot] = revision;
    return snapshot;
  }

  @override
  Future<FavoriteCollections> fetchFavoriteCollections({String? categoryId}) =>
      fetchFavoriteCollectionsPage(categoryId: categoryId);

  @override
  Future<FavoriteCollections> fetchFavoriteCollectionsPage(
      {String? categoryId, int page = 1}) async {
    requests.add(page);
    final snapshot = _native(page);
    if (page == 3 && revision == 0) {
      oldThird = snapshot;
      return await third.future;
    }
    return snapshot;
  }

  @override
  Future<FavoriteCollectionMutation> removeFavorites(
      FavoriteCollections snapshot,
      List<FavoriteCollectionEntry> entries) async {
    writes.add((snapshot, List.of(entries)));
    if (writes.length == 1) {
      revision++;
      return FavoriteCollectionMutation(
        status: FavoriteMutationStatus.confirmed,
        message: 'Fixture confirmed write',
        collections: _native(1),
      );
    }
    return FavoriteCollectionMutation(
      status: FavoriteMutationStatus.rejected,
      message: 'Fixture stops after inspecting the second call',
    );
  }
}

void main() {
  testWidgets(
      'a confirmed favorites write retires an older pending page and binds the fresh snapshot',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'settings.loading.favorites': 'continuous'});
    await LoadingPreferences.load();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _RevisionRepository();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: FavoriteThreadsPage(repository: repository)),
    ));
    await tester.pumpAndSettle();
    try {
      for (var attempt = 0;
          attempt < 3 && repository.oldThird == null;
          attempt++) {
        await tester.drag(find.byType(ListView), const Offset(0, 200));
        await tester.drag(find.byType(ListView), const Offset(0, -20000));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(repository.requests, [1, 2, 3]);
      expect(repository.oldThird, isNotNull,
          reason: 'The old native page must already be on its way');
      expect(find.textContaining('第 1–2/3 页'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('favorite-select-start')));
      await tester.pump(const Duration(milliseconds: 300));
      final selected = find.byKey(const ValueKey('favorite-select:205'));
      await tester.ensureVisible(selected);
      await tester.tap(selected);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('favorite-remove-selected')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
      await tester.pumpAndSettle();
      expect(repository.writes, hasLength(1));
      expect(find.text('Fresh authoritative row'), findsOneWidget);
      repository.third.complete(repository.oldThird!);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'A retired page read must not leave a loading spinner');
      final retiredRows = find
          .textContaining('retired page 3', skipOffstage: false)
          .evaluate()
          .length;
      final retiredHeader = find
          .textContaining('第 1–3/3 页', skipOffstage: false)
          .evaluate()
          .isNotEmpty;
      // Let the first notification leave the action bar unobstructed.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('favorite-select-start')));
      await tester.pumpAndSettle();
      final freshRow = find.byKey(const ValueKey('favorite-select:901'));
      await tester.ensureVisible(freshRow);
      await tester.tap(freshRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('favorite-remove-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
      await tester.pumpAndSettle();
      debugPrint(
          'FAVORITE_REVISION retiredRows=$retiredRows header=$retiredHeader '
          'requests=${repository.requests} '
          'writePages=${repository.writes.map((write) => write.$1.page).toList()}');
      expect(repository.writes.map((write) => write.$1.page), [2, 1]);
      expect(
          repository.writes.map((write) => write.$2.single.id), ['205', '901']);
      expect(repository.nativeRevisions[repository.writes.first.$1], 0);
      expect(repository.nativeRevisions[repository.writes.last.$1], 1);
      for (final (snapshot, entries) in repository.writes) {
        expect(repository.nativeRevisions.containsKey(snapshot), isTrue,
            reason: 'A display-only merged copy is not a native capability');
        expect(
            entries.every(
                (entry) => snapshot.items.any((raw) => identical(raw, entry))),
            isTrue);
      }
      expect(tester.takeException(), isNull);
      expect(retiredRows, 0,
          reason:
              'The write retires reads started against the previous revision');
      expect(retiredHeader, isFalse);
    } finally {
      if (!repository.third.isCompleted && repository.oldThird != null) {
        repository.third.complete(repository.oldThird!);
      }
    }
  });
}
