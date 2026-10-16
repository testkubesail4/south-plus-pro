import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic titles and tokens only.
const _removable = UserListItem(
  title: 'Fixture favourite A',
  url: 'read.php?tid-1.html',
  author: 'Fixture author',
  favoriteRemoval: FavoriteListRemoval(id: '11', verify: 'fixture-verify'),
);
const _fixed =
    UserListItem(title: 'Fixture favourite B', url: 'read.php?tid-2.html');

class _Repo extends ForumRepository {
  _Repo({this.succeed = true, this.gate});

  final bool succeed;
  final Completer<void>? gate;
  final removed = <UserListItem>[];
  var fresh = false;

  @override
  bool get isLoggedIn => true;

  @override
  Future<UserProfile> fetchUserProfileFavorites(String url) async =>
      UserProfile(uid: '1', name: 'fixture', url: 'u.php', favorites: [
        // A reload brings the same rows back as new objects.
        fresh ? _copy(_removable) : _removable,
        _fixed,
      ]);

  @override
  Future<FavoriteResult> removeFavoriteFromList(UserListItem item) async {
    removed.add(item);
    await gate?.future;
    return FavoriteResult(
      success: succeed,
      message: succeed ? '已取消收藏' : 'fixture refusal',
      state: succeed
          ? ThreadFavoriteState.notFavorite
          : ThreadFavoriteState.favorite,
    );
  }
}

UserListItem _copy(UserListItem item) => UserListItem(
      title: item.title,
      url: item.url,
      author: item.author,
      favoriteRemoval: item.favoriteRemoval,
    );

void main() {
  Future<_Repo> pump(WidgetTester tester,
      {bool succeed = true, Completer<void>? gate}) async {
    final repo = _Repo(succeed: succeed, gate: gate);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FavoriteThreadsPage(repository: repo)),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> chooseRemove(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏').last);
    await tester.pumpAndSettle();
  }

  testWidgets('only rows the site lets us remove offer 取消收藏', (tester) async {
    await pump(tester);
    expect(find.text('2 个主题'), findsOneWidget);
    expect(find.byTooltip('更多'), findsOneWidget);
  });

  testWidgets('取消收藏 asks first, then removes the row', (tester) async {
    final repo = await pump(tester);
    await chooseRemove(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.removed, isEmpty, reason: 'nothing is sent before confirming');

    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(repo.removed, [same(_removable)]);
    expect(find.text('Fixture favourite A'), findsNothing);
    expect(find.text('Fixture favourite B'), findsOneWidget);
    expect(find.text('1 个主题'), findsOneWidget);
    expect(find.text('已取消收藏'), findsOneWidget);
  });

  testWidgets('dismissing the confirmation keeps the favourite',
      (tester) async {
    final repo = await pump(tester);
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(TextButton, '保留'));
    await tester.pumpAndSettle();
    expect(repo.removed, isEmpty);
    expect(find.text('Fixture favourite A'), findsOneWidget);
  });

  testWidgets('long-pressing a row opens the same menu', (tester) async {
    await pump(tester);
    await tester.longPress(find.text('Fixture favourite A'));
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsOneWidget);
    // A row without the site's token has no menu.
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Fixture favourite B'));
    await tester.pumpAndSettle();
    expect(find.text('取消收藏'), findsNothing);
  });

  testWidgets('a refused removal keeps the row and says why', (tester) async {
    final repo = await pump(tester, succeed: false);
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pumpAndSettle();
    expect(repo.removed, hasLength(1));
    expect(find.text('Fixture favourite A'), findsOneWidget);
    expect(find.textContaining('fixture refusal'), findsOneWidget);
  });

  testWidgets('a refresh during a removal still drops the removed row',
      (tester) async {
    final gate = Completer<void>();
    final repo = await pump(tester, gate: gate);
    await chooseRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, '取消收藏'));
    await tester.pump();

    repo.fresh = true;
    tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh()
        .ignore();
    // The row's spinner never settles; let the reload land.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('更多'), findsNothing,
        reason: 'the refreshed row is still being removed');

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Fixture favourite A'), findsNothing);
    expect(find.text('1 个主题'), findsOneWidget);
  });
}
