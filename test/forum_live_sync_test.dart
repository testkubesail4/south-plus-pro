import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_live_sync.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';

void main() {
  testWidgets('overlapping entry and pull share one check and one busy signal',
      (tester) async {
    final held = Completer<void>();
    var checks = 0;
    final service = ForumLiveSync(checkMessages: () {
      checks++;
      return held.future;
    });
    addTearDown(service.dispose);
    final busy = <bool>[];
    service.messagesSyncing.addListener(() {
      busy.add(service.messagesSyncing.value);
    });
    final entry = service.syncMessages();
    final pull = service.syncMessages(user: true);
    expect(checks, 1);
    expect(busy, [true]);
    held.complete();
    await Future.wait([entry, pull]);
    expect(busy, [true, false]);
  });

  testWidgets(
      'background failures stay quiet; user intent receives the failure',
      (tester) async {
    final service = ForumLiveSync(
      checkMessages: () => Future.error(StateError('offline')),
    );
    addTearDown(service.dispose);
    final quiet = service.syncMessages();
    final user = service.syncMessages(user: true);
    await expectLater(user, throwsStateError);
    await quiet;
    expect(service.messagesSyncing.value, isFalse);
  });

  testWidgets(
      'one foreground timer checks messages and invalidates home at five minutes',
      (tester) async {
    var now = DateTime.utc(2026);
    var checks = 0;
    final service = ForumLiveSync(
      clock: () => now,
      checkMessages: () async => checks++,
    );
    addTearDown(service.dispose);
    service.start();
    service.start();
    for (var minute = 1; minute <= 5; minute++) {
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(checks, minute);
      expect(service.homeRevision.value, minute == 5 ? 1 : 0);
    }
    service.stop();
    now = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(minutes: 10));
    expect(checks, 5);
    expect(service.homeRevision.value, 1);
  });

  testWidgets(
      'long resume refreshes once; brief interruptions and paused timers do not',
      (tester) async {
    var now = DateTime.utc(2026);
    var checks = 0;
    final service = ForumLiveSync(
      clock: () => now,
      checkMessages: () async => checks++,
    );
    addTearDown(service.dispose);
    service.start();
    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 10));
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(checks, 0);
    service.didChangeAppLifecycleState(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 10));
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(checks, 0);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(checks, 1);
    expect(service.homeRevision.value, 1);
    service.didChangeAppLifecycleState(AppLifecycleState.detached);
    await tester.pump(const Duration(minutes: 5));
    expect(checks, 1);
  });

  testWidgets(
      'only the foreground receives notices; session change removes old content',
      (tester) async {
    final service = ForumLiveSync(checkMessages: () async {});
    addTearDown(service.dispose);
    service.noticeReceived(NoticeNotificationKind.pm, 1, 'Before start');
    expect(service.latestNotice.value, isNull);
    service.start();
    service.noticeReceived(NoticeNotificationKind.pm, 2, 'Subject');
    final first = service.latestNotice.value!;
    expect(first.kind, NoticeNotificationKind.pm);
    expect(first.count, 2);
    expect(first.title, 'Subject');
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    service.noticeReceived(NoticeNotificationKind.reply, 1, 'Hidden');
    expect(service.latestNotice.value, same(first));
    service.sessionChanged();
    expect(service.latestNotice.value, isNull);
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    service.noticeReceived(NoticeNotificationKind.reply, 1, 'Reply');
    expect(service.latestNotice.value!.serial, greaterThan(first.serial));
    service.stop();
  });
}
