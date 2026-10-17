import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';

class ForumTaskStateStore {
  const ForumTaskStateStore();

  static const _snapshotKey = 'forum_task_snapshot_v2';

  String _key(String? scope) => scope == null
      ? _snapshotKey
      : '$_snapshotKey:${base64Url.encode(utf8.encode(scope))}';

  Future<ForumTaskSnapshot?> load({String? scope}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(scope));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return ForumTaskSnapshot.fromJson(decoded);
  }

  Future<void> save(ForumTaskSnapshot snapshot, {String? scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(scope), jsonEncode(snapshot.toJson()));
  }

  Future<void> clear({String? scope}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(scope));
  }
}
