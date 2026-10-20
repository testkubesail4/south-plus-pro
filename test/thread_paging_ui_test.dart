import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/reply/reply_sheet.dart';
import 'package:south_plus_rewrite/features/thread/thread_detail_screen.dart';
import 'package:south_plus_rewrite/features/thread/thread_floor_actions.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic fixtures only: fictional host, tid and authors.
const _url = 'https://south-plus.net/read.php?tid-7.html';
const _thread =
    ForumThread(title: 'paging', url: _url, replies: 0, section: '');

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LoadingPreferences.load();
  });

  Future<_Repository> pumpThread(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    double keyboard = 0,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    final repository = _Repository();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ThreadDetailScreen(repository: repository, thread: _thread),
    ));
    await tester.pumpAndSettle();
    return repository;
  }

  ScrollPosition list(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  bool composerShown(WidgetTester tester) =>
      find.byType(ReplyComposer).hitTestable().evaluate().isNotEmpty;

  Future<void> jumpToEnd(WidgetTester tester) async {
    final position = list(tester);
    for (var i = 0; i < 20 && position.pixels < position.maxScrollExtent; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
  }

  for (final (mode, theme, palette) in [
    (ThemeMode.light, AppTheme.light, AppColors.lightPalette),
    (ThemeMode.dark, AppTheme.dark, AppColors.darkPalette),
  ]) {
    testWidgets('the 写回复 button takes the brand pair ($mode)', (tester) async {
      AppThemeController.notifier.value = mode;
      addTearDown(() => AppThemeController.notifier.value = ThemeMode.system);
      await pumpThread(tester, theme: theme);
      final fab = find.byTooltip('写回复');
      final fill = tester
          .widget<Material>(
              find.descendant(of: fab, matching: find.byType(Material)).first)
          .color;
      final icon = IconTheme.of(tester.element(find.descendant(
        of: fab,
        matching: find.byIcon(Icons.edit_outlined),
      ))).color;
      expect((fill, icon), (palette.brand, palette.onBrand));
    });
  }

  testWidgets('the page-end 下一页 turns to the next page at its top',
      (tester) async {
    final repository = await pumpThread(tester);
    await jumpToEnd(tester);
    await tester.tap(find.byKey(const ValueKey('thread-next-page')));
    await tester.pumpAndSettle();

    expect(repository.pages, [1, 2]);
    expect(list(tester).pixels, 0);
    expect(find.text('第 2 / 3 页'), findsOneWidget);
    expect(find.text('reply 31', findRichText: true), findsOneWidget);
    expect(find.text('reply 1', findRichText: true), findsNothing);
  });

  testWidgets('with 自动接续 on, the end offers loading more instead',
      (tester) async {
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.continuous);
    await pumpThread(tester);
    await jumpToEnd(tester);

    expect(find.byKey(const ValueKey('thread-next-page')), findsNothing);
    expect(find.text('加载第 2 页'), findsOneWidget);

    // Turning it off in 设置 restores explicit paging on the open thread.
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.manual);
    await tester.pumpAndSettle();
    await jumpToEnd(tester);
    expect(find.byKey(const ValueKey('thread-next-page')), findsOneWidget);
    expect(find.text('加载第 2 页'), findsNothing);
  });

  testWidgets('the page picker opens the chosen page', (tester) async {
    final repository = await pumpThread(tester);
    await tester.tap(find.byTooltip('跳转'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(repository.pages, [1, 3]);
    expect(find.text('第 3 / 3 页'), findsOneWidget);
  });

  testWidgets('a floor 回复 keeps the draft and docks without moving reading',
      (tester) async {
    await pumpThread(tester);
    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'existing body');
    await tester.tap(find.byTooltip('收起回复框'));
    await tester.pumpAndSettle();
    final footer = find.ancestor(
      of: find.byKey(const ValueKey('floor-actions-user1-B1F')),
      matching: find.byType(ThreadFloorFooter),
    );
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    final before = list(tester).pixels;
    expect(before, greaterThan(0));
    expect(composerShown(tester), isFalse);

    await tester.tap(find.descendant(
        of: footer, matching: find.byIcon(Icons.reply_outlined)));
    await tester.pumpAndSettle();

    expect(composerShown(tester), isTrue);
    expect(list(tester).pixels, before);
    // The site's own subject changes without replacing the draft body.
    expect(find.text('回 1楼(user1) 的帖子'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'existing body');
  });

  testWidgets('folding the composer keeps its draft; back folds it first',
      (tester) async {
    await pumpThread(tester);
    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'draft text');

    await tester.tap(find.byTooltip('收起回复框'));
    await tester.pumpAndSettle();
    expect(composerShown(tester), isFalse);

    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();
    expect(find.text('draft text'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(composerShown(tester), isFalse);
    expect(find.byType(ThreadDetailScreen), findsOneWidget);
  });

  testWidgets('on a wide window the dock shares the posts\' reading width',
      (tester) async {
    await pumpThread(tester, size: const Size(1440, 900));
    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();

    final dock = tester.getRect(find
        .ancestor(
            of: find.byType(ReplyComposer), matching: find.byType(Material))
        .first);
    final post = tester.getRect(find.byType(Card).first);
    expect(dock.left, post.left);
    expect(dock.right, post.right);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
        'the dock fits a short landscape window with the keyboard up '
        '(text x$textScale)', (tester) async {
      await pumpThread(
        tester,
        size: const Size(900, 360),
        keyboard: 250,
        textScale: textScale,
      );
      await tester.tap(find.byTooltip('写回复'));
      await tester.pumpAndSettle();

      // An overflow would have failed the test as a reported exception.
      expect(find.byType(ReplyComposer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a sent floor reply leaves the next reply generic',
      (tester) async {
    final repository = await pumpThread(tester);
    final footer = find.ancestor(
      of: find.byKey(const ValueKey('floor-actions-user1-B1F')),
      matching: find.byType(ThreadFloorFooter),
    );
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: footer, matching: find.byIcon(Icons.reply_outlined)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'to floor one');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reply-submit-button')));
    await tester.pumpAndSettle();
    expect(repository.sentTitles, ['回 1楼(user1) 的帖子']);
    expect(composerShown(tester), isFalse);

    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();
    expect(find.text('Re:paging'), findsOneWidget);
    expect(find.text('回 1楼(user1) 的帖子'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
  });
}

class _Repository extends ForumRepository {
  final pages = <int>[];
  final sentTitles = <String>[];

  @override
  Future<ReplyResult> submitReply({
    required ForumThread thread,
    required String title,
    required String content,
  }) async {
    sentTitles.add(title);
    return const ReplyResult(success: true, message: '回复成功');
  }

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
    pages.add(page);
    final first = (page - 1) * 30;
    return ThreadDetail(
      thread: _thread,
      body: page == 1 ? 'opening body' : '',
      pagination: ThreadPagination(currentPage: page, totalPages: 3),
      replies: [
        for (var floor = first + 1; floor <= first + 30; floor++)
          ThreadReply(
            author: 'user$floor',
            content: 'reply $floor',
            floor: 'B${floor}F',
            replyTitle: '回 $floor楼(user$floor) 的帖子',
          ),
      ],
    );
  }
}
