import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

import 'profile_appendfix_support.dart';

// The search form lists every board at one depth; the homepage says which
// board sits under which. Both children are called 同人志&CG.
const _options = [
  ForumSearchBoard(id: 'all', name: '全部版块'),
  ForumSearchBoard(id: '', name: '>> 同人展会', selectable: false),
  ForumSearchBoard(id: '229', name: '|- CM108', depth: 1),
  ForumSearchBoard(id: '230', name: '|- 同人志&CG', depth: 1),
  ForumSearchBoard(id: '226', name: '|- CM107', depth: 1),
  ForumSearchBoard(id: '227', name: '|- 同人志&CG', depth: 1),
  ForumSearchBoard(id: '300', name: '|- 阅读区', depth: 1),
];

const _sections = [
  ForumSection(title: '同人展会', items: [
    ForumBoard(
        name: 'CM108',
        url: 'https://south-plus.net/thread.php?fid-229.html',
        section: '同人展会',
        children: [
          ForumBoard(
              name: '同人志&CG',
              url: 'https://south-plus.net/thread.php?fid-230.html',
              section: '同人展会 / CM108'),
        ]),
    ForumBoard(
        name: 'CM107',
        url: 'https://south-plus.net/thread.php?fid-226.html',
        section: '同人展会',
        children: [
          ForumBoard(
              name: '同人志&CG',
              url: 'https://south-plus.net/thread.php?fid-227.html',
              section: '同人展会 / CM107'),
        ]),
  ]),
];

class _PushWatcher extends NavigatorObserver {
  var pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeProfileRepository> open(
    WidgetTester tester, {
    bool sectionsFail = false,
    NavigatorObserver? watcher,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = FakeProfileRepository(
      topics: [listItem('第一页主题', tid: '1')],
      onContent: (_) async => contentResult(items: [listItem('命中', tid: '2')]),
    )
      ..boards = _options
      ..sections = _sections
      ..sectionsFail = sectionsFail;
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [if (watcher != null) watcher],
      home: UserProfileScreen(
        userUrl: profileFixture.url,
        repository: repository,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openSheet(WidgetTester tester, [String chip = '版块：全部']) async {
    await tester.tap(find.text(chip));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  Finder row(String id) => find.byKey(ValueKey('board-filter:$id'));

  testWidgets('a parent only folds; its own row and each child select by FID',
      (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    expect(find.text('CM108'), findsNothing,
        reason: 'folded under its section');
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    expect(find.text('CM108'), findsOneWidget);
    expect(row('230'), findsNothing, reason: 'children stay folded');

    await tapKey(tester, 'board-filter-group:229');
    expect(repository.queries, isEmpty, reason: 'folding asks nothing');
    expect(row('229'), findsOneWidget);
    expect(find.text('仅筛选 CM108'), findsOneWidget);
    expect(find.text('不含子版块'), findsOneWidget);
    expect(row('230'), findsOneWidget);
    expect(row('227'), findsNothing,
        reason: 'the other parent is still folded');

    await tester.tap(row('229'));
    await tester.pumpAndSettle();
    expect(repository.queries.map((q) => q.boardId), ['229'],
        reason: 'the parent alone, never its children');
    expect(find.text('版块：CM108'), findsOneWidget);
  });

  testWidgets('a child is chosen on its own and keeps its parent in the label',
      (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'board-filter-group:226');
    await tester.tap(row('227'));
    await tester.pumpAndSettle();
    expect(repository.queries.map((q) => q.boardId), ['227']);
    expect(find.text('版块：CM107 / 同人志&CG'), findsOneWidget);
  });

  testWidgets('closing the sheet after folding changes nothing',
      (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'board-filter-group:229');
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text('筛选版块'), findsNothing, reason: 'the sheet is closed');
    expect(repository.queries, isEmpty);
    expect(find.text('版块：全部'), findsOneWidget);
    expect(find.text('第一页主题'), findsOneWidget);
  });

  testWidgets('a search lists same-named children with their parents',
      (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    await tester.enterText(find.widgetWithText(TextField, '筛选版块'), '同人志');
    await tester.pumpAndSettle();
    expect(row('230'), findsOneWidget);
    expect(row('227'), findsOneWidget);
    expect(find.text('CM108'), findsOneWidget, reason: 'parent of the first');
    expect(find.text('CM107'), findsOneWidget, reason: 'parent of the second');
    await tester.tap(row('227'));
    await tester.pumpAndSettle();
    expect(repository.queries.map((q) => q.boardId), ['227']);
  });

  testWidgets('reopening opens the way to the chosen child, no other',
      (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'board-filter-group:226');
    await tester.tap(row('227'));
    await tester.pumpAndSettle();
    await openSheet(tester, '版块：CM107 / 同人志&CG');
    expect(row('227'), findsOneWidget);
    expect(tester.widget<ListTile>(row('227')).selected, isTrue);
    expect(row('230'), findsNothing, reason: 'the other parent stays folded');
    expect(repository.queries, hasLength(1));
  });

  testWidgets('the topic and reply lists keep their own board', (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    await tester.tap(row('300'));
    await tester.pumpAndSettle();
    expect(find.text('版块：阅读区'), findsOneWidget);
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    // The reply list starts folded and unfiltered: no chip until opened.
    expect(find.textContaining('版块：'), findsNothing);
    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();
    expect(find.text('版块：全部'), findsOneWidget);
    expect(repository.queries.map((q) => q.boardId), ['300']);
  });

