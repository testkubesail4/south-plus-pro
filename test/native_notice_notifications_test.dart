import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/native_notice_notifications.dart';
import 'package:south_plus_rewrite/services/parsers/forum_pm_parser.dart';
import 'package:south_plus_rewrite/services/parsers/forum_reply_notice_parser.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

class _RealHttp extends HttpOverrides {}

class _CaptureStdout implements Stdout {
  final output = StringBuffer();
  @override
  void writeln([Object? object = '']) => output.writeln(object);
  @override
  void write(Object? object) => output.write(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends ForumClient {
  _Client(this.baseUri, HttpClient transport)
      : super(httpClient: transport, delay: (_) async {});
  @override
  final Uri baseUri;
  @override
  bool get isLoggedIn => true;
}

class _Bridge extends WatchNotifications {
  final shown = <(String, String, NoticeNotificationKind)>[];
  final cancelled = <(String, NoticeNotificationKind)>[];
  final calls = <String>[];
  final muted = <NoticeNotificationKind>{};
  WatchNotificationPermission granted = WatchNotificationPermission.granted;
  Map<String, dynamic>? tap;
  @override
  void listen(Future<void> Function()? callback) {}
  @override
  Future<WatchNotificationPermission> permission({
    bool request = false,
  }) async =>
      granted;
  @override
  Future<bool> showNotice(
    String owner,
    String id,
    NoticeNotificationKind kind,
  ) async {
    if (muted.contains(kind)) return false;
    shown.add((owner, id, kind));
    return true;
  }

  @override
  Future<void> cancelKind(String owner, NoticeNotificationKind kind) async {
    cancelled.add((owner, kind));
    calls.add('cancel:${kind.name}');
  }

  @override
  Future<void> cancelAll() async {
    calls.add('cancelAll');
    tap = null;
  }

  @override
  Future<Map<String, dynamic>?> takeTap() async {
    calls.add('takeTap');
    final result = tap;
    tap = null;
    return result;
  }
}

class _Fixture {
  late HttpServer server;
  late HttpClient transport;
  late _Client client;
  final bridge = _Bridge();
  final inApp = <(NoticeNotificationKind, int, String?)>[];
  String owner = 'A';
  int epoch = 0;
  String? headerUid;
  bool pmFlag = false;
  bool replyFlag = false;
  bool brokenPm = false;
  bool brokenReplies = false;
  bool omitPager = false;
  bool repeatFirstPage = false;
  bool missingToken = false;
  bool omitPmIndicator = false;
  List<List<(String, bool)>> pm = [
    [('1', false)],
  ];
  List<(int, String)> replies = [];
  int threadPages = 1;
  final requests = <(String, String)>[];
  final replyActions = <String>[];
  Completer<void>? pmEntered;
  Completer<void>? releasePm;
  Completer<void>? replyEntered;
  Completer<void>? releaseReply;
  DateTime now = DateTime.utc(2026);
  late NativeNoticeNotifications native;
  late WatchService watch;
  ForumPmParser get pmParser => ForumPmParser(baseUri: client.baseUri);
  ForumReplyNoticeParser get replyParser =>
      ForumReplyNoticeParser(urls: ForumUrlResolver(baseUri: client.baseUri));
  int pageOf(String value) =>
      int.tryParse(
        RegExp(r'(?:[?&-])page[-=](\d+)').firstMatch(value)?.group(1) ?? '',
      ) ??
      1;
  WatchSession scope() {
    final savedOwner = owner;
    final savedEpoch = epoch;
    final credentials = client.credentialGeneration;
    return WatchSession(
      owner: savedOwner,
      uid: owner == 'A' ? '9' : '10',
      epoch: savedEpoch,
      client: client,
      urls: ForumUrlResolver(baseUri: client.baseUri),
      requireCurrent: () {
        if (owner != savedOwner ||
            epoch != savedEpoch ||
            !client.isCredentialCurrent(credentials))
          throw StateError('stale owner');
      },
    );
  }

  Future<void> open() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
    client = _Client(Uri.parse('http://127.0.0.1:${server.port}/'), transport);
    server.listen(_serve);
    native = NativeNoticeNotifications(
      session: scope,
      notifications: bridge,
      clock: () => now,
      onNotice: (kind, count, title) => inApp.add((kind, count, title)),
      refreshFlags: (_) async {
        final doc = html.parse(
          await client.getForm('index.php', followRedirects: false),
        );
        return ForumNoticeFlags(
          unreadPm: replyParser.hasUnreadPm(doc),
          replyNotice: replyParser.hasReplyNotice(doc),
        );
      },
      loadInbox: (path) async {
        final target = path ?? 'message.php?action-receivebox.html';
        return pmParser.parseBox(
          html.parse(await client.getForm(target, followRedirects: false)),
          ForumPmBox.inbox,
          currentPage: pageOf(target),
        );
      },
      loadReplies: () async {
        final response = await client.post(
          'pw_ajax.php?nowtime=1&verify=TESTTOK1',
          {'action': 'newrp'},
        );
        return response == '您的回复列表为空'
            ? const []
            : replyParser.parse(html.parse(response));
      },
    );
    watch = WatchService(
      session: scope,
      notifications: bridge,
      clock: () => now,
      checkNativeNotices: native.check,
      acceptNativeNoticeTap: native.acceptTap,
    );
  }

  String index() =>
      '<html><head>${missingToken ? '' : '<script>var verifyhash="TESTTOK1";</script>'}</head><body>'
      '<div id="user-login"><a href="u.php">Synthetic $owner</a></div>'
      '<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-${headerUid ?? (owner == 'A' ? '9' : '10')}.html">个人资料</a></div></div>'
      '${omitPmIndicator ? '' : '<div id="td_msg"><img src="images/${pmFlag ? 'shortmail.gif' : 'no-shortmail.gif'}"></div>'}'
      '${replyFlag ? '<a id="newrp">回复提醒</a>' : ''}</body></html>';
  String inbox(int requested) {
    if (brokenPm) return '<html>not a native list</html>';
    final page = repeatFirstPage ? 1 : requested.clamp(1, pm.length).toInt();
    final rows = pm[page - 1]
        .map(
          (row) => '<tr><td>Peer</td><td><a class="${row.$2 ? 'b' : ''}" '
              'href="message.php?action-read-mid-${row.$1}.html">private synthetic title</a></td><td>2026-01-01</td></tr>',
        )
        .join();
    return '<form method="post" action="message.php?action=receivebox"><input name="towhere" value="receivebox">'
        '<input name="verify" value="TESTTOK1"><table><tr><th>标题</th><th>时间</th></tr>$rows</table></form>'
        '${pm.length == 1 || omitPager ? '' : '<div class="pages">Pages: $page/${pm.length}<b>$page</b>'
            '${page > 1 ? '<a href="message.php?action-receivebox-page-${page - 1}.html">上一页</a>' : ''}'
            '${page < pm.length ? '<a href="message.php?action-receivebox-page-${page + 1}.html">下一页</a>' : ''}</div>'}';
  }

