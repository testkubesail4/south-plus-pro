import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only: fictional tid and categories.
const _url = 'https://south-plus.net/read.php?tid-7.html';

class _Repo extends ForumRepository {
  final epoch = ValueNotifier<int>(0);
  final calls = <String>[];
  var categories = [
    const FavoriteCategory(id: '0', label: '默认分类'),
    const FavoriteCategory(id: '1', label: '资料'),
  ];
  var addStatus = FavoriteMutationStatus.confirmed;

  /// Hold the forum's answers, so late replies can be tested.
  Completer<void>? holdFetch;
  Completer<void>? holdAdd;

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
      ForumThread t, ThreadReadPosition p) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread,
          {int page = 1}) async =>
      ThreadDetail(
        thread: thread.copyWith(title: '合成主题', author: '楼主甲'),
        body: 'body',
        replies: const [],
        favorite: const ThreadFavorite(
          tid: '7',
          verify: 'synthetic',
          state: ThreadFavoriteState.notFavorite,
        ),
      );

  FavoriteCollections _snapshot() => FavoriteCollections(
      categories: categories, items: const [], canCreate: true);

  // A read: it must never favorite anything.
  @override
  Future<FavoriteCollections> fetchFavoriteCollections(
      {String? categoryId}) async {
    calls.add('fetch');
    await holdFetch?.future;
    return _snapshot();
  }

  @override
  Future<FavoriteCollectionMutation> createFavoriteCategory(
      FavoriteCollections snapshot, String name) async {
    calls.add('create:$name');
    categories = [
      ...categories,
      FavoriteCategory(id: '${categories.length}', label: name),
    ];
    return FavoriteCollectionMutation(
        status: FavoriteMutationStatus.confirmed,
        message: 'ok',
        collections: _snapshot());
  }

  @override
  Future<FavoriteCollectionMutation> addFavoriteToCollection(
      FavoriteCollections snapshot,
      ThreadFavorite favorite,
      String categoryId) async {
    calls.add('add:$categoryId');
    await holdAdd?.future;
    return FavoriteCollectionMutation(
        status: addStatus,
        message: addStatus == FavoriteMutationStatus.confirmed
            ? '帖子收藏成功'
            : 'synthetic refusal');
  }
}

