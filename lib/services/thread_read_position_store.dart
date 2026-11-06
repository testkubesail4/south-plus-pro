import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';

class ThreadReadPositionStore {
  static const _legacyKey = 'thread_read_positions_v1';

  /// Prefs key for one account/guest scope. Legacy v1 stays unowned.
  static String keyForScope(String scope) => 'thread_read_positions_v2:$scope';

  static final _anchor = RegExp(r'^(?:tpc|[1-9]\d*)$');

  Map<String, dynamic> _positions(SharedPreferences prefs, String prefsKey) {
    final raw = prefs.get(prefsKey);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<ThreadReadPosition?> _loadKey(
      String prefsKey, String threadKey) async {
    final prefs = await SharedPreferences.getInstance();
    final value = _positions(prefs, prefsKey)[threadKey];
    if (value is! Map) return null;
    final page = value['page'];
    final anchor = value['anchor'];
    if (page is! int ||
        page < 1 ||
        page > 0x7fffffff ||
        (anchor != null && (anchor is! String || !_anchor.hasMatch(anchor)))) {
      return null;
    }
    return ThreadReadPosition(page: page, anchor: anchor as String?);
  }

  Future<void> _saveKey(
    String prefsKey,
    String threadKey,
    ThreadReadPosition position,
  ) async {
    final anchor = position.anchor?.replaceFirst(RegExp(r'^#'), '');
    if (position.page < 1 ||
        position.page > 0x7fffffff ||
        (anchor != null && !_anchor.hasMatch(anchor))) {
      throw ArgumentError('Invalid thread read position');
    }
    final prefs = await SharedPreferences.getInstance();
    final positions = _positions(prefs, prefsKey)..remove(threadKey);
    positions[threadKey] = {'page': position.page, 'anchor': anchor};
    while (positions.length > 500) {
      positions.remove(positions.keys.first);
    }
    if (!await prefs.setString(prefsKey, jsonEncode(positions))) {
      throw StateError('Could not save thread read position');
    }
  }

  /// Legacy v1 (unowned).
  Future<ThreadReadPosition?> load(String threadKey) =>
      _loadKey(_legacyKey, threadKey);

  /// Scoped v2 bucket.
  Future<ThreadReadPosition?> loadForScope(String scope, String threadKey) =>
      _loadKey(keyForScope(scope), threadKey);

  /// Legacy v1 (unowned).
  Future<void> save(String threadKey, ThreadReadPosition position) =>
      _saveKey(_legacyKey, threadKey, position);

  /// Scoped v2 write with captured scope.
  Future<void> saveForScope(
    String scope,
    String threadKey,
    ThreadReadPosition position,
  ) =>
      _saveKey(keyForScope(scope), threadKey, position);

  /// Clears legacy v1 only.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_legacyKey)) {
      throw StateError('Could not clear thread read positions');
    }
  }

  /// Clears one scoped v2 bucket.
  Future<void> clearForScope(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(keyForScope(scope))) {
      throw StateError('Could not clear thread read positions');
    }
  }
}
