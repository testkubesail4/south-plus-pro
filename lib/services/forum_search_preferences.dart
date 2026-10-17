import 'dart:convert';

import '../models/forum_models.dart';
import 'local_state_preferences.dart';

class ForumSearchPinnedBoard {
  const ForumSearchPinnedBoard({required this.id, required this.label});
  final String id;
  final String label;
}

class ForumSearchPreferences {
  const ForumSearchPreferences({
    this.defaultMatch = ForumSearchMatch.partial,
    this.defaultTime = ForumSearchTime.year,
    this.pinnedBoards = const [],
  });

  final ForumSearchMatch defaultMatch;
  final ForumSearchTime defaultTime;
  final List<ForumSearchPinnedBoard> pinnedBoards;

  static const _matchKey = 'forum_search_match_v1';
  static const _timeKey = 'forum_search_time_v1';
  static const _boardsKey = 'forum_search_pinned_boards_v1';

  static Future<ForumSearchPreferences> load({String? account}) =>
      LocalStatePreferences.read((prefs) {
        final match = ForumSearchMatch.values.where(
            (value) => value.name == prefs.getString(_key(_matchKey, account)));
        final time = ForumSearchTime.values.where(
            (value) => value.name == prefs.getString(_key(_timeKey, account)));
        final pinned = <ForumSearchPinnedBoard>[];
        try {
          final decoded =
              jsonDecode(prefs.getString(_key(_boardsKey, account)) ?? '[]');
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map &&
                  item['id'] is String &&
                  item['label'] is String) {
                pinned.add(ForumSearchPinnedBoard(
                    id: item['id'], label: item['label']));
              }
            }
          }
        } on FormatException {
          // Corrupt local shortcuts do not prevent searching.
        }
        return ForumSearchPreferences(
          defaultMatch: match.isEmpty ? ForumSearchMatch.partial : match.first,
          defaultTime: time.isEmpty ? ForumSearchTime.year : time.first,
          pinnedBoards: List.unmodifiable(_validBoards(pinned)),
        );
      });

  static Future<void> saveDefaultMatch(ForumSearchMatch value,
          {String? account}) =>
      LocalStatePreferences.write(
          (prefs) => prefs.setString(_key(_matchKey, account), value.name));

  static Future<void> saveDefaultTime(ForumSearchTime value,
          {String? account}) =>
      LocalStatePreferences.write(
          (prefs) => prefs.setString(_key(_timeKey, account), value.name));

  static Future<void> savePinnedBoards(List<ForumSearchPinnedBoard> values,
          {String? account}) =>
      LocalStatePreferences.write((prefs) => prefs.setString(
          _key(_boardsKey, account),
          jsonEncode([
            for (final board in _validBoards(values))
              {'id': board.id, 'label': board.label},
          ])));

  static String _key(String key, String? account) =>
      account == null || account.isEmpty
          ? 'anonymous/$key'
          : 'account/${Uri.encodeComponent(account)}/$key';

  static Iterable<ForumSearchPinnedBoard> _validBoards(
      List<ForumSearchPinnedBoard> values) sync* {
    final seen = <String>{};
    for (final board in values) {
      if (!RegExp(r'^[1-9]\d*$').hasMatch(board.id) ||
          board.label.trim().isEmpty ||
          !seen.add(board.id)) continue;
      yield ForumSearchPinnedBoard(id: board.id, label: board.label.trim());
    }
  }
}
