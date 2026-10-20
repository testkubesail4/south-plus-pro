import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/friends_screen.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

// Synthetic friends only: 4 a page, 3 pages.
class _Repo extends ForumRepository {
  final pages = <int>[];
  final deleted = <(ForumFriendPage, List<ForumFriend>)>[];
  // Page 1 lists no one, though the forum counts 3 pages.
  bool emptyFirst = false;

  @override
  Future<ForumFriendPage> fetchFriends(
      {bool pending = false, int page = 1}) async {
    if (!pending) pages.add(page);
    return ForumFriendPage(
      pending: pending,
      page: page,
      pageCount: pending ? 1 : 3,
      items: pending || (emptyFirst && page == 1)
          ? const []
          : [
              for (var i = 0; i < 4; i++)
                ForumFriend(
                  uid: '${page * 100 + i}',
                  name: 'Friend ${page * 100 + i}',
                  url: 'u.php?uid-${page * 100 + i}.html',
                ),
            ],
    );
  }

  @override
  Future<ForumFriendMutationResult> deleteFriends(
      ForumFriendPage snapshot, List<ForumFriend> selected) async {
    deleted.add((snapshot, selected));
    return const ForumFriendMutationResult(confirmed: true, message: '');
  }
}

void main() {
  Future<_Repo> pump(WidgetTester tester, LoadingMode mode,
      {bool emptyFirst = false}) async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
    await LoadingPreferences.save(LoadingDomain.friends, mode);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()..emptyFirst = emptyFirst;
    await tester.pumpWidget(MaterialApp(home: FriendsScreen(repository: repo)));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> toEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
  }

  testWidgets('手动翻页: 下一页 turns to page 2 alone', (tester) async {
    final repo = await pump(tester, LoadingMode.manual);
    await toEnd(tester);
    expect(repo.pages, [1]);
    await tester.tap(find.byKey(const ValueKey('page-end-next')));
    await tester.pumpAndSettle();
    expect(repo.pages, [1, 2]);
    expect(find.text('Friend 200'), findsOneWidget);
    expect(find.text('Friend 100', skipOffstage: false), findsNothing);
  });

  testWidgets('自动接续 shows later friends under an empty first page',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous, emptyFirst: true);
    await toEnd(tester);
    expect(repo.pages.take(2), [1, 2]);
    expect(find.text('还没有好友'), findsNothing);
    expect(find.text('本页没有好友', skipOffstage: false), findsOneWidget);
    expect(find.text('Friend 200', skipOffstage: false), findsOneWidget);
  });

  testWidgets('自动接续 appends; a row is removed with the page it came on',
      (tester) async {
    final repo = await pump(tester, LoadingMode.continuous);
    await toEnd(tester);
    expect(repo.pages.take(2), [1, 2]);
    final read = repo.pages.length;

    final delete = find.byTooltip('删除好友 Friend 203');
    await tester.ensureVisible(delete);
    await tester.pumpAndSettle();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    final (snapshot, friends) = repo.deleted.single;
    expect(snapshot.page, 2);
    expect(friends.single.uid, '203');
    // The write retires the pages read before it: the list starts over.
    expect(repo.pages[read], 1);
  });
}
