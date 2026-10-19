import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_preferences_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_tasks_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_sale_box_view.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// The existing Linux fixture harness, never a real forum or session.
class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

const _config = ForumNetworkConfig(
  site: _FixtureSite(),
  dohEnabled: false,
  dohProvider: ForumNetworkConfig.defaultProvider,
);
const _pinnedTitle = '置顶阅读指南：本地收藏、用户备注与长标题换行的完整阅读示例';
const _signature = '认真阅读每一段文字，记录值得回看的讨论，只在本机保存备注，不向论坛公开个人笔记。';
const _profileUrl = 'http://127.0.0.1:8765/u.php?action-show-uid-930002.html';
const _paidThread = ForumThread(
  title: '付费阅读示例',
  url: 'http://127.0.0.1:8765/read.php?tid-930001.html',
  replies: 0,
  section: '本地阅读版块',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ForumRepository repository;
  var scale = 1.0;
  var reducedMotion = false;
  final frames = <String>[];

  Future<List<int>> fixture(String path, {bool reset = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = _config.baseUri.resolve(path);
      expect(uri.host, '127.0.0.1');
      final request = await client.openUrl(reset ? 'POST' : 'GET', uri);
      if (reset) {
        final body = utf8.encode('fixture-only');
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      expect(response.statusCode, 200);
      return await response
          .fold<List<int>>([], (all, bytes) => all..addAll(bytes));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> stats() async =>
      jsonDecode(utf8.decode(await fixture('appendfix/stats')))
          as Map<String, dynamic>;

  Future<ForumRepository> restore() async {
    final repo = ForumRepository(config: _config);
    expect(await repo.restoreSession(), isTrue);
    expect(repo.accountIdentity.value?.uid, '930001');
    return repo;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });
    await fixture('appendfix/reset', reset: true);
    await ForumSessionStore().saveCookies({
      'appendfix_winduser': ForumStoredCookie.session(
        name: 'appendfix_winduser',
        value: 'synthetic-local-only',
        origin: _config.baseUri,
      ),
    });
    await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
    await AppThemeController.setMode(ThemeMode.light);
    scale = 1;
    reducedMotion = false;
    repository = await restore();
  });

  Widget app(Widget home) => ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.notifier,
        builder: (context, mode, _) => MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion,
            ),
            child: child!,
          ),
          home: home,
        ),
      );

  Future<String> window(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      await tester.pump();
      final result = await Process.run('xdotool',
          ['search', '--onlyvisible', '--name', r'^south_plus_rewrite$']);
      final ids = '${result.stdout}'.trim();
      if (result.exitCode == 0 && ids.isNotEmpty) return ids.split('\n').first;
      expect(DateTime.now().isBefore(deadline), isTrue,
          reason: 'Native window did not become visible within 15s '
              '(xdotool exit ${result.exitCode}): ${result.stderr}');
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    final result = await Process.run('xdotool', [
      'windowsize',
      await window(tester),
      '${size.width.toInt()}',
      '${size.height.toInt()}',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: name);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final path = '/output/$name.png';
    final result =
        await Process.run('import', ['-window', await window(tester), path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File(path).lengthSync(), greaterThan(1000));
    frames.add(path);
    File('/output/appendfix-frames.json').writeAsStringSync(jsonEncode({
      'scope': 'Synthetic loopback Linux native app; no live forum writes',
      'accountSave': 'Unknown fixture ACK; confirmed by form GET readback',
      'avatar':
          'Existing constructor picker injection; preview only, no upload',
      'frames': frames,
    }));
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (finder.evaluate().isEmpty) {
      await screenshot(tester, 'appendfix_failure');
    }
    expect(finder, findsWidgets);
  }

  /// Scrolls [finder] into the window and waits until its centre is inside
  /// the view and hit-testable. ensureVisible only moves the scroll position;
  /// the native build needs frames before the widget is laid out there, so a
  /// tap straight after it can land outside the window.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final target = finder.first;
    final view = tester.view;
    final size = view.physicalSize / view.devicePixelRatio;
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 100));
      final center = tester.getCenter(target);
      final inside = center.dx > 0 &&
          center.dx < size.width &&
          center.dy > 0 &&
          center.dy < size.height;
      if (inside && target.hitTestable().evaluate().isNotEmpty) return;
    }
    fail('$finder stayed outside the $size window at '
        '${tester.getCenter(target)}');
  }

  Future<void> readyToTap(WidgetTester tester, Finder finder) async {
    await tester.pump();
    await waitFor(tester, finder);
    await reveal(tester, finder);
    final target = finder.first;
    expect(target.hitTestable(), findsOneWidget,
        reason: '$finder must be hit-testable before tapping');
    final widget = tester.widget(target);
    final buttons = <ButtonStyleButton>[
      if (widget is ButtonStyleButton) widget,
      for (final element in find
          .ancestor(
              of: target,
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
          .evaluate())
        element.widget as ButtonStyleButton,
    ];
    for (final button in buttons) {
      expect(button.onPressed, isNotNull,
          reason: '$finder must be enabled before tapping');
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await readyToTap(tester, finder);
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(home));
  }

  Future<void> darkLarge(WidgetTester tester) async {
    scale = 2;
    reducedMotion = true;
    await AppThemeController.setMode(ThemeMode.dark);
    await resize(tester, const Size(400, 800));
  }

  testWidgets(
      'native home preferences survive remount and board appends page 2',
      (tester) async {
    // GTK maps the window only after Flutter presents its first frame.
    await mount(tester, HomeShell(repository: repository));
    await resize(tester, const Size(400, 800));
    await waitFor(tester, find.text('付费阅读示例'));
    await tester.pumpAndSettle();
    expect(MediaQuery.sizeOf(tester.element(find.byType(HomeShell))),
        const Size(400, 800));

    for (final rows in [3, 8]) {
      await tap(tester, find.byTooltip('速览设置'));
      await tap(tester, find.text('显示行数'));
      await tap(tester, find.text('$rows 行'));
      await tap(tester, find.byType(BackButton));
      expect(
          (await HomeReadingPreferences.load(
                  account: repository.localPreferenceAccount))
              .quickRowCount,
          rows);
      expect(find.text('本地讨论 1.3'), findsOneWidget);
      expect(find.text('本地讨论 1.8'), rows == 8 ? findsOneWidget : findsNothing);
    }

    final homeScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('阅读分区 1'), 250,
        scrollable: homeScroll);
    await tap(tester, find.text('阅读分区 1'));
    expect(
        find.byKey(const ValueKey('home-grid-0')).hitTestable(), findsNothing);
    await tester.scrollUntilVisible(find.text('添加常用版块'), -200,
        scrollable: homeScroll);
    await tap(tester, find.text('添加常用版块'));
    await tap(tester, find.byKey(const ValueKey('board-row:g0')));
    await tap(tester, find.byKey(const ValueKey('board-add:0/0')));
    await waitFor(tester, find.byTooltip('移除 本地阅读版块'));
    await tap(tester, find.text('完成'));

    // New screens and repository read the settings written through the UI.
    await tester.pumpWidget(const SizedBox.shrink());
    repository = await restore();
    await mount(tester, HomeShell(repository: repository));
    await waitFor(tester, find.text('付费阅读示例'));
    await tester.pumpAndSettle();
    expect(find.text('本地讨论 1.8'), findsOneWidget);
    final stored = await HomeReadingPreferences.load(
        account: repository.localPreferenceAccount);
    expect(stored.collapsedIds, contains('section:阅读分区 1'));
    await tester.scrollUntilVisible(find.text('阅读分区 1'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('home-grid-0')).hitTestable(), findsNothing);

    await darkLarge(tester);
    await mount(tester, HomeShell(repository: repository));
    await waitFor(tester, find.text('本地讨论 1.8'));
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    await screenshot(tester, 'flow1_phone-dark2-reduced_rows8');
    await tester.scrollUntilVisible(
        find.widgetWithText(ActionChip, '本地阅读版块'), 250,
        scrollable: find.byType(Scrollable).first);
    await tap(tester, find.widgetWithText(ActionChip, '本地阅读版块'));
    await waitFor(tester, find.text(_pinnedTitle));
    await tester.pumpAndSettle();
    expect(find.byType(BoardThreadListScreen), findsOneWidget);
    await reveal(tester, find.text(_pinnedTitle));
    await screenshot(tester, 'flow1_phone-dark2-reduced_pinned-title');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await waitFor(tester, find.text('第 2 页'));
    await tester.scrollUntilVisible(find.text('第 2 页讨论 9'), 450,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first,
        maxScrolls: 20);
    await waitFor(tester, find.text('已到最后一页'));
    expect((await stats())['board_pages'], containsAllInOrder([1, 2]));

    scale = 1;
    reducedMotion = false;
    await AppThemeController.setMode(ThemeMode.light);
    await tester.pumpWidget(const SizedBox.shrink());
    await resize(tester, const Size(1100, 800));
    await mount(tester, HomeShell(repository: repository));
    await waitFor(tester, find.text('本地讨论 1.8'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    await screenshot(tester, 'flow1_wide-light_home-persisted');
    expect((await stats())['writes'], isEmpty);
    expect((await stats())['purchases'], 0);
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets(
      'native profile note and bounded filters lead to rich paid reveal',
      (tester) async {
    await mount(tester,
        UserProfileScreen(userUrl: _profileUrl, repository: repository));
    await resize(tester, const Size(400, 800));
    await tap(tester, find.text('添加备注'));
    expect(find.textContaining('仅本机'), findsWidgets);
    expect(find.textContaining('930002'), findsWidgets);
    expect(find.textContaining('原名：林间书签'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '常读作者');
    await tester.pump();
    await screenshot(tester, 'flow2_phone-light_local-note-editor');
    await tap(tester, find.text('保存'));
    await waitFor(tester, find.text('备注：常读作者'));
    await tap(tester, find.text('主题'));
    await waitFor(tester, find.text('本地阅读笔记'));
    await tap(tester, find.text('版块：全部'));
    await tap(tester, find.text('本地阅读版块'));
    await waitFor(tester, find.text('版块：本地阅读版块'));
    await tap(tester, find.text('分类：全部'));
    await tap(tester, find.text('阅读笔记'));
    await waitFor(tester, find.text('待确认 (1)'));
    await tap(tester, find.text('待确认 (1)'));
    await waitFor(tester, find.text('尚未确认分类的阅读记录'));
    await tester.ensureVisible(find.text('尚未确认分类的阅读记录'));
    await tester.pumpAndSettle();
    expect(find.text('本地阅读笔记'), findsOneWidget);
    expect(find.text('没有符合条件的内容'), findsNothing);
    expect(find.text('搜索范围：已加载内容'), findsOneWidget);
    expect(find.text('在已加载的 1 页中找到 1 条 · 待确认 1 条'), findsOneWidget);
    await screenshot(tester, 'flow2_phone-light_filtered-unknown-visible');

    await darkLarge(tester);
    await mount(tester,
        ThreadDetailScreen(repository: repository, thread: _paidThread));
    await waitFor(tester, find.textContaining('常读作者', findRichText: true));
    await waitFor(tester, find.text(_signature));
    expect(find.textContaining('2026-01-03 09:20'), findsWidgets);
    await tester.pumpAndSettle();
    await screenshot(tester, 'flow2_phone-dark2-reduced_long-signature');
    final box = find.byType(ThreadSaleBoxView);
    final buyButton = find.text('购买查看');
    await readyToTap(tester, buyButton);
    final beforeY = tester.getTopLeft(box).dy;
    await tester.tap(buyButton);
    final revealed = find.textContaining('已解锁的阅读笔记', findRichText: true);
    await waitFor(tester, revealed);
    final reveal = find.byType(ThreadPurchaseReveal);
    expect(reveal, findsOneWidget);
    expect(MediaQuery.disableAnimationsOf(tester.element(reveal)), isTrue);
    final paidHeaderText =
        find.textContaining('此帖售价 1 SP币,已有 4 人购买', findRichText: true);
    final paidHeaderCard = find
        .ancestor(of: paidHeaderText, matching: find.byType(Container))
        .first;
    final firstTop = tester.getTopLeft(paidHeaderCard).dy;
    expect(firstTop, closeTo(beforeY, 14),
        reason:
            'native header card replaces the box at the same screen position');
    // Render the app's end-of-frame scroll-anchor correction before measuring drift.
    await tester.pump();
    expect(tester.getTopLeft(paidHeaderCard).dy, closeTo(beforeY, 14));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(paidHeaderCard).dy;
    expect(top, closeTo(beforeY, 14));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(paidHeaderCard).dy, closeTo(top, 1));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(paidHeaderCard).dy, closeTo(top, 1));
    for (final text in [
      '嵌套引用仍可阅读',
      '清单里的第一条笔记',
      'local_example = 42',
      '表格里的阅读记录',
      '继续阅读本地主题',
    ]) {
      expect(find.textContaining(text, findRichText: true), findsWidgets);
    }
    expect(find.text('购买查看'), findsNothing);
    expect((await stats())['purchases'], 1);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(paidHeaderCard).dy, closeTo(top, 1));
    await tester.ensureVisible(
        find.textContaining('local_example = 42', findRichText: true));
    await tester.pumpAndSettle();
    await screenshot(tester, 'flow2_phone-dark2-reduced_paid-nested-reveal');
    await tap(tester, find.textContaining('继续阅读本地主题', findRichText: true));
    await waitFor(tester, find.textContaining('普通主题正文', findRichText: true));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('购买查看'), findsNothing);
    expect((await stats())['purchases'], 1);
    expect((await stats())['writes'], isEmpty,
        reason: 'notes and filters never submit account/forum writes');
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets(
      'native forms save locally by readback, avatar previews, tasks read only',
      (tester) async {
    await mount(tester, ForumPreferencesScreen(repository: repository));
    await resize(tester, const Size(400, 800));
    await waitFor(tester, find.text('屏蔽用户组'));
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNull);
    final blacklist = find.byType(TextField);
    await tester.ensureVisible(blacklist);
    await tester.enterText(blacklist, '930003, 930004');
    await tester.pump();
    await screenshot(tester, 'flow3_phone-light_preferences-dirty');
    await tap(tester, find.widgetWithText(TextButton, '保存'));
    await waitFor(tester, find.text('已保存'));
    final savedPrefs = await repository.fetchForumPreferences();
    expect(savedPrefs.field('banidinfo')!.value, '930003, 930004');
    expect(savedPrefs.field('msggroups[]')!.values, ['6', '7']);
    expect((await stats())['writes'], ['bbsset']);

    final bytes = await fixture('fixture.png');
    await mount(
        tester,
        AccountProfileEditScreen(
          repository: repository,
          avatarPicker: () async => ForumAccountUpload(
            bytes: Uint8List.fromList(bytes),
            fileName: 'local-avatar.png',
            mimeType: 'image/png',
          ),
        ));
    await waitFor(tester, find.text('头像类型'));
    await tap(tester, find.text('头像类型'));
    await tap(tester, find.text('上传头像').last);
    // Picker injection plus the real crop; not proof of the OS chooser or upload.
    await tap(tester, find.text('选择图片'));
    await waitFor(tester, find.byKey(const Key('avatar-crop-confirm')));
    await tap(tester, find.byKey(const Key('avatar-crop-confirm')));
    expect(
        find.byWidgetPredicate((w) => w is Image && w.semanticLabel == '新头像预览'),
        findsOneWidget);
    expect(find.textContaining('avatar.png'), findsOneWidget);
    await screenshot(tester, 'flow3_phone-light_avatar-preview-only');
    // Discard the preview instead of fabricating an unobserved upload callback.
    await mount(tester, AccountProfileEditScreen(repository: repository));
    await waitFor(tester, find.text('头像类型'));
    final nickname = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '本地读者');
    await tester.ensureVisible(nickname);
    await tester.enterText(nickname, '林间读者');
    await tester.pump();
    await tap(tester, find.widgetWithText(TextButton, '保存'));
    await waitFor(tester, find.text('已保存'));
    final savedProfile = await repository.fetchAccountProfileForm();
    expect(savedProfile.field('field_1')!.value, '林间读者');
    expect((await stats())['writes'], ['bbsset', 'modify']);

    await tester.pumpWidget(const SizedBox.shrink());
    await resize(tester, const Size(1100, 800));
    await mount(tester, ForumTasksScreen(repository: repository));
    await tap(tester, find.text('新任务'));
    await waitFor(tester, find.text('每日阅读奖励'));
    await tester.pumpAndSettle();
    expect(find.text('已领取'), findsOneWidget);
    expect(find.text('上次领取未超过 24 小时'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget);
    await screenshot(tester, 'flow3_wide-light_claimed-and-unknown-tasks');
    expect((await stats())['writes'], ['bbsset', 'modify']);
    expect((await stats())['purchases'], 0);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
