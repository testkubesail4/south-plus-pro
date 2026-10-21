import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/friends_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';

import 'profile_appendfix_support.dart';

const _self = '900';

ForumFriend _friend(String uid, String name, {String? message}) => ForumFriend(
      uid: uid,
      name: name,
      url: 'https://south-plus.net/u.php?action-show-uid-$uid.html',
      joinedAt: '2026-01-02',
      verificationMessage: message,
    );

/// Profile 123 (Alice) seen by account [_self], plus scripted friend calls.
class _Repo extends FakeProfileRepository {
  _Repo({String? selfUid = _self}) {
    identity.value = ForumAccountIdentity(systemName: 'me', uid: selfUid);
  }

  final identity = ValueNotifier<ForumAccountIdentity?>(null);
  UserProfile overview = profileFixture;
  List<UserActivityItem> feed = const [];

  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity => identity;

  @override
  bool get isLoggedIn => true;

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => overview;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => overview;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview,
          {bool forceReload = false}) async =>
      overview.copyWith(homeActivities: feed);

  ForumFriendAddResult addResult = const ForumFriendAddResult(
      status: ForumFriendAddStatus.added, message: '');
  final confirmed = <String>[];

  @override
  Future<ForumFriendAddResult> addFriend(String uid) async => addResult;

  @override
  Future<ForumFriendAddResult> confirmFriendRequest(ForumFriendRequest request,
      {required String message}) async {
    confirmed.add(message);
    return const ForumFriendAddResult(
        status: ForumFriendAddStatus.pending, message: '');
  }

  List<ForumFriend> friends = [_friend('201', 'Bob')];
  List<ForumFriend> requests = [_friend('301', 'Carol', message: '同好求加')];
  // While set, list reads wait for it.
  Completer<void>? hold;
  final fetches = <bool>[];
  final calls = <String>[];

  @override
  Future<ForumFriendPage> fetchFriends(
      {bool pending = false, int page = 1}) async {
    fetches.add(pending);
    await hold?.future;
    return ForumFriendPage(
        items: pending ? requests : friends, pending: pending);
  }

  @override
  Future<ForumFriendMutationResult> deleteFriends(
      ForumFriendPage snapshot, List<ForumFriend> selected) async {
    calls.add('delete ${selected.map((f) => f.uid).join()}');
    friends = [];
    return const ForumFriendMutationResult(confirmed: true, message: '');
  }

  @override
  Future<ForumFriendMutationResult> respondToFriendRequests(
      ForumFriendPage snapshot,
      List<ForumFriend> selected,
      ForumFriendResponse response,
      {String refusalMessage = ''}) async {
    calls.add('${response.name} ${selected.single.uid} $refusalMessage'.trim());
    requests = [...requests]..remove(selected.single);
    return const ForumFriendMutationResult(confirmed: true, message: '');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  Future<void> openProfile(WidgetTester tester, _Repo repo) => pump(
      tester, UserProfileScreen(userUrl: repo.overview.url, repository: repo));

  group('profile', () {
    testWidgets('another user offers 加为好友; the own profile offers 好友',
        (tester) async {
      final repo = _Repo();
      await openProfile(tester, repo);
      expect(find.text('加为好友'), findsOneWidget);
      expect(find.text('好友'), findsNothing);

      repo.identity.value =
          const ForumAccountIdentity(systemName: 'me', uid: '123');
      await tester.pumpAndSettle();
      expect(find.text('加为好友'), findsNothing);
      await tester.tap(find.text('好友'));
      await tester.pumpAndSettle();
      expect(find.byType(FriendsScreen), findsOneWidget);
    });

    testWidgets('without a known own UID nobody can be added', (tester) async {
      await openProfile(tester, _Repo(selfUid: null));
      expect(find.text('加为好友'), findsNothing);
    });

    testWidgets('a verifying user gets the optional message', (tester) async {
      final repo = _Repo()
        ..addResult = const ForumFriendAddResult(
          status: ForumFriendAddStatus.verificationRequired,
          message: '',
          request: ForumFriendRequest(uid: '123'),
        );
      await openProfile(tester, repo);
      await tester.tap(find.text('加为好友'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '一起看番');
      await tester.tap(find.text('发送请求'));
      await tester.pumpAndSettle();
      expect(repo.confirmed, ['一起看番']);
      expect(find.text('已发送好友请求，等待对方验证'), findsOneWidget);
    });

    testWidgets('the forum\'s refusal is shown in its own words',
        (tester) async {
      final repo = _Repo()
        ..addResult = const ForumFriendAddResult(
            status: ForumFriendAddStatus.rejected, message: '该用户拒绝任何人加为好友。');
      await openProfile(tester, repo);
      await tester.tap(find.text('加为好友'));
      await tester.pumpAndSettle();
      expect(find.text('该用户拒绝任何人加为好友。'), findsOneWidget);
    });

    testWidgets('the own feed mixes friends in; a friendship opens the person',
        (tester) async {
      final repo = _Repo()
        ..identity.value =
            const ForumAccountIdentity(systemName: 'me', uid: '123')
        ..feed = const [
          UserActivityItem(
            title: '我的主题',
            url: 'read.php?tid-1.html',
            action: '发表了主题',
            author: 'Alice',
            authorUrl: 'https://south-plus.net/u.php?action-show-uid-123.html',
          ),
          UserActivityItem(
            title: '',
            url: null,
            action: '成为了好友',
            author: 'Alice',
            authorUrl: 'https://south-plus.net/u.php?action-show-uid-123.html',
            targetName: 'Bob',
            targetUrl: 'https://south-plus.net/u.php?action-show-uid-201.html',
          ),
        ];
      await openProfile(tester, repo);
      expect(find.text('动态'), findsOneWidget);
      expect(find.text('我 发表了主题'), findsOneWidget);
      await tester.tap(find.text('我 和 Bob 成为了好友'));
      await tester.pumpAndSettle();
      final opened =
          tester.widget<UserProfileScreen>(find.byType(UserProfileScreen).last);
      expect(opened.userUrl,
          'https://south-plus.net/u.php?action-show-uid-201.html');
    });
  });

  group('short screen, big text, keyboard up', () {
    void keyboardUp(WidgetTester tester) =>
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);

    Future<void> pumpTight(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 2, maxScaleFactor: 2, child: child!),
        home: home,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the request sheet still reaches 发送请求', (tester) async {
      String? sent;
      await pumpTight(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  sent = await showFriendRequestSheet(context, name: 'Alice'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      keyboardUp(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('发送请求'));
      await tester.tap(find.text('发送请求'));
      await tester.pumpAndSettle();
      expect(sent, '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the refusal dialog still reaches 拒绝', (tester) async {
      final repo = _Repo();
      await pumpTight(
          tester, FriendsScreen(repository: repo, initialPending: true));
      await tester.ensureVisible(find.text('拒绝'));
      await tester.tap(find.text('拒绝'));
      keyboardUp(tester);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, '拒绝');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(repo.calls, ['refuse 301']);
      expect(tester.takeException(), isNull);
    });
  });

  group('friends screen', () {
    testWidgets('deleting a friend asks first, then reloads both lists',
        (tester) async {
      final repo = _Repo();
      await pump(tester, FriendsScreen(repository: repo));
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('待验证 1'), findsOneWidget);
      repo.fetches.clear();

      await tester.tap(find.byTooltip('删除好友 Bob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['delete 201']);
      expect(repo.fetches, unorderedEquals([false, true]));
      expect(find.text('还没有好友'), findsOneWidget);
    });

    testWidgets('requests: accept and add, or refuse with a note',
        (tester) async {
      final repo = _Repo()..requests.add(_friend('302', 'Dan'));
      await pump(tester, FriendsScreen(repository: repo, initialPending: true));
      expect(find.text('同好求加'), findsOneWidget);
      await tester.tap(find.text('接受并加好友').first);
      await tester.pumpAndSettle();
      expect(repo.calls, ['acceptadd 301']);
      expect(find.text('Carol'), findsNothing);

      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '不认识');
      await tester.tap(find.widgetWithText(FilledButton, '拒绝'));
      await tester.pumpAndSettle();
      expect(repo.calls.last, 'refuse 302 不认识');
    });

    testWidgets('a session change hides the old lists until reloaded',
        (tester) async {
      final repo = _Repo();
      await pump(tester, FriendsScreen(repository: repo, initialPending: true));
      expect(find.text('Carol'), findsOneWidget);
      repo.fetches.clear();
      repo.hold = Completer();

      repo.epoch.value++;
      await tester.pump();
      expect(find.text('Carol'), findsNothing);
      expect(find.text('同好求加'), findsNothing);
      expect(find.text('待验证 1'), findsNothing);
      expect(repo.fetches, isEmpty);

      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(repo.fetches, unorderedEquals([false, true]));
      expect(find.text('Carol'), findsNothing);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Carol'), findsOneWidget);
    });
  });
}
