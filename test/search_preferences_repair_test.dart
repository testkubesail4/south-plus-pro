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
