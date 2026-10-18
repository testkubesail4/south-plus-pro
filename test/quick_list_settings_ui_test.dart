import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/quick_list_settings_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';

// Synthetic boards only.
class _Repo extends ForumRepository {
  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async => const [
        ForumSearchBoard(id: 'all', name: '全部版块'),
        // A search category: its value is no board's fid.
        ForumSearchBoard(id: '7', name: '>> 示例分区'),
        ForumSearchBoard(id: '12', name: '|- Fixture board', depth: 1),
      ];

  @override
  Future<List<ForumSection>> fetchForumSections() async => const [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a list takes a board and order; the last shown list stays',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await HomeReadingPreferences.saveQuickSources(const [
      HomeQuickSource(),
      HomeQuickSource(kind: HomeQuickSourceKind.hidden),
      HomeQuickSource(kind: HomeQuickSourceKind.hidden),
    ]);
    await tester.pumpWidget(
        MaterialApp(home: QuickListSettingsScreen(repository: _Repo())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('栏目 1'));
    await tester.pumpAndSettle();
    expect(find.text('至少保留一个栏目'), findsOneWidget);
    // The sheet's row, above the list rows that say the same.
    await tester.tap(find.text('不显示').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await HomeReadingPreferences.load()).quickSources.first,
        const HomeQuickSource());

    await tester.tap(find.text('栏目 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定版块'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();
    // The category folds; only the board under it can be chosen.
    expect(find.text('全部版块'), findsNothing);
    await tester.tap(find.text('示例分区'));
    await tester.pumpAndSettle();
    expect(find.text('示例分区（本版）'), findsNothing);
    await tester.tap(find.text('Fixture board'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最新回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      (await HomeReadingPreferences.load()).quickSources[1],
      const HomeQuickSource(
          kind: HomeQuickSourceKind.board,
          fid: '12',
          order: QuickOrder.replied),
    );
    expect(find.text('示例分区 / Fixture board · 最新回复'), findsOneWidget);
  });
}
