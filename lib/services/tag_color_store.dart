import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_state_preferences.dart';
import 'user_tag_store.dart';

class TagColorStore {
  static const ids = [
    'red', 'orange', 'amber', 'green', 'teal',
    'blue', 'indigo', 'purple', 'pink', 'brown',
  ];
  static final revision = ValueNotifier<int>(0);

  static String key(String tag) => UserTagStore.normalize([tag]).single.toLowerCase();

  static String _storageKey(String? account) => account == null || account.isEmpty
      ? 'anonymous/user_tag_colors_v1'
      : 'account/${Uri.encodeComponent(account)}/user_tag_colors_v1';

  static Map<String, String> _read(SharedPreferences prefs, String storageKey) {
    final raw = prefs.get(storageKey);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final colors = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String ||
            !ids.contains(entry.value)) continue;
        try {
          colors[key(entry.key as String)] = entry.value as String;
        } on ArgumentError {
          // A corrupt label must not hide valid colours in the same account.
        }
      }
      return colors;
    } on FormatException {
      return {};
    }
  }

  static Future<Map<String, String>> load({String? account}) =>
      LocalStatePreferences.read((prefs) =>
          Map.unmodifiable(_read(prefs, _storageKey(account))));

  static Future<void> save(String tag, String? id, {String? account}) async {
    final label = key(tag);
    if (id != null && !ids.contains(id)) throw ArgumentError.value(id, 'id');
    await LocalStatePreferences.write((prefs) {
      final storageKey = _storageKey(account);
      final colors = _read(prefs, storageKey);
      if (id == null) {
        colors.remove(label);
      } else {
        colors[label] = id;
      }
      return colors.isEmpty
          ? prefs.remove(storageKey)
          : prefs.setString(storageKey, jsonEncode(colors));
    });
    revision.value++;
  }
}
