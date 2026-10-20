import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/friends_screen.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

import 'app_redesign_fixture.dart';

class _FriendsRepository extends AppRedesignRepository {
  final requests = <(String?, bool, int)>[];

  @override
  Future<ForumFriendPage> fetchFriends({bool pending = false, int page = 1}) {
    requests.add((currentUsername, pending, page));
    return SynchronousFuture(ForumFriendPage(
      pending: pending,
      page: page,
      pageCount: pending ? 1 : 3,
      items: pending
          ? const []
          : [
              ForumFriend(
                uid: '${100 + page}',
                name: '$currentUsername friend page $page',
                url: 'u.php?uid-${100 + page}.html',
              ),
            ],
    ));
  }
}

void main() {
  testWidgets('an old friend page picker cannot change the new account page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FriendsRepository();
    await tester
        .pumpWidget(MaterialApp(home: FriendsScreen(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('fixture-owner-a friend page 1'), findsOneWidget);
    final picker = find.byTooltip('选择页码');
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    expect(picker.hitTestable(), findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    repository.changeOwner('fixture-owner-b');
    await tester.pump();
    expect(find.text('fixture-owner-a friend page 1', skipOffstage: false),
        findsNothing);
    expect(find.text('登录状态已变化', skipOffstage: false), findsOneWidget);
    expect(repository.requests.where((read) => read.$1 == 'fixture-owner-b'),
        isEmpty);
    final oldSecond =
        find.descendant(of: find.byType(BottomSheet), matching: find.text('2'));
    expect(oldSecond.hitTestable(), findsOneWidget);
    await tester.tap(oldSecond);
    await tester.pumpAndSettle();
    final leakedSecond = repository.requests.any(
        (read) => read.$1 == 'fixture-owner-b' && !read.$2 && read.$3 == 2);
    expect(find.byType(BottomSheet), findsNothing);
    final retry = find.text('重试');
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    final newPages = repository.requests
        .where((read) => read.$1 == 'fixture-owner-b' && !read.$2)
        .map((read) => read.$3)
        .toList();
    debugPrint('FRIENDS_OLD_PICKER leakedSecond=$leakedSecond '
        'newPages=$newPages allRequests=${repository.requests}');
    expect(leakedSecond, isFalse,
        reason: 'The retired picker must not invoke its old page callback');
    expect(newPages, [1], reason: 'Reload starts the new account at page 1');
    expect(find.text('fixture-owner-b friend page 1'), findsOneWidget);
    expect(find.text('fixture-owner-b friend page 2', skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
