import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ImageLoadMode {
  automatic,
  wifiOnly,
  manual,
}

class ImageLoadingSettings {
  ImageLoadingSettings._();

  static const _modeKey = 'settings.imageLoadMode';
  static const _networkChannel =
      MethodChannel('south_plus_rewrite/network_state');

  static Future<ImageLoadMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_modeKey);
    return ImageLoadMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ImageLoadMode.automatic,
    );
  }

  static Future<void> saveMode(ImageLoadMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  static Future<bool> canAutoLoadImages() async {
    final mode = await loadMode();
    return switch (mode) {
      ImageLoadMode.automatic => true,
      ImageLoadMode.manual => false,
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
    };
  }

  String get description {
    return switch (this) {
      ImageLoadMode.automatic => '滚动到图片时自动加载并缓存。',
      ImageLoadMode.wifiOnly => '移动网络下先显示占位，点击后再加载。',
      ImageLoadMode.manual => '所有帖子图片默认占位，点击后加载。',
    };
  }
}
