import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/auth/login_screen.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/history/browsing_history_screen.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_tasks_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/reply/reply_sheet.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_post_body.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

void main() {
  testWidgets('app boots to simple home screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });

    await tester.pumpWidget(const SouthPlusApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('southplus'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('home exposes a light and dark mode toggle', (tester) async {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });

    await tester.pumpWidget(const SouthPlusApp());
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('切换为暗黑模式'), findsOneWidget);

    await tester.tap(find.byTooltip('切换为暗黑模式'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('切换为白天模式'), findsOneWidget);

    await tester.tap(find.byTooltip('切换为白天模式'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('切换为暗黑模式'), findsOneWidget);
  });

  testWidgets('skeleton card fits compact three-line layouts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: SkeletonCard(height: 86, lines: [0.92, 0.58, 0.36]),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('login failure remains visible if captcha refresh fails',
      (tester) async {
    final repository = _FakeLoginRepository();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(repository: repository)),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('密码错误'), findsOneWidget);
    expect(
      find.textContaining('验证码加载失败：没有找到登录表单'),
      findsOneWidget,
    );
  });

  testWidgets('login submits selected forum options', (tester) async {
    final repository = _FakeLoginRepository();

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('UID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一年'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一个月').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐身登录'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '10001');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(repository.lastFields, containsPair('lgt', '1'));
    expect(repository.lastFields, containsPair('hideid', '1'));
    expect(repository.lastFields, containsPair('cktime', '2592000'));
  });

  testWidgets('board thread list supports pull refresh on short pages',
      (tester) async {
    final repository = _FakeBoardRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.category,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
  });

  testWidgets('board thread list exposes nested sub boards at the top',
      (tester) async {
    final repository = _FakeBoardRepository();

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.archiveCategory,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('子版块'), findsOneWidget);
    expect(find.text('同人志&CG'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('同人志&CG'));
    await tester.pumpAndSettle();

    expect(find.text('子版主题'), findsOneWidget);
    expect(repository.requestedCategoryUrls, [
      'https://south-plus.net/thread.php?fid-218.html',
      'https://south-plus.net/thread.php?fid-213.html',
    ]);
  });

  testWidgets('board thread list enters doujin sub board for empty parents',
      (tester) async {
    final repository = _FakeBoardRepository();

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.emptyParentCategory,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('同人志&CG'), findsWidgets);
    expect(find.text('同人志&CG (图墙模式)'), findsNothing);
    expect(find.text('子版主题'), findsOneWidget);
    expect(repository.requestedCategoryUrls, [
      'https://south-plus.net/thread.php?fid-226.html',
      'https://south-plus.net/thread.php?fid-227.html',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board thread list keeps multi-child empty parents selectable',
      (tester) async {
    final repository = _FakeBoardRepository();

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.multiChildParentCategory,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('网赚资源区'), findsWidgets);
    expect(find.text('CG资源'), findsOneWidget);
    expect(find.text('实用动画'), findsOneWidget);
    expect(find.text('这个板块的主题在子版块中'), findsOneWidget);
    expect(repository.requestedCategoryUrls, [
      'https://south-plus.net/thread.php?fid-170.html',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board thread list keeps known sub boards when fetch lacks them',
      (tester) async {
    final repository = _FakeBoardRepository();

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.category,
          repository: repository,
          initialSubBoards: const [
            ForumBoard(
              name: '同人志&CG',
              url: 'https://south-plus.net/thread.php?fid-227.html',
              section: 'Comic Market 107',
            ),
            ForumBoard(
              name: '同人志&CG (图墙模式)',
              url: 'https://south-plus.net/thread.php?fid-228.html',
              section: 'Comic Market 107',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('子版块'), findsOneWidget);
    expect(find.text('同人志&CG'), findsOneWidget);
    expect(find.text('同人志&CG (图墙模式)'), findsOneWidget);
    expect(find.text('子版主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board sub board entry scrolls with thread list', (tester) async {
    final repository = _FakeBoardRepository();

    await tester.binding.setSurfaceSize(const Size(360, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: BoardThreadListScreen(
          category: _FakeBoardRepository.archiveCategory,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('子版块'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('子版块'), findsNothing);
    expect(find.text('父版主题 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home renders nested boards as mobile-friendly child chips',
      (tester) async {
    final repository = _FakeHomeRepository();

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('漫区特设'), findsOneWidget);

    await tester.tap(find.text('漫区特设'));
    await tester.pumpAndSettle();

    expect(find.text('旧物仓库'), findsOneWidget);
    expect(find.text('C103'), findsOneWidget);
    expect(find.text('C102'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('C103'));
    await tester.pumpAndSettle();

    expect(repository.requestedCategoryUrls, [
      'https://south-plus.net/thread.php?fid-218.html',
    ]);
  });

  testWidgets('home passes parent board children into board pages',
      (tester) async {
    final repository = _FakeHomeRepository();

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('漫区特设'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旧物仓库'));
    await tester.pumpAndSettle();

    expect(find.text('子版块'), findsOneWidget);
    expect(find.text('C103'), findsOneWidget);
    expect(find.text('C102'), findsOneWidget);
    expect(repository.requestedCategoryUrls, [
      'https://south-plus.net/thread.php?fid-43.html',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home exposes forum tasks shortcut', (tester) async {
    final repository = _FakeHomeRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('任务奖励'), findsOneWidget);

    await tester.tap(find.text('任务奖励'));
    await tester.pumpAndSettle();

    expect(find.text('论坛任务'), findsWidgets);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('home task shortcut claims rewards in one tap', (tester) async {
    final repository = _FakeQuickClaimHomeRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('任务奖励'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(repository.claimRequests, 1);
    expect(find.text('任务奖励领取完成'), findsOneWidget);
    expect(find.text('日常奖励领取完成SP+2'), findsOneWidget);
    expect(find.text('周常奖励领取完成SP+7'), findsOneWidget);
  });

  testWidgets('home task shortcut shows cached completed state',
      (tester) async {
    final repository = _FakeCompletedTaskHomeRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('已签到'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets(
      'home task shortcut shows claimable when in-progress reward exists',
      (tester) async {
    final repository = _FakeClaimableTaskHomeRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('可领取'), findsOneWidget);
    expect(find.text('已签到'), findsNothing);
    expect(find.byIcon(Icons.redeem_outlined), findsOneWidget);
  });

  testWidgets('home task shortcut matches current live daily-claimable state',
      (tester) async {
    final repository = _FakeClaimableTaskHomeRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('可领取'), findsOneWidget);
    expect(find.text('已签到'), findsNothing);
    expect(find.text('已自动签到'), findsNothing);
  });

  testWidgets('home task shortcut shows automatic sign-in success',
      (tester) async {
    final repository = _FakeAutoClaimHomeRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(repository.autoClaimRequests, 1);
    expect(find.text('已自动签到'), findsOneWidget);
    expect(find.text('自动签到完成'), findsOneWidget);
    expect(find.text('日常奖励领取完成SP+2'), findsOneWidget);
  });

  testWidgets('browsing history opens a viewed thread', (tester) async {
    final repository = _FakeHistoryRepository();

    await tester.pumpWidget(
      MaterialApp(home: BrowsingHistoryScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('浏览历史'), findsOneWidget);
    expect(find.text('看过的主题'), findsOneWidget);
    expect(find.text('10 回'), findsOneWidget);

    await tester.tap(find.text('看过的主题'));
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls, [
      'https://south-plus.net/read.php?tid-88.html',
    ]);
    expect(find.text('history body', findRichText: true), findsOneWidget);
  });

  testWidgets('browsing history can be cleared after confirmation',
      (tester) async {
    final repository = _FakeHistoryRepository();

    await tester.pumpWidget(
      MaterialApp(home: BrowsingHistoryScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('清空浏览历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();

    expect(repository.cleared, isTrue);
    expect(find.text('还没有浏览历史'), findsOneWidget);
    expect(find.text('浏览历史已清空'), findsOneWidget);
  });

  testWidgets('profile overview renders before detail tabs finish loading',
      (tester) async {
    final repository = _FakeProfileRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          userUrl: 'https://south-plus.net/u.php?action-show-uid-1.html',
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('UID 1'), findsOneWidget);
    expect(find.text('个人动态'), findsNothing);

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('论坛资历'), findsOneWidget);

    repository.completeDetails();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();

    expect(find.text('个人动态'), findsOneWidget);
    expect(find.text('发表了主题'), findsOneWidget);
  });

  testWidgets('forum tasks can claim an in-progress reward', (tester) async {
    final repository = _FakeTasksRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(
          repository: repository,
          onLoggedOut: () {},
          packageInfoLoader: _fakePackageInfo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('论坛任务'));
    await tester.pumpAndSettle();

    expect(find.text('日常'), findsOneWidget);
    expect(find.text('SP币 2 G'), findsOneWidget);
    expect(find.text('领取奖励'), findsOneWidget);

    await tester.tap(find.text('领取奖励'));
    await tester.pumpAndSettle();

    expect(repository.ranTaskIds, ['15']);
    expect(find.text('奖励领取完成'), findsOneWidget);
    expect(find.text('完成时间 2026-06-17 AM:11:37:46'), findsOneWidget);
  });

  testWidgets('account screen exposes theme mode settings', (tester) async {
    final repository = _FakeTasksRepository();
    SharedPreferences.setMockInitialValues({});
    await AppThemeController.setMode(ThemeMode.system);
    addTearDown(() async {
      await AppThemeController.setMode(ThemeMode.system);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(
          repository: repository,
          onLoggedOut: () {},
          packageInfoLoader: _fakePackageInfo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('界面设置'),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('界面设置'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('白天模式'), findsOneWidget);
    expect(find.text('暗黑模式'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('暗黑模式'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    expect(AppThemeController.themeMode, ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.themeMode'), 'dark');

    await AppThemeController.setMode(ThemeMode.light);
    expect(AppThemeController.themeMode, ThemeMode.light);

    await AppThemeController.setMode(ThemeMode.system);
    expect(AppThemeController.themeMode, ThemeMode.system);
  });

  testWidgets('account screen exposes app version and update check',
      (tester) async {
    final repository = _FakeTasksRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(
          repository: repository,
          onLoggedOut: () {},
          packageInfoLoader: _fakePackageInfo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('应用'),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('南+'), findsOneWidget);
    expect(find.text('v0.1.8+8'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('forum tasks page exposes quick claim fallback', (tester) async {
    final repository = _FakeQuickClaimTasksRepository();

    await tester.pumpWidget(
      MaterialApp(home: ForumTasksScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('一键领取任务奖励'), findsOneWidget);

    await tester.tap(find.text('一键领取任务奖励'));
    await tester.pumpAndSettle();

    expect(repository.claimRequests, 1);
    expect(find.text('任务奖励领取完成'), findsOneWidget);
    expect(find.text('日常奖励领取完成SP+2'), findsOneWidget);
  });

  testWidgets('profile uses cached overview while refreshing fresh data',
      (tester) async {
    final repository = _CachedProfileRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          userUrl: 'https://south-plus.net/u.php?action-show-uid-1.html',
          repository: repository,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Cached Alice'), findsOneWidget);
    expect(find.text('Fresh Alice'), findsNothing);

    repository.completeFreshOverview();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Fresh Alice'), findsOneWidget);
    expect(find.text('Cached Alice'), findsNothing);
  });

  testWidgets('deferred inline image placeholder stays compact',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(ImageLoadMode.manual);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ThreadInlineImage(
              image: ThreadImage(url: 'https://example.com/image.jpg'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final inlineImageContainerFinder =
        find.byKey(const ValueKey('thread-inline-image-container'));
    final inlineImageContainer =
        tester.widget<Container>(inlineImageContainerFinder);
    final forumImage = tester.widget<CachedForumImage>(
      find.descendant(
        of: inlineImageContainerFinder,
        matching: find.byType(CachedForumImage),
      ),
    );

    expect(inlineImageContainer.color, isNull);
    expect(forumImage.memCacheWidth, 720);
    expect(forumImage.memCacheHeight, isNull);
    expect(tester.getSize(find.byType(ThreadInlineImage)).height, 160);
    expect(find.byIcon(Icons.download_outlined), findsNothing);

    final inlineImageTapTarget = tester.widget<InkWell>(
      find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.onLongPress != null,
      ),
    );
    inlineImageTapTarget.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('保存图片'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('点击加载图片'),
      ),
      findsNothing,
    );

    final viewerImage = tester.widget<CachedForumImage>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(CachedForumImage),
      ),
    );
    expect(viewerImage.bypassLoadPolicy, isTrue);
  });

  testWidgets('post body does not duplicate inline links as buttons',
      (tester) async {
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(arguments['text']! as String);
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{
            'text': clipboardWrites.isEmpty ? null : clipboardWrites.last,
          };
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThreadPostBody(
            content: 'Example',
            segments: const [
              ThreadContentSegment.text(
                'Example',
                href: 'https://example.com',
              ),
            ],
            quote: null,
            images: const [],
            links: const [
              ThreadLink(url: 'https://example.com', label: 'Example'),
            ],
            saleBoxes: const [],
            saleBoxesFirst: false,
            buyingSaleBoxes: const {},
            onBuySaleBox: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.longPress(find.text('Example'));
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, 'https://example.com');
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('post body rich text participates in system selection',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThreadPostBody(
            content: '',
            segments: const [
              ThreadContentSegment.text('第一段正文'),
              ThreadContentSegment.quote([
                ThreadContentSegment.text('引用内容'),
              ]),
              ThreadContentSegment.text('第二段正文'),
            ],
            quote: null,
            images: const [],
            links: const [],
            saleBoxes: const [],
            saleBoxesFirst: false,
            buyingSaleBoxes: const {},
            onBuySaleBox: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    expect(richTexts, isNotEmpty);
    for (final richText in richTexts) {
      expect(richText.selectionRegistrar, isNotNull);
      expect(richText.selectionColor, isNotNull);
    }
  });

  testWidgets('paid content sale box renders clear metadata and action',
      (tester) async {
    final purchases = <ThreadSaleBox>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThreadPostBody(
            content: '',
            segments: const [],
            quote: null,
            images: const [],
            links: const [],
            saleBoxes: const [
              ThreadSaleBox(
                summary: '此帖售价 5 SP币,已有 8 人购买',
                buyPath: 'job.php?action=buytopic&tid=1&pid=1',
                warning: '购买风险提示',
                price: 5,
                buyers: 8,
              ),
            ],
            saleBoxesFirst: true,
            buyingSaleBoxes: const {},
            onBuySaleBox: purchases.add,
          ),
        ),
      ),
    );

    expect(find.text('付费内容'), findsOneWidget);
    expect(find.text('5 SP币'), findsOneWidget);
    expect(find.text('8 人购买'), findsOneWidget);
    expect(find.text('购买查看'), findsOneWidget);
    expect(find.text('购买风险提示'), findsOneWidget);

    await tester.tap(find.text('购买查看'));
    expect(purchases, hasLength(1));
  });

  testWidgets('reply composer can focus content field', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReplyComposer(
            thread: _FakeThreadRepository.thread,
            repository: _FakeThreadRepository(),
            onSubmitted: (_) {},
          ),
        ),
      ),
    );

    final contentFieldFinder = find.byType(TextField).last;
    final submitButtonFinder =
        find.byKey(const ValueKey('reply-submit-button'));
    expect(tester.widget<TextField>(contentFieldFinder).focusNode?.hasFocus,
        isFalse);
    expect(
      tester.widget<ButtonStyleButton>(submitButtonFinder).onPressed,
      isNull,
    );

    final state = tester.state<ReplyComposerState>(find.byType(ReplyComposer));
    state.focusContent();
    await tester.pump();

    expect(tester.widget<TextField>(contentFieldFinder).focusNode?.hasFocus,
        isTrue);

    await tester.enterText(contentFieldFinder, '有效回复');
    await tester.pump();

    expect(
      tester.widget<ButtonStyleButton>(submitButtonFinder).onPressed,
      isNotNull,
    );
  });

  testWidgets('download links render preview and download actions',
      (tester) async {
    final clipboardWrites = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(arguments['text']! as String);
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{
            'text': clipboardWrites.isEmpty ? null : clipboardWrites.last,
          };
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    const magnetUrl =
        'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThreadRichContent(
            segments: [
              ThreadContentSegment.text(magnetUrl),
            ],
          ),
        ),
      ),
    );

    expect(find.text(magnetUrl), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);

    await tester.tap(find.text('复制'));
    await tester.pump();

    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboardData?.text, magnetUrl);
    expect(find.text('链接已复制'), findsOneWidget);
  });

  testWidgets('download link preview dialog includes copy action',
      (tester) async {
    const magnetUrl =
        'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThreadRichContent(
            segments: [
              ThreadContentSegment.text(magnetUrl),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('复制'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ThreadRichContent renders emoji without manual-load placeholder',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(ImageLoadMode.manual);
    addTearDown(() async {
      await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThreadRichContent(
            segments: [
              ThreadContentSegment.image(
                url: 'https://example.com/emoji-wide.png',
                isEmoji: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('点击加载图片'), findsNothing);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('thread detail shows avatar fallback and page controls',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('thread-author-avatar-fallback')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('南+ / 事务受理'),
      ),
      findsOneWidget,
    );
    expect(find.text('南+ South Plus'), findsNothing);
    expect(find.text('上一主题'), findsOneWidget);
    expect(find.text('下一主题'), findsOneWidget);
    expect(find.text('RSS'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsOneWidget);
    expect(find.text('只看该作者'), findsNothing);
    expect(find.text('2 / 4'), findsNWidgets(2));
    expect(find.text('page 2 body', findRichText: true), findsNothing);
    expect(find.text('reply on page 2', findRichText: true), findsOneWidget);

    await tester.tap(find.text('»').first);
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 3]);
    expect(find.text('reply on page 3', findRichText: true), findsOneWidget);
  });

  testWidgets('thread detail jump clamps page number', (tester) async {
    final repository = _FakeThreadRepository(initialPage: 2);

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('跳转').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'abc',
    );
    await tester.tap(find.widgetWithText(FilledButton, '跳转'));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效页码'), findsOneWidget);
    expect(repository.requestedPages, [1]);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '99',
    );
    await tester.tap(find.widgetWithText(FilledButton, '跳转'));
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 4]);
    expect(find.text('reply on page 4', findRichText: true), findsOneWidget);
  });

  testWidgets('thread detail keeps current content when pagination fails',
      (tester) async {
    final repository = _FakeThreadRepository(failPages: {3});

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('»').first);
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 3]);
    expect(find.text('reply on page 2', findRichText: true), findsOneWidget);
    expect(find.text('reply on page 3', findRichText: true), findsNothing);
    expect(find.textContaining('页面加载失败：boom page 3'), findsOneWidget);
  });

  testWidgets('thread detail loads and clears server author filter',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('floor-actions-Bob-B2F')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看该作者'));
    await tester.pumpAndSettle();

    expect(repository.requestedPages, [1, 1]);
    expect(repository.requestedThreadUrls, [
      'https://south-plus.net/read.php?tid-1.html',
      'https://south-plus.net/read.php?tid-1-uid-2.html',
    ]);
    expect(find.text('只看 Bob'), findsOneWidget);
    expect(find.text('第 1 / 1 页 · 本页 1 楼'), findsOneWidget);

    await tester.tap(find.byTooltip('取消只看该作者'));
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls.last,
        'https://south-plus.net/read.php?tid-1.html');
    expect(find.text('只看 Bob'), findsNothing);
  });

  testWidgets('thread detail uses server pagination for original poster filter',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.text('只看楼主'),
        matching: find.byType(FilterChip),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls, [
      'https://south-plus.net/read.php?tid-1.html',
      'https://south-plus.net/read.php?tid-1-uid-1.html',
    ]);
    expect(find.text('只看 Alice'), findsOneWidget);
    expect(find.text('第 1 / 2 页 · 本页 1 楼'), findsOneWidget);
    expect(find.text('op filtered page 1', findRichText: true), findsOneWidget);
    expect(find.text('1 / 2'), findsWidgets);
    expect(find.text('2 / 4'), findsNothing);
    expect(
      tester
          .widget<FilterChip>(
            find.ancestor(
              of: find.text('只看楼主'),
              matching: find.byType(FilterChip),
            ),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.text('»').first);
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls.last,
        'https://south-plus.net/read.php?tid-1-uid-1.html');
    expect(repository.requestedPages, [1, 1, 2]);
    expect(find.text('op filtered page 2', findRichText: true), findsOneWidget);
    expect(find.text('2 / 2'), findsWidgets);
    expect(find.text('第 2 / 2 页 · 本页 1 楼'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('只看楼主'),
        matching: find.byType(FilterChip),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedThreadUrls.last,
        'https://south-plus.net/read.php?tid-1.html');
    expect(find.text('只看 Alice'), findsNothing);
    expect(find.text('1 / 4'), findsWidgets);
  });

  testWidgets('thread detail shows empty state for empty author filter',
      (tester) async {
    final repository = _FakeThreadRepository(emptyAuthorFilter: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('floor-actions-Bob-B2F')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看该作者'));
    await tester.pumpAndSettle();

    expect(find.text('只看 Bob'), findsOneWidget);
    expect(find.text('第 1 / 1 页 · 本页 0 楼'), findsOneWidget);
    expect(find.text('没有该作者内容'), findsOneWidget);
    expect(find.text('当前筛选结果没有可展示的楼层。'), findsOneWidget);
  });

  testWidgets('thread detail inserts server quote draft when available',
      (tester) async {
    final repository = _FakeThreadRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: ThreadDetailScreen(
          thread: _FakeThreadRepository.thread,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final floorActions = find.byKey(const ValueKey('floor-actions-Bob-B2F'));
    await tester.ensureVisible(floorActions);
    await tester.pumpAndSettle();
    await tester.tap(floorActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('引用').last);
    await tester.pumpAndSettle();

    expect(repository.requestedQuoteUrls, [
      'https://south-plus.net/post.php?action-quote-fid-2-tid-1-pid-20-article-1.html',
    ]);
    final contentField = tester.widget<TextField>(find.byType(TextField).last);
    expect(contentField.controller?.text,
        '[quote]server quote from Bob[/quote]\n');
  });
}

Future<PackageInfo> _fakePackageInfo() async {
  return PackageInfo(
    appName: '南+',
    packageName: 'com.example.south_plus_rewrite',
    version: '0.1.8',
    buildNumber: '8',
  );
}

class _FakeProfileRepository extends ForumRepository {
  _FakeProfileRepository();

  final _detailsCompleter = Completer<UserProfile>();

  static const overview = UserProfile(
    uid: '1',
    name: 'Alice',
    url: 'https://south-plus.net/u.php?action-show-uid-1.html',
    tagline: '干净签名',
    level: 'Lv.3',
    isOnline: true,
    statusText: '在线',
    messageUrl: 'https://south-plus.net/message.php?action-write-touid-1.html',
    info: [
      UserProfileField(label: 'UID', value: '1'),
      UserProfileField(label: '昵称', value: 'alice'),
    ],
    stats: [
      UserProfileField(label: '在线时间', value: '9 小时'),
    ],
  );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => null;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => overview;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) {
    return _detailsCompleter.future;
  }

  void completeDetails() {
    if (_detailsCompleter.isCompleted) return;
    _detailsCompleter.complete(
      overview.copyWith(
        homeActivities: const [
          UserActivityItem(
            title: '测试主题',
            url: 'https://south-plus.net/read.php?tid-1.html',
            action: '发表了主题',
          ),
        ],
      ),
    );
  }
}

class _FakeLoginRepository extends ForumRepository {
  int challengeRequests = 0;
  Map<String, String>? lastFields;

  @override
  Future<LoginChallenge> fetchLoginChallenge() async {
    challengeRequests += 1;
    if (challengeRequests == 1) {
      return LoginChallenge(
        captchaBytes: Uint8List.fromList(_onePixelPng),
        fields: const {'step': '2'},
      );
    }
    throw const ForumRepositoryException('没有找到登录表单');
  }

  @override
  Future<LoginResult> submitLogin({
    required String username,
    required String password,
    required String captcha,
    required Map<String, String> fields,
  }) async {
    lastFields = Map<String, String>.from(fields);
    return const LoginResult(success: false, message: '密码错误');
  }
}

class _FakeBoardRepository extends ForumRepository {
  static const category = ForumCategory(
    name: '测试版块',
    slug: 'test',
    url: 'https://south-plus.net/thread.php?fid-1.html',
  );
  static const archiveCategory = ForumCategory(
    name: 'C103',
    slug: 'fid-218',
    url: 'https://south-plus.net/thread.php?fid-218.html',
  );
  static const emptyParentCategory = ForumCategory(
    name: 'Comic Market 107',
    slug: 'fid-226',
    url: 'https://south-plus.net/thread.php?fid-226.html',
  );
  static const multiChildParentCategory = ForumCategory(
    name: '网赚资源区',
    slug: 'fid-170',
    url: 'https://south-plus.net/thread.php?fid-170.html',
  );

  final requestedCategoryUrls = <String>[];

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
  }) async {
    requestedCategoryUrls.add(category.url ?? '');
    if (category.url?.contains('fid-218') == true) {
      return ForumThreadPage(
        currentPage: 1,
        totalPages: 1,
        subBoards: [
          ForumBoard(
            name: '同人志&CG',
            url: 'https://south-plus.net/thread.php?fid-213.html',
            section: 'C103',
            postCount: 26246,
          ),
          ForumBoard(
            name: '同人志&CG (图墙模式)',
            url: 'https://south-plus.net/thread.php?fid-214.html',
            section: 'C103',
          ),
        ],
        threads: [
          for (var index = 1; index <= 12; index++)
            ForumThread(
              title: '父版主题 $index',
              url: 'https://south-plus.net/read.php?tid-$index.html',
              replies: index,
              section: 'C103',
            ),
        ],
      );
    }
    if (category.url?.contains('fid-226') == true) {
      return const ForumThreadPage(
        currentPage: 1,
        totalPages: 1,
        threads: [],
        subBoards: [
          ForumBoard(
            name: '同人志&CG',
            url: 'https://south-plus.net/thread.php?fid-227.html',
            section: 'Comic Market 107',
          ),
          ForumBoard(
            name: '同人志&CG (图墙模式)',
            url: 'https://south-plus.net/thread.php?fid-228.html',
            section: 'Comic Market 107',
          ),
        ],
      );
    }
    if (category.url?.contains('fid-170') == true) {
      return const ForumThreadPage(
        currentPage: 1,
        totalPages: 1,
        threads: [],
        subBoards: [
          ForumBoard(
            name: 'CG资源',
            url: 'https://south-plus.net/thread.php?fid-171.html',
            section: '网赚资源区',
          ),
          ForumBoard(
            name: '实用动画',
            url: 'https://south-plus.net/thread.php?fid-172.html',
            section: '网赚资源区',
          ),
        ],
      );
    }
    return const ForumThreadPage(
      currentPage: 1,
      totalPages: 1,
      threads: [
        ForumThread(
          title: '子版主题',
          url: 'https://south-plus.net/read.php?tid-2.html',
          replies: 0,
          section: '测试版块',
        ),
      ],
    );
  }
}

class _FakeHomeRepository extends ForumRepository {
  final requestedCategoryUrls = <String>[];

  @override
  Future<ForumHomeSnapshot> fetchHome() async {
    return const ForumHomeSnapshot(
      latest: [
        ForumThread(
          title: '首页主题',
          url: 'https://south-plus.net/read.php?tid-1.html',
          replies: 1,
          section: '茶馆',
        ),
      ],
      hot: [
        ForumCategory(
          name: '茶馆',
          slug: 'fid-9',
          url: 'https://south-plus.net/thread.php?fid-9.html',
        ),
      ],
      sections: [
        ForumSection(
          title: '漫区特设',
          items: [
            ForumBoard(
              name: '旧物仓库',
              url: 'https://south-plus.net/thread.php?fid-43.html',
              section: '漫区特设',
              topicCount: 35097,
              postCount: 882487,
              children: [
                ForumBoard(
                  name: 'C103',
                  url: 'https://south-plus.net/thread.php?fid-218.html',
                  section: '漫区特设 / 旧物仓库',
                ),
                ForumBoard(
                  name: 'C102',
                  url: 'https://south-plus.net/thread.php?fid-215.html',
                  section: '漫区特设 / 旧物仓库',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
  }) async {
    requestedCategoryUrls.add(category.url ?? '');
    return const ForumThreadPage(
      currentPage: 1,
      totalPages: 1,
      threads: [
        ForumThread(
          title: '子版主题',
          url: 'https://south-plus.net/read.php?tid-2.html',
          replies: 0,
          section: 'C103',
        ),
      ],
    );
  }

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async {
    return null;
  }
}

class _FakeQuickClaimHomeRepository extends _FakeHomeRepository {
  var claimRequests = 0;

  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumTaskQuickClaimResult> claimForumTaskRewards() async {
    claimRequests += 1;
    return const ForumTaskQuickClaimResult(
      appliedCount: 2,
      claimedRewards: [
        ForumTaskClaimItem(
          name: '日常',
          reward: 'SP币 2 G',
          spAmount: 2,
          message: 'success',
        ),
        ForumTaskClaimItem(
          name: '周常',
          reward: 'SP币 7 G',
          spAmount: 7,
          message: 'success',
        ),
      ],
      failures: [],
    );
  }
}

class _FakeCompletedTaskHomeRepository extends _FakeHomeRepository {
  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async {
    return ForumTaskSnapshot(
      updatedAt: DateTime.utc(2026, 6, 17),
      tasks: const [
        ForumTaskState(
          name: '日常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 2 G',
          spAmount: 2,
          completedAt: '2026-06-17 AM:11:37:46',
          cooldownRemaining: Duration(hours: 18),
        ),
        ForumTaskState(
          name: '周常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 7 G',
          spAmount: 7,
          completedAt: '2026-06-17 PM:13:28:02',
          cooldownRemaining: Duration(hours: 158),
        ),
      ],
    );
  }
}

class _FakeClaimableTaskHomeRepository extends _FakeHomeRepository {
  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async {
    return ForumTaskSnapshot(
      updatedAt: DateTime.utc(2026, 6, 19),
      tasks: const [
        ForumTaskState(
          name: '日常',
          availability: ForumTaskAvailability.claimable,
          reward: 'SP币 2 G',
          spAmount: 2,
          progressPercent: 100,
          completedAt: '2026-06-17 AM:11:37:46',
        ),
        ForumTaskState(
          name: '周常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 7 G',
          spAmount: 7,
          completedAt: '2026-06-17 PM:13:28:02',
          cooldownRemaining: Duration(hours: 158),
        ),
      ],
    );
  }
}

class _FakeAutoClaimHomeRepository extends _FakeHomeRepository {
  var autoClaimRequests = 0;
  var _autoClaimed = false;

  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async {
    autoClaimRequests += 1;
    _autoClaimed = true;
    return const ForumTaskQuickClaimResult(
      appliedCount: 1,
      claimedRewards: [
        ForumTaskClaimItem(
          name: '日常',
          reward: 'SP币 2 G',
          spAmount: 2,
          message: 'success',
        ),
      ],
      failures: [],
    );
  }

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async {
    if (!_autoClaimed) return null;
    final now = DateTime.now().toUtc();
    return ForumTaskSnapshot(
      updatedAt: now,
      tasks: [
        ForumTaskState(
          name: '日常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 2 G',
          spAmount: 2,
          nextAvailableAt: now.add(const Duration(hours: 23)),
        ),
        ForumTaskState(
          name: '周常',
          availability: ForumTaskAvailability.completed,
          reward: 'SP币 7 G',
          spAmount: 7,
          nextAvailableAt: now.add(const Duration(days: 6)),
        ),
      ],
    );
  }
}

class _FakeQuickClaimTasksRepository extends _FakeTasksRepository {
  var claimRequests = 0;

  @override
  Future<ForumTaskQuickClaimResult> claimForumTaskRewards() async {
    claimRequests += 1;
    return const ForumTaskQuickClaimResult(
      appliedCount: 1,
      claimedRewards: [
        ForumTaskClaimItem(
          name: '日常',
          reward: 'SP币 2 G',
          spAmount: 2,
          message: 'success',
        ),
      ],
      failures: [],
    );
  }
}

class _FakeHistoryRepository extends ForumRepository {
  bool cleared = false;
  var _entries = [
    BrowsingHistoryEntry(
      thread: ForumThread(
        title: '看过的主题',
        url: 'https://south-plus.net/read.php?tid-88.html',
        replies: 10,
        section: '茶馆',
        bodyPreview: '历史里的摘要',
        author: 'Alice',
      ),
      viewedAt: DateTime.now().subtract(const Duration(minutes: 3)).toUtc(),
    ),
  ];
  final requestedThreadUrls = <String>[];

  @override
  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) async {
    return _entries;
  }

  @override
  Future<void> clearBrowsingHistory() async {
    cleared = true;
    _entries = const [];
  }

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    requestedThreadUrls.add(thread.url);
    return ThreadDetail(
      thread: thread.copyWith(
        author: 'Alice',
        lastPost: '2026-05-30 10:00',
      ),
      body: 'history body',
      bodySegments: const [ThreadContentSegment.text('history body')],
      replies: const [],
      pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
    );
  }
}

class _FakeTasksRepository extends ForumRepository {
  final ranTaskIds = <String>[];
  var _claimed = false;

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => 'alice';

  @override
  Future<List<ForumTask>> fetchForumTasks(ForumTaskStatus status) async {
    if (status == ForumTaskStatus.inProgress && !_claimed) {
      return const [
        ForumTask(
          id: '15',
          name: '日常',
          status: ForumTaskStatus.inProgress,
          description: '每日SP+2的日常。',
          reward: 'SP币 2 G',
          progressPercent: 100,
          actionLabel: '领取此奖励',
        ),
      ];
    }
    if (status == ForumTaskStatus.completed && _claimed) {
      return const [
        ForumTask(
          name: '日常',
          status: ForumTaskStatus.completed,
          description: '每日SP+2的日常。',
          reward: 'SP币 2 G',
          progressPercent: 100,
          completedAt: '2026-06-17 AM:11:37:46',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<ForumTaskActionResult> runForumTask(
    ForumTask task, {
    bool claimReward = false,
  }) async {
    ranTaskIds.add(task.id ?? '');
    _claimed = true;
    return const ForumTaskActionResult(
      success: true,
      message: '奖励领取完成',
    );
  }
}

const _onePixelPng = <int>[
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

class _CachedProfileRepository extends ForumRepository {
  _CachedProfileRepository();

  final _overviewCompleter = Completer<UserProfile>();
  final _detailsCompleter = Completer<UserProfile>();

  static const cached = UserProfile(
    uid: '1',
    name: 'Cached Alice',
    url: 'https://south-plus.net/u.php?action-show-uid-1.html',
    tagline: '缓存签名',
    level: 'Lv.2',
    isOnline: true,
    statusText: '在线',
    info: [
      UserProfileField(label: 'UID', value: '1'),
    ],
  );

  static const fresh = UserProfile(
    uid: '1',
    name: 'Fresh Alice',
    url: 'https://south-plus.net/u.php?action-show-uid-1.html',
    tagline: '最新签名',
    level: 'Lv.3',
    isOnline: true,
    statusText: '在线',
    info: [
      UserProfileField(label: 'UID', value: '1'),
    ],
  );

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => cached;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) {
    return _overviewCompleter.future;
  }

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) {
    return _detailsCompleter.future;
  }

  void completeFreshOverview() {
    if (_overviewCompleter.isCompleted) return;
    _overviewCompleter.complete(fresh);
  }
}

class _FakeThreadRepository extends ForumRepository {
  _FakeThreadRepository({
    this.initialPage = 2,
    this.failPages = const {},
    this.emptyAuthorFilter = false,
  });

  final int initialPage;
  final Set<int> failPages;
  final bool emptyAuthorFilter;
  final requestedPages = <int>[];
  final requestedThreadUrls = <String>[];
  final requestedQuoteUrls = <String>[];

  static const thread = ForumThread(
    title: '测试主题',
    url: 'https://south-plus.net/read.php?tid-1.html',
    replies: 3,
    section: '事务受理',
    author: 'Alice',
    authorUrl: 'https://south-plus.net/u.php?action-show-uid-1.html',
  );

  @override
  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    requestedThreadUrls.add(thread.url);
    final requested = requestedPages.isEmpty ? initialPage : page;
    requestedPages.add(page);
    if (failPages.contains(requested)) {
      throw 'boom page $requested';
    }
    if (thread.url.contains('uid-1')) {
      final current = requested.clamp(1, 2).toInt();
      return ThreadDetail(
        thread: thread.copyWith(
          author: 'Alice',
          authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
          lastPost: '2026-05-30 10:00',
        ),
        body: current == 1 ? 'op filtered page 1' : '',
        bodySegments: current == 1
            ? [const ThreadContentSegment.text('op filtered page 1')]
            : const [],
        replies: [
          if (current == 2)
            const ThreadReply(
              author: 'Alice',
              content: 'op filtered page 2',
              segments: [ThreadContentSegment.text('op filtered page 2')],
              floor: 'B9F',
              postedAt: '2026-05-30 12:00',
            ),
        ],
        pagination: ThreadPagination(currentPage: current, totalPages: 2),
      );
    }
    if (thread.url.contains('uid-2')) {
      if (emptyAuthorFilter) {
        return ThreadDetail(
          thread: thread.copyWith(
            author: 'Alice',
            authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
            lastPost: '2026-05-30 10:00',
          ),
          body: '',
          replies: const [],
          pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
        );
      }
      return ThreadDetail(
        thread: thread.copyWith(
          author: 'Alice',
          authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
          lastPost: '2026-05-30 10:00',
        ),
        body: '',
        replies: const [
          ThreadReply(
            author: 'Bob',
            content: 'bob filtered page 1',
            segments: [ThreadContentSegment.text('bob filtered page 1')],
            floor: 'B2F',
            postedAt: '2026-05-30 11:00',
          ),
        ],
        pagination: const ThreadPagination(currentPage: 1, totalPages: 1),
      );
    }
    final current = requested.clamp(1, 4).toInt();
    final openingPage = current == 1;
    return ThreadDetail(
      thread: thread.copyWith(
        author: 'Alice',
        authorAvatarUrl: openingPage ? null : thread.authorAvatarUrl,
        authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-1.html',
        lastPost: '2026-05-30 10:00',
      ),
      body: openingPage ? 'page $current body' : '',
      bodySegments: openingPage
          ? [ThreadContentSegment.text('page $current body')]
          : const [],
      replies: [
        ThreadReply(
          author: 'Bob',
          authorAvatarUrl: null,
          content: 'reply on page $current',
          segments: [ThreadContentSegment.text('reply on page $current')],
          authorPostsUrl: 'https://south-plus.net/read.php?tid-1-uid-2.html',
          quoteUrl:
              'https://south-plus.net/post.php?action-quote-fid-2-tid-1-pid-${current}0-article-1.html',
          floor: 'B${current}F',
          postedAt: '2026-05-30 11:00',
        ),
      ],
      pagination: ThreadPagination(currentPage: current, totalPages: 4),
      previousThread: const ThreadActionLink(
        label: '上一主题',
        url:
            'https://south-plus.net/job.php?action-previous-fid-2-tid-1-fpage-0-goto-previous.html',
      ),
      nextThread: const ThreadActionLink(
        label: '下一主题',
        url:
            'https://south-plus.net/job.php?action-previous-fid-2-tid-1-fpage-0-goto-next.html',
      ),
      rssFeed: const ThreadActionLink(
        label: 'Rss订阅本帖最新内容',
        url: 'https://south-plus.net/rss.php?tid=1',
      ),
    );
  }

  @override
  Future<String?> fetchQuoteDraft(ThreadReply reply) async {
    requestedQuoteUrls.add(reply.quoteUrl!);
    return '[quote]server quote from ${reply.author}[/quote]';
  }
}
