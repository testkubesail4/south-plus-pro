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
  static const _playInlineKey = 'settings.playInlineAnimations';
  static final playInline = ValueNotifier<bool>(false);
  static const _networkChannel =
      MethodChannel('south_plus_rewrite/network_state');
  static final notifier = ValueNotifier<ImageLoadMode?>(null);
  static Future<ImageLoadMode>? _modeFuture;
  static Future<bool>? _wifiCheck;

  static Future<ImageLoadMode> loadMode() async {
    final cached = notifier.value;
    if (cached != null) return cached;
    final inFlight = _modeFuture;
    if (inFlight != null) return inFlight;
    return _modeFuture = _loadMode();
  }

  static Future<ImageLoadMode> _loadMode() =>
      LocalStatePreferences.read((prefs) {
        playInline.value = prefs.getBool(_playInlineKey) ?? false;
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
          notifier.value = mode;
        }
        return saved;
      });

  static Future<void> savePlayInline(bool value) =>
      LocalStatePreferences.write((prefs) async {
        final saved = await prefs.setBool(_playInlineKey, value);
        if (saved) playInline.value = value;
        return saved;
      });

  static Future<bool> canAutoLoadImages() async {
    final mode = await loadMode();
    return switch (mode) {
      ImageLoadMode.automatic => true,
      ImageLoadMode.manual || ImageLoadMode.noImages => false,
      ImageLoadMode.wifiOnly => _wifiCheck ??=
          isOnWifi().whenComplete(() => _wifiCheck = null),
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
}
