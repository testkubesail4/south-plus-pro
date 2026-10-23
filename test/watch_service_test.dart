import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

String post(
  String id, {
  String uid = '8',
  int floor = 1,
  String body = 'body',
}) =>
    '<table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-$uid.html"><strong>User</strong></a></th>'
    '<th class="r_one" id="td_$id"><div class="tiptop"><span class="fl"><a class="s3">B${floor}F</a></span></div>'
    '<div class="tpc_content"><div id="read_$id">$body</div></div></th></tr></table>';
String thread(String rows, {int page = 1, int pages = 1, int tid = 70}) =>
    '<h1 id="subject_tpc">Thread title</h1><a href="read.php?tid-$tid.html">Thread</a>'
    '<div class="pages">Pages: $page/$pages</div>$rows';
String row(
  int id, {
  int tid = 70,
  bool reply = true,
  String title = 'Thread title',
}) =>
    '<tr><td><a href="${reply ? 'job.php?action-topost-tid-$tid-pid-$id.html' : 'read.php?tid-$id.html'}">$title</a></td></tr>';
String list(
  String rows, {
  String action = 'post',
  int page = 1,
  int pages = 1,
}) =>
    '<div id="u-contentmain"><table class="u-table">$rows</table>'
    '${pages == 1 ? '' : '<div class="pages">Pages: $page/$pages<a href="u.php?action-$action-uid-8-page-$pages.html">»</a></div>'}</div>';
int pageOf(String path) =>
    int.tryParse(RegExp(r'page-(\d+)').firstMatch(path)?.group(1) ?? '') ?? 1;
WatchRule rule(
  String id, {
  WatchScope scope = WatchScope.thread,
  String subject = '70',
  Set<WatchContentKind> kinds = const {WatchContentKind.replies},
  String keyword = '',
  WatchKeywordField field = WatchKeywordField.body,
  String? involving,
  bool paused = false,
}) =>
    WatchRule(
      id: id,
      scope: scope,
      subjectId: subject,
      label: 'Synthetic target',
      kinds: kinds,
      keyword: keyword,
      keywordField: field,
      involvingUid: involving,
      paused: paused,
    );

class Notices extends WatchNotifications {
  final shown = <WatchEvent>[];
  int cancels = 0;
  Map<String, dynamic>? tap;
  Future<void> Function()? onTap;
  Completer<void>? tapTaken;
  WatchNotificationPermission granted = WatchNotificationPermission.granted;
  @override
  Future<WatchNotificationPermission> permission({
    bool request = false,
  }) async =>
      granted;
  @override
  Future<void> show(String owner, WatchEvent event) async {
    shown.add(event);
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    tap = null;
  }

  @override
  Future<Map<String, dynamic>?> takeTap() async {
    final value = tap;
    tap = null;
    tapTaken?.complete();
    tapTaken = null;
    return value;
  }

  @override
  void listen(Future<void> Function()? callback) => onTap = callback;
}

class SourceClient extends ForumClient {
  Future<String> Function(String) respond = (_) async => thread(post('100'));
  final paths = <String>[];
  @override
  Future<String> getWatch(
    String path, {
    required void Function() requireCurrentSession,
    required void Function() beforeSend,
  }) async {
    requireCurrentSession();
    beforeSend();
    paths.add(path);
    final response = await respond(path);
    requireCurrentSession();
    return response;
  }
}

class Rig {
  final client = SourceClient();
  final notices = Notices();
  final urls = ForumUrlResolver();
  String owner = 'synthetic-owner';
  int epoch = 0;
  DateTime now = DateTime.utc(2026);
  late final WatchService service = WatchService(
    session: () {
      final savedOwner = owner;
      final savedEpoch = epoch;
      return WatchSession(
        owner: savedOwner,
        uid: '9',
        epoch: savedEpoch,
        client: client,
        urls: urls,
        requireCurrent: () {
          if (owner != savedOwner || epoch != savedEpoch)
            throw StateError('stale owner');
        },
      );
    },
    notifications: notices,
    clock: () => now,
  );
  void dispose() {
    service.dispose();
    client.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var preferenceWrites = 0;
  var preferenceReads = 0;
  var rejectReads = false;
  var rejectWrites = false;
  Completer<void>? heldRead;
  Completer<void>? readStarted;
  late Map<String, Object> stored;
  setUp(() {
    preferenceWrites = 0;
    preferenceReads = 0;
    rejectReads = false;
    rejectWrites = false;
    heldRead = null;
    readStarted = null;
    SharedPreferences.resetStatic();
    stored = <String, Object>{};
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'getAll') {
        preferenceReads++;
        final held = heldRead;
        if (held != null) {
          heldRead = null;
          readStarted!.complete();
          await held.future;
        }
        if (rejectReads) throw PlatformException(code: 'fixture-read-failure');
        return Map<String, Object>.of(stored);
      }
      final args = call.arguments as Map;
      preferenceWrites++;
      if (rejectWrites) return false;
      if (call.method == 'remove') {
        stored.remove(args['key']);
      } else {
        stored[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
  });
  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(preferences, null);
  });

