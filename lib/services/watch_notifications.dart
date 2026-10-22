import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/watch_models.dart';

enum WatchNotificationPermission { granted, denied, unsupported }

class WatchNotifications {
  static const channel = MethodChannel(
    'south_plus_rewrite/watch_notifications',
  );

  void listen(Future<void> Function()? onTap) {
    channel.setMethodCallHandler(
      onTap == null
          ? null
          : (call) async {
              if (call.method == 'tap') await onTap();
            },
    );
  }

  Future<WatchNotificationPermission> permission({bool request = false}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return WatchNotificationPermission.unsupported;
    }
    try {
      final granted = await channel.invokeMethod<bool>(
        request ? 'requestPermission' : 'permission',
      );
      return granted == true
          ? WatchNotificationPermission.granted
          : WatchNotificationPermission.denied;
    } on MissingPluginException {
      return WatchNotificationPermission.unsupported;
    } on PlatformException {
      return WatchNotificationPermission.denied;
    }
  }

  Future<void> show(String owner, WatchEvent event) async {
    try {
      await channel.invokeMethod<void>('show', {
        'owner': owner,
        'eventId': event.id,
      });
    } on MissingPluginException {
      // Unsupported platforms retain the in-app event.
    } on PlatformException {
      // A revoked permission must not discard a persisted event.
    }
  }

  Future<void> cancelAll() async {
    try {
      await channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      // Unsupported platforms do not have pending native notifications.
    } on PlatformException {
      // Account guards also reject any stale notification taps.
    }
  }

  Future<Map<String, dynamic>?> takeTap() async {
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>('takeTap');
      return raw;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
