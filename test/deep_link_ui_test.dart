import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/profile/friends_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/search/search_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';

// Synthetic fixtures only: fictional ids and names on the configured mirror.
const _thread = 'https://south-plus.net/read.php?tid-9001-page-2.html';
const _aliasUser =
    'https://www.white-plus.net/u.php?action-topic-uid-7001.html';
const _board = 'https://south-plus.net/thread.php?fid-77.html';
const _search =
    'https://south-plus.net/search.php?keyword=fixture&pwuser=sample_user&f_fid=77';
// Userscript wire shape: #prefill(<URI-encoded JSON pairs without brackets>).
final _prefill = 'https://south-plus.net/search.php#prefill('
    '${Uri.encodeComponent('"fid",77,"keyword","fixture","pwuser","sample_user"')})';
const _unsupported = 'https://south-plus.net/hack.php?H_name=fixture';

const _channel = MethodChannel('south_plus_rewrite/incoming_links');

void main() {
  late List<Object?> acks;
  late List<MethodCall> launches;
  late List<String> clipboard;
  Map<String, Object?>? initialLink;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });
    acks = [];
    launches = [];
    clipboard = [];
    initialLink = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'takeInitialLink':
          final link = initialLink;
          initialLink = null;
          return link;
        case 'acknowledgeLink':
          final args = call.arguments;
          acks.add(args is Map ? args['id'] : args);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launches.add(call);
        return true;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // Spinners never settle, so step through futures, post-frame pushes and
  // route transitions explicitly.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> sendLink(WidgetTester tester, int id, String url) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(
        MethodCall('openLink', {'id': id, 'url': url}),
      ),
      (_) {},
    );
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('cold link waits for the session, then opens once over home',
      (tester) async {
    initialLink = {'id': 1, 'url': _thread};
    final repository = _FakeRepository();
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);

    expect(find.byType(HomeShell), findsNothing);
    expect(find.byType(ThreadDetailScreen), findsNothing);

    // A stale replay of the same native event must not stack a second page.
    await sendLink(tester, 1, _thread);
    repository.restore.complete(false);
    await settle(tester);

    expect(find.byType(ThreadDetailScreen), findsOneWidget);
    final thread = tester
        .widget<ThreadDetailScreen>(find.byType(ThreadDetailScreen))
        .thread;
    expect(thread.url, contains('tid-9001'));
    expect(thread.url, contains('page-2'));
    expect(acks, contains(1));

    await back(tester);
    expect(find.byType(ThreadDetailScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('links before readiness keep only the latest', (tester) async {
    final repository = _FakeRepository();
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);

    await sendLink(tester, 2, _thread);
    await sendLink(tester, 3, _board);
    expect(find.byType(BoardThreadListScreen), findsNothing);

    repository.restore.complete(true);
    await settle(tester);

    expect(find.byType(BoardThreadListScreen), findsOneWidget);
    expect(find.byType(ThreadDetailScreen), findsNothing);
    expect(acks, contains(3));
  });

  testWidgets('session error holds the link until the user continues',
      (tester) async {
    initialLink = {'id': 4, 'url': _thread};
    final repository = _FakeRepository();
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    repository.restore.completeError(StateError('offline'));
    await settle(tester);

    expect(find.text('登录状态恢复失败'), findsOneWidget);
    expect(find.byType(ThreadDetailScreen), findsNothing);

    await tester.tap(find.text('先浏览公开内容'));
    await settle(tester);
    expect(find.byType(ThreadDetailScreen), findsOneWidget);
  });

  testWidgets(
      'warm alias link opens the profile tab on the configured mirror; '
      'repeats on top are ignored, reopening after back works', (tester) async {
    final repository = _FakeRepository()..restore.complete(true);
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);

    await sendLink(tester, 5, _aliasUser);
    expect(find.byType(UserProfileScreen), findsOneWidget);
    final profile =
        tester.widget<UserProfileScreen>(find.byType(UserProfileScreen));
    expect(profile.initialTab, UserProfileTab.topics);
    expect(Uri.parse(profile.userUrl).host, 'south-plus.net');

    await sendLink(tester, 6, _aliasUser);
    expect(find.byType(UserProfileScreen), findsOneWidget);
    await back(tester);
    expect(find.byType(UserProfileScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);

    await sendLink(tester, 7, _aliasUser);
    expect(find.byType(UserProfileScreen), findsOneWidget);
    await back(tester);
    expect(find.byType(UserProfileScreen), findsNothing);
  });

  for (final (label, url) in [('query', _search), ('userscript', _prefill)]) {
    testWidgets(
        '$label search link prefills the form without searching and keeps '
        'edits under a later link', (tester) async {
      final repository = _FakeRepository()..restore.complete(true);
      await tester
          .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
      await settle(tester);

      await sendLink(tester, 8, url);
      final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
      expect(search.initialKeyword, 'fixture');
      expect(search.initialUsername, 'sample_user');
      expect(search.initialBoard?.id, '77');
      expect(find.widgetWithText(TextField, 'fixture'), findsOneWidget);
      expect(repository.searches, 0);

      await tester.enterText(
          find.widgetWithText(TextField, 'fixture'), 'my draft');
      await sendLink(tester, 9, _thread);
      expect(find.byType(ThreadDetailScreen), findsOneWidget);

      await back(tester);
      expect(find.byType(ThreadDetailScreen), findsNothing);
      expect(find.widgetWithText(TextField, 'my draft'), findsOneWidget);
      expect(repository.searches, 0);
    });
  }

  testWidgets('unsupported forum page offers copy, never a browser',
      (tester) async {
    final repository = _FakeRepository()..restore.complete(true);
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);

    await sendLink(tester, 10, _unsupported);
    expect(find.text('暂不支持在应用内打开'), findsOneWidget);
    await tester.tap(find.text('复制链接'));
    await settle(tester);

    expect(clipboard.single, contains('hack.php'));
    expect(launches, isEmpty);
    expect(find.text('暂不支持在应用内打开'), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  for (final (label, url) in [
    ('foreign host', 'https://example.invalid/read.php?tid-9001.html'),
    ('credentials', 'https://fixture@south-plus.net/read.php?tid-9001.html'),
    ('mutation', 'https://south-plus.net/message.php?action-del-id-1.html'),
    ('scheme', 'javascript:alert(1)'),
    ('malformed', 'not a link'),
  ]) {
    testWidgets('rejected $label link shows a notice without copy or browser',
        (tester) async {
      initialLink = {'id': 11, 'url': url};
      final repository = _FakeRepository();
      await tester
          .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
      repository.restore.complete(false);
      await settle(tester);

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.text('暂不支持在应用内打开'), findsOneWidget);
      expect(find.text('复制链接'), findsNothing);
      expect(find.byType(ThreadDetailScreen), findsNothing);
      expect(launches, isEmpty);
      expect(acks, contains(11));
    });
  }

  testWidgets('a pending-friends link asks a guest to log in, then opens',
      (tester) async {
    const pending =
        'https://south-plus.net/u.php?action-friend-o-check-fuid-7001.html';
    final repository = _FakeRepository()..restore.complete(true);
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);

    await sendLink(tester, 13, pending);
    expect(find.text('登录后才能打开这个页面'), findsOneWidget);
    expect(find.byType(FriendsScreen), findsNothing);
    expect(find.text('暂不支持在应用内打开'), findsNothing);
    expect(launches, isEmpty);

    repository.signedIn = true;
    await sendLink(tester, 14, pending);
    expect(find.byType(FriendsScreen), findsOneWidget);
    expect(
        tester.widget<FriendsScreen>(find.byType(FriendsScreen)).initialPending,
        isTrue);
  });

  testWidgets("another account's friend page stays closed, never a browser",
      (tester) async {
    final repository = _FakeRepository()
      ..signedIn = true
      ..restore.complete(true);
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);

    await sendLink(
        tester, 15, 'https://south-plus.net/u.php?action-friend-uid-7002.html');
    expect(find.text('无法确认这是当前账号的页面'), findsOneWidget);
    expect(find.byType(FriendsScreen), findsNothing);
    expect(launches, isEmpty);
  });

  testWidgets('a repeated homepage link reselects home after a tab change',
      (tester) async {
    // Phone width: the shell shows its bottom NavigationBar.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeRepository()..restore.complete(true);
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);
    int selected() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
    Future<void> selectAccount() async {
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('我的')));
      await settle(tester);
    }

    await selectAccount();
    await sendLink(tester, 16, 'https://south-plus.net/index.php');
    expect(selected(), HomeShell.homeTab);
    await selectAccount();
    await sendLink(tester, 17, 'https://south-plus.net/index.php');
    expect(selected(), HomeShell.homeTab);
    expect(launches, isEmpty);
  });

  testWidgets('links after dispose are dropped', (tester) async {
    final repository = _FakeRepository()..restore.complete(true);
    await tester
        .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
    await settle(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    await sendLink(tester, 12, _thread);
    expect(tester.takeException(), isNull);
    expect(find.byType(ThreadDetailScreen), findsNothing);
    expect(acks, isNot(contains(12)));
  });
}

class _FakeRepository extends ForumRepository {
  _FakeRepository() : this._(ForumClient());
  _FakeRepository._(this.client) : super(client: client);
  final ForumClient client;
  final restore = Completer<bool>();
  int searches = 0;
  bool signedIn = false;

  @override
  bool get isLoggedIn => signedIn;

  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity =>
      ValueNotifier(signedIn
          ? ForumAccountIdentity(
              systemName: 'me',
              uid: '7000',
              credentialGeneration: client.credentialGeneration)
          : null);

  @override
  Future<ForumFriendPage> fetchFriends({bool pending = false, int page = 1}) =>
      Completer<ForumFriendPage>().future;

  @override
  Future<bool> restoreSession() => restore.future;

  @override
  Future<ForumHomeSnapshot> fetchHome() =>
      Completer<ForumHomeSnapshot>().future;

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread, {int page = 1}) =>
      Completer<ThreadDetail>().future;

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) =>
      Completer<UserProfile>().future;

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) =>
      Completer<ForumThreadPage>().future;

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() =>
      Completer<List<ForumSearchBoard>>().future;

  @override
  Future<ForumSearchPage> searchForum(ForumSearchQuery query) {
    searches++;
    return Completer<ForumSearchPage>().future;
  }
}