  testWidgets(
      'no board is offered until the homepage says whose child it is, '
      'then the parent shows', (tester) async {
    final repository = await open(tester);
    final hold = repository.holdSections = Completer<void>();
    await tester.tap(find.text('版块：全部'));
    // The loading line spins, so wait by frames, not until idle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('正在加载版块层级…'), findsOneWidget);
    expect(row('all'), findsOneWidget);
    expect(find.text('同人展会'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '筛选版块'), '同人志');
    await tester.pump(const Duration(milliseconds: 100));
    expect(row('230'), findsNothing, reason: 'no bare same-named child');
    expect(row('227'), findsNothing);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('正在加载版块层级…'), findsNothing);
    expect(row('230'), findsOneWidget);
    expect(row('227'), findsOneWidget);
    expect(find.text('CM108'), findsOneWidget);
    expect(find.text('CM107'), findsOneWidget);
  });

  testWidgets('two headings sharing one placeholder id fold on their own',
      (tester) async {
    final repository = await open(tester);
    repository.boards = const [
      ForumSearchBoard(id: 'all', name: '全部版块'),
      ForumSearchBoard(id: '0', name: '>> 甲区', selectable: false),
      ForumSearchBoard(id: '7', name: '|- 甲版', depth: 1),
      ForumSearchBoard(id: '0', name: '>> 乙区', selectable: false),
      ForumSearchBoard(id: '8', name: '|- 乙版', depth: 1),
    ];
    repository.sections = const [];
    await openSheet(tester);
    await tester.tap(find.text('甲区'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(row('7'), findsOneWidget);
    expect(row('8'), findsNothing, reason: 'the other heading stays folded');
    await tester.tap(find.text('乙区'));
    await tester.pumpAndSettle();
    expect(row('8'), findsOneWidget);
    await tester.tap(find.text('甲区'));
    await tester.pumpAndSettle();
    expect(row('7'), findsNothing);
    expect(row('8'), findsOneWidget);
  });

  testWidgets('a session change closes the open sheet and picks nothing',
      (tester) async {
    final repository = await open(tester);
    await openSheet(tester);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    expect(row('300'), findsOneWidget);
    repository.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('同人展会'), findsNothing,
        reason: 'no board name of the old account stays');
    expect(repository.queries, isEmpty);
  });

  testWidgets(
      'a session change after the sheet is pushed but before its first '
      'frame shows no boards', (tester) async {
    final watcher = _PushWatcher();
    final repository = await open(tester, watcher: watcher);
    final before = watcher.pushes;
    await tester.tap(find.text('版块：全部'));
    // The tap pushes the sheet's route; no frame has been drawn yet.
    expect(watcher.pushes, before + 1, reason: 'the sheet route is pushed');
    repository.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('同人展会'), findsNothing);
    expect(repository.queries, isEmpty);
  });

  testWidgets('boards nest on a forum with its own origin too', (tester) async {
    final repository = await open(tester);
    repository.config = const ForumNetworkConfig(
      site: ForumSite('first.invalid'),
      mode: ForumNetworkMode.native,
      dohProvider: ForumNetworkConfig.defaultProvider,
    );
    repository.sections = [
      for (final section in _sections)
        ForumSection(title: section.title, items: [
          for (final board in section.items)
            ForumBoard(
              name: board.name,
              url: board.url.replaceFirst('south-plus.net', 'first.invalid'),
              section: board.section,
              children: [
                for (final child in board.children)
                  ForumBoard(
                    name: child.name,
                    url: child.url
                        .replaceFirst('south-plus.net', 'first.invalid'),
                    section: child.section,
                  ),
              ],
            ),
        ]),
    ];
    await openSheet(tester);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-filter-group:229')), findsOneWidget,
        reason: 'the home links are read against this forum');
    expect(row('230'), findsNothing, reason: 'folded under its parent');
  });

  testWidgets('a search keeps the flat-list warning and its retry',
      (tester) async {
    final repository = await open(tester, sectionsFail: true);
    await openSheet(tester);
    final field = find.widgetWithText(TextField, '筛选版块');
    await tester.enterText(field, '同人志');
    await tester.pumpAndSettle();
    expect(find.text('未能加载版块层级，按平铺列表显示'), findsOneWidget);
    expect(row('230'), findsOneWidget);
    expect(find.text('CM108'), findsNothing, reason: 'no parent without it');

    await tester.enterText(field, '没有这个版块');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的版块'), findsOneWidget);
    expect(find.text('未能加载版块层级，按平铺列表显示'), findsOneWidget,
        reason: 'also with no hit');

    await tester.enterText(field, '同人志');
    await tester.pumpAndSettle();
    repository.sectionsFail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('未能加载版块层级，按平铺列表显示'), findsNothing);
    expect(find.text('CM108'), findsOneWidget, reason: 'the parent shows now');
    expect(find.text('CM107'), findsOneWidget);
  });

  testWidgets(
      'without the homepage the boards show flat under their section, '
      'and 重试 brings the nesting', (tester) async {
    final repository = await open(tester, sectionsFail: true);
    await openSheet(tester);
    expect(find.text('未能加载版块层级，按平铺列表显示'), findsOneWidget);
    await tester.tap(find.text('同人展会'));
    await tester.pumpAndSettle();
    expect(row('230'), findsOneWidget,
        reason: 'not nested without the homepage');
    expect(find.byKey(const ValueKey('board-filter-group:229')), findsNothing);

    repository.sectionsFail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('未能加载版块层级，按平铺列表显示'), findsNothing);
    expect(
        find.byKey(const ValueKey('board-filter-group:229')), findsOneWidget);
    expect(row('230'), findsNothing, reason: 'now folded under CM108');
  });
}
