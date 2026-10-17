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

  /// Hold the forum's answers, so late replies can be tested.
  Completer<void>? holdAdd;
  Completer<void>? holdSelect;

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

  @override
  Future<FavoriteResult> addFavorite(ThreadFavorite favorite) async {
    calls.add('add');
    await holdAdd?.future;
    return FavoriteResult(
      success: false,
      message: '选择分类',
      state: ThreadFavoriteState.notFavorite,
      categorySelection: FavoriteCategorySelection(categories: const [
        FavoriteCategory(id: '0', label: '默认分类'),
        FavoriteCategory(id: '1', label: '资料'),
      ]),
    );
  }

  @override
  Future<FavoriteResult> selectFavoriteCategory(
      FavoriteCategorySelection selection, String categoryId) async {
    calls.add('select:$categoryId');
    await holdSelect?.future;
    return const FavoriteResult(
      success: true,
      message: '帖子收藏成功',
      state: ThreadFavoriteState.favorite,
    );
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

  Future<void> tapFavorite(WidgetTester tester) async {
    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    // The page behind keeps a busy spinner turning while the menu waits for a
    // choice, so it never settles: pump until the menu is really up.
    for (var i = 0; i < 20 && find.text('选择收藏分类').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('选择收藏分类'), findsOneWidget,
        reason: 'the category menu is shown');
  }

  testWidgets('a category menu asks first and favorites nothing yet',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    expect(find.text('选择收藏分类'), findsOneWidget);
    expect(find.text('默认分类'), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('选择分类'), findsNothing, reason: 'menu text is no notice');
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('已收藏'), findsNothing);
    expect(repo.calls, ['add']);
  });

  testWidgets('cancelling sends nothing, changes nothing, and can be retried',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['add']);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('已收藏'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    // Not left busy: the button works again.
    await tapFavorite(tester);
    expect(repo.calls, ['add', 'add']);
    expect(find.text('选择收藏分类'), findsOneWidget);
  });

  testWidgets('choosing a category completes it, and only then is it favorite',
      (tester) async {
    final repo = await pumpThread(tester);
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category:1')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['add', 'select:1']);
    expect(find.text('帖子收藏成功'), findsOneWidget);
    expect(find.text('已收藏'), findsOneWidget);
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
      'a session change while the forum is still answering shows no menu',
      (tester) async {
    final repo = await pumpThread(tester);
    repo.holdAdd = Completer<void>();
    await tester.ensureVisible(button('收藏'));
    await tester.tap(button('收藏'));
    await tester.pump();
    repo.holdAdd!.complete();
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['add']);
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
    expect(repo.calls, ['add']);
  });

  testWidgets('a session change closes the sheet and drops a late answer',
      (tester) async {
    final repo = await pumpThread(tester);
    repo.holdSelect = Completer<void>();
    await tapFavorite(tester);
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('选择收藏分类'), findsNothing);
    expect(repo.calls, ['add'], reason: 'closing is not a choice');

    // A choice already in flight when the session changes is ignored.
    await tapFavorite(tester);
    await tester.tap(find.byKey(const ValueKey('favorite-category:0')));
    await tester.pump();
    repo.epoch.value++;
    repo.holdSelect!.complete();
    await tester.pumpAndSettle();
    expect(repo.calls, ['add', 'add', 'select:0']);
    expect(find.text('已收藏'), findsNothing);
    expect(find.text('帖子收藏成功'), findsNothing);
    // The screen is not left busy by the obsolete call.
    await tapFavorite(tester);
    expect(repo.calls.where((c) => c == 'add'), hasLength(3));
  });
}
