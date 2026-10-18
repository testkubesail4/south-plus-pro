import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_state_preferences.dart';

class UserDisplayName {
  const UserDisplayName({this.nickname, this.hashName});

  final String? nickname;
  final String? hashName;

  String? get displayName => nickname ?? hashName;
}

class UserDisplayNameStore {
  static const maxNameRunes = 64;
  static final revision = ValueNotifier<int>(0);
  static final _uid = RegExp(r'^[1-9]\d*$');
  static final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]');

  static String _key(String? account) => account == null || account.isEmpty
      ? 'anonymous/user_display_names_v1'
      : 'account/${Uri.encodeComponent(account)}/user_display_names_v1';

  static String? _name(Object? raw) {
    if (raw is! String || _controls.hasMatch(raw)) return null;
    final value = raw.trim();
    return value.isEmpty || value.runes.length > maxNameRunes ? null : value;
  }

  static Map<String, UserDisplayName> _read(
      SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    if (raw is! String) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, UserDisplayName>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String ||
            !_uid.hasMatch(entry.key as String) ||
            entry.value is! Map) continue;
        final fields = entry.value as Map;
        final nickname = _name(fields['nickname']);
        final hashName = _name(fields['hashName']);
        if (nickname != null || hashName != null) {
          result[entry.key as String] =
              UserDisplayName(nickname: nickname, hashName: hashName);
        }
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  static Future<Map<String, UserDisplayName>> load({String? account}) =>
      LocalStatePreferences.read(
          (prefs) => Map.unmodifiable(_read(prefs, _key(account))));

  // Null keeps a field; empty values error. Only clear flags remove fields.
  static Future<void> save(
    String uid, {
    String? nickname,
    String? hashName,
    bool clearNickname = false,
    bool clearHashName = false,
    String? account,
  }) async {
    if (!_uid.hasMatch(uid)) throw ArgumentError.value(uid, 'uid');
    if ((clearNickname && nickname != null) ||
        (clearHashName && hashName != null)) {
      throw ArgumentError('不能同时提供名称和清除标记');
    }
    final cleanNickname = nickname == null ? null : _name(nickname);
    final cleanHashName = hashName == null ? null : _name(hashName);
    if ((nickname != null && cleanNickname == null) ||
        (hashName != null && cleanHashName == null)) {
      throw ArgumentError('名称不能为空，最多 64 个字符，不能包含换行或控制字符');
    }
    var changed = false;
    await LocalStatePreferences.write((prefs) {
      final key = _key(account);
      final names = _read(prefs, key);
      final previous = names[uid] ?? const UserDisplayName();
      final nextNickname =
          clearNickname ? null : cleanNickname ?? previous.nickname;
      final nextHashName =
          clearHashName ? null : cleanHashName ?? previous.hashName;
      if (nextNickname == previous.nickname &&
          nextHashName == previous.hashName) {
        return Future.value(true);
      }
      changed = true;
      if (nextNickname == null && nextHashName == null) {
        names.remove(uid);
      } else {
        names[uid] =
            UserDisplayName(nickname: nextNickname, hashName: nextHashName);
      }
      return names.isEmpty
          ? prefs.remove(key)
          : prefs.setString(
              key,
              jsonEncode({
                for (final entry in names.entries)
                  entry.key: {
                    if (entry.value.nickname != null)
                      'nickname': entry.value.nickname,
                    if (entry.value.hashName != null)
                      'hashName': entry.value.hashName,
                  },
              }));
    });
    if (changed) revision.value++;
  }

  static Future<void> clear(String uid, {String? account}) =>
      save(uid, clearNickname: true, clearHashName: true, account: account);
}
