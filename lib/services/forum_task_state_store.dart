import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forum_models.dart';

class ForumTaskStateStore {
  const ForumTaskStateStore();

  static const _snapshotKey = 'forum_task_snapshot_v1';

  Future<ForumTaskSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return ForumTaskSnapshot.fromJson(decoded);
  }

  Future<void> save(ForumTaskSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snapshotKey);
  }
}
