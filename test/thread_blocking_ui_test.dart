import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/profile/blocking_settings_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/features/watch/watch_tab.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

import 'support/fake_watch.dart';

// Synthetic fixtures only: fictional host, uids, authors and texts.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _thread = ForumThread(
  title: 'blocking',
  url: _url,
  replies: 0,
  section: '',
  author: 'op',
  authorUrl: 'https://south-plus.net/u.php?action-show-uid-500.html',
  authorAvatarUrl: 'https://south-plus.net/avatar/500.png',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repository> pumpThread(WidgetTester tester,
      {bool loggedIn = true}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repository(loggedIn: loggedIn);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openMenu(WidgetTester tester, String key) async {
    final more = find.byKey(ValueKey(key));
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
  }

  testWidgets('屏蔽内容 collapses matching floors, 显示 reveals one, 撤销 undoes',
      (tester) async {
    final repository = await pumpThread(tester);
    await openMenu(tester, 'floor-actions-alice-B1F');
    await tester.tap(find.text('屏蔽内容'));
    await tester.pumpAndSettle();

    // B1F and B3F share the same short text.
    expect(find.text('B1F · 已屏蔽相同内容'), findsOneWidget);
    expect(find.text('B3F · 已屏蔽相同内容'), findsOneWidget);
    expect(find.text('B2F · 已屏蔽相同内容'), findsNothing);
    expect(repository.server.actions, isNot(contains('updateblocklist')),
        reason: 'content rules stay local');

    await tester.tap(find.text('显示').first);
    await tester.pumpAndSettle();
    expect(find.text('B1F · 已屏蔽相同内容'), findsNothing);
    expect(find.text('B3F · 已屏蔽相同内容'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(repository.blocking.notifier.value.contentKeys, isEmpty);
    expect(find.textContaining('已屏蔽相同内容'), findsNothing);
  });

  testWidgets('屏蔽此人 writes the native list and hides that author',
      (tester) async {
    final repository = await pumpThread(tester);
    await openMenu(tester, 'floor-actions-bob-B2F');
    expect(find.text('同步南+屏蔽配置 · 隐藏 TA 的主题与回复'), findsOneWidget);
    await tester.tap(find.text('屏蔽此人'));
    await tester.pumpAndSettle();

    // Rules load once read-only; the write merges a fresh read.
    expect(repository.server.actions,
        ['getblocklist', 'getblocklist', 'updateblocklist']);
    final blist = repository.server.config['blist'] as Map;
    expect((blist['602'] as Map)['level'], ['topic']);
    expect(find.text('B2F · 已屏蔽此人的发言'), findsOneWidget);
    expect(find.text('已屏蔽此人'), findsOneWidget);

    // The menu now offers the reverse.
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();
    await openMenu(tester, 'floor-actions-bob-B2F');
    expect(find.text('取消屏蔽此人'), findsOneWidget);
  });

  testWidgets('the 屏蔽 group\'s 管理 opens the blocking settings', (tester) async {
    await pumpThread(tester);
    await openMenu(tester, 'floor-actions-bob-B2F');
    // 关注 has its own 管理 above; 屏蔽's is the last.
    final manage = find.widgetWithText(TextButton, '管理').last;
    expect(tester.getSize(manage).height, greaterThanOrEqualTo(48));

    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.byType(BlockingSettingsScreen), findsOneWidget);
  });

  testWidgets('关注 hears of shown floors only; a hidden one once revealed',
      (tester) async {
    final repository = await pumpThread(tester);
    expect(repository.fakeWatch.seen.last, _seen('7', ['901', '902', '903']));

    await openMenu(tester, 'floor-actions-alice-B1F');
    await tester.tap(find.text('屏蔽内容'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '显示').first);
    await tester.pumpAndSettle();
    // B3F holds the same text and stays hidden.
    expect(repository.fakeWatch.seen.last, _seen('7', ['901', '902']));
  });

  testWidgets('a page that loads behind another page is unread until shown',
      (tester) async {
    final repository = _Repository(loggedIn: true)..gate = Completer();
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    Navigator.of(tester.element(find.byType(ThreadDetailScreen)))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(repository.fakeWatch.seen, isEmpty);

    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();
    expect(repository.fakeWatch.seen.single, _seen('7', ['901', '902', '903']));
  });

  testWidgets('no opening body, no opening post read', (tester) async {
    final repository = _Repository(loggedIn: true, openingBody: '');
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();
    expect(repository.fakeWatch.seen.last,
        _seen('7', ['901', '902', '903'], opening: false));
  });

  testWidgets('a blocked opening poster leaves the opening post unread',
      (tester) async {
    final repository = await pumpThread(tester);
    await repository.blocking.setUser('500', 'op', blocked: true);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(
          key: UniqueKey(), repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();
    expect(repository.fakeWatch.seen.last,
        _seen('7', ['901', '902', '903'], opening: false));
  });

  testWidgets('a floor offers 关注 TA and 本帖中涉及 TA 的回复', (tester) async {
    await pumpThread(tester);
    await openMenu(tester, 'floor-actions-bob-B2F');
    await tester.tap(find.text('关注 TA'));
    await tester.pumpAndSettle();
    expect(find.text('关注用户 · 新规则'), findsOneWidget);
    expect(find.text('bob'), findsWidgets);
    Navigator.of(tester.element(find.text('关注用户 · 新规则'))).pop();
    await tester.pumpAndSettle();

    await openMenu(tester, 'floor-actions-bob-B2F');
    await tester.tap(find.text('本帖中涉及 TA 的回复'));
    await tester.pumpAndSettle();
    expect(find.text('回复或引用 bob 的新回复'), findsOneWidget);
  });

  testWidgets('the 关注 group\'s 管理 opens 关注', (tester) async {
    await pumpThread(tester);
    await openMenu(tester, 'floor-actions-bob-B2F');
    await tester.tap(find.widgetWithText(TextButton, '管理').first);
    await tester.pumpAndSettle();
    expect(find.byType(WatchScreen), findsOneWidget);
  });

  testWidgets('⋮ 关注本帖 adds a rule, then counts it', (tester) async {
    final repository = await pumpThread(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关注本帖'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '关注'));
    await tester.pumpAndSettle();
    final rule = repository.fakeWatch.rules.single;
    expect((rule.scope, rule.subjectId, rule.label),
        (WatchScope.thread, '7', 'blocking'));

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('已关注本帖 · 1 条'), findsOneWidget);
  });

  testWidgets('signed out, no floor or thread offers 关注', (tester) async {
    await pumpThread(tester, loggedIn: false);
    await openMenu(tester, 'floor-actions-bob-B2F');
    expect(find.text('关注 TA'), findsNothing);
  });

  testWidgets('屏蔽头像 only swaps the avatar for the initial', (tester) async {
    final repository = await pumpThread(tester);
    final bobAvatar = find.byWidgetPredicate((widget) =>
        widget is CachedForumImage && widget.url.endsWith('/602.png'));
    expect(bobAvatar, findsOneWidget);
    await openMenu(tester, 'floor-actions-bob-B2F');
    await tester.tap(find.text('屏蔽头像'));
    await tester.pumpAndSettle();

    expect(
        (repository.server.config['blist'] as Map)['602']['level'], ['avatar']);
    expect(find.text('已屏蔽头像'), findsOneWidget);
    expect(find.textContaining('已屏蔽此人的发言'), findsNothing);
    expect(bobAvatar, findsNothing);
    expect(find.text('something else', findRichText: true), findsOneWidget);
  });

  for (final openingBody in ['opening body', '']) {
    testWidgets(
        "a blocked avatar leaves the opening poster's card "
        '(${openingBody.isEmpty ? 'header only' : 'with body'})',
        (tester) async {
      final repository = _Repository(loggedIn: true, openingBody: openingBody);
      repository.blocking.notifier.value = const BlockingRules(users: [
        BlockedUser(
            uid: '500', name: 'op', userBlocked: false, avatarBlocked: true),
      ]);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ThreadDetailScreen(repository: repository, thread: _thread),
      ));
      await tester.pumpAndSettle();

      expect(find.text('blocking'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) =>
            widget is CachedForumImage && widget.url.endsWith('/500.png')),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate((widget) =>
            widget is CachedForumImage && widget.url.endsWith('/601.png')),
        findsOneWidget,
      );
    });
  }

  testWidgets('a blocked opening poster keeps the title, hides the body',
      (tester) async {
    final repository = _Repository(loggedIn: true);
    repository.blocking.notifier.value = const BlockingRules(users: [
      BlockedUser(
          uid: '500', name: 'op', userBlocked: true, avatarBlocked: false),
    ]);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();

    expect(find.text('blocking'), findsOneWidget);
    expect(find.text('楼主 · 已屏蔽此人的发言'), findsOneWidget);
    expect(find.text('opening body', findRichText: true), findsNothing);
  });

  Future<_SessionClient> pumpFresh(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _SessionClient();
    final repository = _FreshRepository(client);
    await tester.pumpWidget(MaterialApp(
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();
    return client;
  }

  ForumRepository repositoryOf(WidgetTester tester) => tester
      .widget<ThreadDetailScreen>(find.byType(ThreadDetailScreen))
      .repository;

  testWidgets('a fresh session learns its uid before offering 屏蔽此人',
      (tester) async {
    final client = await pumpFresh(tester);
    expect(client.gets, isEmpty);
    await openMenu(tester, 'floor-actions-bob-B2F');

    // Read-only bootstrap: the account page and the current rules.
    expect(client.gets, ['index.php']);
    expect(client.posts, ['getblocklist']);
    await tester.tap(find.text('屏蔽此人'));
    await tester.pumpAndSettle();
    expect(client.posts, ['getblocklist', 'getblocklist', 'updateblocklist']);
    expect(find.text('B2F · 已屏蔽此人的发言'), findsOneWidget);
  });

  /// Ends account A's session and signs account B in on the same screen.
  Future<ForumRepository> switchToB(
      WidgetTester tester, _SessionClient client) async {
    final repository = repositoryOf(tester);
    await repository.clearSession();
    client
      ..loggedIn = true
      ..uid = '102'
      ..name = 'Synthetic second account';
    await repository.restoreSession();
    await repository.ensureAccountIdentity();
    await repository.blocking.load();
    await tester.pumpAndSettle();
    expect(repository.blocking.canWriteNative, isTrue);
    return repository;
  }

  testWidgets("account A's 撤销 never edits account B's rules", (tester) async {
    final client = await pumpFresh(tester);
    await openMenu(tester, 'floor-actions-alice-B1F');
    await tester.tap(find.text('屏蔽内容'));
    await tester.pumpAndSettle();
    expect(find.text('B1F · 已屏蔽相同内容'), findsOneWidget);

    final repository = await switchToB(tester, client);
    // B holds the very rule A's 撤销 would remove.
    await repository.blocking.setContent('same short text', blocked: true);
    await tester.pumpAndSettle();
    final posts = List.of(client.posts);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(client.posts, posts);
    // Reloaded from storage: B's local rule survived.
    await repository.blocking.load(refresh: true);
    expect(repository.blocking.notifier.value.contentKeys, {'same short text'});
  });

  testWidgets("a menu opened as account A never writes for account B",
      (tester) async {
    final client = await pumpFresh(tester);
    await openMenu(tester, 'floor-actions-bob-B2F');
    final repository = await switchToB(tester, client);
    final posts = List.of(client.posts);
    final blocklist = jsonEncode(client.blocklist);

    await tester.tap(find.text('屏蔽此人'));
    await tester.pumpAndSettle();
    expect(client.posts, posts);
    expect(jsonEncode(client.blocklist), blocklist);
    expect(repository.blocking.notifier.value.users, isEmpty);
  });

  testWidgets('guests see why native blocking is unavailable', (tester) async {
    await pumpThread(tester, loggedIn: false);
    await openMenu(tester, 'floor-actions-bob-B2F');
    expect(find.text('登录后可同步南+屏蔽配置'), findsNWidgets(2));
    expect(
      tester
          .widget<ListTile>(find.ancestor(
              of: find.text('屏蔽此人'), matching: find.byType(ListTile)))
          .enabled,
      isFalse,
    );
  });
}

/// A real repository whose session has not captured its own uid yet.
class _FreshRepository extends ForumRepository {
  _FreshRepository(this.client) : super(client: client);

  final _SessionClient client;

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
    ForumThread t,
    ThreadReadPosition p,
  ) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(ForumThread thread, {int page = 1}) =>
      _Repository(loggedIn: true).fetchThreadDetail(thread, page: page);
}