  Future<void> _serve(HttpRequest request) async {
    requests.add((request.method, request.uri.path));
    final form = await utf8.decoder.bind(request).join();
    if (request.uri.path == '/index.php') {
      request.response.write(index());
    } else if (request.uri.path == '/simple/index.php') {
      request.response.write(
        '<a href="read.php?tid-123.html">Fixture title</a>'
        '<table><tr><th><h2>Fixture section</h2></th></tr><tr><th>'
        '<h3><a href="thread.php?fid-42.html">Fixture board</a></h3>'
        '</th><td>1 / 2</td></tr></table>',
      );
    } else if (request.uri.path == '/message.php') {
      final body = inbox(pageOf(request.uri.toString()));
      if (releasePm != null) {
        pmEntered?.complete();
        final pending = releasePm!;
        releasePm = null;
        await pending.future;
      }
      request.response.write(body);
    } else if (request.uri.path == '/login.php') {
      request.response.headers.add(
        HttpHeaders.setCookieHeader,
        'winduser=synthetic-$owner; Path=/',
      );
      request.response.write('登录成功');
    } else if (request.uri.path == '/pw_ajax.php') {
      replyActions.add(Uri.splitQueryString(form)['action'] ?? '');
      if (form == 'action=newrp' && releaseReply != null) {
        replyEntered?.complete();
        final pending = releaseReply!;
        releaseReply = null;
        await pending.future;
      }
      if (form != 'action=newrp') {
        request.response.statusCode = 400;
      } else if (brokenReplies) {
        request.response.write('not native reply popup');
      } else if (replies.isEmpty) {
        request.response.write('您的回复列表为空');
      } else {
        request.response.write(
          '<table><tr><th class="h">回复提醒</th></tr>${replies.map((row) => '<tr class="tr3"><td class="tal"><a href="read.php?tid-${row.$1}.html">private thread title</a></td>'
              '<td><a href="thread.php?fid-48.html">Board</a></td><td>${row.$2}</td></tr>').join()}</table>',
        );
      }
    } else if (request.uri.path == '/read.php') {
      final page = pageOf(request.uri.toString());
      request.response.write(
        '<h1 id="subject_tpc">Thread</h1><a href="read.php?tid-70.html">Thread</a>'
        '<div class="pages">Pages: $page/$threadPages</div><table class="js-post"><tr>'
        '<th class="r_two"><a href="u.php?action-show-uid-8.html"><strong>User</strong></a></th>'
        '<th class="r_one" id="td_${100 + page}"><div id="read_${100 + page}">Body</div></th></tr></table>',
      );
    }
    await request.response.close();
  }

  void nextWindow() {
    now = now.add(const Duration(minutes: 6));
  }

  Future<void> close() async {
    watch.dispose();
    client.close(force: true);
    transport.close(force: true);
    await server.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectWrites = false;
  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectWrites = false;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      if (rejectWrites) return false;
      final args = call.arguments as Map;
      if (call.method == 'remove') {
        persisted.remove(args['key']);
      } else {
        persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(preferences, null);
    messenger.setMockMethodCallHandler(WatchNotifications.channel, null);
  });
  Future<_Fixture> fixture() async {
    final value = _Fixture();
    await value.open();
    addTearDown(value.close);
    return value;
  }

  test(
    'full paged baseline is silent; new unread MID while flag stays true alerts once; old read-to-unread is silent',
    () async {
      final f = await fixture();
      f.pmFlag = true;
      f.pm = [
        [('10', true)],
        [('9', false)],
        [('8', true)],
      ];
      await f.watch.checkNow();
      final baseline = jsonDecode(
        persisted.values.whereType<String>().firstWhere(
              (v) => v.contains('pmSeen'),
            ),
      ) as Map;
      expect(baseline['pmInitialized'], isTrue);
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.pm[0] = [('11', true), ('10', true)];
      f.pm[1] = [('9', true)];
      await f.watch.checkNow();
      expect(f.bridge.shown.map((e) => e.$3), [NoticeNotificationKind.pm]);
      f.nextWindow();
      await f.watch.checkNow();
      expect(f.bridge.shown, hasLength(1));
      expect(
        persisted.values.join(),
        isNot(contains('private synthetic title')),
      );
      expect(persisted.values.join(), isNot(contains('TESTTOK1')));
      expect(f.requests.every((r) => r.$2 != '/read.php'), isTrue);
    },
  );

  for (final missing in ['PM indicator', 'reply token']) {
    test('a home header missing its $missing invalidates native freshness',
        () async {
      final f = await fixture();
      final initial = f.now;
      final repository = ForumRepository(client: f.client, clock: () => f.now);
      addTearDown(repository.liveSync.dispose);
      addTearDown(repository.watch.dispose);
      expect(await repository.restoreSession(), isTrue);
      await repository.watch.checkNow();
      expect(repository.pmInbox.value, isNotNull);

      f.now = initial.add(const Duration(seconds: 50));
      await repository.fetchHome();
      // Keep the account and directory valid, but replace the notice header
      // while the previous verified stamp is still within its minute.
      f.omitPmIndicator = missing == 'PM indicator';
      f.replyFlag = missing == 'reply token';
      f.missingToken = missing == 'reply token';
      f.now = initial.add(const Duration(seconds: 70));
      await repository.fetchHome();
      expect(repository.accountIdentity.value!.uid, '9');

      f.now = initial.add(const Duration(seconds: 90));
      final before = f.requests.length;
      await expectLater(
        repository.liveSync.syncMessages(user: true),
        throwsA(isA<ForumRequestException>()
            .having((error) => error.kind, 'kind', ForumRequestKind.server)),
      );
      expect(f.requests.sublist(before), [('GET', '/index.php')],
          reason: 'verify unknown flags before reading either notice list');
    });
  }

  test(
      'home pull and message entry share the index header, cooldown and native budget',
      () async {
    final f = await fixture();
    f.pmFlag = true;
    f.replyFlag = true;
    f.replies = [(70, '2026-01-01')];
    final repository = ForumRepository(client: f.client, clock: () => f.now);
    addTearDown(repository.liveSync.dispose);
    addTearDown(repository.watch.dispose);
    expect(await repository.restoreSession(), isTrue);
    final home = repository.fetchHome();
    final sync = repository.liveSync.syncMessages(user: true);
    await Future.wait([home, sync]);
    expect(f.requests.where((r) => r.$2 == '/index.php'), hasLength(1),
        reason:
            'reuse the verified desktop header instead of fetching it twice');
    expect(repository.pmInbox.value!.messages.single.id, '1');
    expect(repository.replyNotices.value!.single.tid, 70);
    int noticeSends() =>
        f.requests
            .where((r) => {'/index.php', '/message.php'}.contains(r.$2))
            .length +
        f.replyActions.where((action) => action == 'newrp').length;
    final count = noticeSends();
    await Future.wait([
      repository.liveSync.syncMessages(),
      repository.liveSync.syncMessages(user: true),
      repository.watch.checkNow(),
    ]);
    expect(noticeSends(), count, reason: 'all entry points share freshness');
    for (var minute = 1; minute <= 3; minute++) {
      f.now = f.now.add(const Duration(minutes: 1));
      await repository.liveSync.syncMessages(user: true);
    }
    expect(noticeSends() - count, 6,
        reason: 'two three-send rounds use the remaining native reservation');
    final exhausted = noticeSends();
    f.now = f.now.add(const Duration(minutes: 1));
    await repository.liveSync.syncMessages(user: true);
    expect(noticeSends(), exhausted,
        reason:
            'continuation blocks more requests until the rolling budget opens');
  });

  test('in-app notices ignore OS permission but require persisted fresh IDs',
      () async {
    final f = await fixture();
    f.bridge.granted = WatchNotificationPermission.denied;
    f.pmFlag = true;
    f.replyFlag = true;
    f.replies = [(70, '2026-01-01')];
    await f.watch.checkNow();
    expect(f.inApp, isEmpty, reason: 'initial baselines stay silent');
    f.nextWindow();
    f.pm[0] = [('2', true), ('1', false)];
    f.replies.add((71, '2026-01-01'));
    rejectWrites = true;
    await f.watch.checkNow();
    expect(f.inApp, isEmpty, reason: 'no event before ledger acknowledgement');
    expect(f.native.lastError, isNotNull);
    rejectWrites = false;
    f.nextWindow();
    await f.watch.checkNow();
    expect(f.inApp, [
      (NoticeNotificationKind.pm, 1, 'private synthetic title'),
      (NoticeNotificationKind.reply, 1, 'private thread title'),
    ]);
    expect(f.bridge.shown, isEmpty);
    f.nextWindow();
    await f.watch.checkNow();
    expect(f.inApp, hasLength(2), reason: 'same IDs never replay');
    expect(persisted.values.join(), isNot(contains('private synthetic title')));
    expect(persisted.values.join(), isNot(contains('private thread title')));
  });

  test(
    'reply fingerprints union while true, reset only false, changed dates are best-effort distinct',
    () async {
      final f = await fixture();
      f.replyFlag = true;
      f.replies = [(70, '2026-01-01')];
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.replies = [(71, '2026-01-01')];
      await f.watch.checkNow();
      expect(f.bridge.shown, hasLength(1));
      f.nextWindow();
      f.replies = [(70, '2026-01-01')];
      await f.watch.checkNow();
      expect(f.bridge.shown, hasLength(1));
      f.nextWindow();
      f.replies = [(70, '2026-01-02')];
      await f.watch.checkNow();
      expect(f.bridge.shown, hasLength(2));
      f.nextWindow();
      f.replyFlag = false;
      await f.watch.checkNow();
      f.nextWindow();
      f.replyFlag = true;
      f.replies = [(70, '2026-01-01')];
      await f.watch.checkNow();
      expect(f.bridge.shown, hasLength(3));
    },
  );

  test(
    'native eight-per-window cap survives repeated checks and account switch, reserving twelve actual sends for watches',
    () async {
      final f = await fixture();
      f.pm = [
        for (var p = 1; p <= 30; p++) [('${p * 10}', false)],
      ];
      f.replyFlag = true;
      f.replies = [(70, '2026-01-01')];
      f.threadPages = 20;
      await f.watch.addRule(
        WatchRule(
          id: 'thread',
          scope: WatchScope.thread,
          subjectId: '70',
          label: 'Thread',
        ),
      );
      await f.watch.checkNow();
      int nativeCount() => f.requests.where((r) => r.$2 != '/read.php').length;
      expect(nativeCount(), 8);
      expect(f.requests.where((r) => r.$2 == '/read.php'), hasLength(12));
      expect(f.requests.take(3).map((r) => r.$2), [
        '/index.php',
        '/message.php',
        '/pw_ajax.php',
      ]);
      await f.watch.checkNow();
      expect(nativeCount(), 8);
      f.owner = 'B';
      f.epoch++;
      f.native.sessionChanged();
      f.watch.sessionChanged();
      await f.watch.checkNow();
      expect(nativeCount(), 8);
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      await f.watch.checkNow();
      expect(nativeCount(), 16);
    },
  );

  test(
    'paged baseline resumes across a new service instance; clamped/repeated pages never complete it',
    () async {
      final f = await fixture();
      f.pmFlag = true;
      f.pm = [
        for (var p = 1; p <= 12; p++) [('$p', true)],
      ];
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.repeatFirstPage = true;
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      final state = jsonDecode(
        persisted.values.whereType<String>().firstWhere(
              (v) => v.contains('pmSeen'),
            ),
      ) as Map;
      expect(state['pmInitialized'], isNot(true));
      expect(state['pmNext'], isNotNull);
      f.repeatFirstPage = false;
      f.nextWindow();
      final restored = NativeNoticeNotifications(
        session: f.scope,
        notifications: f.bridge,
        clock: () => f.now,
        refreshFlags: f.native.refreshFlags,
        loadInbox: f.native.loadInbox,
        loadReplies: f.native.loadReplies,
      );
      var sends = 0;
      await restored.check(f.scope(), () {
        sends++;
      }, f.scope().requireCurrent);
      expect(sends, lessThanOrEqualTo(8));
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.pm[0] = [('99', true), ...f.pm[0]];
      await restored.check(f.scope(), () {}, f.scope().requireCurrent);
      expect(f.bridge.shown.single.$3, NoticeNotificationKind.pm);
    },
  );

  test(
    'network shape and persistence errors do not advance dedupe or manufacture an empty baseline',
    () async {
      final f = await fixture();
      await f.watch.checkNow();
      f.nextWindow();
      f.pmFlag = true;
      f.pm[0] = [('2', true)];
      f.brokenPm = true;
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.brokenPm = false;
      rejectWrites = true;
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      rejectWrites = false;
      f.nextWindow();
      await f.watch.checkNow();
      expect(f.bridge.shown.single.$3, NoticeNotificationKind.pm);
    },
  );

  test(
    'permission denial and per-channel mute stay quiet without backfill when reenabled',
    () async {
      final f = await fixture();
      await f.watch.checkNow();
      f.nextWindow();
      f.bridge.granted = WatchNotificationPermission.denied;
      f.pmFlag = true;
      f.pm[0] = [('2', true)];
      await f.watch.checkNow();
      f.nextWindow();
      f.bridge.granted = WatchNotificationPermission.granted;
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.bridge.muted.add(NoticeNotificationKind.pm);
      f.pm[0] = [('3', true)];
      await f.watch.checkNow();
      f.nextWindow();
      f.bridge.muted.clear();
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
      f.nextWindow();
      f.pm[0] = [('4', true)];
      await f.watch.checkNow();
      expect(f.bridge.shown, hasLength(1));
    },
  );

  test(
    'resume refreshes app permission without requesting it automatically',
    () async {
      final f = await fixture();
      f.bridge.granted = WatchNotificationPermission.denied;
      await f.watch.start();
      expect(
        f.watch.notificationPermission,
        WatchNotificationPermission.denied,
      );
      f.watch.didChangeAppLifecycleState(AppLifecycleState.paused);
      final changed = Completer<void>();
      f.watch.addListener(() {
        if (f.watch.notificationPermission ==
                WatchNotificationPermission.granted &&
            !changed.isCompleted) changed.complete();
      });
      f.bridge.granted = WatchNotificationPermission.granted;
      f.watch.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await changed.future.timeout(const Duration(seconds: 2));
      await f.watch.checkNow();
      expect(
        f.watch.notificationPermission,
        WatchNotificationPermission.granted,
      );
    },
  );

  test(
    'in-flight old-owner response cannot persist or notify in a replacement account',
    () async {
      final f = await fixture();
      await f.watch.checkNow();
      f.nextWindow();
      f.pmFlag = true;
      f.pm[0] = [('2', true)];
      final entered = Completer<void>();
      final release = Completer<void>();
      f.pmEntered = entered;
      f.releasePm = release;
      final pending = f.watch.checkNow();
      await entered.future;
      final beforeCancel = f.bridge.cancelled.length;
      final cancelled = expectLater(
        f.native.cancelKind(NoticeNotificationKind.pm),
        throwsStateError,
      );
      f.owner = 'B';
      f.epoch++;
      f.native.sessionChanged();
      f.watch.sessionChanged();
      release.complete();
      await expectLater(pending, throwsStateError);
      await cancelled;
      expect(f.bridge.cancelled.length, beforeCancel);
      expect(f.bridge.shown, isEmpty);
      await f.watch.checkNow();
      expect(f.bridge.shown, isEmpty);
    },
  );

  test(
    'single dispatcher validates kind/owner/issued ID and consumes cold tap before polling cancels a clear flag',
    () async {
      final f = await fixture();
      await f.watch.checkNow();
      f.nextWindow();
      f.pmFlag = true;
      f.pm[0] = [('2', true)];
      await f.watch.checkNow();
      final event = f.bridge.shown.single;
      f.nextWindow();
      f.pmFlag = false;
      f.bridge.tap = {'owner': event.$1, 'eventId': event.$2, 'kind': 'pm'};
      final restored = NativeNoticeNotifications(
        session: f.scope,
        notifications: f.bridge,
        clock: () => f.now,
        refreshFlags: f.native.refreshFlags,
        loadInbox: f.native.loadInbox,
        loadReplies: f.native.loadReplies,
      );
      final watch = WatchService(
        session: f.scope,
        notifications: f.bridge,
        clock: () => f.now,
        checkNativeNotices: restored.check,
        acceptNativeNoticeTap: restored.acceptTap,
      );
      addTearDown(watch.dispose);
      f.bridge.calls.clear();
      await watch.checkNow();
      expect(watch.takePendingNoticeOpen(), NoticeNotificationKind.pm);
      expect(watch.takePendingNoticeOpen(), isNull);
      expect(
        f.bridge.calls.indexOf('takeTap'),
        lessThan(f.bridge.calls.indexOf('cancel:pm')),
      );
      for (final tap in [
        {'owner': 'B', 'eventId': event.$2, 'kind': 'pm'},
        {'owner': event.$1, 'eventId': event.$2, 'kind': 'reply'},
        {'owner': event.$1, 'eventId': 'unknown', 'kind': 'pm'},
        {'owner': event.$1, 'eventId': event.$2, 'kind': 'external'},
      ]) {
        f.bridge.tap = tap;
        await watch.checkNow();
        expect(watch.takePendingNoticeOpen(), isNull);
      }
    },
  );

  test(
    'native transport allows list-only POST and rejects detail/delete/unknown queries before actual send',
    () async {
      final f = await fixture();
      var sends = 0;
      await f.client.runNativeNoticeReads(
        () async {
          await f.client.getForm('index.php');
          await f.client.getForm('message.php?action=receivebox&page=1');
          await f.client.post('pw_ajax.php?nowtime=1&verify=TESTTOK1', {
            'action': 'newrp',
          });
        },
        requireCurrentSession: () {},
        beforeSend: () {
          sends++;
        },
      );
      expect(sends, 3);
      for (final action in <Future<String> Function()>[
        () => f.client.getForm('message.php?action-read-mid-1.html'),
        () => f.client.getForm('message.php?action=receivebox&page=1&page=2'),
        () => f.client.getForm('index.php?unknown=1'),
        () => f.client.post('pw_ajax.php?nowtime=1&verify=TESTTOK1', {
              'action': 'delnewrp',
            }),
        () => f.client.post('pw_ajax.php?nowtime=1&verify=TESTTOK1&unknown=1', {
              'action': 'newrp',
            }),
        () => f.client.post('pw_ajax.php?nowtime=1&verify=TESTTOK1', {
              'action': 'newrp',
              'tid': '70',
            }),
      ]) {
        final count = f.requests.length;
        await expectLater(
          f.client.runNativeNoticeReads(
            action,
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
        expect(f.requests.length, count);
        expect(sends, 3);
      }
    },
  );

  test(
    'native HTTP trace omits verify token and private list metadata',
    () async {
      final f = await fixture();
      f.pmFlag = true;
      f.pm[0] = [('1', true)];
      f.replyFlag = true;
      f.replies = [(70, '2026-01-01')];
      final capture = _CaptureStdout();
      await IOOverrides.runZoned(() async {
        await f.watch.checkNow();
      }, stdout: () => capture);
      expect(
        f.requests.map((r) => r.$2).toSet(),
        containsAll(['/index.php', '/message.php', '/pw_ajax.php']),
      );
      final trace = capture.output.toString();
      expect(trace, contains('[ForumTrace]'));
      expect(trace, contains('POST profile.php (account)'));
      for (final secret in [
        'TESTTOK1',
        'private synthetic title',
        'private thread title',
      ]) {
        expect(trace, isNot(contains(secret)));
      }
    },
    skip: ForumTraceLogger.enabled
        ? false
        : 'Requires --dart-define=FORUM_TRACE=true',
  );

  for (final clearResponse in [true, false]) {
    test(
      'same-owner credential rotation rejects in-flight reply ${clearResponse ? 'clear' : 'new'} before flags, ledger or OS publication',
      () async {
        final f = await fixture();
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final shown = <Object?>[];
        messenger.setMockMethodCallHandler(WatchNotifications.channel, (
          call,
        ) async {
          if (call.method == 'permission') return true;
          if (call.method == 'show') {
            shown.add(call.arguments);
            return true;
          }
          return null;
        });
        final repository =
            ForumRepository(client: f.client, clock: () => f.now);
        addTearDown(repository.watch.dispose);
        expect(await repository.restoreSession(), isTrue);
        await repository.watch.checkNow();
        f.nextWindow();
        final ledgerKey = persisted.keys.firstWhere(
          (key) => key.contains('native_notice_notifications_v1'),
        );
        final ledger = persisted[ledgerKey];
        final identity = repository.accountIdentity.value;
        final epoch = repository.sessionEpoch.value;
        final generation = f.client.credentialGeneration;
        f.replyFlag = true;
        f.replies = clearResponse ? [] : [(71, '2026-01-02')];
        final entered = Completer<void>();
        final release = Completer<void>();
        f.replyEntered = entered;
        f.releaseReply = release;
        final pending = repository.watch.checkNow();
        await entered.future;
        expect(repository.noticeFlags.value.replyNotice, isTrue);
        await f.client.postLogin({
          'pwuser': 'Synthetic A',
          'pwpwd': 'synthetic-password',
          'gdcode': '1234',
        });
        expect(f.client.isCredentialCurrent(generation), isFalse);
        expect(repository.sessionEpoch.value, epoch);
        expect(repository.accountIdentity.value, same(identity));
        release.complete();
        await expectLater(
          pending,
          throwsA(
            isA<ForumRequestException>().having(
              (e) => e.kind,
              'kind',
              ForumRequestKind.loginRequired,
            ),
          ),
        );
        expect(repository.noticeFlags.value.replyNotice, isTrue);
        expect(persisted[ledgerKey], ledger);
        expect(shown, isEmpty);
      },
    );
  }

  test(
    'missing native reply token fails closed without fallback index, blocking reads or unverified flags',
    () async {
      final f = await fixture();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
        WatchNotifications.channel,
        (call) async => call.method == 'permission' ? true : null,
      );
      final repository = ForumRepository(client: f.client, clock: () => f.now);
      addTearDown(repository.watch.dispose);
      expect(await repository.restoreSession(), isTrue);
      await repository.watch.checkNow();
      f.nextWindow();
      expect(repository.noticeFlags.value.replyNotice, isFalse);
      f.replyFlag = true;
      f.replies = [(70, '2026-01-01')];
      f.missingToken = true;
      final before = f.requests.length;
      await repository.watch.checkNow();
      expect(f.requests.sublist(before), [('GET', '/index.php')]);
      expect(repository.noticeFlags.value.replyNotice, isFalse);
    },
  );

  test(
    'native reply queue never enters ordinary index fallback if another same-account refresh clears its token',
    () async {
      final f = await fixture();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
        WatchNotifications.channel,
        (call) async => call.method == 'permission' ? true : null,
      );
      f.replyFlag = true;
      f.replies = [(70, '2026-01-01')];
      final repository = ForumRepository(client: f.client, clock: () => f.now);
      addTearDown(repository.watch.dispose);
      expect(await repository.restoreSession(), isTrue);
      final entered = Completer<void>();
      final release = Completer<void>();
      f.pmEntered = entered;
      f.releasePm = release;
      final pending = repository.watch.checkNow();
      await entered.future;
      f.missingToken = true;
      expect(await repository.restoreSession(), isTrue);
      final before = f.requests.where((r) => r.$2 == '/index.php').length;
      final reads = f.replyActions.where((action) => action == 'newrp').length;
      release.complete();
      await pending;
      expect(
        f.requests.where((r) => r.$2 == '/index.php').length,
        before,
        reason: 'native queue must not enter ordinary index/blocking fallback',
      );
      expect(f.replyActions.where((action) => action == 'newrp').length, reads);
    },
  );

  test(
    'real repository rejects mismatched UID; iOS syncs lists without OS notice calls',
    () async {
      final f = await fixture();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final shown = <Object?>[];
      messenger.setMockMethodCallHandler(WatchNotifications.channel, (
        call,
      ) async {
        if (call.method == 'permission') return true;
        if (call.method == 'show') {
          shown.add(call.arguments);
          return true;
        }
        return null;
      });
      final repository = ForumRepository(client: f.client, clock: () => f.now);
      addTearDown(repository.watch.dispose);
      expect(await repository.restoreSession(), isTrue);
      await repository.watch.checkNow();
      f.nextWindow();
      f.pmFlag = true;
      f.pm[0] = [('2', true)];
      f.headerUid = '999';
      final before = f.requests.length;
      await repository.watch.checkNow();
      expect(f.requests.length, before + 1);
      expect(shown, isEmpty);
      f.headerUid = null;
      f.nextWindow();
      await repository.watch.checkNow();
      expect(shown, hasLength(1));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final ios = ForumRepository(client: f.client, clock: () => f.now);
      addTearDown(ios.watch.dispose);
      expect(await ios.restoreSession(), isTrue);
      final count = f.requests.length;
      await ios.watch.checkNow();
      expect(f.requests.sublist(count).where((r) => r.$2 == '/message.php'),
          [('GET', '/message.php')]);
      expect(
          f.requests.sublist(count).where((r) => r.$2 == '/index.php'), isEmpty,
          reason: 'reuse the restored index header');
      expect(ios.pmInbox.value, isNotNull);
      expect(
        await ios.watch.notifications.showNotice(
          'A',
          'notice_pm_1',
          NoticeNotificationKind.pm,
        ),
        isFalse,
      );
      expect(shown, hasLength(1));
    },
  );
}
