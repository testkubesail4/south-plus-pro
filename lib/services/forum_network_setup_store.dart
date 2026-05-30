import 'package:shared_preferences/shared_preferences.dart';

class ForumNetworkSetupStore {
  ForumNetworkSetupStore._();

  static const completedKey = 'forum_network_setup_completed_v1';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(completedKey);
  }
}
