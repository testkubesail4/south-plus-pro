import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/features/common/forum_link_opener.dart';
import 'package:south_plus_rewrite/features/messages/pm_box_screen.dart';
import 'package:south_plus_rewrite/features/messages/pm_compose_screen.dart';
import 'package:south_plus_rewrite/features/messages/pm_detail_screen.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_preferences_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_tasks_screen.dart';
import 'package:south_plus_rewrite/features/profile/friends_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

const _site = 'https://south-plus.net';

/// Signed in as UID 900 unless told otherwise; lists answer empty.
class _Repo extends ForumRepository {
  _Repo({bool signedIn = true, String? selfUid = '900'})
      : this._(ForumClient(), signedIn, selfUid);

  _Repo._(ForumClient client, this.signedIn, String? selfUid)
      : super(client: client) {
    identity.value = ForumAccountIdentity(
        systemName: 'me',
        uid: selfUid,
        credentialGeneration: client.credentialGeneration);
  }

  bool signedIn;
  final identity = ValueNotifier<ForumAccountIdentity?>(null);

  @override
  bool get isLoggedIn => signedIn;

  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity => identity;

  final friendReads = <(bool, int)>[];
  final boxReads = <(ForumPmBox, String?)>[];

  @override
  Future<ForumFriendPage> fetchFriends(
      {bool pending = false, int page = 1}) async {
    friendReads.add((pending, page));
    return ForumFriendPage(items: const [], pending: pending);
  }

  // Held so a test can answer after the compose page closed.
  final compose = Completer<ForumPmCompose>();

