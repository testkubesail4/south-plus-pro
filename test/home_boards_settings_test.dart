import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/home_boards_settings_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';

const _sections = [
  ForumSection(nativeId: '7', title: '交流', items: [
    ForumBoard(
        name: '父版块',
        url: 'https://south-plus.net/thread.php?fid-42.html',
        section: '交流',
        children: [
          ForumBoard(
              name: '子版块',
              url: 'https://south-plus.net/thread.php?fid-43.html',
              section: '交流'),
        ]),
  ]),
  ForumSection(nativeId: '39', title: '漫区', items: []),
];

class _Repo extends ForumRepository {
  Completer<List<ForumSection>>? sectionsGate;
  bool failDirectory = false;

  @override
  String? get localPreferenceAccount => 'fixture';
  @override
  Future<List<ForumSection>> fetchForumSections() async {
    if (failDirectory) throw StateError('directory unavailable');
    return sectionsGate == null ? _sections : await sectionsGate!.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: HomeBoardsSettingsScreen(repository: _Repo())));
    await tester.pumpAndSettle();
  }

  testWidgets('a preference revision cannot erase a failed directory retry',
      (tester) async {
    final repo = _Repo()..failDirectory = true;
    await tester.pumpWidget(
        MaterialApp(home: HomeBoardsSettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    await HomeReadingPreferences.saveQuickRowCount(5, account: 'fixture');
    await tester.pumpAndSettle();
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    repo.failDirectory = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('交流'), findsOneWidget);
    expect(find.text('加载失败'), findsNothing);
  });

  testWidgets('a preference revision cannot cancel an in-flight directory load',
      (tester) async {
    final repo = _Repo()..sectionsGate = Completer<List<ForumSection>>();
    await tester.pumpWidget(
        MaterialApp(home: HomeBoardsSettingsScreen(repository: repo)));
    await tester.pump();
    await HomeReadingPreferences.saveQuickRowCount(5, account: 'fixture');
    await tester.pump();
    repo.sectionsGate!.complete(_sections);
    await tester.pumpAndSettle();
    expect(find.text('交流'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'parent visibility and section visibility are independent and children have no controls',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('展开版块').first);
    await tester.pumpAndSettle();
    expect(find.text('父版块'), findsOneWidget);
    expect(find.text('含 1 个子版块'), findsOneWidget);
    expect(find.text('子版块'), findsNothing);
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('home-parent-visible:42')));
    await tester.pumpAndSettle();
    var prefs = await HomeReadingPreferences.load(account: 'fixture');
    expect(prefs.hiddenParentFids, {'42'});
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    prefs = await HomeReadingPreferences.load(account: 'fixture');
    expect(prefs.hiddenSectionIds, {'section-id:7'});
    expect(prefs.hiddenParentFids, {'42'});
    expect(_sections.first.items.single.children.single.name, '子版块');
  });

  testWidgets('restore remains reachable when all hidden and preserves folds',
      (tester) async {
    await HomeReadingPreferences.setCollapsed('section-id:7', true,
        account: 'fixture');
    await HomeReadingPreferences.setSectionHidden('section-id:7', true,
        account: 'fixture', sections: _sections);
    await HomeReadingPreferences.setSectionHidden('section-id:39', true,
        account: 'fixture');
    await HomeReadingPreferences.setParentHidden('42', true,
        account: 'fixture');
    await HomeReadingPreferences.saveSectionOrder(
        ['section-id:39', 'section-id:7'],
        account: 'fixture');
    await pump(tester);
    await tester.tap(find.text('恢复默认').first);
    await tester.pumpAndSettle();
    expect(find.text('恢复分区顺序并显示所有分区与版块（折叠状态不变）'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '恢复默认'));
    await tester.pumpAndSettle();
    final prefs = await HomeReadingPreferences.load(account: 'fixture');
    expect(prefs.sectionOrder, isEmpty);
    expect(prefs.hiddenSectionIds, isEmpty);
    expect(prefs.hiddenParentFids, isEmpty);
    expect(prefs.collapsedIds, {'section-id:7'});
  });

  testWidgets(
      'drag changes section order and a new route reads the saved order',
      (tester) async {
    await pump(tester);
    await tester.drag(
        find.byType(ReorderableDragStartListener).first, const Offset(0, 190));
    await tester.pumpAndSettle();
    final prefs = await HomeReadingPreferences.load(account: 'fixture');
    expect(prefs.sectionOrder, ['section-id:39', 'section-id:7']);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester);
    expect(tester.getTopLeft(find.text('漫区')).dy,
        lessThan(tester.getTopLeft(find.text('交流')).dy));
  });
}
