import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/watch_models.dart';

enum WatchNotificationPermission { granted, denied, unsupported }

enum NoticeNotificationKind { pm, reply }

class WatchNotifications {
  static const channel = MethodChannel(
    'south_plus_rewrite/watch_notifications',
  );

  void Function(int requestId)? onBackgroundStopped;

  void listen(Future<void> Function()? onTap) {
    channel.setMethodCallHandler(
      onTap == null
          ? null
          : (call) async {
              if (call.method == 'tap') {
                await onTap();
              } else if (call.method == 'backgroundStopped') {
                final requestId = call.arguments;
                if (requestId is int && requestId >= 0) {
                  onBackgroundStopped?.call(requestId);
                }
              }
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

  Future<bool> showNotice(
    String owner,
    String eventId,
    NoticeNotificationKind kind,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('show', {
            'owner': owner,
            'eventId': eventId,
            'kind': kind.name,
          }) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> cancelKind(String owner, NoticeNotificationKind kind) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await channel.invokeMethod<void>('cancelKind', {
        'owner': owner,
        'kind': kind.name,
      });
    } on MissingPluginException {
      // Unsupported platforms retain their existing in-app notices.
    } on PlatformException {
      // Cancellation failure cannot change forum read state.
    }
  }

  Future<bool> setBackgroundPolling({
    required bool enabled,
    required int requestId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('setBackgroundPolling', {
            'enabled': enabled,
            'requestId': requestId,
          }) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> openSettings() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }
    try {
      return await channel.invokeMethod<bool>('openSettings') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
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
