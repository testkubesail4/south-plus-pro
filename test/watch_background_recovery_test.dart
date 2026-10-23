import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

import 'watch_background_lease_test.dart' as leases;
import 'watch_service_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  late fixtures.Rig rig;
  late leases.LeaseNotices notices;
  late WatchService service;
  Completer<bool>? acknowledgement;
  Completer<void>? writeStarted;
  var nativeChecks = 0;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    acknowledgement = null;
    writeStarted = null;
    nativeChecks = 0;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final held = acknowledgement;
      if (held != null) {
        acknowledgement = null;
        writeStarted!.complete();
        if (!await held.future) return false;
      }
      final args = call.arguments as Map;
      persisted[args['key'] as String] = args['value'] as Object;
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(preferences, null);
  });

  void startEligible(FakeAsync async) {
    rig = fixtures.Rig();
    notices = leases.LeaseNotices();
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
    service.addRule(fixtures.rule('eligible')).then((_) => service.start());
    async.flushMicrotasks();
    expect(notices.activeId, isNotNull);
    expect(service.nextCheckAt, isNotNull);
  }

  test('failed pause while backgrounding restores actual polling', () {
    fakeAsync((async) {
      try {
        startEligible(async);
        final lease = notices.activeId;
        final before = nativeChecks;
        final reads = rig.client.paths.length;
        final ack = acknowledgement = Completer<bool>();
        writeStarted = Completer<void>();
        Object? error;
        service.setPaused('eligible', true).then<void>((_) {},
            onError: (Object failure) {
          error = failure;
        });
        async.flushMicrotasks();
        expect(writeStarted!.isCompleted, isTrue);
        service.didChangeAppLifecycleState(AppLifecycleState.paused);
        expect(service.nextCheckAt, isNull);
        ack.complete(false);
        async.flushMicrotasks();
        expect(error, isStateError);
        expect(service.rules.single.paused, isFalse);
        expect(notices.activeId, lease);

        rig.now = rig.now.add(WatchService.interval);
        async.elapse(WatchService.interval);
        async.flushMicrotasks();
        expect(nativeChecks, before + 1);
        expect(rig.client.paths.length, greaterThan(reads));
      } finally {
        service.dispose();
        rig.dispose();
        async.flushMicrotasks();
      }
    });
  });

  test('syncing a valid lease preserves its scheduled deadline', () {
    fakeAsync((async) {
      try {
        startEligible(async);
        service.didChangeAppLifecycleState(AppLifecycleState.paused);
        final deadline = service.nextCheckAt;
        final before = nativeChecks;
        const elapsed = Duration(minutes: 5);
        rig.now = rig.now.add(elapsed);
        async.elapse(elapsed);
        service.markRead('missing-event');
        async.flushMicrotasks();
        expect(service.nextCheckAt, deadline);

        rig.now = rig.now.add(WatchService.interval - elapsed);
        async.elapse(WatchService.interval - elapsed);
        async.flushMicrotasks();
        expect(nativeChecks, before + 1);
      } finally {
        service.dispose();
        rig.dispose();
        async.flushMicrotasks();
      }
    });
  });
}
