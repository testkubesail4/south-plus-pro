import 'package:flutter/foundation.dart';

import 'local_state_preferences.dart';

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

  static Future<ForumTextSize> load() => LocalStatePreferences.read((prefs) {
        final value = prefs.getString(_sizeKey);
        final size = ForumTextSize.values.firstWhere(
          (size) => size.name == value,
          orElse: () => ForumTextSize.normal,
        );
        notifier.value = size;
        return size;
      });

  static Future<void> save(ForumTextSize size) =>
      LocalStatePreferences.write((prefs) async {
        final saved = await prefs.setString(_sizeKey, size.name);
        if (saved) notifier.value = size;
        return saved;
      });
}
