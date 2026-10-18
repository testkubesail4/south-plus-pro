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
    this.recentKeywords = const [],
  });

  final ForumSearchMatch defaultMatch;
  final ForumSearchTime defaultTime;
  final List<ForumSearchPinnedBoard> pinnedBoards;
  final List<String> recentKeywords;

  static const maxRecentKeywords = 30;
  static const _keywordsKey = 'forum_search_recent_keywords_v1';
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
          recentKeywords: _keywords(prefs.get(_key(_keywordsKey, account))),
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

  static Future<List<String>> recordKeyword(String keyword, {String? account}) {
    final value = keyword.trim();
    if (value.isEmpty) {
      return LocalStatePreferences.read(
          (prefs) => _keywords(prefs.get(_key(_keywordsKey, account))));
    }
    return _updateKeywords(
        (keywords) => [value, ...keywords.where((entry) => entry != value)]
            .take(maxRecentKeywords)
            .toList(),
        account: account);
  }

  static Future<List<String>> removeKeyword(String keyword,
          {String? account}) =>
      _updateKeywords(
          (keywords) =>
              keywords.where((entry) => entry != keyword.trim()).toList(),
          account: account);

  static Future<List<String>> clearKeywords({String? account}) =>
      _updateKeywords((_) => [], account: account);

  static Future<List<String>> _updateKeywords(
    List<String> Function(List<String>) update, {
    String? account,
  }) async {
    late List<String> keywords;
    final key = _key(_keywordsKey, account);
    await LocalStatePreferences.write((prefs) {
      keywords = List.unmodifiable(update(_keywords(prefs.get(key))));
      return keywords.isEmpty
          ? prefs.remove(key)
          : prefs.setStringList(key, keywords);
    });
    return keywords;
  }

  static List<String> _keywords(Object? raw) {
    final keywords = <String>[];
    final seen = <String>{};
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! String) continue;
        final value = entry.trim();
        if (value.isEmpty || !seen.add(value)) continue;
        keywords.add(value);
        if (keywords.length == maxRecentKeywords) break;
      }
    }
    return List.unmodifiable(keywords);
  }

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
