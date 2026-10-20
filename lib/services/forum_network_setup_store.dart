import 'package:shared_preferences/shared_preferences.dart';

/// Whether the first-run network guide has been finished.
class ForumNetworkSetupStore {
  ForumNetworkSetupStore._();

  static const completedKey = 'forum_network_setup_completed_v1';
  // Written by older versions; the mode now lives in the network config.
  static const _legacyChoiceKey = 'forum_network_setup_choice_v1';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyChoiceKey);
    if (!await prefs.setBool(completedKey, true)) {
      throw Exception('网络引导状态保存失败');
    }
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(completedKey);
    await prefs.remove(_legacyChoiceKey);
  }
}
