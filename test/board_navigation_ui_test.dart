import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/board/board_thread_list_screen.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Synthetic boards, topics and names only.
String _url(int fid) => 'https://south-plus.net/thread.php?fid-$fid.html';

const _hub = ForumCategory(name: 'Hub', slug: 'fid-900');

final _children = [
  ForumBoard(
    name: 'Child A',
    url: _url(901),
    section: 'Hub',
    postCount: 290511,
    lastPostTime: '2020-03-19 13:25',
  ),
  ForumBoard(name: 'Child B', url: _url(902), section: 'Hub', postCount: 8421),
];

ForumThread _topic(String title, {bool sticky = false}) => ForumThread(
      title: title,
      url: 'https://south-plus.net/read.php?tid-1.html',
      replies: 3,
      section: '',
      isSticky: sticky,
    );

ForumBoardFilter _filter(String label, ForumBoardFilterKind kind, String url) =>
    ForumBoardFilter(label: label, url: url, kind: kind);

final _all = _filter('全部', ForumBoardFilterKind.all, 'thread.php?fid-901.html');
final _digest = _filter(
    '精华', ForumBoardFilterKind.digest, 'thread.php?fid-901-search-digest.html');
final _type = _filter('Type one', ForumBoardFilterKind.topicType,
    'thread.php?fid-901-type-1.html');
final _vote = _filter(
    '投票', ForumBoardFilterKind.special, 'thread.php?fid-901-special-1.html');
final _week = _filter(
    '1星期内的主题', ForumBoardFilterKind.range, 'thread.php?fid-901-search-7.html');
final _digestRange = _filter('本版精华区', ForumBoardFilterKind.digest, _digest.url);

class _Repo extends ForumRepository {
  final requests = <(String, int, ForumBoardFilter?)>[];
  final orders = <ForumThreadOrder>[];
  ForumBoardFilter? deepLinkFilter;

  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async {
    requests.add((category.slug, page, filter));
    orders.add(order);
    if (category.slug == _hub.slug) {
      return ForumThreadPage(
        threads: [_topic('Hub notice', sticky: true)],
        currentPage: 1,
        totalPages: 1,
        subBoards: _children,
        boardName: 'Hub',
      );
    }
    final name =
        _children.firstWhere((board) => board.slug == category.slug).name;
    return ForumThreadPage(
      threads: [
        _topic('$name pinned', sticky: true),
        _topic('$name topic 1'),
        _topic('$name topic 2').copyWith(
            authorUrl:
                'https://south-plus.net/u.php?action-show-uid-1002.html'),
      ],
      currentPage: page,
      totalPages: 3,
      boardName: name,
      filters: [_all, _digest, _type, _vote],
      activeFilter: filter ?? deepLinkFilter ?? _all,
      rangeFilters: name == 'Child A' ? [_digestRange, _week] : const [],
      hasPictureWall: name == 'Child A',
      parents: const [_hub],
    );
  }
}

class _LongRepo extends _Repo {
  @override
  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async =>
      ForumThreadPage(
        threads: [
          for (var i = 0; i < 14; i++)
            _topic('Long topic $i').copyWith(
                url:
                    'https://south-plus.net/read.php?tid-${page * 100 + i}.html'),
        ],
        currentPage: page,
        totalPages: 3,
        boardName: 'Child A',
      );
}

