import 'package:shared_preferences/shared_preferences.dart';

enum ForumNetworkSetupChoice { optimize, proxy, skip }

class ForumNetworkSetupStore {
  ForumNetworkSetupStore._();

  static const completedKey = 'forum_network_setup_completed_v1';
  static const _choiceKey = 'forum_network_setup_choice_v1';

  static Future<ForumNetworkSetupChoice?> loadChoice() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_choiceKey);
    return ForumNetworkSetupChoice.values
        .where((choice) => choice.name == saved)
        .firstOrNull;
  }

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted({ForumNetworkSetupChoice? choice}) async {
    final prefs = await SharedPreferences.getInstance();
    if (choice != null) await prefs.setString(_choiceKey, choice.name);
    await prefs.setBool(completedKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(completedKey);
    await prefs.remove(_choiceKey);
  }
}