class _SessionClient extends ForumClient {
  var loggedIn = true;
  var uid = '101';
  var name = 'Synthetic account';
  final gets = <String>[];
  final posts = <String>[];
  Map<String, dynamic> blocklist = {
    'version': '3.1',
    'blist': <String, dynamic>{}
  };

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<void> restoreCookies() async {}

  @override
  Future<void> clearSession() async => loggedIn = false;

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    final response = await get(path);
    requireCurrentSession?.call();
    return response;
  }

  @override
  Future<String> get(String path) async {
    gets.add(path);
    return '''<html><head><script>var verifyhash='TEST1234';</script></head>
      <body><div id="user-login"><a href="u.php">$name</a></div>
      <div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-$uid.html">查看个人资料</a></div></div>
      </body></html>''';
  }

  @override
  Future<String> post(String path, Map<String, String> fields) async {
    final action = Uri.parse(path).queryParameters['action']!;
    posts.add(action);
    if (action == 'getblocklist') {
      return '<ajax><![CDATA[${jsonEncode(blocklist)}]]></ajax>';
    }
    blocklist = jsonDecode(fields['blocklistconfig']!) as Map<String, dynamic>;
    return '<ajax><![CDATA[success]]></ajax>';
  }
}

class _NativeServer {
  final actions = <String>[];
  Map<String, dynamic> config = {
    'version': '3.1',
    'blist': <String, dynamic>{}
  };