class _PushWatcher extends NavigatorObserver {
  var pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pumpThread(WidgetTester tester,
      {NavigatorObserver? watcher}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [if (watcher != null) watcher],
      home: ThreadDetailScreen(
        repository: repo,
        thread:
            const ForumThread(title: '', url: _url, replies: 0, section: ''),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder button(String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      )
      .first;

  // The page behind keeps a busy spinner turning while the menu waits for a
  // choice, so it never settles: pump until [done] holds.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 20 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool menuUp() => find.text('选择收藏分类').evaluate().isNotEmpty;

  Future<void> tapFavorite(WidgetTester tester) async {
    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    await pumpUntil(tester, menuUp);
    expect(find.text('选择收藏分类'), findsOneWidget,
        reason: 'the category menu is shown');
  }

  testWidgets('the menu comes from a read and favorites nothing yet',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    expect(find.text('默认分类'), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-category-new')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('已收藏'), findsNothing);
    expect(repo.calls, ['fetch'], reason: 'opening the menu writes nothing');
  });

  testWidgets('cancelling sends nothing, changes nothing, and can be retried',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['fetch']);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('已收藏'), findsNothing);
    // Not left busy: the button works again.
    await tapFavorite(tester);
    expect(repo.calls, ['fetch', 'fetch']);
  });

  testWidgets('choosing a category is the one write, and only then favorite',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category:1')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['fetch', 'add:1']);
    expect(find.text('帖子收藏成功'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);
  });

  testWidgets('a refusal or an unknown answer does not mark it favorite',
      (tester) async {
    for (final status in [
      FavoriteMutationStatus.rejected,
      FavoriteMutationStatus.unknown,
    ]) {
      // A real remount: the first round's snackbar and state must not carry over.
      await tester.pumpWidget(const SizedBox());
      final repo = await pumpThread(tester);
      repo.addStatus = status;
      await tapFavorite(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-category:1')));
      await tester.pumpAndSettle();
      expect(find.text('已收藏'), findsNothing, reason: '$status');
      expect(
          find.text(status == FavoriteMutationStatus.unknown
              ? '收藏的结果未确认，请刷新核对'
              : 'synthetic refusal'),
          findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('add')), hasLength(1));
    }
  });

  testWidgets('with only the default category the menu still asks first',
      (tester) async {
    final repo = await pumpThread(tester);
    repo.categories = [const FavoriteCategory(id: '0', label: '默认分类')];
    await tapFavorite(tester);
    expect(repo.calls, ['fetch'], reason: 'nothing is written before a pick');
    expect(find.byKey(const ValueKey('favorite-category-new')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-category:0')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['fetch', 'add:0']);
    expect(find.text('已收藏'), findsOneWidget);
  });

  testWidgets('a category list without the default is an error, not a write',
      (tester) async {
    final repo = await pumpThread(tester);
    repo.categories = [];
    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('没有读到收藏分类，请稍后重试'), findsOneWidget);
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['fetch']);
    expect(find.text('收藏'), findsOneWidget, reason: 'not left busy');
  });

  testWidgets('a new category is only added; choosing it is a separate step',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category-new')));
    // The thread's busy spinner keeps turning behind the dialog: wait for the
    // dialog itself, not for the page to go idle.
    await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('favorite-category-name'))
            .evaluate()
            .isNotEmpty);
    expect(
        find.byKey(const ValueKey('favorite-category-name')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('favorite-category-name')), '阅读');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-category-create')));
    await pumpUntil(tester, menuUp);
    expect(repo.calls, ['fetch', 'create:阅读']);
    expect(find.text('已新建分类「阅读」，请选择分类'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-category:2')), findsOneWidget,
        reason: 'the menu is back, with the new category in it');
    expect(find.text('已收藏'), findsNothing,
        reason: 'creating is not favoriting');

    // Walking away now leaves the category and no favorite.
    await tester.tap(find.byKey(const ValueKey('favorite-category-cancel')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('add')), isEmpty);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets('another session never inherits the last favorite state',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category:1')));
    await tester.pumpAndSettle();
    expect(find.text('已收藏'), findsOneWidget);
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('已收藏'), findsNothing);
    expect(find.text('收藏'), findsOneWidget);
  });

  testWidgets(
      'a session change while the categories are being read shows no '
      'menu', (tester) async {
    final repo = await pumpThread(tester);
    repo.holdFetch = Completer<void>();
    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    await tester.pump();
    repo.holdFetch!.complete();
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['fetch']);
    repo.holdFetch = null;
    await tapFavorite(tester);
    expect(find.text('选择收藏分类'), findsOneWidget);
  });

  testWidgets(
      'a session change after the sheet is pushed but before its first frame '
      'shows no categories', (tester) async {
    final watcher = _PushWatcher();
    final repo = await pumpThread(tester, watcher: watcher);
    final before = watcher.pushes;
    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    // Let the answer arrive without drawing a frame.
    for (var i = 0; i < 50 && watcher.pushes == before; i++) {
      await Future<void>.microtask(() {});
    }
    expect(watcher.pushes, before + 1, reason: 'the sheet route is pushed');
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(find.text('默认分类'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(repo.calls, ['fetch']);
  });

  testWidgets('a session change closes the sheet and drops a late answer',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['fetch'], reason: 'closing is not a choice');

    // A choice already in flight when the session changes is ignored.
    repo.holdAdd = Completer<void>();
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category:0')));
    await tester.pump();
    repo.epoch.value++;
    repo.holdAdd!.complete();
    await tester.pumpAndSettle();
    expect(repo.calls, ['fetch', 'fetch', 'add:0']);
    expect(find.text('已收藏'), findsNothing);
    expect(find.text('帖子收藏成功'), findsNothing);
    // The screen is not left busy by the obsolete call.
    repo.holdAdd = null;
    await tapFavorite(tester);
    expect(repo.calls.where((c) => c == 'fetch'), hasLength(3));
  });
}
