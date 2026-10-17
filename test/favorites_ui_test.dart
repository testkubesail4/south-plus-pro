import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic titles and names only.
FavoriteCollectionEntry _entry(String id, String title, String category) =>
    FavoriteCollectionEntry(
      id: id,
      categoryId: category,
      thread: UserListItem(
          title: title, url: 'read.php?tid-$id.html', author: 'Fixture author'),
    );

enum _Mode { ok, reject, unknown, unknownNoSnapshot, noSnapshot, partial }

/// One forum: two categories and two favourites, and every answer a fresh
/// snapshot, as the real service returns.
class _Repo extends ForumRepository {
  final epoch = ValueNotifier<int>(0);
  var mode = _Mode.ok;
  Completer<void>? gate;

  /// A category whose read fails.
  String? failView;
  final calls = <String>[];

  /// Rows the forum's page leaves out (an incomplete view).
  Set<String> omit = {};
  var categories = [
    const FavoriteCategory(id: '0', label: '默认分类'),
    const FavoriteCategory(id: '1', label: '资料', canDelete: true),
  ];
  var entries = [
    _entry('11', 'Fixture favourite A', '0'),
    _entry('12', 'Fixture favourite B', '1'),
  ];

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  @override
  bool get isLoggedIn => true;

  /// What the forum says about its pages (page 1 of 1 unless a test says).
  int? pageCount = 1;

  FavoriteCollections _view(String? id) => FavoriteCollections(
        pageCount: pageCount,
        categories: categories,
        items: [
          for (final e in entries)
            if ((id == null || e.categoryId == id) && !omit.contains(e.id)) e,
        ],
        categoryId: id,
        canCreate: true,
      );

  @override
  Future<FavoriteCollections> fetchFavoriteCollections(
      {String? categoryId}) async {
    calls.add('fetch:${categoryId ?? 'all'}');
    if (categoryId != null &&
        (categoryId == failView ||
            !categories.any((c) => c.id == categoryId))) {
      throw StateError('synthetic read failure');
    }
    return _view(categoryId);
  }

  Future<FavoriteCollectionMutation> _answer(
    FavoriteCollections snapshot,
    String call,
    void Function() apply, {
    List<FavoriteItemMutation> items = const [],
  }) async {
    calls.add(call);
    await gate?.future;
    switch (mode) {
      case _Mode.reject:
        return FavoriteCollectionMutation(
            status: FavoriteMutationStatus.rejected,
            message: 'fixture refusal',
            collections: _view(null));
      case _Mode.unknown:
        return FavoriteCollectionMutation(
            status: FavoriteMutationStatus.unknown,
            message: '',
            collections: _view(null));
      case _Mode.unknownNoSnapshot:
        apply();
        return FavoriteCollectionMutation(
            status: FavoriteMutationStatus.unknown, message: '');
      case _Mode.noSnapshot:
        apply();
        return FavoriteCollectionMutation(
            status: FavoriteMutationStatus.confirmed, message: 'ok');
      case _Mode.partial:
        // As the real service answers: one rejected item rejects the whole,
        // and items[] says which went through.
        apply();
        return FavoriteCollectionMutation(
            status: FavoriteMutationStatus.rejected,
            message: 'fixture partial',
            collections: _view(null),
            items: items);
      case _Mode.ok:
        apply();
        return FavoriteCollectionMutation(
            status: FavoriteMutationStatus.confirmed,
            message: 'ok',
            collections: _view(null),
            items: items);
    }
  }

  @override
  Future<FavoriteCollectionMutation> removeFavorites(
    FavoriteCollections snapshot,
    List<FavoriteCollectionEntry> chosen,
  ) =>
      _answer(snapshot, 'remove:${chosen.map((e) => e.id).join(',')}', () {
        entries = [
          for (final e in entries)
            if (!chosen.any((c) => c.id == e.id)) e,
        ];
      });

  @override
  Future<FavoriteCollectionMutation> moveFavorites(
    FavoriteCollections snapshot,
    List<FavoriteCollectionEntry> chosen,
    String toCategoryId,
  ) {
    final moved = mode == _Mode.partial ? chosen.take(1).toList() : chosen;
    return _answer(
      snapshot,
      'move:${chosen.map((e) => e.id).join(',')}>$toCategoryId',
      () {
        entries = [
          for (final e in entries)
            moved.any((c) => c.id == e.id)
                ? _entry(e.id, e.thread.title, toCategoryId)
                : e,
        ];
      },
      items: [
        for (final e in chosen)
          FavoriteItemMutation(
              id: e.id,
              status: moved.contains(e)
                  ? FavoriteMutationStatus.confirmed
                  : FavoriteMutationStatus.rejected),
      ],
    );
  }

