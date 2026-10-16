import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/messages/pm_box_screen.dart';
import 'package:south_plus_rewrite/features/profile/settings_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic accounts only.
const _userA = 'fixture-user-a';
const _userB = 'fixture-user-b';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'app',
      version: '0',
      buildNumber: '0',
      buildSignature: '',
    );
  });

  Future<_NavRepository> pumpShell(
    WidgetTester tester, {
    String? user,
    double textScale = 1,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _NavRepository()..signIn(user);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeShell(repository: repository),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('tabs separate personal content from device settings',
      (tester) async {
    final repository = await pumpShell(tester);
    for (final label in ['首页', '收藏', '搜索', '消息', '我的']) {
      expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text(label)),
        findsOneWidget,
      );
    }
    // Startup only loads the home page.
    expect(repository.pmRequests, 0);
    expect(repository.profileRequests, 0);

    await selectTab(tester, '我的');
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('登录南+账号'), findsOneWidget);
    expect(find.text('界面设置'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('界面设置'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
  });

  testWidgets('login returns to the same shell and unlocks messages',
      (tester) async {
    final repository = await pumpShell(tester);
    await selectTab(tester, '消息');
    expect(find.byType(PmBoxScreen), findsNothing);

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), _userA);
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(PmBoxScreen), findsOneWidget);
    expect(repository.pmRequests, 1);

    await selectTab(tester, '我的');
    expect(find.text(_userA), findsWidgets);
    expect(find.text('主题'), findsOneWidget);
  });

  testWidgets('logout asks first, then returns to the home tab',
      (tester) async {
    final repository = await pumpShell(tester, user: _userA);
    await selectTab(tester, '我的');
    await tester.scrollUntilVisible(find.text('退出登录'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.currentUsername, _userA);

    await tester.tap(find.text('退出登录').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();
    expect(repository.currentUsername, isNull);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('登录'), findsOneWidget, reason: 'home shows login');
  });

  testWidgets('logout still returns home when clearing outlives the tab',
      (tester) async {
    final repository = await pumpShell(tester, user: _userA);
    repository.clearGate = Completer<void>();
    await selectTab(tester, '我的');
    await tester.scrollUntilVisible(find.text('退出登录'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    // The owner is gone (tab rebuilt) while cookie deletion is still pending.
    await tester.pump();
    await tester.pump();
    repository.clearGate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('a new account rebuilds account tabs', (tester) async {
    final repository = await pumpShell(tester, user: _userA);
    await selectTab(tester, '消息');
    expect(repository.pmRequests, 1);

    repository.signIn(_userB);
    await tester.pumpAndSettle();
    expect(repository.pmRequests, 2, reason: 'B gets a fresh inbox');
    await selectTab(tester, '我的');
    expect(find.text(_userB), findsWidgets);
    expect(find.text(_userA), findsNothing);
  });

  testWidgets('back from another tab goes home before leaving', (tester) async {
    await pumpShell(tester);
    await selectTab(tester, '搜索');
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('large text keeps the bar readable', (tester) async {
    await pumpShell(tester,
        user: _userA, textScale: 2, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior,
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
    await selectTab(tester, '首页');
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('退出登录'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(tester.takeException(), isNull);
  });
}

class _NavRepository extends ForumRepository {
  final _session = ValueNotifier<String?>(null);
  int pmRequests = 0;
  int profileRequests = 0;

  void signIn(String? user) => _session.value = user;

  @override
  ValueListenable<String?> get sessionUser => _session;

  @override
  String? get currentUsername => _session.value;

  @override
  bool get isLoggedIn => _session.value != null;

  Completer<void>? clearGate;

  // Like the real repository: the owner clears first, persistence follows.
  @override
  Future<void> clearSession() async {
    _session.value = null;
    await clearGate?.future;
  }

  @override
  Future<ForumHomeSnapshot> fetchHome() async =>
      const ForumHomeSnapshot(latest: [], hot: [], sections: []);

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;

  @override
  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    pmRequests++;
    return ForumPmPage(box: box, messages: const []);
  }

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async {
    profileRequests++;
    return UserProfile(uid: '1', name: currentUsername ?? '', url: url);
  }

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview,
          {bool forceReload = false}) async =>
      overview;

  @override
  Future<UserProfile> fetchUserProfileFavorites(String url) =>
      fetchUserProfileOverview(url);

  @override
  Future<LoginChallenge> fetchLoginChallenge() async => LoginChallenge(
        captchaBytes: Uint8List.fromList(_onePixelPng),
        fields: const {'step': '2'},
      );

  @override
  Future<LoginResult> submitLogin({
    required String username,
    required String password,
    required String captcha,
    required Map<String, String> fields,
  }) async {
    signIn(username);
    return const LoginResult(success: true, message: '登录成功');
  }
}

const _onePixelPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
