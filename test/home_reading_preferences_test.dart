import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('quick rows persist every allowed count and reject out-of-range writes',
      () async {
    expect((await HomeReadingPreferences.load()).quickRowCount, 8);
    for (var rows = 3; rows <= 8; rows++) {
      await HomeReadingPreferences.saveQuickRowCount(rows);
      expect((await HomeReadingPreferences.load()).quickRowCount, rows);
    }
    for (final rows in [-1, 0, 2, 9, 100]) {
      await expectLater(
          HomeReadingPreferences.saveQuickRowCount(rows), throwsArgumentError);
    }
    expect((await HomeReadingPreferences.load()).quickRowCount, 8);
  });

  test('section and board collapse states persist independently by stable ID',
      () async {
    await HomeReadingPreferences.setCollapsed('section:交流', true);
    await HomeReadingPreferences.setCollapsed('board:42', true);
    await HomeReadingPreferences.saveQuickRowCount(3);
    final state = await HomeReadingPreferences.load();
    expect(state.collapsedIds, {'section:交流', 'board:42'});
    await HomeReadingPreferences.setCollapsed('section:交流', false);
    expect((await HomeReadingPreferences.load()).collapsedIds, {'board:42'});
    expect((await HomeReadingPreferences.load()).quickRowCount, 3);
    for (final id in ['', '42', 'section: ', 'board:0', 'board:all']) {
      await expectLater(
          HomeReadingPreferences.setCollapsed(id, true), throwsArgumentError);
    }
  });

  test('recent boards deduplicate FID across URL forms and bound MRU order',
      () async {
    for (var fid = 1; fid <= 10; fid++) {
      await HomeReadingPreferences.recordBoardVisit(
          ForumCategory(name: '版块$fid', slug: 'fid-$fid'));
    }
    var recent = (await HomeReadingPreferences.load()).recentBoards;
    expect(recent.map((board) => board.id),
        ['10', '9', '8', '7', '6', '5', '4', '3']);
    await HomeReadingPreferences.recordBoardVisit(const ForumCategory(
      name: ' 更新后的名称 ',
      slug: 'f5',
      url: 'https://south-plus.net/simple/index.php?f5_2.html',
    ));
    recent = (await HomeReadingPreferences.load()).recentBoards;
    expect(recent.map((board) => board.id),
        ['5', '10', '9', '8', '7', '6', '4', '3']);
    expect(recent.first.label, '更新后的名称');
    await HomeReadingPreferences.recordBoardVisit(const ForumCategory(
      name: '查询格式',
      slug: '',
      url: 'thread.php?fid=5&page=2',
    ));
    expect((await HomeReadingPreferences.load()).recentBoards.length, 8);
    expect(
        (await HomeReadingPreferences.load()).recentBoards.first.label, '查询格式');
  });

  test('anonymous and account home state stay isolated and pins stay separate',
      () async {
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '99', label: '常用'),
    ], account: 'reader/a');
    await HomeReadingPreferences.saveQuickRowCount(3, account: 'reader/a');
    await HomeReadingPreferences.setCollapsed('board:42', true,
        account: 'reader/a');
    await HomeReadingPreferences.recordBoardVisit(
        const ForumCategory(name: '最近', slug: 'fid-42'),
        account: 'reader/a');
    await HomeReadingPreferences.saveQuickRowCount(5, account: 'reader%2Fa');
    final a = await HomeReadingPreferences.load(account: 'reader/a');
    final b = await HomeReadingPreferences.load(account: 'reader%2Fa');
    final anonymous = await HomeReadingPreferences.load();
    expect(a.quickRowCount, 3);
    expect(a.collapsedIds, {'board:42'});
    expect(a.recentBoards.single.id, '42');
    expect(b.quickRowCount, 5);
    expect(b.collapsedIds, isEmpty);
    expect(b.recentBoards, isEmpty);
    expect(anonymous.quickRowCount, 8);
    expect(anonymous.collapsedIds, isEmpty);
    expect(anonymous.recentBoards, isEmpty);
    await HomeReadingPreferences.clearRecentBoards(account: 'reader/a');
    expect(
        (await HomeReadingPreferences.load(account: 'reader/a')).recentBoards,
        isEmpty);
    expect(
        (await HomeReadingPreferences.load(account: 'reader/a')).collapsedIds,
        {'board:42'});
    expect(
        (await ForumSearchPreferences.load(account: 'reader/a'))
            .pinnedBoards
            .single
            .id,
        '99');
  });

  test('wrong types and corrupt JSON fall back without blocking home',
      () async {
    for (final rows in ['3', true, 2, 9]) {
      SharedPreferences.setMockInitialValues({
        'anonymous/home_quick_rows_v1': rows,
        'anonymous/home_collapsed_ids_v1': 'not a list',
        'anonymous/home_recent_boards_v1': '{bad json',
      });
      final state = await HomeReadingPreferences.load();
      expect(state.quickRowCount, 8);
      expect(state.collapsedIds, isEmpty);
      expect(state.recentBoards, isEmpty);
    }
    for (final raw in [false, 'null', '{}']) {
      SharedPreferences.setMockInitialValues({
        'anonymous/home_recent_boards_v1': raw,
      });
      expect((await HomeReadingPreferences.load()).recentBoards, isEmpty);
    }
  });

  test('legacy-shaped malformed entries are sanitized on next recent write',
      () async {
    SharedPreferences.setMockInitialValues({
      'anonymous/home_collapsed_ids_v1': [
        'section:交流',
        'board:42',
        'board:0',
        'index:0',
        'section: ',
      ],
      'anonymous/home_recent_boards_v1': jsonEncode([
        {'id': '0', 'label': 'invalid'},
        {'id': '1', 'label': ' 首次 '},
        {'id': '1', 'label': '重复'},
        {'id': '2', 'label': ' '},
        {'id': 3, 'label': 'wrong type'},
        null,
        for (var fid = 4; fid <= 14; fid++) {'id': '$fid', 'label': '版块$fid'},
      ]),
    });
    final state = await HomeReadingPreferences.load();
    expect(state.collapsedIds, {'section:交流', 'board:42'});
    expect(state.recentBoards.map((board) => board.id),
        ['1', '4', '5', '6', '7', '8', '9', '10']);
    expect(state.recentBoards.first.label, '首次');
    await HomeReadingPreferences.recordBoardVisit(
        const ForumCategory(name: '四', slug: 'fid-4'));
    final raw = (await SharedPreferences.getInstance())
        .getString('anonymous/home_recent_boards_v1')!;
    expect((jsonDecode(raw) as List).length, 8);
    expect((await HomeReadingPreferences.load()).recentBoards.first.label, '四');
  });

  test('invalid visits are ignored and successful changes notify listeners',
      () async {
    final revision = HomeReadingPreferences.revision.value;
    for (final category in const [
      ForumCategory(name: '全部', slug: 'all'),
      ForumCategory(name: '', slug: 'fid-42'),
      ForumCategory(name: '无效', slug: 'fid-0'),
    ]) {
      await HomeReadingPreferences.recordBoardVisit(category);
    }
    expect(HomeReadingPreferences.revision.value, revision);
    expect((await HomeReadingPreferences.load()).recentBoards, isEmpty);
    await HomeReadingPreferences.recordBoardVisit(
        const ForumCategory(name: '版块', slug: 'fid-42'));
    await HomeReadingPreferences.saveQuickRowCount(3);
    await HomeReadingPreferences.setCollapsed('board:42', true);
    await HomeReadingPreferences.clearRecentBoards();
    expect(HomeReadingPreferences.revision.value, revision + 4);
  });
}
