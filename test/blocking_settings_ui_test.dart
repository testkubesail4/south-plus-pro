import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/blocking_settings_screen.dart';
import 'package:south_plus_rewrite/features/profile/settings_screen.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic UIDs, names and content only.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Server> pump(WidgetTester tester,
      {bool loggedIn = true, String? uid = '101', bool fail = false}) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server()..fail = fail;
    final repo = _Repo(loggedIn, uid, server);
    if (loggedIn && uid != null) {
      await repo.blocking.setContent('synthetic reply<EMOJI>', blocked: true);
      await repo.blocking
          .setLocalUser('303', 'Local author', scope: LocalBlockScope.topics);
    }
    await tester.pumpWidget(
        MaterialApp(home: BlockingSettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    return server;
  }

  Finder row(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

  testWidgets('guests are asked to sign in and nothing is requested',
      (tester) async {
    final server = await pump(tester, loggedIn: false, uid: null);
    expect(find.text('登录后可配置屏蔽规则'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(server.actions, isEmpty);
  });

  testWidgets('an unidentified account is looked up first, then retried',
      (tester) async {
    final server = await pump(tester, uid: null);
    expect(_Repo.last.identityLookups, 1);
    expect(find.textContaining('暂时无法识别当前账号'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(_Repo.last.identityLookups, 2);
    expect(server.actions, isEmpty);
  });

  testWidgets('lists synced and local rules and edits each where it lives',
      (tester) async {
    final server = await pump(tester);
    expect(find.text('Synced author'), findsOneWidget);
    expect(find.text('替换头像'), findsOneWidget);
    expect(find.textContaining('已同步'), findsOneWidget);
    expect(find.text('Local author'), findsOneWidget);
    expect(find.text('只屏蔽主题帖'), findsOneWidget);
    expect(find.text('synthetic reply〔表情〕'), findsOneWidget);

    // The site's list: add 隐藏主题和回复 through a fresh read and a write.
    await tester.tap(find.descendant(
        of: row('Synced author'), matching: find.byType(PopupMenuButton<int>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏主题和回复').last);
    await tester.pumpAndSettle();
    expect(server.actions.last, 'updateblocklist');
    expect(server.config['blist']['202']['level'], ['avatar', 'topic']);
    expect(find.text('隐藏主题和回复 · 替换头像'), findsOneWidget);

    // Local rules never touch the site.
    final writes = server.actions.length;
    await tester.tap(find.descendant(
        of: row('synthetic reply〔表情〕'), matching: find.byTooltip('取消屏蔽')));
    await tester.pumpAndSettle();
    expect(find.text('synthetic reply〔表情〕'), findsNothing);
    await tester.tap(find.descendant(
        of: row('Local author'), matching: find.byType(PopupMenuButton<int>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('屏蔽所有内容').last);
    await tester.pumpAndSettle();
    expect(find.text('屏蔽所有内容'), findsOneWidget);
    expect(server.actions, hasLength(writes));
  });

  testWidgets('设置 opens 屏蔽配置', (tester) async {
    final repo = _Repo(false, null, _Server());
    await tester
        .pumpWidget(MaterialApp(home: SettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('屏蔽配置'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('屏蔽配置'));
    await tester.pumpAndSettle();
    expect(find.byType(BlockingSettingsScreen), findsOneWidget);
  });

  testWidgets('a failed sync keeps local rules and retries', (tester) async {
    final server = await pump(tester, fail: true);
    expect(find.textContaining('屏蔽配置同步失败'), findsOneWidget);
    expect(find.text('Local author'), findsOneWidget);
    server.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('Synced author'), findsOneWidget);
  });

  testWidgets('signing in on the page loads that account\'s rules',
      (tester) async {
    final server = await pump(tester, loggedIn: false, uid: null);
    expect(find.text('登录后可配置屏蔽规则'), findsOneWidget);
    _Repo.last.switchTo('101');
    await tester.pumpAndSettle();
    expect(find.text('Synced author'), findsOneWidget);
    expect(server.actions, ['getblocklist']);

    _Repo.last.switchTo(null);
    await tester.pumpAndSettle();
    expect(find.text('登录后可配置屏蔽规则'), findsOneWidget);
  });

  testWidgets('a menu left open across an account switch edits nothing',
      (tester) async {
    final server = await pump(tester);
    for (final (title, choice) in [
      ('Synced author', '隐藏主题和回复'),
      ('Local author', '屏蔽所有内容'),
    ]) {
      _Repo.last.switchTo('101');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: row(title), matching: find.byType(PopupMenuButton<int>)));
      await tester.pumpAndSettle();
      // Account B signs in while A's menu is open; the choice comes after.
      final siteConfig = jsonEncode(server.config);
      _Repo.last.switchTo('102');
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
      // B's site list and local rules are untouched; only B's list was read.
      expect(server.actions.where((a) => a != 'getblocklist'), isEmpty);
      expect(jsonEncode(server.config), siteConfig);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('blocking.local.102'), isNull);
      expect(prefs.getString('blocking.local.101'), contains('topics'));
      expect(find.text('账号已变化，请重新选择'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
    }
  });
}

class _Repo extends ForumRepository {
  _Repo(this.loggedIn, this.uid, _Server server)
      : blocking = ForumBlockingSettings(
            accountUid: () => last.loggedIn ? last.uid : null,
            request: server.request) {
    last = this;
  }

  static late _Repo last;
  bool loggedIn;
  String? uid;
  var identityLookups = 0;
  final _epoch = ValueNotifier(0);

  /// Signs in as [uid], or out when null, as a new session.
  void switchTo(String? uid) {
    loggedIn = uid != null;
    this.uid = uid;
    _epoch.value++;
  }

  @override
  ValueListenable<int> get sessionEpoch => _epoch;

  // The fixture's account is known or stays unknown; never fetched.
  @override
  Future<void> ensureAccountIdentity() async => identityLookups++;

  @override
  final ForumBlockingSettings blocking;

  @override
  bool get isLoggedIn => loggedIn;
}

class _Server {
  final actions = <String>[];
  var fail = false;
  Map<String, dynamic> config = {
    'version': '3.1',
    'curiosity': false,
    'showBTN': true,
    'blist': {
      '202': {
        'name': 'Synced author',
        'level': ['avatar'],
      },
    },
  };

  Future<String> request(String action, Map<String, String> fields) async {
    actions.add(action);
    if (fail) throw StateError('offline');
    if (action == 'getblocklist') {
      return '<ajax><![CDATA[${jsonEncode(config)}]]></ajax>';
    }
    config = jsonDecode(fields['blocklistconfig']!) as Map<String, dynamic>;
    return '<ajax><![CDATA[success]]></ajax>';
  }
}
