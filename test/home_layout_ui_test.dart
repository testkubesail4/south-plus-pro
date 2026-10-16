import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';

// Synthetic boards and titles only.
ForumThread _thread(String title) => ForumThread(
    title: title, url: 'read.php?tid-1.html', replies: 0, section: '');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Repo> pumpAt(
    WidgetTester tester,
    double width, {
    double height = 900,
    double textScale = 1,
    bool guest = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()..loggedIn = !guest;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeShell(repository: repo),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder boardTile() => find
      .ancestor(of: find.text('Fixture board'), matching: find.byType(InkWell))
      .first;

  Future<void> showBoard(WidgetTester tester) =>
      tester.scrollUntilVisible(find.text('Fixture board'), 200,
          scrollable: find.byType(Scrollable).first);

  testWidgets('phone: bottom bar, one-row header, tabbed lists, board rows',
      (tester) async {
    final repo = await pumpAt(tester, 360);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Fixture user'), findsOneWidget);
    final account = find
        .ancestor(of: find.text('Fixture user'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(account).height, greaterThanOrEqualTo(48));
    // Notices live in the 消息 tab; the header has no copies, unread or not.
    repo.flags.value =
        const ForumNoticeFlags(replyNotice: true, unreadPm: true);
    await tester.pump();
    final header = find.ancestor(
        of: find.text('Fixture user'), matching: find.byType(Row));
    for (final icon in [Icons.alternate_email, Icons.mail_outline]) {
      expect(find.descendant(of: header, matching: find.byIcon(icon)),
          findsNothing);
    }
    repo.flags.value = const ForumNoticeFlags();
    await tester.pump();
    expect(repo.quickListLoads, ['最新回复', '提问求物'],
        reason: 'the other lists load on their own');

    expect(find.text('Latest 1'), findsOneWidget);
    await tester.tap(find.text('最新回复'));
    await tester.pumpAndSettle();
    expect(repo.quickListLoads, hasLength(2), reason: 'no reload on tab');
    expect(find.text('Reply 8'), findsOneWidget);
    expect(find.text('Reply 9'), findsNothing, reason: 'eight rows at most');
    expect(find.text('7'), findsOneWidget, reason: 'Reply 8 has 7 replies');
    expect(find.text('0'), findsNothing, reason: 'no count without replies');
    expect(find.text('Latest 1'), findsNothing);

    await showBoard(tester);
    expect(find.text('今日 2'), findsOneWidget);
    expect(find.text('Last topic'), findsOneWidget);
    expect(find.text('2026-01-01 10:00 · 1,234 主题'), findsOneWidget);
    expect(
      find.descendant(of: boardTile(), matching: find.byType(Badge)),
      findsNothing,
      reason: 'a board with new posts gets no dot',
    );
    expect(find.bySemanticsLabel('有新帖'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.textContaining('fid-'), findsNothing, reason: 'no slugs');
  });

  testWidgets('phone: swiping the 速览 lists switches tabs both ways',
      (tester) async {
    final repo = await pumpAt(tester, 360);
    await tester.fling(find.text('Latest 1'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Reply 1'), findsOneWidget);
    expect(find.text('Latest 1'), findsNothing);
    final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(tabs.index, 1, reason: 'the tab follows the swipe');

    await tester.fling(find.text('Reply 1'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Latest 1'), findsOneWidget);
    expect(tabs.index, 0);
    expect(repo.quickListLoads, hasLength(2), reason: 'no reload on swipe');
  });

  testWidgets('速览 hides blocked authors as soon as a rule changes',
      (tester) async {
    final repo = await pumpAt(tester, 360);
    await tester.tap(find.text('最新回复'));
    await tester.pumpAndSettle();
    expect(find.text('Reply 2'), findsOneWidget);

    repo.blocking.notifier.value = const BlockingRules(users: [
      BlockedUser(
          uid: '1002', name: 'B', userBlocked: true, avatarBlocked: false),
    ]);
    await tester.pump();
    expect(find.text('Reply 1'), findsOneWidget);
    expect(find.text('Reply 2'), findsNothing);
    expect(repo.quickListLoads, hasLength(2), reason: 'filtered locally');
  });

  testWidgets('a hidden list that fails offers retry when opened',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()..failOnce.add('提问求物');
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: repo)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('提问求物'));
    await tester.pumpAndSettle();
    expect(find.textContaining('加载失败'), findsOneWidget);
    await tester.tap(find.textContaining('加载失败'));
    await tester.pumpAndSettle();
    expect(find.text('Reply 1'), findsOneWidget);
  });

  testWidgets('desktop: slim rail, centred column, list columns, board grid',
      (tester) async {
    await pumpAt(tester, 1440);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.all);
    expect(find.byType(NavigationBar), findsNothing);
    for (final label in ['回复提醒', '短消息']) {
      expect(find.widgetWithText(ActionChip, label), findsNothing,
          reason: 'notices live in the 消息 tab');
    }
    final account = find
        .ancestor(of: find.text('Fixture user'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(account).height, greaterThanOrEqualTo(48));

    // All three lists side by side, already loaded.
    for (final title in ['最新讨论', '最新回复', '提问求物']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Reply 1'), findsNWidgets(2));
    expect(find.text('点按加载'), findsNothing);
    final rowHeight = tester
        .getSize(find
            .ancestor(of: find.text('Latest 1'), matching: find.byType(InkWell))
            .first)
        .height;
    expect(rowHeight, greaterThanOrEqualTo(48));

    // Content is centred at most 1200 wide.
    final header = tester.getRect(find.text('速览'));
    expect(header.left, (1440 - 81 - 1200) / 2 + 81);

    await showBoard(tester);
    expect(tester.getSize(boardTile()).width, closeTo((1200 - 24 - 16) / 3, 1));
    expect(find.text('Child board'), findsNothing);
    expect(find.textContaining('fid-'), findsNothing, reason: 'no slugs');
  });

  for (final size in const [Size(400, 800), Size(900, 700), Size(1440, 900)]) {
    testWidgets(
        'text scale 2 fits at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      await pumpAt(tester, size.width, height: size.height, textScale: 2);
      expect(tester.takeException(), isNull);
      await showBoard(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('速览 rows are divided so wrapped titles never run together',
      (tester) async {
    await pumpAt(tester, 360);
    await tester.tap(find.text('最新回复'));
    await tester.pumpAndSettle();
    for (var i = 1; i < 8; i++) {
      final above = tester.getRect(find.text('Reply $i'));
      final below = tester.getRect(find.text('Reply ${i + 1}'));
      final dividers = find
          .byType(Divider)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)));
      expect(
        dividers.where((d) => d.top >= above.bottom && d.bottom <= below.top),
        hasLength(1),
        reason: 'a hairline between Reply $i and Reply ${i + 1}',
      );
      expect(below.top - above.bottom, greaterThanOrEqualTo(20));
    }
  });

  // The skeleton is the loaded layout with placeholders, so nothing moves.
  // The first load ever knows no directory: everything down to the first
  // section's title holds. Later loads remember its shape: everything holds.
  // Tall views build every section; short and empty 速览 lists keep the card.
  for (final (width, scale, guest) in const [
    (360.0, 1.0, false),
    (360.0, 2.0, true),
    (900.0, 1.0, true),
    (900.0, 2.0, false),
    (1440.0, 1.0, false),
    (1440.0, 2.0, true),
  ]) {
    testWidgets(
        'loading skeleton matches the loaded layout at ${width.toInt()} '
        'x$scale ${guest ? 'guest' : 'user'}', (tester) async {
      tester.view.physicalSize = Size(width, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<_Repo> launch() async {
        final repo = _Repo()
          ..loggedIn = !guest
          ..latestCount = guest ? 0 : 2
          ..homeGate = Completer<void>();
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: HomeShell(key: UniqueKey(), repository: repo),
        ));
        await tester.pump();
        await tester.pump();
        return repo;
      }

      List<Rect> geometry({bool directory = true}) => [
            tester.getRect(find.text('速览')),
            tester.getRect(find.text('热门版块')),
            tester.getRect(find.byKey(const ValueKey('home-section-0'))),
            if (directory)
              for (final key in [
                'home-grid-0',
                'home-section-1',
                'home-grid-1'
              ])
                tester.getRect(find.byKey(ValueKey(key))),
          ];

      var repo = await launch();
      final first = geometry(directory: false);
      repo.homeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Fixture board'), findsOneWidget);
      expect(geometry(directory: false), first);

      repo = await launch();
      final later = geometry();
      repo.homeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Fixture board'), findsOneWidget);
      expect(geometry(), later);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an unreadable remembered shape falls back to the guess',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'home_layout_shape/fixture_login': '{"hot":"x"}'});
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()..homeGate = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: HomeShell(repository: repo)));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('home-grid-1')), findsOneWidget);
    repo.homeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Fixture board'), findsOneWidget);
  });

  testWidgets('guests: welcome and 登录, hot boards, no notices', (tester) async {
    await pumpAt(tester, 1440, guest: true);
    expect(find.text('欢迎来到南+'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.text('回复提醒'), findsNothing);
    expect(find.text('热门版块'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Hot board'), findsOneWidget);

    await pumpAt(tester, 400, guest: true);
    expect(find.text('欢迎来到南+'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.byTooltip('回复提醒'), findsNothing);
  });

  testWidgets('pinned boards from search replace the hot boards',
      (tester) async {
    await ForumSearchPreferences.savePinnedBoards(
      const [ForumSearchPinnedBoard(id: '42', label: 'Pinned board')],
      account: 'fixture_login',
    );
    await pumpAt(tester, 1200);
    expect(find.text('常用版块'), findsOneWidget);
    expect(find.text('Pinned board'), findsOneWidget);
    expect(find.text('热门版块'), findsNothing);

    // Pins edited in search show up when home is shown again.
    await ForumSearchPreferences.savePinnedBoards(
      const [ForumSearchPinnedBoard(id: '43', label: 'Repinned board')],
      account: 'fixture_login',
    );
    await tester.tap(find.text('搜索').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('Repinned board'), findsOneWidget);
    expect(find.text('Pinned board'), findsNothing);
  });
}

class _Repo extends ForumRepository {
  final quickListLoads = <String>[];
  final failOnce = <String>{};

  var loggedIn = true;
  var latestCount = 5;
  Completer<void>? homeGate;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  String? get currentUsername => 'fixture_login';

  final flags = ValueNotifier(const ForumNoticeFlags());

  @override
  ValueNotifier<ForumNoticeFlags> get noticeFlags => flags;

  @override
  final accountIdentity = ValueNotifier(const ForumAccountIdentity(
      systemName: 'fixture_login', nickname: 'Fixture user'));

  @override
  Future<ForumHomeSnapshot> fetchHome() async {
    await homeGate?.future;
    return _home;
  }

  ForumHomeSnapshot get _home => ForumHomeSnapshot(
        latest: [_thread('Latest 1')],
        quickLists: [
          ForumQuickList(title: '最新讨论', threads: [
            // A title too long for one line must not grow its row.
            for (var i = 1; i <= latestCount; i++)
              _thread(i == 3 ? 'A long latest title ' * 6 : 'Latest $i'),
          ]),
          const ForumQuickList(title: '最新回复'),
          const ForumQuickList(title: '提问求物'),
        ],
        hot: [
          const ForumCategory(name: 'Hot board', slug: 'fid-7'),
          for (var i = 2; i <= 9; i++)
            ForumCategory(name: 'Hot board number $i', slug: 'fid-7'),
        ],
        sections: [
          ForumSection(
            // Long enough to wrap if a section title could.
            title: 'Boards with a rather long section title',
            items: [
              for (var i = 2; i <= 4; i++)
                ForumBoard(
                  name: 'Board $i',
                  url: 'https://south-plus.net/thread.php?fid-4$i.html',
                  section: 'Boards',
                  // Tiles without a last post or without meta are shorter.
                  lastPostTitle: i == 3 ? null : 'Topic $i',
                  lastPostTime: i == 4 ? null : '2026-01-0$i 09:00',
                ),
              ForumBoard(
                name: 'Fixture board',
                url: 'https://south-plus.net/thread.php?fid-42.html',
                section: 'Boards',
                topicCount: 1234,
                postCount: 156,
                todayCount: 2,
                lastPostTitle: 'Last topic',
                lastPostTime: '2026-01-01 10:00',
                hasNew: true,
                children: [
                  ForumBoard(
                    name: 'Child board',
                    url: 'https://south-plus.net/thread.php?fid-43.html',
                    section: 'Boards',
                  ),
                ],
              ),
            ],
          ),
          const ForumSection(title: 'More', items: [
            ForumBoard(
              name: 'Board 5',
              url: 'https://south-plus.net/thread.php?fid-45.html',
              section: 'More',
            ),
          ]),
        ],
      );

  @override
  Future<List<ForumThread>> fetchQuickList(ForumQuickList list) async {
    quickListLoads.add(list.title);
    if (failOnce.remove(list.title)) {
      throw const ForumRepositoryException('fixture failure');
    }
    // 提问求物 is short, for the card height.
    return [
      for (var i = 1; i <= (list.title == '提问求物' ? 2 : 9); i++)
        ForumThread(
            title: 'Reply $i',
            url: 'read.php?tid-1.html',
            replies: i - 1,
            section: '',
            authorUrl:
                'https://south-plus.net/u.php?action-show-uid-${1000 + i}.html'),
    ];
  }

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => const [];

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}
