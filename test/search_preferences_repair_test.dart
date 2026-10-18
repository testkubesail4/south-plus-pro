import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'invalid or duplicate shortcuts and corrupt local data do not block searching',
      () async {
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: 'all', label: 'Fixture all'),
      ForumSearchPinnedBoard(id: '', label: 'Fixture heading'),
      ForumSearchPinnedBoard(id: '42', label: '  '),
      ForumSearchPinnedBoard(id: '43', label: ' First label '),
      ForumSearchPinnedBoard(id: '43', label: 'Duplicate label'),
    ]);
    final valid = await ForumSearchPreferences.load();
    expect(valid.pinnedBoards.map((b) => (b.id, b.label)),
        [('43', 'First label')]);
    SharedPreferences.setMockInitialValues({
      'anonymous/forum_search_pinned_boards_v1': '{bad json',
      'anonymous/forum_search_match_v1': 'unsupported',
      'anonymous/forum_search_time_v1': 'unsupported',
    });
    final repaired = await ForumSearchPreferences.load();
    expect(repaired.pinnedBoards, isEmpty);
    expect(repaired.defaultMatch, ForumSearchMatch.partial);
    expect(repaired.defaultTime, ForumSearchTime.year);
  });

  test('account and anonymous search preferences remain isolated', () async {
    await ForumSearchPreferences.saveDefaultMatch(ForumSearchMatch.exact,
        account: 'fixture-account-a');
    await ForumSearchPreferences.saveDefaultTime(ForumSearchTime.day,
        account: 'fixture-account-a');
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '42', label: 'Fixture private shortcut'),
    ], account: 'fixture-account-a');
    await ForumSearchPreferences.saveDefaultTime(ForumSearchTime.week,
        account: 'fixture-account-b');
    final a = await ForumSearchPreferences.load(account: 'fixture-account-a');
    final b = await ForumSearchPreferences.load(account: 'fixture-account-b');
    final anonymous = await ForumSearchPreferences.load();
    expect(a.defaultMatch, ForumSearchMatch.exact);
    expect(a.defaultTime, ForumSearchTime.day);
    expect(a.pinnedBoards.single.id, '42');
    expect(b.defaultMatch, ForumSearchMatch.partial);
    expect(b.defaultTime, ForumSearchTime.week);
    expect(b.pinnedBoards, isEmpty);
    expect(anonymous.defaultMatch, ForumSearchMatch.partial);
    expect(anonymous.defaultTime, ForumSearchTime.year);
    expect(anonymous.pinnedBoards, isEmpty);
  });

  test('keyword history trims, preserves case, bounds MRU and serializes edits',
      () async {
    for (var index = 0; index < 35; index++) {
      await ForumSearchPreferences.recordKeyword('q$index');
    }
    final moved = await ForumSearchPreferences.recordKeyword(' q10 ');
    expect(moved, hasLength(30));
    expect(moved.take(3), ['q10', 'q34', 'q33']);
    expect(moved, isNot(contains('q4')));
    final caseVariant = await ForumSearchPreferences.recordKeyword('Q10');
    expect(caseVariant.take(2), ['Q10', 'q10']);
    expect(await ForumSearchPreferences.recordKeyword(' \n '), caseVariant);
    await Future.wait([
      ForumSearchPreferences.recordKeyword('q35'),
      ForumSearchPreferences.recordKeyword('q36'),
    ]);
    final recent = (await ForumSearchPreferences.load()).recentKeywords;
    expect(recent, hasLength(30));
    expect(recent.take(4), ['q36', 'q35', 'Q10', 'q10']);
    final removed = await ForumSearchPreferences.removeKeyword(' q35 ');
    expect(removed.take(3), ['q36', 'Q10', 'q10']);
    expect(removed, isNot(contains('q35')));
    expect(() => removed.add('mutation'), throwsUnsupportedError);
    expect(await ForumSearchPreferences.clearKeywords(), isEmpty);
    expect((await ForumSearchPreferences.load()).recentKeywords, isEmpty);
    expect(caseVariant.first, 'Q10', reason: 'published lists are snapshots');
  });

  test(
      'keyword history isolates exact accounts and leaves defaults and pins alone',
      () async {
    await ForumSearchPreferences.saveDefaultMatch(ForumSearchMatch.exact,
        account: 'reader/a');
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '42', label: 'Keep pin'),
    ], account: 'reader/a');
    await Future.wait([
      ForumSearchPreferences.recordKeyword('Guest'),
      ForumSearchPreferences.recordKeyword('Account A', account: 'reader/a'),
      ForumSearchPreferences.recordKeyword('Account B', account: 'reader%2Fa'),
    ]);
    expect(
        (await ForumSearchPreferences.load(account: 'reader/a')).recentKeywords,
        ['Account A']);
    expect(await ForumSearchPreferences.clearKeywords(account: 'reader/a'),
        isEmpty);
    final a = await ForumSearchPreferences.load(account: 'reader/a');
    expect(a.recentKeywords, isEmpty);
    expect(a.defaultMatch, ForumSearchMatch.exact);
    expect(a.pinnedBoards.single.id, '42');
    expect(
        (await ForumSearchPreferences.load(account: 'reader%2Fa'))
            .recentKeywords,
        ['Account B']);
    expect((await ForumSearchPreferences.load()).recentKeywords, ['Guest']);
  });

  test(
      'corrupt keyword history salvages trimmed strings without blocking search',
      () async {
    const key = 'anonymous/forum_search_recent_keywords_v1';
    for (final raw in [false, 42, 'not a list']) {
      SharedPreferences.setMockInitialValues({key: raw});
      expect((await ForumSearchPreferences.load()).recentKeywords, isEmpty);
    }
    SharedPreferences.setMockInitialValues({
      key: <Object?>[
        ' Keep ',
        'Keep',
        null,
        7,
        ' ',
        'keep',
        for (var index = 0; index < 40; index++) 'entry$index'
      ],
    });
    final restored = (await ForumSearchPreferences.load()).recentKeywords;
    expect(restored, hasLength(30));
    expect(restored.take(2), ['Keep', 'keep']);
    final saved = await ForumSearchPreferences.recordKeyword('new');
    expect(saved.take(3), ['new', 'Keep', 'keep']);
    expect(saved, hasLength(30));
  });

  test(
      'search defaults save independently and board shortcuts preserve order and labels',
      () async {
    final initial = await ForumSearchPreferences.load();
    expect(initial.defaultMatch, ForumSearchMatch.partial);
    expect(initial.defaultTime, ForumSearchTime.year);
    expect(initial.pinnedBoards, isEmpty);
    await ForumSearchPreferences.saveDefaultMatch(ForumSearchMatch.exact);
    await ForumSearchPreferences.saveDefaultTime(ForumSearchTime.week);
    await ForumSearchPreferences.savePinnedBoards(const [
      ForumSearchPinnedBoard(id: '42', label: 'Fixture shortcut'),
      ForumSearchPinnedBoard(id: '43', label: 'Another shortcut'),
    ]);
    await ForumSearchPreferences.saveDefaultMatch(ForumSearchMatch.partial);
    final saved = await ForumSearchPreferences.load();
    expect(saved.defaultMatch, ForumSearchMatch.partial);
    expect(saved.defaultTime, ForumSearchTime.week);
    expect(saved.pinnedBoards.map((b) => (b.id, b.label)), [
      ('42', 'Fixture shortcut'),
      ('43', 'Another shortcut'),
    ]);
    await ForumSearchPreferences.savePinnedBoards([saved.pinnedBoards.last]);
    final removed = await ForumSearchPreferences.load();
    expect(removed.pinnedBoards.single.id, '43');
    expect(removed.defaultTime, ForumSearchTime.week);
  });
}