  @override
  Future<FavoriteCollectionMutation> createFavoriteCategory(
    FavoriteCollections snapshot,
    String name,
  ) =>
      _answer(snapshot, 'create:$name', () {
        categories = [
          ...categories,
          FavoriteCategory(
              id: '${categories.length}', label: name, canDelete: true),
        ];
      });

  @override
  Future<FavoriteCollectionMutation> deleteFavoriteCategory(
    FavoriteCollections snapshot,
    String categoryId,
  ) =>
      _answer(snapshot, 'delete:$categoryId', () {
        // The site moves the favourites to 默认分类 and renumbers.
        entries = [
          for (final e in entries)
            e.categoryId == categoryId ? _entry(e.id, e.thread.title, '0') : e,
        ];
        categories = [
          for (final c in categories)
            if (c.id != categoryId) c,
        ];
      });
}

class _PushWatcher extends NavigatorObserver {
  var pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  Future<_Repo> pump(WidgetTester tester,
      [_Repo? repo, NavigatorObserver? watcher]) async {
    repo ??= _Repo();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [if (watcher != null) watcher],
      home: Scaffold(body: FavoriteThreadsPage(repository: repo)),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.tap(key(k));
    await tester.pumpAndSettle();
  }

  Future<void> chooseRemove(WidgetTester tester, [int row = 0]) async {
    await tester.tap(find.byTooltip('更多').at(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏').last);
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, List<String> ids) async {
    await tapKey(tester, 'favorite-select-start');
    for (final id in ids) {
      await tapKey(tester, 'favorite-select:$id');
    }
  }

  testWidgets('shows every favourite with its category and the views',
      (tester) async {
    final repo = await pump(tester);
    expect(repo.calls, ['fetch:all']);
    expect(find.text('已加载 2 个主题'), findsOneWidget);
    expect(find.text('Fixture favourite A'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(key('favorite-folder:1'), findsOneWidget);
    expect(find.textContaining('资料 · Fixture author'), findsOneWidget);
  });

  testWidgets('more pages, or an unreadable pager, is said and never guessed',
      (tester) async {
    final repo = _Repo()..pageCount = 3;
    await pump(tester, repo);
    expect(find.text('已加载 2 个主题 · 第 1/3 页'), findsOneWidget);
    repo.pageCount = null;
    await tester.pumpWidget(const SizedBox());
    await pump(tester, repo);
    expect(find.text('已加载 2 个主题 · 页数未能确认'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets(
      'an empty page of an unknown or longer list is not "no favorites"',
      (tester) async {
    for (final pages in <int?>[null, 3]) {
      final repo = _Repo()
        ..entries = []
        ..pageCount = pages;
      await tester.pumpWidget(const SizedBox());
      await pump(tester, repo);
      expect(find.text('本页没有主题'), findsOneWidget, reason: '$pages');
      expect(find.text('还没有收藏'), findsNothing, reason: '$pages');
      expect(
          find.text(
              pages == null ? '已加载 0 个主题 · 页数未能确认' : '已加载 0 个主题 · 第 1/3 页'),
          findsOneWidget);
      expect(find.textContaining('下拉刷新'), findsOneWidget);
    }
    // A complete single page that is empty says so.
    final empty = _Repo()..entries = [];
    await tester.pumpWidget(const SizedBox());
    await pump(tester, empty);
    expect(find.text('还没有收藏'), findsOneWidget);
  });

  testWidgets('a category view asks for that category only', (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-folder:1');
    expect(repo.calls.last, 'fetch:1');
    expect(find.text('Fixture favourite B'), findsOneWidget);
    expect(find.text('Fixture favourite A'), findsNothing);
    repo.entries = [];
    await tapKey(tester, 'favorite-folder:0');
    expect(find.text('这个分类还没有主题'), findsOneWidget);
  });

  testWidgets(
      'a failed category read never shows the old rows under the new '
      'name, nor writes against them', (tester) async {
    final repo = await pump(tester);
    repo.failView = '1';
    await tapKey(tester, 'favorite-folder:1');
    expect(find.text('收藏加载失败'), findsOneWidget);
    expect(find.text('Fixture favourite A'), findsNothing);
    expect(find.text('Fixture favourite B'), findsNothing);
    expect(tester.widget<ActionChip>(key('favorite-manage')).onPressed, isNull);
    expect(key('favorite-select-start'), findsNothing);
    expect(find.byTooltip('更多'), findsNothing);

    repo.failView = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'fetch:1');
    expect(find.text('Fixture favourite B'), findsOneWidget);
    expect(find.text('Fixture favourite A'), findsNothing);
    expect(find.text('收藏加载失败'), findsNothing);
  });

  testWidgets('a change made inside a category stays inside it',
      (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-folder:1');
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    // The forum answers with everything; the page asks for the view again.
    expect(repo.calls.takeLast(2), ['remove:12', 'fetch:1']);
    expect(
        tester.widget<ChoiceChip>(key('favorite-folder:1')).selected, isTrue);
    expect(find.text('这个分类还没有主题'), findsOneWidget);
    expect(find.text('Fixture favourite A'), findsNothing);
  });

  testWidgets(
      'unfinished rows stay chosen after a partial change in a category',
      (tester) async {
    final repo = _Repo()
      ..entries = [
        _entry('11', 'Fixture favourite A', '1'),
        _entry('12', 'Fixture favourite B', '1')
      ]
      ..mode = _Mode.partial;
    await pump(tester, repo);
    await tapKey(tester, 'favorite-folder:1');
    await select(tester, ['11', '12']);
    await tapKey(tester, 'favorite-move');
    await tapKey(tester, 'favorite-move-to:0');
    expect(repo.calls.last, 'fetch:1', reason: 'back in the category');
    expect(find.text('已选 1 个'), findsOneWidget);
    expect(find.text('Fixture favourite A'), findsNothing, reason: 'moved');
    expect(tester.widget<Checkbox>(key('favorite-select:12')).value, isTrue);
  });

  testWidgets('a category that was renumbered is found again by its name',
      (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-folder:1');
    // Another page deleted a category: 资料 is number 2 now.
    repo.categories = [
      const FavoriteCategory(id: '0', label: '默认分类'),
      const FavoriteCategory(id: '2', label: '资料', canDelete: true),
    ];
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'fetch:2', reason: 'by name, not the old number');
    expect(
        tester.widget<ChoiceChip>(key('favorite-folder:2')).selected, isTrue);
    expect(key('favorite-folder:1'), findsNothing);
  });

  testWidgets('取消收藏 asks first, then removes the row', (tester) async {
    final repo = await pump(tester);
    await chooseRemove(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.calls, ['fetch:all'],
        reason: 'nothing is sent before confirming');

    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'remove:11');
    expect(find.text('Fixture favourite A'), findsNothing);
    expect(find.text('已加载 1 个主题'), findsOneWidget);
    expect(find.text('已取消收藏'), findsOneWidget);
  });

  testWidgets('dismissing the confirmation keeps the favourite',
      (tester) async {
    final repo = await pump(tester);
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(TextButton, '保留'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['fetch:all']);
    expect(find.text('Fixture favourite A'), findsOneWidget);
  });

  testWidgets('long-pressing a row opens the same menu', (tester) async {
    await pump(tester);
    await tester.longPress(find.text('Fixture favourite A'));
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsOneWidget);
    expect(find.text('移动到…'), findsOneWidget);
    expect(find.text('多选'), findsOneWidget);
  });

  testWidgets('a refused removal keeps the row and says why', (tester) async {
    final repo = await pump(tester);
    repo.mode = _Mode.reject;
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'remove:11');
    expect(find.text('Fixture favourite A'), findsOneWidget);
    expect(find.text('fixture refusal'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-unconfirmed')), findsNothing,
        reason: 'a refusal is known, nothing is locked');
  });

  testWidgets('choosing rows then moving them is one request', (tester) async {
    final repo = await pump(tester);
    await select(tester, ['11', '12']);
    expect(find.text('已选 2 个'), findsOneWidget);
    await tapKey(tester, 'favorite-move');
    expect(find.text('移动 2 个主题到…'), findsOneWidget);
    await tapKey(tester, 'favorite-move-to:1');
    expect(repo.calls.where((c) => c.startsWith('move')), ['move:11,12>1']);
    expect(find.text('已移动 2 个到「资料」'), findsOneWidget);
    expect(find.text('已选 2 个'), findsNothing, reason: 'selection is over');
  });

  testWidgets('what the forum did not finish stays selected', (tester) async {
    final repo = await pump(tester);
    repo.mode = _Mode.partial;
    await select(tester, ['11', '12']);
    await tapKey(tester, 'favorite-move');
    await tapKey(tester, 'favorite-move-to:1');
    expect(find.text('已完成 1 个，还有 1 个未完成'), findsOneWidget);
    expect(find.text('已选 1 个'), findsOneWidget);
    expect(tester.widget<Checkbox>(key('favorite-select:11')).value, isFalse);
    expect(tester.widget<Checkbox>(key('favorite-select:12')).value, isTrue);
    expect(repo.calls.where((c) => c.startsWith('move')), hasLength(1));
  });

  testWidgets('an unfinished row the page no longer shows is not left chosen',
      (tester) async {
    final repo = await pump(tester);
    repo.mode = _Mode.partial;
    await select(tester, ['11', '12']);
    repo.omit = {'12'};
    await tapKey(tester, 'favorite-move');
    await tapKey(tester, 'favorite-move-to:1');
    expect(find.text('已完成 1 个，还有 1 个未完成'), findsOneWidget);
    expect(find.textContaining('已选'), findsNothing, reason: 'choosing is over');
    expect(key('favorite-select:12'), findsNothing);
    expect(key('favorite-remove-selected'), findsNothing,
        reason: 'no action on a row nobody sees');
  });

  testWidgets('全选 takes the loaded rows, 完成 leaves choosing', (tester) async {
    await pump(tester);
    await tapKey(tester, 'favorite-select-start');
    await tapKey(tester, 'favorite-select-all');
    expect(find.text('已选 2 个'), findsOneWidget);
    await tapKey(tester, 'favorite-select-all');
    expect(find.text('已选 0 个'), findsOneWidget);
    expect(
        tester.widget<FilledButton>(key('favorite-remove-selected')).onPressed,
        isNull);
    await tapKey(tester, 'favorite-select-exit');
    expect(key('favorite-select:11'), findsNothing);
    expect(find.text('已加载 2 个主题'), findsOneWidget);
  });

  testWidgets('removing several asks once and sends one request',
      (tester) async {
    final repo = await pump(tester);
    await select(tester, ['11', '12']);
    await tapKey(tester, 'favorite-remove-selected');
    expect(
        find.text(
            '2 个主题将从收藏中移除：\n「Fixture favourite A」\n「Fixture favourite B」'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏').last);
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('remove')), ['remove:11,12']);
    expect(find.text('已取消收藏 2 个'), findsOneWidget);
    expect(find.text('还没有收藏'), findsOneWidget);
  });

  testWidgets('an unknown result locks writing until the list is read again',
      (tester) async {
    final repo = await pump(tester);
    repo.mode = _Mode.unknown;
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(find.text('结果未确认，请刷新核对'), findsWidgets);
    expect(
        tester.widget<ChoiceChip>(key('favorite-folder:1')).onSelected, isNull);
    expect(tester.widget<ActionChip>(key('favorite-manage')).onPressed, isNull);
    expect(tester.widget<TextButton>(key('favorite-select-start')).onPressed,
        isNull);
    expect(repo.calls.where((c) => c.startsWith('remove')), hasLength(1),
        reason: 'never sent a second time');

    repo.mode = _Mode.ok;
    await tapKey(tester, 'favorite-refresh');
    expect(repo.calls.last, 'fetch:all');
    expect(key('favorite-unconfirmed'), findsNothing);
    expect(
        tester.widget<ActionChip>(key('favorite-manage')).onPressed, isNotNull);
  });

  testWidgets('an answer without a fresh list makes the page read it again',
      (tester) async {
    final repo = await pump(tester);
    repo.mode = _Mode.noSnapshot;
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(repo.calls.takeLast(2), ['remove:11', 'fetch:all']);
    expect(find.text('Fixture favourite A'), findsNothing);
  });

  testWidgets('an unknown delete of the open category is read back from all',
      (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-folder:1');
    repo.mode = _Mode.unknownNoSnapshot;
    await tapKey(tester, 'favorite-manage');
    await tapKey(tester, 'favorite-folder-delete:1');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('结果未确认，请刷新核对'), findsWidgets);
    expect(tester.widget<ChoiceChip>(key('favorite-folder:all')).onSelected,
        isNull,
        reason: 'locked until read again');
    // The forum already dropped the category; its old number is gone.
    await tapKey(tester, 'favorite-refresh');
    expect(repo.calls.last, 'fetch:all', reason: 'not the vanished number');
    expect(key('favorite-unconfirmed'), findsNothing);
    expect(key('favorite-folder:1'), findsNothing);
    expect(find.text('Fixture favourite B'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('delete')), ['delete:1'],
        reason: 'nothing is sent a second time');
  });

  testWidgets('a new category is named, created, and shown', (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-manage');
    await tapKey(tester, 'favorite-folder-new');
    expect(
        tester.widget<FilledButton>(key('favorite-category-create')).onPressed,
        isNull,
        reason: 'a name is needed');
    await tester.enterText(key('favorite-category-name'), '  阅读  ');
    await tester.pump();
    await tapKey(tester, 'favorite-category-create');
    expect(repo.calls.last, 'create:阅读');
    expect(find.text('已新建分类「阅读」'), findsOneWidget);
    expect(key('favorite-folder:2'), findsOneWidget);
  });

  testWidgets('cancelling the name sends nothing', (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-manage');
    await tapKey(tester, 'favorite-folder-new');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['fetch:all']);
  });

  testWidgets(
      'deleting a category says where its favourites go; the default '
      'has no delete', (tester) async {
    final repo = await pump(tester);
    await tester.tap(key('favorite-folder:1'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'favorite-manage');
    expect(key('favorite-folder-delete:0'), findsNothing);
    await tapKey(tester, 'favorite-folder-delete:1');
    expect(find.text('删除分类「资料」？'), findsOneWidget);
    expect(find.text('其中的主题会移到默认分类。'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('delete')), ['delete:1']);
    expect(repo.calls.last, 'fetch:all',
        reason: 'numbers shift, so the view starts from all again');
    expect(key('favorite-folder:1'), findsNothing);
    expect(find.text('Fixture favourite B'), findsOneWidget);
  });

  testWidgets('a session change closes an open sheet and clears the page',
      (tester) async {
    final repo = await pump(tester);
    await tapKey(tester, 'favorite-manage');
    expect(find.text('收藏分类'), findsOneWidget);
    repo.entries = [_entry('99', 'Other account favourite', '0')];
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('收藏分类'), findsNothing);
    expect(find.text('Fixture favourite A'), findsNothing);
    expect(find.text('Other account favourite'), findsOneWidget);
  });

  // Each route below is pushed by the tap itself; the session then changes
  // before any frame is drawn, and nothing of the old account may show.
  Future<void> untilPushed(_PushWatcher w, int count) async {
    for (var i = 0; i < 50 && w.pushes < count; i++) {
      await Future<void>.microtask(() {});
    }
    expect(w.pushes, count, reason: 'the route is pushed');
  }

  testWidgets('the manage sheet pushed before a session change shows nothing',
      (tester) async {
    final watcher = _PushWatcher();
    final repo = await pump(tester, null, watcher);
    final before = watcher.pushes;
    await tester.tap(key('favorite-manage'));
    await untilPushed(watcher, before + 1);
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('收藏分类'), findsNothing);
    expect(key('favorite-folder-delete:1'), findsNothing);
  });

  testWidgets('the move sheet pushed before a session change shows nothing',
      (tester) async {
    final watcher = _PushWatcher();
    final repo = await pump(tester, null, watcher);
    await select(tester, ['11']);
    final before = watcher.pushes;
    await tester.tap(key('favorite-move'));
    await untilPushed(watcher, before + 1);
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.textContaining('移动 1 个主题到'), findsNothing);
    expect(key('favorite-move-to:1'), findsNothing);
  });