Future<void> _pump(WidgetTester tester, Widget home, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, String label) =>
    containsSemantics(isSelected: true)
        .matches(tester.getSemantics(find.text(label).last), {});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a hub lists its sub-boards as tiles that open their own page',
      (tester) async {
    final repo = _Repo();
    await _pump(
        tester, BoardThreadListScreen(category: _hub, repository: repo));

    expect(find.text('子版块'), findsOneWidget);
    expect(find.text('29.1万 帖 · 2020-03-19'), findsOneWidget);
    expect(find.text('8,421 帖'), findsOneWidget);

    await tester.tap(find.text('Child A'));
    await tester.pumpAndSettle();
    expect(find.text('Child A topic 1'), findsOneWidget);
    expect(find.text('Hub'), findsOneWidget, reason: 'parent named above');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('子版块'), findsOneWidget, reason: 'back is the hub');
    expect(repo.requests.map((r) => r.$1), ['fid-900', 'fid-901']);
  });

  testWidgets('the title switches to a sibling and back still reaches the hub',
      (tester) async {
    final repo = _Repo();
    await _pump(
        tester, BoardThreadListScreen(category: _hub, repository: repo));
    await tester.tap(find.text('Child A'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Child A').first);
    await tester.pumpAndSettle();
    expect(find.text('返回上级版块'), findsOneWidget);
    await tester.tap(find.text('Child B').last);
    await tester.pumpAndSettle();
    expect(find.text('Child B topic 1'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('子版块'), findsOneWidget);
  });

  testWidgets('wide windows keep the sibling list beside the topics',
      (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
        repository: repo,
        parent: _hub,
        siblings: _children,
      ),
      size: const Size(1440, 900),
    );
    expect(find.text('返回上级版块'), findsOneWidget);
    expect(find.text('Child B'), findsOneWidget);

    await tester.tap(find.text('Child B'));
    await tester.pumpAndSettle();
    expect(find.text('Child B topic 1'), findsOneWidget);
  });

  for (final size in const [Size(400, 800), Size(1440, 900)]) {
    testWidgets(
        'at ${size.width.toInt()} px topics keep the list width and the '
        'pager ends clear of the 发帖 button', (tester) async {
      await _pump(
        tester,
        BoardThreadListScreen(
          category:
              ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
          repository: _LongRepo(),
        ),
        size: size,
      );
      final row = tester.getRect(find.ancestor(
          of: find.text('Long topic 0'),
          matching: find.byType(ForumThreadRow)));
      expect(row.width, size.width < 600 ? size.width - 32 : AppWidths.list);
      expect(row.center.dx, size.width / 2);

      // Each time the end is reached the next page is appended, so the
      // pager reads the last page once all three are in.
      await tester.scrollUntilVisible(find.text('第 3 / 3 页'), 600,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final pager = tester.getRect(find.text('第 3 / 3 页'));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(pager.bottom, lessThan(fab.top), reason: '$pager vs $fab');
    });
  }

  testWidgets('a filter tab refetches page one with that filter',
      (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
        repository: repo,
      ),
    );
    expect(_selected(tester, '全部'), isTrue);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();
    expect(repo.requests.last, ('fid-901', 1, _digest));
    expect(_selected(tester, '精华'), isTrue);
    expect(_selected(tester, '全部'), isFalse);

    // 全部 is passed explicitly so a deep link's own filter is cleared too.
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(repo.requests.last, ('fid-901', 1, _all));
    expect(repo.requests.length, 4);
  });

  testWidgets('the native time range combines with sort and tabs',
      (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
        repository: repo,
      ),
    );
    final range = find.byKey(const ValueKey('board-range-button'));
    expect(find.descendant(of: range, matching: find.text('全部时间')),
        findsOneWidget);

    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    await tester.tap(range);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1星期内的主题'));
    await tester.pumpAndSettle();
    expect(repo.requests.last, ('fid-901', 1, _week));
    expect(find.descendant(of: range, matching: find.text('1星期内')),
        findsOneWidget);
    expect(_selected(tester, '全部'), isFalse);

    // Sort keeps the range, as the site's next-page links do.
    await tester.tap(find.byKey(const ValueKey('board-order-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人气'));
    await tester.pumpAndSettle();
    expect(repo.requests.last, ('fid-901', 1, _week));
    expect(repo.orders.last, ForumThreadOrder.hits);

    // 本版精华区 is the 精华 tab.
    await tester.tap(range);
    await tester.pumpAndSettle();
    await tester.tap(find.text('本版精华区'));
    await tester.pumpAndSettle();
    expect(repo.requests.last.$3?.url, _digest.url);
    expect(_selected(tester, '精华'), isTrue);

    await tester.tap(range);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部时间').last);
    await tester.pumpAndSettle();
    expect(repo.requests.last, ('fid-901', 1, _all));
    expect(repo.orders.last, ForumThreadOrder.hits);
    expect(_selected(tester, '全部'), isTrue);
  });

  testWidgets('a deep-linked range shows on the range button', (tester) async {
    final repo = _Repo()..deepLinkFilter = _week;
    await _pump(
      tester,
      BoardThreadListScreen(
        category: const ForumCategory(
          name: '',
          slug: 'fid-901',
          url: 'https://south-plus.net/thread.php?fid-901-search-7.html',
        ),
        repository: repo,
      ),
    );
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('board-range-button')),
            matching: find.text('1星期内')),
        findsOneWidget);
  });

  testWidgets('boards without the native range select have no range button',
      (tester) async {
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child B', slug: 'fid-902', url: _url(902)),
        repository: _Repo(),
      ),
    );
    expect(find.byKey(const ValueKey('board-range-button')), findsNothing);
  });

  testWidgets('the pager picks any page from the shared page sheet',
      (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
        repository: repo,
      ),
    );
    await tester.ensureVisible(find.text('第 1 / 3 页'));
    await tester.tap(find.text('第 1 / 3 页'));
    await tester.pumpAndSettle();
    expect(find.text('选择页码'), findsOneWidget);
    await tester.tap(find.text('3').last);
    await tester.pumpAndSettle();
    expect(repo.requests.last.$2, 3);
    expect(find.text('第 3 / 3 页'), findsOneWidget);
  });

  testWidgets('a deep-linked filter shows as the selected tab', (tester) async {
    final repo = _Repo()..deepLinkFilter = _type;
    await _pump(
      tester,
      BoardThreadListScreen(
        category: const ForumCategory(
          name: '',
          slug: 'fid-901',
          url: 'https://south-plus.net/thread.php?fid-901-type-1.html',
        ),
        repository: repo,
      ),
    );
    expect(_selected(tester, 'Type one'), isTrue);
    expect(_selected(tester, '全部'), isFalse);
  });

  testWidgets('the picture wall shows the same page as cards', (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
        repository: repo,
      ),
    );
    await tester.tap(find.text('精华'));
    await tester.pumpAndSettle();
    final requests = repo.requests.length;

    await tester.tap(find.byTooltip('图墙'));
    await tester.pumpAndSettle();
    expect(find.text('Child A topic 1'), findsOneWidget);
    expect(find.text('Child A pinned'), findsOneWidget);
    expect(find.byTooltip('列表'), findsOneWidget);
    expect(_selected(tester, '精华'), isTrue);
    expect(repo.requests.length, requests, reason: 'same data, no refetch');

    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('图墙'), findsOneWidget);
  });

  testWidgets('a blocked author leaves the list and the wall at once',
      (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child A', slug: 'fid-901', url: _url(901)),
        repository: repo,
      ),
    );
    expect(find.text('Child A topic 2'), findsOneWidget);

    repo.blocking.notifier.value = const BlockingRules(users: [
      BlockedUser(
          uid: '1002', name: 'B', userBlocked: true, avatarBlocked: false),
    ]);
    await tester.pump();
    expect(find.text('Child A topic 1'), findsOneWidget);
    expect(find.text('Child A topic 2'), findsNothing);

    await tester.tap(find.byTooltip('图墙'));
    await tester.pumpAndSettle();
    expect(find.text('Child A topic 1'), findsOneWidget);
    expect(find.text('Child A topic 2'), findsNothing);
    expect(repo.requests.length, 1, reason: 'filtered locally');
  });

  testWidgets('boards without a picture wall have no wall switch',
      (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      BoardThreadListScreen(
        category:
            ForumCategory(name: 'Child B', slug: 'fid-902', url: _url(902)),
        repository: repo,
      ),
    );
    expect(find.text('Child B topic 1'), findsOneWidget);
    expect(find.byTooltip('图墙'), findsNothing);
  });

  for (final (mode, theme, palette) in [
    (ThemeMode.light, AppTheme.light, AppColors.lightPalette),
    (ThemeMode.dark, AppTheme.dark, AppColors.darkPalette),
  ]) {
    testWidgets('the 发帖 button takes the brand pair ($mode)', (tester) async {
      AppThemeController.notifier.value = mode;
      addTearDown(() => AppThemeController.notifier.value = ThemeMode.system);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: BoardThreadListScreen(category: _hub, repository: _Repo()),
      ));
      await tester.pumpAndSettle();
      final fab = find.byTooltip('发帖');
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

  testWidgets('large text keeps the board screen within bounds',
      (tester) async {
    final repo = _Repo();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: BoardThreadListScreen(category: _hub, repository: repo),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('图墙'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
