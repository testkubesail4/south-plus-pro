import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_state_preferences.dart';

class UserTagStore {
  static const maxTags = 8;
  static const maxTagRunes = 16;
  static final revision = ValueNotifier<int>(0);
  static final _uid = RegExp(r'^[1-9]\d*$');
  static final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]');

  static String _key(String? account) => account == null || account.isEmpty
      ? 'anonymous/user_tags_v1'
      : 'account/${Uri.encodeComponent(account)}/user_tags_v1';

  static String? _tag(Object? raw) {
    if (raw is! String || _controls.hasMatch(raw)) return null;
    final tag = raw.trim();
    return tag.isEmpty || tag.runes.length > maxTagRunes ? null : tag;
  }

  static List<String> normalize(Iterable<String> tags) {
    final values = <String>[];
    final seen = <String>{};
    for (final raw in tags) {
      final tag = _tag(raw);
      if (tag == null) throw ArgumentError('标签不能为空，最多 16 个字符，不能包含换行或控制字符');
      if (seen.add(tag.toLowerCase())) values.add(tag);
    }
    if (values.length > maxTags) throw ArgumentError('每位用户最多 8 个标签');
    return List.unmodifiable(values);
  }

  static Map<String, List<String>> _read(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, List<String>>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String ||
            !_uid.hasMatch(entry.key as String) ||
            entry.value is! List) continue;
        final values = <String>[];
        final seen = <String>{};
        for (final raw in entry.value as List) {
          final tag = _tag(raw);
          if (tag == null || !seen.add(tag.toLowerCase())) continue;
          values.add(tag);
          if (values.length == maxTags) break;
        }
        if (values.isNotEmpty)
          result[entry.key as String] = List.unmodifiable(values);
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  static Future<Map<String, List<String>>> load({String? account}) =>
      LocalStatePreferences.read(
          (prefs) => Map.unmodifiable(_read(prefs, _key(account))));

  static Future<void> save(String uid, List<String> tags,
      {String? account}) async {
    if (!_uid.hasMatch(uid)) throw ArgumentError.value(uid, 'uid');
    final values = normalize(tags);
    await LocalStatePreferences.write((prefs) {
      final key = _key(account);
      final users = _read(prefs, key);
      if (values.isEmpty) {
        users.remove(uid);
      } else {
        users[uid] = values;
      }
      return users.isEmpty
          ? prefs.remove(key)
          : prefs.setString(key, jsonEncode(users));
    });
    revision.value++;
  }

  static Future<void> clear(String uid, {String? account}) =>
      save(uid, [], account: account);
}