  test('failed watch read recovers and coalesces checks in the same session',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.service.addRule(rule('durable'));
    await rig.service.checkNow();
    SharedPreferences.resetStatic();
    rejectReads = true;
    final restored =
        WatchService(session: rig.service.session, notifications: rig.notices);
    addTearDown(restored.dispose);
    final writes = preferenceWrites;
    await expectLater(restored.checkNow(), throwsStateError);
    expect(restored.statuses['storage']!.phase, WatchPhase.unavailable);
    expect(restored.rules, isEmpty);
    expect(preferenceWrites, writes);
    rejectReads = false;
    final reads = preferenceReads;
    final first = restored.checkNow();
    final second = restored.checkNow();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(preferenceReads, reads + 1);
    expect(restored.statuses.containsKey('storage'), isFalse);
    expect(restored.rules.map((r) => r.id), ['durable']);
    expect(restored.events, isEmpty, reason: 'saved baseline is not reset');
    await restored.checkNow();
    expect(restored.rules, hasLength(1));
    expect(restored.events, isEmpty);
  });

  test('unreadable watch state does not block native polls or validated taps',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    final raw = jsonEncode({
      'rules': [rule('saved').toJson()],
      'events': [],
      'states': {'saved/replies': 42},
    });
    stored['flutter.account/${rig.owner}/watch_v1'] = raw;
    var nativeChecks = 0;
    rig.notices.tap = {
      'owner': rig.owner,
      'eventId': 'issued',
      'kind': 'pm',
    };
    final service = WatchService(
      session: rig.service.session,
      notifications: rig.notices,
      checkNativeNotices: (scope, reserve, guard) async {
        guard();
        nativeChecks++;
        return null;
      },
      acceptNativeNoticeTap: (tap) async => tap['eventId'] == 'issued',
    );
    addTearDown(service.dispose);
    await expectLater(service.checkNow(), throwsStateError);
    expect(nativeChecks, 1);
    expect(service.takePendingNoticeOpen(), NoticeNotificationKind.pm);
    expect(service.rules, isEmpty, reason: 'decode is published atomically');
    expect(service.events, isEmpty);
    expect(service.statuses.containsKey('storage'), isTrue);
    await expectLater(service.addRule(rule('blocked')), throwsStateError);
    expect(preferenceWrites, 0);
    expect(stored['flutter.account/${rig.owner}/watch_v1'], raw);
  });

  for (final kind in NoticeNotificationKind.values) {
    for (final overlap in [false, true]) {
      test('newer ${kind.name} tap supersedes deferred Watch; overlap=$overlap',
          () async {
        final rig = Rig();
        addTearDown(rig.dispose);
        await rig.service.addRule(rule('durable'));
        await rig.service.checkNow();
        rig.client.respond = (_) async => thread(post('101'));
        await rig.service.checkNow();
        final event = rig.service.events.single;
        SharedPreferences.resetStatic();
        rejectReads = true;
        final notices = Notices()
          ..tap = {'owner': rig.owner, 'eventId': event.id};
        final service = WatchService(
          session: rig.service.session,
          notifications: notices,
          acceptNativeNoticeTap: (tap) async => tap['eventId'] == 'issued',
        );
        addTearDown(service.dispose);
        await service.start();
        expect(service.statuses.containsKey('storage'), isTrue);
        expect(service.pendingOpen, isNull);
        rejectReads = false;
        Future<void>? recovery;
        Future<void>? oldTap;
        Completer<void>? released;
        if (overlap) {
          released = heldRead = Completer<void>();
          readStarted = Completer<void>();
          recovery = service.checkNow();
          await readStarted!.future.timeout(const Duration(seconds: 2));
          notices.tap = {'owner': rig.owner, 'eventId': event.id};
          final taken = notices.tapTaken = Completer<void>();
          oldTap = notices.onTap!();
          await taken.future.timeout(const Duration(seconds: 2));
        }
        try {
          notices.tap = {
            'owner': rig.owner,
            'eventId': 'issued',
            'kind': kind.name,
          };
          if (overlap) {
            await notices.onTap!();
            expect(service.pendingNoticeOpen, kind);
          } else {
            await service.checkNow();
          }
        } finally {
          released?.complete();
        }
        await oldTap;
        await recovery;
        expect(service.takePendingNoticeOpen(), kind);
        expect(service.takePendingOpen(), isNull);
        expect(service.events.single.unread, isTrue);
      });
    }
  }

  test('invalid native taps preserve a deferred Watch intent', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.service.addRule(rule('durable'));
    await rig.service.checkNow();
    rig.client.respond = (_) async => thread(post('101'));
    await rig.service.checkNow();
    final event = rig.service.events.single;
    SharedPreferences.resetStatic();
    rejectReads = true;
    final notices = Notices()..tap = {'owner': rig.owner, 'eventId': event.id};
    final service = WatchService(
      session: rig.service.session,
      notifications: notices,
      acceptNativeNoticeTap: (tap) async => tap['eventId'] == 'issued',
    );
    addTearDown(service.dispose);
    await expectLater(service.checkNow(), throwsStateError);
    for (final tap in [
      {'owner': 'stale-owner', 'eventId': 'issued', 'kind': 'pm'},
      {'owner': rig.owner, 'eventId': 'not-in-ledger', 'kind': 'reply'},
    ]) {
      notices.tap = tap;
      await expectLater(service.checkNow(), throwsStateError);
      expect(service.pendingNoticeOpen, isNull);
    }
    rejectReads = false;
    await service.checkNow();
    expect(service.takePendingOpen()!.id, event.id);
    expect(service.takePendingOpen(), isNull);
  });

  test('watch tap survives transient storage failure until its event is loaded',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.service.addRule(rule('durable'));
    await rig.service.checkNow();
    rig.client.respond = (_) async => thread(post('101'));
    await rig.service.checkNow();
    final event = rig.service.events.single;
    SharedPreferences.resetStatic();
    rejectReads = true;
    final notices = Notices()..tap = {'owner': rig.owner, 'eventId': event.id};
    final service =
        WatchService(session: rig.service.session, notifications: notices);
    addTearDown(service.dispose);
    await expectLater(service.checkNow(), throwsStateError);
    expect(service.pendingOpen, isNull);
    rejectReads = false;
    await service.checkNow();
    expect(service.takePendingOpen()!.id, event.id);
    expect(service.takePendingOpen(), isNull);
    expect(service.events.single.unread, isTrue);
    expect(service.rules, hasLength(1));
  });

  test('account switch during recovery discards the old load and deferred tap',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.service.addRule(rule('private'));
    await rig.service.checkNow();
    rig.client.respond = (_) async => thread(post('101'));
    await rig.service.checkNow();
    final event = rig.service.events.single;
    final saved = Map<String, Object>.of(stored);
    final writes = preferenceWrites;
    SharedPreferences.resetStatic();
    rejectReads = true;
    final notices = Notices()..tap = {'owner': rig.owner, 'eventId': event.id};
    final service =
        WatchService(session: rig.service.session, notifications: notices);
    addTearDown(service.dispose);
    await expectLater(service.checkNow(), throwsStateError);
    rejectReads = false;
    final released = heldRead = Completer<void>();
    readStarted = Completer<void>();
    final retry = service.checkNow();
    final rejected = expectLater(retry, throwsStateError);
    try {
      await readStarted!.future.timeout(const Duration(seconds: 2));
      rig.owner = 'next-owner';
      rig.epoch++;
      service.sessionChanged();
    } finally {
      released.complete();
    }
    await rejected;
    await service.checkNow();
    expect(service.rules, isEmpty);
    expect(service.events, isEmpty);
    expect(service.pendingOpen, isNull);
    expect(preferenceWrites, writes);
    expect(stored, saved);
  });

  test('native request budget cannot prevent local watch-store recovery',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.service.addRule(rule('durable'));
    await rig.service.checkNow();
    SharedPreferences.resetStatic();
    rejectReads = true;
    final service = WatchService(
      session: rig.service.session,
      notifications: rig.notices,
      checkNativeNotices: (scope, reserve, guard) async {
        guard();
        throw const WatchBudgetExhausted();
      },
    );
    addTearDown(service.dispose);
    await expectLater(service.checkNow(), throwsStateError);
    rejectReads = false;
    await service.checkNow();
    expect(service.rules.single.id, 'durable');
    expect(service.statuses.containsKey('storage'), isFalse);
    expect(service.events, isEmpty);
  });

  test('unacknowledged poll state never becomes an alert or an event',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    rig.service.notificationPermission = WatchNotificationPermission.granted;
    await rig.service.addRule(rule('durable'));
    await rig.service.checkNow();
    rig.client.respond = (_) async => thread(post('101'));
    rejectWrites = true;
    await expectLater(rig.service.checkNow(), throwsException);
    expect(rig.service.events, isEmpty);
    expect(rig.notices.shown, isEmpty);
    rejectWrites = false;
    await rig.service.checkNow();
    expect(rig.service.events.single.pid, '101');
    expect(rig.notices.shown, hasLength(1));
  });

  test('mixed rules produce one persisted summary per poll without backfill',
      () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    rig.service.notificationPermission = WatchNotificationPermission.granted;
    await rig.service.addRule(rule('plain'));
    await rig.service.addRule(rule('keyword', keyword: 'needle'));
    await rig.service.checkNow();
    expect(rig.notices.shown, isEmpty);
    rig.client.respond = (_) async =>
        thread(post('101', body: 'needle') + post('102', body: 'needle'));
    await rig.service.checkNow();
    expect(rig.service.events, hasLength(4));
    expect(rig.service.events.map((e) => e.pid).toSet(), {'101', '102'});
    expect(rig.notices.shown, hasLength(1));
    expect(rig.service.events.map((e) => e.id),
        contains(rig.notices.shown.single.id));
    await rig.service.checkNow();
    expect(rig.notices.shown, hasLength(1));
    expect(rig.service.events, hasLength(4));
  });

  test(
    'silent baseline and known history checkpoint once per page rather than once per native ID',
    () async {
      for (final scope in [WatchScope.user, WatchScope.thread]) {
        final rig = Rig()..owner = 'batch_${scope.name}';
        addTearDown(rig.dispose);
        await rig.service.addRule(
          rule(
            'batch',
            scope: scope,
            subject: scope == WatchScope.user ? '8' : '70',
          ),
        );
        rig.client.respond = (path) async {
          final page = pageOf(path);
          return scope == WatchScope.user
              ? list(
                  [for (var i = 1; i <= 30; i++) row(page * 100 + i)].join(),
                  page: page,
                  pages: 3,
                )
              : thread(
                  [
                    for (var i = 1; i <= 30; i++) post('${page * 100 + i}'),
                  ].join(),
                  page: page,
                  pages: 3,
                );
        };
        var before = preferenceWrites;
        await rig.service.checkNow();
        expect(preferenceWrites - before, lessThanOrEqualTo(5));
        before = preferenceWrites;
        await rig.service.checkNow();
        expect(preferenceWrites - before, lessThanOrEqualTo(5));
        expect(rig.service.events, isEmpty);
        expect(rig.service.statuses['batch']!.phase, WatchPhase.current);
      }
    },
  );

  test(
    'stop and restart drains cancelled request, preserves scoped baseline and immediately performs a fresh check',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('lifecycle'));
      await rig.service.start();
      final entered = Completer<void>();
      final response = Completer<String>();
      rig.client.respond = (_) {
        entered.complete();
        return response.future;
      };
      final oldCheck = rig.service.checkNow();
      await entered.future;
      rig.service.stop();
      expect(rig.service.nextCheckAt, isNull);
      final restarted = rig.service.start();
      rig.client.respond = (_) async => thread(post('102'));
      response.complete(thread(post('101')));
      await expectLater(oldCheck, throwsStateError);
      await restarted;
      expect(rig.service.events.single.pid, '102');
      expect(rig.notices.shown.single.pid, '102');
      expect(rig.service.nextCheckAt, isNotNull);
      rig.service.stop();
      expect(rig.service.nextCheckAt, isNull);
    },
  );

  test(
    'thread baseline is silent; subsequent all-page catchup terminates and exact read set does not clear earlier PIDs',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('thread'));
      await rig.service.checkNow();
      expect(rig.service.events, isEmpty);
      rig.client.respond = (path) async {
        final page = pageOf(path);
        return thread(post('${100 + page}'), page: page, pages: 3);
      };
      await rig.service.checkNow();
      expect(rig.service.events.map((e) => e.pid).toSet(), {
        '101',
        '102',
        '103',
      });
      expect(rig.service.statuses['thread']!.phase, WatchPhase.current);
      await rig.service.markPostsSeen('70', ['103']);
      expect(
        rig.service.events.where((e) => e.unread).map((e) => e.pid).toSet(),
        {'101', '102'},
      );
      await rig.service.markPostsSeen('70', [], openingSeen: true);
      expect(rig.service.unreadCount, 2);
      await rig.service.checkNow();
      expect(rig.service.events, hasLength(3));
    },
  );

  test(
    'thread shrink twelve pages to five still catches every new PID on early pages',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      var shrunk = false;
      rig.client.respond = (path) async {
        final page = pageOf(path);
        return shrunk
            ? thread(
                '${page == 1 ? post('100') : ''}${post('${500 + page}')}',
                page: page,
                pages: 5,
              )
            : thread(post('${page * 40 + 20}'), page: page, pages: 12);
      };
      await rig.service.addRule(rule('shrink'));
      await rig.service.checkNow();
      expect(rig.service.events, isEmpty);
      shrunk = true;
      await rig.service.checkNow();
      expect(rig.service.events.map((e) => e.pid).toSet(), {
        '501',
        '502',
        '503',
        '504',
        '505',
      });
      expect(rig.service.statuses['shrink']!.phase, WatchPhase.current);
    },
  );

  test(
    'continuous tail appends do not restart reverse catchup across budget windows',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('busy'));
      await rig.service.checkNow();
      var pages = 60;
      rig.client.respond = (path) async {
        final page = pageOf(path);
        return thread(
          '${page == 1 ? post('100') : ''}${post('${100 + page}')}',
          page: page,
          pages: pages,
        );
      };
      var completed = false;
      for (var window = 0; window < 6; window++) {
        rig.now = rig.now.add(const Duration(minutes: 6));
        await rig.service.checkNow();
        if (rig.service.statuses['busy']!.phase == WatchPhase.current) {
          completed = true;
          break;
        }
        pages++;
      }
      expect(completed, isTrue);
      final ids = rig.service.events.map((e) => e.pid).toSet();
      expect(ids.containsAll([for (var i = 101; i <= 160; i++) '$i']), isTrue);
    },
  );

  test(
    'user baseline includes out-of-order historical IDs from later pages without historical notifications',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(
        rule('unordered', scope: WatchScope.user, subject: '8'),
      );
      var added = false;
      rig.client.respond = (path) async {
        if (!path.startsWith('u.php')) {
          final pid = RegExp(r'pid-(\d+)').firstMatch(path)!.group(1)!;
          return thread(post(pid));
        }
        final page = pageOf(path);
        return list(
          page == 1 ? '${added ? row(501) : ''}${row(100)}' : row(500),
          page: page,
          pages: 2,
        );
      };
      await rig.service.checkNow();
      await rig.service.checkNow();
      expect(rig.service.events, isEmpty);
      added = true;
      await rig.service.checkNow();
      expect(rig.service.events.single.pid, '501');
    },
  );

  test(
    '20-send budget retains candidate continuation over storage reload; exact PID body not list title decides keyword',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.service.notificationPermission = WatchNotificationPermission.granted;
      await rig.service.addRule(
        rule('user', scope: WatchScope.user, subject: '8', keyword: 'needle'),
      );
      rig.client.respond = (_) async => list(row(100));
      await rig.service.checkNow();
      rig.client.respond = (path) async {
        if (path.startsWith('u.php'))
          return list(
            [
              for (var i = 125; i >= 101; i--)
                row(i, title: 'needle in THREAD title'),
            ].join(),
          );
        final pid = RegExp(r'pid-(\d+)').firstMatch(path)!.group(1)!;
        return thread(
          post(pid, body: pid == '101' ? 'no matching body' : 'needle'),
        );
      };
      await rig.service.checkNow();
      expect(rig.client.paths.length, 20);
      expect(rig.service.pendingUntil, isNotNull);
      expect(rig.service.statuses['user']!.phase, WatchPhase.pending);
      final firstCount = rig.service.events.length;
      expect(firstCount, greaterThan(0));
      expect(rig.notices.shown, hasLength(1),
          reason: 'budget stop still sends one summary for persisted results');
      final restored = WatchService(
        session: rig.service.session,
        notifications: rig.notices,
        clock: () => rig.now,
      );
      addTearDown(restored.dispose);
      rig.now = rig.now.add(const Duration(minutes: 6));
      await restored.checkNow();
      expect(restored.events, hasLength(24));
      expect(restored.events.any((e) => e.pid == '101'), isFalse);
      expect(restored.statuses['user']!.phase, WatchPhase.current);
    },
  );

  test(
    'same-source rules share cached GETs; active cap applies to resume, paused continuation remains stored',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      for (var i = 0; i < 10; i++) {
        await rig.service.addRule(rule('r$i'));
      }
      await rig.service.addRule(rule('paused', paused: true));
      await expectLater(
        rig.service.setPaused('paused', false),
        throwsA(isA<WatchLimitException>()),
      );
      await rig.service.checkNow();
      expect(rig.client.paths, hasLength(1));
      await rig.service.setPaused('r0', true);
      await rig.service.setPaused('paused', false);
      expect(rig.service.activeCount, 10);
      expect(rig.service.rules, hasLength(11));
      expect(
        () => rule(
          'bad',
          scope: WatchScope.user,
          subject: '8',
          involving: '9',
          kinds: {WatchContentKind.topics, WatchContentKind.replies},
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'all kinds must finish before OR-rule is current; invisible favorites remain incomplete not empty',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(
        rule(
          'mixed',
          scope: WatchScope.user,
          subject: '8',
          kinds: {WatchContentKind.favorites, WatchContentKind.topics},
        ),
      );
      rig.client.respond = (path) async => path.contains('favor')
          ? list('', action: 'favor')
          : list(row(10, reply: false), action: 'topic');
      await rig.service.checkNow();
      expect(rig.service.events, isEmpty);
      expect(rig.service.statuses['mixed']!.phase, WatchPhase.incomplete);
    },
  );

  test(
    'favorites complete baseline across pages then report only newly visible inventory',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(
        rule(
          'favorites',
          scope: WatchScope.user,
          subject: '8',
          kinds: {WatchContentKind.favorites},
        ),
      );
      var changed = false;
      rig.client.respond = (path) async {
        final page = pageOf(path);
        return list(
          row(page == 1 && changed ? 11 : page, reply: false),
          action: 'favor',
          page: page,
          pages: 2,
        );
      };
      await rig.service.checkNow();
      expect(rig.service.events, isEmpty);
      changed = true;
      await rig.service.checkNow();
      expect(rig.service.events.single.tid, '11');
      expect(rig.service.events.single.reason, contains('可见快照'));
    },
  );

  test(
    'quote requires resolved native target author; inherited title alone never matches; probable never OS pushed',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      rig.service.notificationPermission = WatchNotificationPermission.granted;
      await rig.service.addRule(rule('quote', involving: '7'));
      await rig.service.checkNow();
      rig.client.respond = (_) async => thread(
            post('tpc', uid: '7', floor: 0) +
                post('101', body: 'ordinary body'),
            pages: 1,
          ).replaceFirst('Thread title', 'Re:回0楼(target)的帖子');
      await rig.service.checkNow();
      expect(rig.service.events, isEmpty);
      rig.client.respond = (_) async => thread(
            post('tpc', uid: '7', floor: 0) +
                post('102',
                    body: '<blockquote>引用第0楼 target</blockquote>response'),
          );
      await rig.service.checkNow();
      expect(rig.service.events.single.confidence, WatchConfidence.probable);
      expect(rig.notices.shown, isEmpty);
      rig.client.respond = (_) async => thread(
            post('tpc', uid: '7', floor: 0) +
                post('50', floor: 1) +
                post(
                  '103',
                  body:
                      '<blockquote>引用第1楼 other</blockquote><blockquote>引用第0楼 target</blockquote>response',
                ),
          );
      await rig.service.checkNow();
      expect(rig.service.events, hasLength(2));
      expect(rig.service.events.first.pid, '103');
      expect(rig.service.events.first.confidence, WatchConfidence.probable);
      rig.client.respond = (_) async => thread(
            post('104',
                body: '<blockquote>引用第999楼 target</blockquote>response'),
          );
      await rig.service.checkNow();
      expect(rig.service.events, hasLength(2));
      expect(rig.service.statuses['quote']!.phase, WatchPhase.incomplete);
    },
  );

  test(
    'queued add, pause and read from owner A reject rather than bind to owner B with the same rule ID',
    () async {
      final rig = Rig()..owner = 'owner-B';
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('shared'));
      await rig.service.checkNow();
      rig.client.respond = (_) async => thread(post('101'));
      await rig.service.checkNow();
      final sharedEvent = rig.service.events.single.id;
      rig.owner = 'owner-A';
      rig.epoch++;
      rig.service.sessionChanged();
      await rig.service.addRule(rule('shared'));
      rig.client.respond = (_) async => thread(post('100'));
      await rig.service.checkNow();
      final entered = Completer<void>();
      final response = Completer<String>();
      rig.client.respond = (_) {
        entered.complete();
        return response.future;
      };
      final oldCheck = rig.service.checkNow();
      await entered.future;
      final add = expectLater(
        rig.service.addRule(rule('private-A')),
        throwsStateError,
      );
      final pause = expectLater(
        rig.service.setPaused('shared', true),
        throwsStateError,
      );
      final read = expectLater(
        rig.service.markRead(sharedEvent),
        throwsStateError,
      );
      rig.owner = 'owner-B';
      rig.epoch++;
      rig.service.sessionChanged();
      response.complete(thread(post('101')));
      await expectLater(oldCheck, throwsStateError);
      await Future.wait([add, pause, read]);
      rig.client.respond = (_) async => thread(post('101'));
      await rig.service.checkNow();
      expect(rig.service.rules.map((r) => r.id), ['shared']);
      expect(rig.service.rules.single.paused, isFalse);
      expect(rig.service.events.single.id, sharedEvent);
      expect(rig.service.events.single.unread, isTrue);
    },
  );

  test(
    'in-flight account change cannot publish; initial cold tap survives but owner switch cancels stale tap',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('owner'));
      await rig.service.checkNow();
      rig.client.respond = (_) async => thread(post('101'));
      await rig.service.checkNow();
      final event = rig.service.events.single;
      final restoredNotices = Notices()
        ..tap = {'owner': rig.owner, 'eventId': event.id};
      final restored = WatchService(
        session: rig.service.session,
        notifications: restoredNotices,
      );
      addTearDown(restored.dispose);
      await restored.checkNow();
      expect(restoredNotices.cancels, 0);
      expect(restored.takePendingOpen()!.id, event.id);
      final entered = Completer<void>();
      final response = Completer<String>();
      rig.client.respond = (_) {
        entered.complete();
        return response.future;
      };
      final pending = rig.service.checkNow();
      await entered.future;
      rig.owner = 'other-owner';
      rig.epoch++;
      rig.service.sessionChanged();
      response.complete(thread(post('102')));
      await expectLater(pending, throwsStateError);
      expect(rig.service.rules, isEmpty);
      expect(rig.service.events, isEmpty);
      expect(rig.notices.cancels, 1);
    },
  );

  test(
    'permission denial and own posts keep in-app events without OS notification',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('privacy'));
      await rig.service.checkNow();
      rig.notices.granted = WatchNotificationPermission.denied;
      await rig.service.requestNotifications();
      rig.client.respond = (_) async => thread(post('101'));
      await rig.service.checkNow();
      expect(rig.service.unreadCount, 1);
      expect(rig.notices.shown, isEmpty);
      rig.service.notificationPermission = WatchNotificationPermission.granted;
      rig.client.respond = (_) async => thread(post('102', uid: '9'));
      await rig.service.checkNow();
      expect(rig.service.unreadCount, 2);
      expect(rig.notices.shown, isEmpty);
    },
  );

  test(
    'actual transport gate counts redirects and aborts before budget-exceeding request reaches server',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var received = 0;
      server.listen((request) async {
        received++;
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/read.php?tid=70&page=$received',
        );
        await request.response.close();
      });
      final transport = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        RealHttp(),
      );
      addTearDown(() => transport.close(force: true));
      final client = LocalClient(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        transport,
      );
      addTearDown(() => client.close(force: true));
      var sends = 0;
      await expectLater(
        client.getWatch(
          'job.php?action-topost-tid-70-pid-101.html',
          requireCurrentSession: () {},
          beforeSend: () {
            if (sends == 2) throw const WatchBudgetExhausted();
            sends++;
          },
        ),
        throwsA(isA<WatchBudgetExhausted>()),
      );
      expect(sends, 2);
      expect(received, 2);
      await expectLater(
        client.getWatch(
          'u.php?action-delete-uid-8.html',
          requireCurrentSession: () {},
          beforeSend: () {
            sends++;
          },
        ),
        throwsException,
      );
      expect(received, 2);
    },
  );

  test(
    'transport permits only typed same-thread read redirects and rejects invalid fields before sending',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var received = 0;
      var destination = '/read.php?tid=70&page=1';
      server.listen((request) async {
        received++;
        if (request.uri.path == '/job.php') {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, destination);
        } else {
          request.response.write('native body');
        }
        await request.response.close();
      });
      final transport = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        RealHttp(),
      );
      addTearDown(() => transport.close(force: true));
      final client = LocalClient(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        transport,
      );
      addTearDown(() => client.close(force: true));
      var sends = 0;
      expect(
        await client.getWatch(
          'job.php?action-topost-tid-70-pid-101.html',
          requireCurrentSession: () {},
          beforeSend: () {
            sends++;
          },
        ),
        'native body',
      );
      expect(received, 2);
      expect(sends, 2);
      for (final query in [
        'tid=70&action=delete',
        'tid=70&%61ction=delete',
        'tid=70&tid=71&page=1',
        'tid=70&page=0',
        'tid=70&page=1&page=2',
        'tid=70&uid=7',
        'tid=71&page=1',
        'tid=70&page=x',
        'tid-70-unknown-x-page-1.html',
      ]) {
        final previousReceived = received;
        final previousSends = sends;
        destination = '/read.php?$query';
        await expectLater(
          client.getWatch(
            'job.php?action-topost-tid-70-pid-101.html',
            requireCurrentSession: () {},
            beforeSend: () {
              sends++;
            },
          ),
          throwsA(
            isA<ForumRequestException>().having(
              (e) => e.kind,
              'kind',
              ForumRequestKind.invalidInput,
            ),
          ),
        );
        expect(received, previousReceived + 1, reason: query);
        expect(sends, previousSends + 1, reason: query);
      }
    },
  );

  testWidgets('guest or no-active-rule startup leaves no polling timer', (
    tester,
  ) async {
    final guest = WatchService(session: () => null, notifications: Notices());
    await guest.start();
    expect(guest.nextCheckAt, isNull);
    guest.dispose();
    final rig = Rig();
    await rig.service.start();
    expect(rig.service.nextCheckAt, isNull);
    expect(rig.client.paths, isEmpty);
    rig.dispose();
  });

  test(
    'board follows postdate DESC, ignores classic pins and refetches truncated title before matching',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(
        rule(
          'board',
          scope: WatchScope.board,
          subject: '48',
          kinds: {WatchContentKind.topics},
          keyword: 'needle',
          field: WatchKeywordField.title,
        ),
      );
      var changed = false;
      rig.client.respond = (path) async {
        if (path.startsWith('read.php'))
          return thread(
            post('tpc'),
            tid: 101,
          ).replaceFirst('Thread title', 'Full needle title');
        expect(path, contains('orderway-postdate-asc-DESC'));
        return '<table id="ajaxtable"><tr class="tr3"><td><h3><a href="read.php?tid-9999.html">needle ancient pin</a></h3></td></tr></table>'
            '<div class="pages">Pages: 1/1</div><ul class="stream">'
            '${changed ? '<li class="dcsns-li"><div class="section-title"><a href="read.php?tid-101.html">Full nee..</a></div></li>' : ''}'
            '<li class="dcsns-li"><div class="section-title"><a href="read.php?tid-100.html">old topic</a></div></li></ul>';
      };
      await rig.service.checkNow();
      changed = true;
      await rig.service.checkNow();
      expect(rig.service.events.single.tid, '101');
      expect(rig.service.events.single.title, 'Full needle title');
      expect(rig.client.paths.any((p) => p.contains('tid-9999')), isFalse);
    },
  );

  test(
    'rule validation enforces applicable AND filters and positive native IDs at domain boundary',
    () {
      final invalid = <WatchRule Function()>[
        () => rule(
              'bad',
              scope: WatchScope.user,
              involving: '8',
              kinds: {WatchContentKind.topics},
            ),
        () => rule('bad', kinds: {}),
        () => rule(
              'bad',
              scope: WatchScope.board,
              kinds: {WatchContentKind.topics},
              keyword: 'x',
            ),
        () => rule(
              'bad',
              scope: WatchScope.board,
              kinds: {WatchContentKind.topics},
              field: WatchKeywordField.title,
            ),
        () => rule('bad', involving: '0'),
        () => rule('bad', subject: '-1'),
        () => rule('bad/id'),
      ];
      for (final make in invalid) {
        expect(make, throwsArgumentError);
      }
    },
  );

  test(
    'failed persistence rolls rule update and delete back in memory and on reload',
    () async {
      SharedPreferences.resetStatic();
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final stored = <String, Object>{};
      var reject = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAll') return Map<String, Object>.of(stored);
        if (reject) return false;
        final args = call.arguments as Map;
        if (call.method == 'remove') {
          stored.remove(args['key']);
        } else {
          stored[args['key'] as String] = args['value'] as Object;
        }
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        SharedPreferences.resetStatic();
      });
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.service.addRule(rule('durable'));
      reject = true;
      await expectLater(
        rig.service.setPaused('durable', true),
        throwsStateError,
      );
      expect(rig.service.rules.single.paused, isFalse);
      await expectLater(rig.service.removeRule('durable'), throwsStateError);
      expect(rig.service.rules.single.id, 'durable');
      reject = false;
      final restored = WatchService(
        session: rig.service.session,
        notifications: rig.notices,
      );
      addTearDown(restored.dispose);
      await restored.checkNow();
      expect(restored.rules.single.paused, isFalse);
    },
  );
}

class RealHttp extends HttpOverrides {}

class LocalClient extends ForumClient {
  LocalClient(this.baseUri, HttpClient transport)
      : super(httpClient: transport, delay: (_) async {});
  @override
  final Uri baseUri;
}
