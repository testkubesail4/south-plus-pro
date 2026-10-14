import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
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
    for (final label in ['回复提醒', '短消息']) {
      final button = find.ancestor(
          of: find.byTooltip(label), matching: find.byType(IconButton));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    final account = find
        .ancestor(of: find.text('Fixture user'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(account).height, greaterThanOrEqualTo(48));
    repo.flags.value =
        const ForumNoticeFlags(replyNotice: true, unreadPm: true);
    await tester.pump();
    expect(find.byTooltip('回复提醒，有未读'), findsOneWidget);
    expect(find.byTooltip('短消息，有未读'), findsOneWidget);
    repo.flags.value = const ForumNoticeFlags();
    await tester.pump();
    expect(repo.quickListLoads, ['最新回复', '提问求物'],
        reason: 'the other lists load on their own');

    expect(find.text('Latest 1'), findsOneWidget);
    await tester.tap(find.text('最新回复'));
    await tester.pumpAndSettle();
    expect(repo.quickListLoads, hasLength(2), reason: 'no reload on tab');
    expect(find.text('Reply 5'), findsOneWidget);
    expect(find.text('Reply 6'), findsNothing, reason: 'five rows at most');
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
    expect(find.text('回复提醒'), findsOneWidget, reason: 'header chips');
    final account = find
        .ancestor(of: find.text('Fixture user'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(account).height, greaterThanOrEqualTo(48));
    for (final label in ['回复提醒', '短消息']) {
      final chip = find.ancestor(
          of: find.text(label), matching: find.byType(ActionChip));
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
    }

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
  Future<ForumHomeSnapshot> fetchHome() async => ForumHomeSnapshot(
        latest: [_thread('Latest 1')],
        quickLists: [
          ForumQuickList(title: '最新讨论', threads: [_thread('Latest 1')]),
          const ForumQuickList(title: '最新回复'),
          const ForumQuickList(title: '提问求物'),
        ],
        hot: const [
          ForumCategory(name: 'Hot board', slug: 'fid-7'),
        ],
        sections: const [
          ForumSection(
            title: 'Fixture section',
            items: [
              ForumBoard(
                name: 'Fixture board',
                url: 'https://south-plus.net/thread.php?fid-42.html',
                section: 'Fixture section',
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
                    section: 'Fixture section',
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  @override
  Future<List<ForumThread>> fetchQuickList(ForumQuickList list) async {
    quickListLoads.add(list.title);
    if (failOnce.remove(list.title)) {
      throw const ForumRepositoryException('fixture failure');
    }
    return [for (var i = 1; i <= 6; i++) _thread('Reply $i')];
  }

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => const [];

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async => null;

  @override
  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async =>
      null;
}
