import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';
import 'forum_search_preferences.dart';
import 'forum_url_resolver.dart';
import 'local_state_preferences.dart';

class HomeReadingPreferences {
  const HomeReadingPreferences({
    this.quickRowCount = 8,
    this.collapsedIds = const {},
    this.recentBoards = const [],
  });

  final int quickRowCount;
  final Set<String> collapsedIds;
  final List<ForumSearchPinnedBoard> recentBoards;

  static const maxRecentBoards = 8;
  static final revision = ValueNotifier<int>(0);
  static final _fid = RegExp(r'^[1-9]\d*$');
  static final _urls = ForumUrlResolver();
  static const _rowsKey = 'home_quick_rows_v1';
  static const _collapsedKey = 'home_collapsed_ids_v1';
  static const _recentKey = 'home_recent_boards_v1';

  static String _key(String key, String? account) =>
      account == null || account.isEmpty
          ? 'anonymous/$key'
          : 'account/${Uri.encodeComponent(account)}/$key';

  static bool _validCollapsedId(String id) =>
      (id.startsWith('section:') && id.substring(8).trim().isNotEmpty) ||
      (id.startsWith('board:') && _fid.hasMatch(id.substring(6)));

  static Set<String> _collapsed(SharedPreferences prefs, String? account) {
    final raw = prefs.get(_key(_collapsedKey, account));
    return {
      if (raw is List)
        for (final id in raw)
          if (id is String && _validCollapsedId(id)) id,
    };
  }

  static List<ForumSearchPinnedBoard> _recent(
      SharedPreferences prefs, String? account) {
    final raw = prefs.get(_key(_recentKey, account));
    if (raw is! String) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <ForumSearchPinnedBoard>[];
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id'];
        final label = item['label'];
        if (id is! String ||
            !_fid.hasMatch(id) ||
            label is! String ||
            label.trim().isEmpty ||
            !seen.add(id)) continue;
        result.add(ForumSearchPinnedBoard(id: id, label: label.trim()));
        if (result.length == maxRecentBoards) break;
      }
      return result;
    } on FormatException {
      return [];
    }
  }

  static Future<HomeReadingPreferences> load({String? account}) =>
      LocalStatePreferences.read((prefs) {
        final rows = prefs.get(_key(_rowsKey, account));
        return HomeReadingPreferences(
          quickRowCount: rows is int && rows >= 3 && rows <= 8 ? rows : 8,
          collapsedIds: Set.unmodifiable(_collapsed(prefs, account)),
          recentBoards: List.unmodifiable(_recent(prefs, account)),
        );
      });

  static Future<void> saveQuickRowCount(int rows, {String? account}) async {
    if (rows < 3 || rows > 8) throw ArgumentError.value(rows, 'rows');
    await LocalStatePreferences.write(
        (prefs) => prefs.setInt(_key(_rowsKey, account), rows));
    revision.value++;
  }

  static Future<void> setCollapsed(String stableId, bool collapsed,
      {String? account}) async {
    if (!_validCollapsedId(stableId)) {
      throw ArgumentError.value(stableId, 'stableId');
    }
    await LocalStatePreferences.write((prefs) {
      final ids = _collapsed(prefs, account);
      if (collapsed) {
        ids.add(stableId);
      } else {
        ids.remove(stableId);
      }
      return prefs.setStringList(_key(_collapsedKey, account), ids.toList());
    });
    revision.value++;
  }

  static Future<void> recordBoardVisit(ForumCategory category,
      {String? account}) async {
    final id = _urls.fidFromCategory(category);
    final label = category.name.trim();
    if (id == null || !_fid.hasMatch(id) || label.isEmpty) return;
    await LocalStatePreferences.write((prefs) {
      final boards = [
        ForumSearchPinnedBoard(id: id, label: label),
        ..._recent(prefs, account).where((board) => board.id != id),
      ].take(maxRecentBoards);
      return prefs.setString(
          _key(_recentKey, account),
          jsonEncode([
            for (final board in boards) {'id': board.id, 'label': board.label},
          ]));
    });
    revision.value++;
  }

  static Future<void> clearRecentBoards({String? account}) async {
    await LocalStatePreferences.write(
        (prefs) => prefs.remove(_key(_recentKey, account)));
    revision.value++;
  }
}
