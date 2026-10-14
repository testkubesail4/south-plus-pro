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
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
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

  Finder boardCard() => find
      .ancestor(of: find.text('Fixture board'), matching: find.byType(InkWell))
      .first;

  bool newDot(WidgetTester tester) => tester
      .widget<Badge>(find.ancestor(
        of: find.byIcon(Icons.tag_outlined).last, // hot boards come first
        matching: find.byType(Badge),
      ))
      .isLabelVisible;

  testWidgets('phone: bottom bar, notice chips, tabbed lists, board rows',
      (tester) async {
    final repo = await pumpAt(tester, 360);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('回复提醒'), findsOneWidget);
    expect(repo.quickListLoads, isEmpty, reason: 'nothing extra at startup');

    expect(find.text('Latest 1'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '最新回复'));
    await tester.pumpAndSettle();
    expect(repo.quickListLoads, ['最新回复']);
    expect(find.text('Reply 5'), findsOneWidget);
    expect(find.text('Reply 6'), findsNothing, reason: 'five rows at most');
    expect(find.text('Latest 1'), findsNothing);

    // Sections start collapsed on phones.
    expect(find.text('Fixture board'), findsNothing);
    await tester.scrollUntilVisible(find.text('Fixture section'), 200);
    await tester.tap(find.text('Fixture section'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture board'), findsOneWidget);
    expect(find.text('今日 2'), findsOneWidget);
    expect(find.text('2026-01-01 10:00'), findsOneWidget);
    expect(newDot(tester), isTrue);
    expect(find.text('Child board'), findsOneWidget);
    expect(find.text('Last topic'), findsNothing, reason: 'rows stay short');
  });

  testWidgets('tablet: rail, two list columns load on tap, board cards',
      (tester) async {
    final repo = await pumpAt(tester, 700);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(find.byType(NavigationBar), findsNothing);

    expect(find.text('Latest 1'), findsOneWidget);
    expect(find.text('点按加载'), findsNWidgets(2));
    await tester.tap(find.text('点按加载').first);
    await tester.pumpAndSettle();
    expect(repo.quickListLoads, ['最新回复']);
    expect(find.text('Reply 1'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Fixture board'), 200);
    expect(find.text('Last topic'), findsOneWidget);
    expect(find.textContaining('主题 /'), findsNothing);
  });

  testWidgets('desktop: extended rail, side panel, counts on cards',
      (tester) async {
    await pumpAt(tester, 1200);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(find.text('热门版块'), findsOneWidget, reason: 'in the side panel');
    expect(find.text('Hot board'), findsOneWidget);
    expect(find.text('回复提醒'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Fixture board'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('2026-01-01 10:00 · 6 主题 / 156 文章'), findsOneWidget);
  });

  testWidgets('expanded boundary keeps the feed usable without side panel',
      (tester) async {
    await pumpAt(tester, 841);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isTrue,
    );
    expect(find.text('回复提醒'), findsOneWidget, reason: 'chips in the feed');
    await tester.scrollUntilVisible(find.text('Fixture board'), 200);
    expect(tester.getSize(boardCard()).width, greaterThanOrEqualTo(260));
    expect(tester.takeException(), isNull);
  });

  for (final width in [600.0, 841.0, 1100.0]) {
    testWidgets('large text fits at ${width.toInt()}px', (tester) async {
      await pumpAt(tester, width, textScale: 2);
      await tester.scrollUntilVisible(find.text('Fixture board'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('side panel lists the boards pinned in search', (tester) async {
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

  @override
  bool get isLoggedIn => true;

  @override
  String? get currentUsername => 'fixture_login';

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
                topicCount: 6,
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
