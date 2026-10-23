import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_state_preferences.dart';

enum ImageLoadMode {
  automatic,
  wifiOnly,
  manual,
  noImages,
}

class ImageLoadingSettings {
  ImageLoadingSettings._();

  static const _modeKey = 'settings.imageLoadMode';
  static const _networkChannel =
      MethodChannel('south_plus_rewrite/network_state');
  static final notifier = ValueNotifier<ImageLoadMode?>(null);
  static Future<ImageLoadMode>? _modeFuture;
  static Future<bool>? _canAutoLoadImagesFuture;

  static Future<ImageLoadMode> loadMode() async {
    final cached = notifier.value;
    if (cached != null) return cached;
    final inFlight = _modeFuture;
    if (inFlight != null) return inFlight;
    return _modeFuture = _loadMode();
  }

  static Future<ImageLoadMode> _loadMode() =>
      LocalStatePreferences.read((prefs) {
        final value = prefs.getString(_modeKey);
        final mode = ImageLoadMode.values.firstWhere(
          (mode) => mode.name == value,
          orElse: () => ImageLoadMode.automatic,
        );
        notifier.value = mode;
        _modeFuture = null;
        return mode;
      });

  static Future<void> saveMode(ImageLoadMode mode) =>
      LocalStatePreferences.write((prefs) async {
        final saved = await prefs.setString(_modeKey, mode.name);
        if (saved) {
          _modeFuture = Future<ImageLoadMode>.value(mode);
          _canAutoLoadImagesFuture = null;
          notifier.value = mode;
        }
        return saved;
      });

  static Future<bool> canAutoLoadImages() async {
    return _canAutoLoadImagesFuture ??= _resolveCanAutoLoadImages();
  }

  static Future<bool> _resolveCanAutoLoadImages() async {
    final mode = await loadMode();
    return switch (mode) {
      ImageLoadMode.automatic => true,
      ImageLoadMode.manual || ImageLoadMode.noImages => false,
      ImageLoadMode.wifiOnly => isOnWifi(),
    };
  }

  static Future<bool> isOnWifi() async {
    try {
      return await _networkChannel.invokeMethod<bool>('isOnWifi') ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }
}

extension ImageLoadModeLabel on ImageLoadMode {
  String get label {
    return switch (this) {
      ImageLoadMode.automatic => '自动加载',
      ImageLoadMode.wifiOnly => '仅 Wi-Fi 自动加载',
      ImageLoadMode.manual => '手动点击加载',
      ImageLoadMode.noImages => '无图模式',
    };
  }

  String get description {
    return switch (this) {
      ImageLoadMode.automatic => '滚动到图片时自动加载并缓存。',
      ImageLoadMode.wifiOnly => '移动网络下先显示占位，点击后再加载。',
      ImageLoadMode.manual => '所有帖子图片默认占位，点击后加载。',
      ImageLoadMode.noImages => '隐藏论坛图片、表情、头像和预览截图，保留文字与链接。',
    };
  }
}
