import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(WatchNotifications.channel, null);
    WatchNotifications().listen(null);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform opens app notification settings through native completion',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(WatchNotifications.channel,
          (call) async {
        calls.add(call);
        return true;
      });
      expect(await WatchNotifications().openSettings(), isTrue);
      expect(calls.map((call) => call.method), ['openSettings']);
    });
  }

  test('unsupported platform never requests native notification settings',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var calls = 0;
    messenger.setMockMethodCallHandler(WatchNotifications.channel, (_) async {
      calls++;
      return true;
    });
    expect(await WatchNotifications().openSettings(), isFalse);
    expect(calls, 0);
  });

  test(
      'Android lease forwards enabled request identity and reports actual native state',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <MethodCall>[];
    var running = true;
    messenger.setMockMethodCallHandler(WatchNotifications.channel,
        (call) async {
      calls.add(call);
      return running;
    });
    final notifications = WatchNotifications();
    expect(
        await notifications.setBackgroundPolling(enabled: true, requestId: 7),
        isTrue);
    running = false;
    expect(
        await notifications.setBackgroundPolling(enabled: false, requestId: 8),
        isFalse);
    expect(calls.map((call) => call.method),
        ['setBackgroundPolling', 'setBackgroundPolling']);
    expect(calls.first.arguments, {'enabled': true, 'requestId': 7});
    expect(calls.last.arguments, {'enabled': false, 'requestId': 8});
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
    test('$platform never starts an Android background lease', () async {
      debugDefaultTargetPlatformOverride = platform;
      var calls = 0;
      messenger.setMockMethodCallHandler(WatchNotifications.channel, (_) async {
        calls++;
        return true;
      });
      expect(
          await WatchNotifications()
              .setBackgroundPolling(enabled: true, requestId: 9),
          isFalse);
      expect(calls, 0);
    });
  }

  for (final failure in ['denied', 'missing', 'platform']) {
    test(
        'native $failure never becomes successful settings or lease acknowledgement',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(WatchNotifications.channel, (_) async {
        if (failure == 'missing') throw MissingPluginException();
        if (failure == 'platform') throw PlatformException(code: 'denied');
        return false;
      });
      final notifications = WatchNotifications();
      expect(await notifications.openSettings(), isFalse);
      expect(
          await notifications.setBackgroundPolling(
              enabled: true, requestId: 10),
          isFalse);
    });
  }

  test('native stop identities dispatch without swallowing notification taps',
      () async {
    final notifications = WatchNotifications();
    final stopped = <int>[];
    var taps = 0;
    notifications.onBackgroundStopped = stopped.add;
    notifications.listen(() async {
      taps++;
    });
    Future<void> receive(String method, Object? arguments) async {
      final completed = Completer<void>();
      ui.channelBuffers.push(
        WatchNotifications.channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, arguments)),
        (_) => completed.complete(),
      );
      await completed.future;
    }

    await receive('tap', null);
    await receive('backgroundStopped', 21);
    await receive('backgroundStopped', 22);
    for (final invalid in [
      null,
      -1,
      '22',
      1.5,
      {'requestId': 22}
    ]) {
      await receive('backgroundStopped', invalid);
    }
    expect(taps, 1);
    expect(stopped, [21, 22]);
  });
}
