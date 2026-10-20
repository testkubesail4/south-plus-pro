import 'package:flutter/foundation.dart';
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
    _Repository? repository,
    Size size = const Size(400, 800),
    double keyboard = 0,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    repository ??= _Repository();
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
    await tester.tap(find.byKey(const ValueKey('page-end-next')));
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

    expect(find.byKey(const ValueKey('page-end-next')), findsNothing);
    expect(find.text('加载第 2 页'), findsOneWidget);

    // Turning it off in 设置 restores explicit paging on the open thread.
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.manual);
    await tester.pumpAndSettle();
    await jumpToEnd(tester);
    expect(find.byKey(const ValueKey('page-end-next')), findsOneWidget);
    expect(find.text('加载第 2 页'), findsNothing);
  });

  testWidgets('the last page ends with 已到最后一页 and a refresh', (tester) async {
    final repository = _Repository()..totalPages = 1;
    await pumpThread(tester, repository: repository);
    await jumpToEnd(tester);
    expect(find.text('已到最后一页'), findsOneWidget);
    expect(find.byKey(const ValueKey('page-end-next')), findsNothing);

    await tester.tap(find.text('刷新本页，看看新回复'));
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 1]);
  });

  testWidgets('自动接续 pauses after two pages of repeated floors', (tester) async {
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.continuous);
    final repository = _Repository()
      ..totalPages = 5
      ..repeats = true;
    await pumpThread(tester, repository: repository);
    // Only the reader's own scrolling follows on.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    await jumpToEnd(tester);

    expect(repository.pages, [1, 2, 3]);
    // Repeated floors show once.
    expect(find.text('reply 30', findRichText: true), findsOneWidget);
    expect(find.text('后续页面的内容已被过滤或重复'), findsOneWidget);
    // A tap starts a fresh run: page 4 repeats too, so 5 follows on.
    await tester.tap(find.text('继续加载第 4 页'));
    await tester.pumpAndSettle();
    expect(repository.pages, [1, 2, 3, 4, 5]);
    expect(find.text('已到最后一页'), findsOneWidget);
  });

  testWidgets('empty pages stop following on even as the page count grows',
      (tester) async {
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.continuous);
    final repository = _Repository()..emptyGrowing = true;
    await pumpThread(tester, repository: repository);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    await jumpToEnd(tester);
    await tester.pump(const Duration(seconds: 5));

    // One scroll, then at most two pages that add nothing.
    expect(repository.pages, [1, 2, 3]);
    expect(find.text('继续加载第 4 页'), findsOneWidget);
  });

  testWidgets('floors without a site id are kept, never taken for repeats',
      (tester) async {
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.continuous);
    // Many pages still to come: only the reader's scrolling asks for them.
    final repository = _Repository()
      ..totalPages = 50
      ..repeats = true
      ..unnumbered = true;
    await pumpThread(tester, repository: repository);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
    await tester.pumpAndSettle();
    await jumpToEnd(tester);
    await tester.pump(const Duration(seconds: 5));

    expect(repository.pages, [1, 2]);
    // Same author and time as page 1's floors, yet page 2's rows stay.
    expect(find.text('again 30', findRichText: true), findsOneWidget);
    expect(find.text('已到最后一页'), findsNothing);

    // Scrolling on asks for more, and only while it lasts.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final asked = repository.pages.length;
    expect(asked, greaterThan(2));
    await tester.pump(const Duration(seconds: 5));
    expect(repository.pages.length, asked);
  });

  testWidgets('another session drops the pages and the draft in one frame',
      (tester) async {
    final repository =
        await pumpThread(tester, repository: _Repository()..viewer = 'A ');
    expect(find.text('A reply 1', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('写回复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'A unsent draft');

    repository.epoch.value++;
    repository.viewer = 'B ';
    await tester.pump();
    expect(find.textContaining('A ', findRichText: true, skipOffstage: false),
        findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('B reply 1', findRichText: true), findsOneWidget);
    expect(find.textContaining('A ', findRichText: true, skipOffstage: false),
        findsNothing);
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
  int totalPages = 3;
  // Every later page repeats page 1's floors, as when the thread moved.
  bool repeats = false;
  // Later pages carry no post id: nothing proves a repeat.
  bool unnumbered = false;
  // Later pages come back empty while the site keeps reporting one more.
  bool emptyGrowing = false;

  // Whose view of the thread the site answers with.
  final epoch = ValueNotifier<int>(0);
  var viewer = '';

  @override
  ValueListenable<int> get sessionEpoch => epoch;
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
    final sentAs = viewer;
    final first = repeats ? 0 : (page - 1) * 30;
    return ThreadDetail(
      thread: _thread,
      body: page == 1 ? 'opening body' : '',
      pagination: ThreadPagination(
          currentPage: page, totalPages: emptyGrowing ? page + 1 : totalPages),
      replies: [
        if (!emptyGrowing || page == 1)
          for (var floor = first + 1; floor <= first + 30; floor++)
            ThreadReply(
              author: 'user$floor',
              content:
                  '$sentAs${unnumbered && page > 1 ? 'again' : 'reply'} $floor',
              floor: 'B${floor}F',
              postId: unnumbered && page > 1 ? null : '${9000 + floor}',
              postedAt: '2026-01-01 12:00',
              replyTitle: '回 $floor楼(user$floor) 的帖子',
            ),
      ],
    );
  }
}