  Future<String> request(String action, Map<String, String> fields) async {
    actions.add(action);
    if (action == 'getblocklist') {
      return '<ajax><![CDATA[${jsonEncode(config)}]]></ajax>';
    }
    config = jsonDecode(fields['blocklistconfig']!) as Map<String, dynamic>;
    return '<ajax><![CDATA[success]]></ajax>';
  }
}

class _Repository extends ForumRepository {
  _Repository({required this.loggedIn, this.openingBody = 'opening body'});

  final bool loggedIn;
  final fakeWatch = FakeWatch();

  @override
  WatchService get watch => fakeWatch;

  /// Empty on later pages and author-filtered views: a header card only.
  final String openingBody;
  final server = _NativeServer();

  /// Holds page loads until completed, when set.
  Completer<void>? gate;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  late final ForumBlockingSettings blocking = ForumBlockingSettings(
    accountUid: () => loggedIn ? '101' : null,
    request: server.request,
  );

  // The account is already known here; see _FreshRepository for bootstrap.
  @override
  Future<void> ensureAccountIdentity() async {}

  @override
  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread t) async =>
      null;

  @override
  Future<void> saveThreadReadPosition(
    ForumThread t,
    ThreadReadPosition p,
  ) async {}

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    await gate?.future;
    ThreadReply reply(String author, int uid, int floor, String text) =>
        ThreadReply(
          author: author,
          content: text,
          floor: 'B${floor}F',
          authorUrl: 'https://south-plus.net/u.php?action-show-uid-$uid.html',
          authorAvatarUrl: 'https://south-plus.net/avatar/$uid.png',
          blockContentKey: text,
          postId: '${900 + floor}',
        );
    return ThreadDetail(
      thread: _thread,
      body: openingBody,
      replies: [
        reply('alice', 601, 1, 'same short text'),
        reply('bob', 602, 2, 'something else'),
        reply('carol', 603, 3, 'same short text'),
      ],
    );
  }
}

// What the thread told 关注 it showed: tid, PIDs, and the opening post.
Matcher _seen(String tid, List<String> pids, {bool opening = true}) =>
    isA<(String, List<String>, bool)>()
        .having((s) => s.$1, 'tid', tid)
        .having((s) => s.$2, 'pids', pids)
        .having((s) => s.$3, 'openingSeen', opening);
