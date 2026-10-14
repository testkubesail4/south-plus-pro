import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';

class ThreadReadPositionStore {
  static const _key = 'thread_read_positions_v1';
  static final _anchor = RegExp(r'^(?:tpc|[1-9]\d*)$');

  Map<String, dynamic> _positions(SharedPreferences prefs) {
    final raw = prefs.get(_key);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<ThreadReadPosition?> load(String threadKey) async {
    final prefs = await SharedPreferences.getInstance();
    final value = _positions(prefs)[threadKey];
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

  Future<void> save(String threadKey, ThreadReadPosition position) async {
    final anchor = position.anchor?.replaceFirst(RegExp(r'^#'), '');
    if (position.page < 1 ||
        position.page > 0x7fffffff ||
        (anchor != null && !_anchor.hasMatch(anchor))) {
      throw ArgumentError('Invalid thread read position');
    }
    final prefs = await SharedPreferences.getInstance();
    final positions = _positions(prefs)..remove(threadKey);
    positions[threadKey] = {'page': position.page, 'anchor': anchor};
    while (positions.length > 500) {
      positions.remove(positions.keys.first);
    }
    if (!await prefs.setString(_key, jsonEncode(positions))) {
      throw StateError('Could not save thread read position');
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key)) {
      throw StateError('Could not clear thread read positions');
    }
  }
}
