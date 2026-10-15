import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThreadPagingSettings {
  ThreadPagingSettings._();

  static const _key = 'settings.autoLoadNextPage';
  static final notifier = ValueNotifier<bool>(false);

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return notifier.value = prefs.getBool(_key) ?? false;
  }

  static Future<void> save(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_key, enabled)) {
      throw StateError('无法保存自动加载下一页设置');
    }
    notifier.value = enabled;
  }
}
