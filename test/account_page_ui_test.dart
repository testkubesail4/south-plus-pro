import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/history/browsing_history_screen.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/features/profile/settings_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic account only.
class _Repo extends ForumRepository {
  _Repo(this.signedIn);
  final bool signedIn;
  @override
  bool get isLoggedIn => signedIn;
  @override
  String? get currentUsername => signedIn ? 'fixture_login' : null;
  @override
  Future<void> loadAccountNickname() async {}
  @override
  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) async =>
      const [];
  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;
  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async =>
      UserProfile(uid: '1', name: 'fixture_login', url: url);
  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview,
          {bool forceReload = false}) async =>
      overview;
}

Future<void> _pump(WidgetTester tester, bool signedIn) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AccountScreen(repository: _Repo(signedIn), onLoggedOut: () {}),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('我的 lists each feature once; the rest has its own home',
      (tester) async {
    await _pump(tester, true);
    for (final row in ['我的主题', '我的回复', '浏览历史', '论坛任务', '屏蔽配置', '退出登录']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    // 设置 is the gear; 短消息/回复提醒 live in 消息, 收藏 in its tab, 资料 behind the header.
    for (final gone in ['设置', '短消息', '回复提醒', '收藏', '资料', '已连接']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the header card opens the own profile', (tester) async {
    await _pump(tester, true);
    await tester.tap(find.text('fixture_login'));
    await tester.pumpAndSettle();
    final profile = tester.widget<UserProfileScreen>(find.byType(UserProfileScreen));
    expect(profile.userUrl, 'u.php');
    expect(profile.initialTab, UserProfileTab.home);
  });

  testWidgets('a guest sees the login action and only local history',
      (tester) async {
    await _pump(tester, false);
    expect(find.text('登录南+账号'), findsOneWidget);
    for (final gone in ['我的主题', '我的回复', '论坛任务', '屏蔽配置', '退出登录']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await tester.tap(find.text('浏览历史'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowsingHistoryScreen), findsOneWidget);
  });
}
