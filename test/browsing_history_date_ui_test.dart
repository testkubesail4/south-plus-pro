import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/features/history/browsing_history_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic retained records; local times so year/month/day are exact.
BrowsingHistoryEntry _entry(String title, DateTime viewed) =>
    BrowsingHistoryEntry(
      thread: ForumThread(
          title: title,
          url:
              'https://south-plus.net/read.php?tid-${title.hashCode.abs()}.html',
          replies: 0,
          section: '茶馆'),
      viewedAt: viewed,
    );

class _Repo extends ForumRepository {
  final entries = [
    _entry('mod 今日', DateTime(2026, 10, 19, 12)),
    _entry('茶 今日', DateTime(2026, 10, 19, 9)),
    _entry('mod 上旬', DateTime(2026, 10, 2, 9)),
    _entry('mod 九月', DateTime(2026, 9, 30, 9)),
    _entry('mod 去年', DateTime(2025, 12, 31, 9)),
  ];

  @override
  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) async =>
      entries;
}

void main() {
  List<String> titles(WidgetTester tester) => [
        for (final row
            in tester.widgetList<ForumThreadRow>(find.byType(ForumThreadRow)))
          row.title,
      ];

  Future<void> pick(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey('history-date:$key')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'year, month and day narrow the retained records with the search; clearing shows all',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: BrowsingHistoryScreen(repository: _Repo())));
    await tester.pumpAndSettle();
    expect(titles(tester), hasLength(5));

    await tester.tap(find.byTooltip('按日期筛选'));
    await tester.pumpAndSettle();
    expect(find.text('2026年 · 4'), findsOneWidget);
    expect(find.text('2025年 · 1'), findsOneWidget);
    await pick(tester, '年2026');
    expect(find.text('10月 · 3'), findsOneWidget);
    expect(find.text('9月 · 1'), findsOneWidget);
    await pick(tester, '月10');
    expect(find.text('19日 · 2'), findsOneWidget);
    await pick(tester, '日19');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('2026年10月19日'), findsOneWidget);
    expect(titles(tester), ['mod 今日', '茶 今日']);
    expect(find.byTooltip('清空浏览历史'), findsNothing,
        reason: 'clearing everything is not offered beside a filtered list');

    // Composes with the keyword search.
    await tester.tap(find.byTooltip('搜索浏览历史'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'mod');
    await tester.pumpAndSettle();
    expect(titles(tester), ['mod 今日']);
    expect(find.text('找到 1 条'), findsOneWidget);

    // Widening to the month keeps the keyword.
    await tester.tap(find.text('2026年10月19日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(titles(tester), ['mod 今日', 'mod 上旬']);

    await tester.tap(find.byTooltip('清除日期筛选'));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsNothing);
    expect(titles(tester), ['mod 今日', 'mod 上旬', 'mod 九月', 'mod 去年']);
  });
}