  testWidgets('the delete and name dialogs likewise', (tester) async {
    final watcher = _PushWatcher();
    final repo = await pump(tester, null, watcher);
    for (final (action, text) in [
      ('favorite-folder-delete:1', '删除分类'),
      ('favorite-folder-new', '新建分类'),
    ]) {
      await tapKey(tester, 'favorite-manage');
      final before = watcher.pushes;
      await tester.tap(key(action));
      await untilPushed(watcher, before + 1);
      repo.epoch.value++;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing, reason: text);
      expect(find.textContaining('删除分类「'), findsNothing, reason: text);
      expect(key('favorite-category-name'), findsNothing, reason: text);
    }
    expect(
        repo.calls
            .where((c) => c.startsWith('delete') || c.startsWith('create')),
        isEmpty);
  });

  testWidgets('an answer that arrives after a session change is dropped',
      (tester) async {
    final gate = Completer<void>();
    final repo = await pump(tester);
    repo.gate = gate;
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pump();
    repo.entries = [_entry('99', 'Other account favourite', '0')];
    repo.epoch.value++;
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('已取消收藏'), findsNothing);
    expect(find.text('Other account favourite'), findsOneWidget);
  });
}

extension on List<String> {
  List<String> takeLast(int n) => sublist(length - n);
}
