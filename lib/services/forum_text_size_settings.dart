import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ForumTextSize {
  small(0.9),
  normal(1.0),
  large(1.15);

  const ForumTextSize(this.scale);

  final double scale;
}

class ForumTextSizeSettings {
  ForumTextSizeSettings._();

  static const _sizeKey = 'settings.forumTextSize';
  static final notifier = ValueNotifier<ForumTextSize>(ForumTextSize.normal);

  static Future<ForumTextSize> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_sizeKey);
    final size = ForumTextSize.values.firstWhere(
      (size) => size.name == value,
      orElse: () => ForumTextSize.normal,
    );
    notifier.value = size;
    return size;
  }

  static Future<void> save(ForumTextSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sizeKey, size.name);
    notifier.value = size;
  }
}
