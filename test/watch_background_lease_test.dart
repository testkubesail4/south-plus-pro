import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

import 'watch_service_test.dart' as fixtures;

class LeaseNotices extends fixtures.Notices {
  final requests = <(bool, int)>[];
  bool allowStart = true;
  int permissionChecks = 0;
  int? activeId;
  Completer<bool>? startResult;
  Completer<int>? startEntered;

  @override
  Future<WatchNotificationPermission> permission({bool request = false}) async {
    permissionChecks++;
    return granted;
  }

  @override
  Future<bool> setBackgroundPolling({
    required bool enabled,
    required int requestId,
  }) async {
    requests.add((enabled, requestId));
    if (!enabled) {
      final stopped = activeId;
      activeId = null;
      if (stopped != null) onBackgroundStopped?.call(stopped);
      return false;
    }
    final result = startResult;
    startResult = null;
    startEntered?.complete(requestId);
    startEntered = null;
    final accepted = result == null ? allowStart : await result.future;
    if (accepted) activeId = requestId;
    return accepted;
  }
}

Future<void> settleLease() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixtures.Rig rig;
  late LeaseNotices notices;
  late WatchService service;
  var signedIn = true;
  var nativeChecks = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    signedIn = true;
    nativeChecks = 0;
    rig = fixtures.Rig();
    notices = LeaseNotices();
    service = WatchService(
      session: () => signedIn ? rig.service.session() : null,
      notifications: notices,
      clock: () => rig.now,
      checkNativeNotices: (scope, reserve, guard) async {
        guard();
        nativeChecks++;
        return null;
      },
    );
  });

  tearDown(() async {
    service.dispose();
    rig.dispose();
    await settleLease();
    SharedPreferences.resetStatic();
  });

  Future<void> startEligible() async {
    await service.addRule(fixtures.rule('eligible'));
    await service.start();
    await settleLease();
  }

  Future<void> changeEligibility(String change) async {
    switch (change) {
      case 'logout':
        signedIn = false;
        service.sessionChanged();
      case 'account':
        rig.owner = 'replacement-owner';
        rig.epoch++;
        service.sessionChanged();
      case 'pause':
        await service.setPaused('eligible', true);
      case 'remove':
        await service.removeRule('eligible');
      case 'notifications':
        await service.updateRule(WatchRule.fromJson({
          ...service.rules.single.toJson(),
          'notificationsEnabled': false,
        }));
      case 'permission':
        notices.granted = WatchNotificationPermission.denied;
        await service.requestNotifications();
      case 'stop':
        service.stop();
      case 'detach':
        service.didChangeAppLifecycleState(AppLifecycleState.detached);
    }
    await settleLease();
  }

  test('accepted lease permits background Watch plus native notices', () async {
    await startEligible();
    expect(notices.activeId, isNotNull);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(service.nextCheckAt, rig.now.add(WatchService.interval));
    final before = nativeChecks;
    final permissionChecks = notices.permissionChecks;
    rig.client.respond = (_) async => fixtures.thread(fixtures.post('101'));
    await service.checkNow();
    expect(nativeChecks, before + 1);
    expect(notices.permissionChecks, permissionChecks + 1);
    expect(service.events.single.pid, '101');
    expect(notices.shown, hasLength(1));
    expect(service.nextCheckAt, rig.now.add(WatchService.interval));
  });

  for (final reason in [
    'no rules',
    'paused',
    'silent',
    'denied',
    'unsupported',
    'guest'
  ]) {
    test('$reason does not create a lease or background native polling',
        () async {
      if (reason == 'paused') {
        await service.addRule(fixtures.rule('eligible', paused: true));
      } else if (reason == 'silent') {
        await service.addRule(WatchRule.fromJson({
          ...fixtures.rule('eligible').toJson(),
          'notificationsEnabled': false,
        }));
      } else if (reason != 'no rules' && reason != 'guest') {
        await service.addRule(fixtures.rule('eligible'));
      }
      if (reason == 'denied')
        notices.granted = WatchNotificationPermission.denied;
      if (reason == 'unsupported')
        notices.granted = WatchNotificationPermission.unsupported;
      if (reason == 'guest') signedIn = false;
      await service.start();
      await settleLease();
      expect(notices.requests, isEmpty);
      final before = nativeChecks;
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await service.checkNow();
      expect(nativeChecks, before);
      expect(service.nextCheckAt, isNull);
    });
  }

  test('a denied native start retains foreground-only polling', () async {
    notices.allowStart = false;
    await startEligible();
    expect(notices.requests.any((r) => r.$1), isTrue);
    expect(notices.activeId, isNull);
    final before = nativeChecks;
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.checkNow();
    expect(nativeChecks, before);
    expect(service.nextCheckAt, isNull);
  });

  test(
      'pending start is not a lease; only actual acknowledgement opens background polling',
      () async {
    final entered = notices.startEntered = Completer<int>();
    final accepted = notices.startResult = Completer<bool>();
    await service.addRule(fixtures.rule('eligible'));
    await service.start();
    final id = await entered.future.timeout(const Duration(seconds: 2));
    notices.onBackgroundStopped!(id + 1000000);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final before = nativeChecks;
    await service.checkNow();
    expect(nativeChecks, before);
    expect(service.nextCheckAt, isNull);
    accepted.complete(true);
    await settleLease();
    expect(service.nextCheckAt, isNotNull);
    await service.checkNow();
    expect(nativeChecks, before + 1);
  });

  for (final change in [
    'logout',
    'account',
    'pause',
    'remove',
    'notifications',
    'permission',
    'stop',
    'detach'
  ]) {
    test('$change stops an accepted native lease and background work',
        () async {
      await startEligible();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await changeEligibility(change);
      expect(notices.activeId, isNull);
      expect(notices.requests.last.$1, isFalse);
      final before = nativeChecks;
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await service.checkNow();
      expect(nativeChecks, before);
      expect(service.nextCheckAt, isNull);
    });

    test('$change compensates a stale accepted start', () async {
      final entered = notices.startEntered = Completer<int>();
      final accepted = notices.startResult = Completer<bool>();
      await service.addRule(fixtures.rule('eligible'));
      await service.start();
      await entered.future.timeout(const Duration(seconds: 2));
      await changeEligibility(change);
      accepted.complete(true);
      await settleLease();
      expect(notices.activeId, isNull);
      expect(notices.requests.last.$1, isFalse);
      final before = nativeChecks;
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await service.checkNow();
      expect(nativeChecks, before);
      expect(service.nextCheckAt, isNull);
    });
  }

  test(
      'latest enabled desire replaces a cancelled pending start without stale-stop interference',
      () async {
    final entered = notices.startEntered = Completer<int>();
    final accepted = notices.startResult = Completer<bool>();
    await service.addRule(fixtures.rule('eligible'));
    await service.start();
    final oldId = await entered.future.timeout(const Duration(seconds: 2));
    await service.setPaused('eligible', true);
    await service.setPaused('eligible', false);
    accepted.complete(true);
    await settleLease();
    final newId = notices.activeId!;
    expect(newId, greaterThan(oldId));
    expect(notices.requests.map((r) => r.$1), [true, false, true]);
    notices.onBackgroundStopped!(oldId);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final before = nativeChecks;
    await service.checkNow();
    expect(nativeChecks, before + 1);
  });

  testWidgets('accepted lease keeps the 15-minute timer alive in background',
      (tester) async {
    service.dispose();
    service = WatchService(
      session: rig.service.session,
      notifications: notices,
      clock: () => rig.now,
      checkNativeNotices: (scope, reserve, guard) async {
        guard();
        nativeChecks++;
        return null;
      },
    );
    await service.addRule(fixtures.rule('eligible'));
    await service.start();
    await tester.pump();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final before = nativeChecks;
    rig.now = rig.now.add(WatchService.interval);
    await tester.pump(WatchService.interval);
    await tester.pump();
    expect(nativeChecks, before + 1);
    expect(service.nextCheckAt, rig.now.add(WatchService.interval));
    service.stop();
  });

  test('background budget exhaustion retains the five-minute continuation',
      () async {
    service.dispose();
    var exhaust = false;
    service = WatchService(
      session: rig.service.session,
      notifications: notices,
      clock: () => rig.now,
      checkNativeNotices: (scope, reserve, guard) async {
        guard();
        if (exhaust) {
          for (var i = 0; i <= WatchService.maxSends; i++) {
            reserve();
          }
        }
        return null;
      },
    );
    await startEligible();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    exhaust = true;
    await service.checkNow();
    expect(service.pendingUntil, rig.now.add(WatchService.budgetWindow));
    expect(service.nextCheckAt, service.pendingUntil);
    expect(notices.activeId, isNotNull);
  });

  test('dispose compensates a late start and unregisters callbacks', () async {
    final entered = notices.startEntered = Completer<int>();
    final accepted = notices.startResult = Completer<bool>();
    await service.addRule(fixtures.rule('eligible'));
    await service.start();
    await entered.future.timeout(const Duration(seconds: 2));
    service.dispose();
    accepted.complete(true);
    await settleLease();
    expect(notices.activeId, isNull);
    expect(notices.requests.last.$1, isFalse);
    expect(notices.onTap, isNull);
    expect(notices.onBackgroundStopped, isNull);
    // Use a fresh unstarted instance for the shared tearDown.
    service = WatchService(session: () => null, notifications: LeaseNotices());
  });

  test(
      'stopped before the matching true acknowledgement cannot resurrect a lease',
      () async {
    final entered = notices.startEntered = Completer<int>();
    final accepted = notices.startResult = Completer<bool>();
    await service.addRule(fixtures.rule('eligible'));
    await service.start();
    final id = await entered.future.timeout(const Duration(seconds: 2));
    notices.onBackgroundStopped!(id);
    accepted.complete(true);
    await settleLease();
    expect(notices.activeId, isNull);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final before = nativeChecks;
    await service.checkNow();
    expect(nativeChecks, before);
    expect(service.nextCheckAt, isNull);
  });

  test('stale stopped callbacks cannot close a replacement lease', () async {
    await startEligible();
    final oldId = notices.activeId!;
    service.stop();
    await settleLease();
    await service.start();
    await settleLease();
    final replacementId = notices.activeId!;
    expect(replacementId, greaterThan(oldId));
    notices.onBackgroundStopped!(oldId);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final before = nativeChecks;
    await service.checkNow();
    expect(nativeChecks, before + 1);
    notices.onBackgroundStopped!(replacementId);
    expect(service.nextCheckAt, isNull);
    await service.checkNow();
    expect(nativeChecks, before + 1);
  });

  test('lease IDs do not repeat across service recreation in the same engine',
      () async {
    await startEligible();
    final oldId = notices.activeId!;
    service.dispose();
    await settleLease();
    service = WatchService(
      session: rig.service.session,
      notifications: notices,
      clock: () => rig.now,
    );
    await service.start();
    await settleLease();
    final newId = notices.activeId!;
    expect(newId, greaterThan(oldId));
    notices.onBackgroundStopped!(oldId);
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(service.nextCheckAt, isNotNull);
  });

  test('global permission is refreshed before any later background HTTP',
      () async {
    await startEligible();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    notices.granted = WatchNotificationPermission.denied;
    final before = nativeChecks;
    final requests = rig.client.paths.length;
    await service.checkNow();
    await settleLease();
    expect(service.notificationPermission, WatchNotificationPermission.denied);
    expect(nativeChecks, before);
    expect(rig.client.paths, hasLength(requests));
    expect(notices.activeId, isNull);
    expect(service.nextCheckAt, isNull);
  });

  test('native stop cancels an already awaiting background response', () async {
    await startEligible();
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    final entered = Completer<void>();
    final response = Completer<String>();
    rig.client.respond = (_) {
      entered.complete();
      return response.future;
    };
    final checking = service.checkNow();
    final rejected = expectLater(checking, throwsStateError);
    await entered.future.timeout(const Duration(seconds: 2));
    notices.onBackgroundStopped!(notices.activeId!);
    response.complete(fixtures.thread(fixtures.post('101')));
    await rejected;
    expect(service.events, isEmpty);
    expect(notices.shown, isEmpty);
    expect(service.nextCheckAt, isNull);
  });
}