  @override
  Future<ForumPmCompose> fetchPmCompose({String? path}) => compose.future;

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) {
    boxReads.add((box, pagePath));
    return Completer<ForumPmPage>().future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> tapLink(WidgetTester tester, _Repo repo, String url) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openForumLink(context, repo, url),
            child: const Text('link'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the PM friend-request link opens the pending list in-app',
      (tester) async {
    final repo = _Repo();
    await tapLink(
        tester, repo, '$_site/u.php?action-friend-o-check-fuid-1001.html');
    final screen = tester.widget<FriendsScreen>(find.byType(FriendsScreen));
    expect(screen.initialPending, isTrue);
    expect(find.text('在浏览器中打开'), findsNothing);

    // The source page stays below it.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('link'), findsOneWidget);
  });

  final routes = <String, Matcher>{
    '$_site/u.php?action-friend-uid-900.html': isA<FriendsScreen>()
        .having((s) => s.initialPending, 'pending', isFalse),
    '$_site/u.php?action-friend-uid-900-o-check.html':
        isA<FriendsScreen>().having((s) => s.initialPending, 'pending', isTrue),
    '$_site/u.php': isA<UserProfileScreen>(),
    '$_site/profile.php?action-modify.html': isA<AccountProfileEditScreen>(),
    '$_site/profile.php?action-bbsset.html': isA<ForumPreferencesScreen>(),
    '$_site/message.php?action-sendbox.html': isA<PmBoxScreen>(),
    '$_site/message.php?action-read-mid-5.html': isA<PmDetailScreen>(),
    '$_site/message.php?action-chatlog-withuid-1001.html':
        isA<PmChatlogScreen>(),
    '$_site/message.php?action-write-touid-1001.html': isA<PmComposeScreen>(),
    '$_site/plugin.php?H_name-tasks-actions-endtasks.html.html':
        isA<ForumTasksScreen>().having(
            (s) => s.initialStatus, 'status', ForumTaskStatus.completed),
    '$_site/search.php?keyword-test.html': isA<SearchScreen>(),
  };
  for (final MapEntry(key: url, value: matcher) in routes.entries) {
    testWidgets('$url opens its screen', (tester) async {
      await tapLink(tester, _Repo(), url);
      expect(find.text('在浏览器中打开'), findsNothing);
      expect(
          tester.widgetList(
              find.byWidgetPredicate((w) => matcher.matches(w, {}))),
          hasLength(1));
      // Lets the opened screen's own retry timers run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  }

  testWidgets('a linked mailbox page opens on that box and page',
      (tester) async {
    final repo = _Repo();
    await tapLink(
        tester, repo, '$_site/message.php?action-sendbox-page-3.html');
    expect(repo.boxReads.single.$1, ForumPmBox.sendbox);
    expect(repo.boxReads.single.$2, contains('page-3'));
  });

  testWidgets('a linked friend-request page opens on that page',
      (tester) async {
    final repo = _Repo();
    await tapLink(
        tester, repo, '$_site/u.php?action-friend-uid-900-o-check-page-2.html');
    expect(repo.friendReads, contains((true, 2)));
  });

  testWidgets('signed out, an account page asks to log in, no browser',
      (tester) async {
    await tapLink(tester, _Repo(signedIn: false),
        '$_site/u.php?action-friend-o-check-fuid-1001.html');
    expect(find.byType(FriendsScreen), findsNothing);
    expect(find.text('在浏览器中打开'), findsNothing);
    expect(find.text('登录后才能打开这个页面'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, '登录'), findsOneWidget);
  });

  testWidgets('logging in from the notice first closes pushed private pages',
      (tester) async {
    final repo = _Repo(signedIn: false);
    await tester.pumpWidget(const MaterialApp(home: Text('root')));
    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: Column(children: [
                const Text('A 的私信'),
                TextButton(
                  onPressed: () => openForumLink(context, repo,
                      '$_site/u.php?action-friend-o-check-fuid-1001.html'),
                  child: const Text('link'),
                ),
              ]),
            ),
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SnackBarAction, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('A 的私信', skipOffstage: false), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('a login inside a linked page closes the private page below',
      (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(const MaterialApp(home: Text('root')));
    tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: Column(children: [
                const Text('A 的私信'),
                TextButton(
                  onPressed: () => openForumLink(
                      context, repo, '$_site/plugin.php?H_name-tasks.html'),
                  child: const Text('link'),
                ),
              ]),
            ),
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();
    expect(find.byType(ForumTasksScreen), findsOneWidget);

    // The cookie expires; the task page offers its own login.
    repo.signedIn = false;
    tester.element(find.byType(ForumTasksScreen)).markNeedsBuild();
    await tester.pumpAndSettle();
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('A 的私信', skipOffstage: false), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('a late compose answer after the page closed stays unseen',
      (tester) async {
    final repo = _Repo();
    await tapLink(
        tester, repo, '$_site/message.php?action-write-touid-1001.html');
    expect(find.byType(PmComposeScreen), findsOneWidget);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    repo.compose.complete(ForumPmCompose(
        actionPath: 'message.php', fields: const {}, body: 'A 的草稿'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('A 的草稿', skipOffstage: false), findsNothing);
  });

  testWidgets('another account\'s page stays closed, no browser',
      (tester) async {
    await tapLink(tester, _Repo(), '$_site/u.php?action-friend-uid-901.html');
    expect(find.byType(FriendsScreen), findsNothing);
    expect(find.text('在浏览器中打开'), findsNothing);
    expect(find.text('无法确认这是当前账号的页面'), findsOneWidget);
  });

  for (final home in [_site, '$_site/', '$_site/index.php']) {
    testWidgets('$home returns to the shell root, signed out too',
        (tester) async {
      final repo = _Repo(signedIn: false);
      await tester.pumpWidget(const MaterialApp(home: Text('root')));
      tester.state<NavigatorState>(find.byType(Navigator)).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openForumLink(context, repo, home),
                  child: const Text('link'),
                ),
              ),
            ),
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('link'));
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
      expect(find.text('link'), findsNothing);
      expect(find.text('在浏览器中打开'), findsNothing);
    });
  }

  testWidgets('a forum page without a screen still asks before the browser',
      (tester) async {
    await tapLink(tester, _Repo(), '$_site/hack.php?H_name-bank.html');
    expect(find.text('在浏览器中打开'), findsOneWidget);
  });
}
