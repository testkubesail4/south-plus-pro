import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_state_preferences.dart';

class UserNoteStore {
  static final revision = ValueNotifier<int>(0);
  static final _uid = RegExp(r'^[1-9]\d*$');

  static String _key(String? account) => account == null || account.isEmpty
      ? 'anonymous/user_notes_v1'
      : 'account/${Uri.encodeComponent(account)}/user_notes_v1';

  static Map<String, String> _read(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String &&
              _uid.hasMatch(entry.key as String) &&
              entry.value is String &&
              (entry.value as String).trim().isNotEmpty)
            entry.key as String: (entry.value as String).trim(),
      };
    } on FormatException {
      return {};
    }
  }

  static Future<Map<String, String>> load({String? account}) =>
      LocalStatePreferences.read(
          (prefs) => Map.unmodifiable(_read(prefs, _key(account))));

  static Future<void> save(String uid, String note, {String? account}) async {
    if (!_uid.hasMatch(uid)) throw ArgumentError.value(uid, 'uid');
    await LocalStatePreferences.write((prefs) {
      final key = _key(account);
      final notes = _read(prefs, key);
      final value = note.trim();
      if (value.isEmpty) {
        notes.remove(uid);
      } else {
        notes[uid] = value;
      }
      return notes.isEmpty
          ? prefs.remove(key)
          : prefs.setString(key, jsonEncode(notes));
    });
    revision.value++;
  }

  static Future<void> clear(String uid, {String? account}) =>
      save(uid, '', account: account);
}
