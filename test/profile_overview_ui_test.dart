import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_image_viewer.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';

import 'profile_appendfix_support.dart';

class _AvatarProfileRepository extends FakeProfileRepository {
  _AvatarProfileRepository({super.topics});

  static final profile = profileFixture.copyWith(
    avatarUrl: 'https://south-plus.net/images/face/a.png',
    level: 'Lv.3',
    messageUrl: 'message.php?action-write-touid-123.html',
    info: const [UserProfileField(label: '性别', value: '保密')],
    stats: const [UserProfileField(label: '注册时间', value: '2024-03-31')],
  );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => profile;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => profile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeProfileRepository> open(WidgetTester tester,
      {UserProfileTab tab = UserProfileTab.home}) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository =
        _AvatarProfileRepository(topics: [listItem('第一页主题', tid: '1')]);
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(
        userUrl: profileFixture.url,
        repository: repository,
        initialTab: tab,
      ),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('the avatar opens the full-screen viewer', (tester) async {
    await open(tester);
    await tester.tap(find.bySemanticsLabel('查看头像'));
    await tester.pumpAndSettle();
    expect(find.byType(ThreadImageViewer), findsOneWidget);
  });

  testWidgets('facts are plain text apart from the operations',
      (tester) async {
    await open(tester);
    expect(find.text('等级 Lv.3'), findsOneWidget);
    expect(find.text('注册时间 2024-03-31'), findsOneWidget);
    for (final action in ['发短消息', '按人查找', '查看登录名']) {
      expect(
          find.ancestor(
              of: find.text(action), matching: find.byType(FilledButton)),
          findsOneWidget,
          reason: action);
    }
    expect(
        find.ancestor(
            of: find.text('等级 Lv.3'), matching: find.byType(FilledButton)),
        findsNothing);
  });

  for (final tab in [UserProfileTab.home, UserProfileTab.profile]) {
    testWidgets('$tab opens 概览 with info and activities', (tester) async {
      await open(tester, tab: tab);
      expect(find.text('首页'), findsNothing);
      expect(find.text('资料'), findsNothing);
      expect(find.text('个人信息'), findsOneWidget);
      expect(find.text('个人动态'), findsOneWidget);
    });
  }

  testWidgets('a 主题 link still opens on the topic list', (tester) async {
    await open(tester, tab: UserProfileTab.topics);
    expect(find.text('第一页主题'), findsOneWidget);
    expect(find.text('个人信息'), findsNothing);
  });

  testWidgets(
      'filters fold behind the toolbar and an active one stays visible with 清除',
      (tester) async {
    final repository = await open(tester, tab: UserProfileTab.topics);
    repository.onContent = (_) async => contentResult();
    expect(find.text('版块：全部'), findsNothing);
    expect(find.text('类型：全部'), findsNothing);

    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('类型：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起筛选'));
    await tester.pumpAndSettle();

    expect(find.text('类型：精华'), findsOneWidget, reason: 'active stays shown');
    expect(find.text('版块：全部'), findsNothing);
    expect(find.text('1'), findsOneWidget, reason: 'badge counts it');

    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('类型：精华'), findsNothing);
    expect(find.text('清除筛选'), findsNothing);
    expect(find.text('第一页主题'), findsOneWidget);
  });
}
