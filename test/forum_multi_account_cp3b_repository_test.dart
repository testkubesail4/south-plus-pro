import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/account_scoped_keys.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/local_database.dart';
import 'package:south_plus_rewrite/services/forum_account_registry.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_slots.dart';
import 'package:south_plus_rewrite/services/forum_task_state_store.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

const _config = ForumNetworkConfig(
  site: ForumSite('fixture.invalid'),
  mode: ForumNetworkMode.native,
);

ForumThread _thread(String tid) => ForumThread(
      title: 't$tid',
      url: 'https://fixture.invalid/read.php?tid-$tid.html',
      replies: 0,
      section: 'board',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  test('localDataScope follows active account even when header fails',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final b = await fx.addAccount(username: 'userB', uid: '102');
      expect(fx.repo.localPreferenceAccount, b.id);

      fx.server.failIndex = true;
      await fx.repo.switchAccount(a.id);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.localPreferenceAccount, a.id,
          reason: 'stable scope aligned from AccountSummary, not header');
      expect(fx.repo.localPreferenceAccount, isNot(b.id));
    });
  });

  test('read positions and clearBrowsingHistory isolate A from B and guest',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      await fx.repo.saveThreadReadPosition(
          _thread('9'), const ThreadReadPosition(page: 4, anchor: 'tpc'));
      expect((await fx.repo.loadThreadReadPosition(_thread('9')))!.page, 4);
      final hist = BrowsingHistoryStore(
        databaseProvider: () async => fx.historyDb,
      );
      await hist.recordThreadForScope(a.id, _thread('1'));
      expect((await fx.repo.browsingHistory()).single.thread.title, 't1');

      final b = await fx.addAccount(username: 'userB', uid: '102');
      expect(await fx.repo.loadThreadReadPosition(_thread('9')), isNull);
      await fx.repo.saveThreadReadPosition(
          _thread('9'), const ThreadReadPosition(page: 7));

      await fx.repo.switchAccount(a.id);
      expect((await fx.repo.loadThreadReadPosition(_thread('9')))!.page, 4);

      await hist.recordThreadForScope(b.id, _thread('2'));
      await fx.repo.clearBrowsingHistory();
      expect(await fx.repo.loadThreadReadPosition(_thread('9')), isNull);
      expect(await fx.repo.browsingHistory(), isEmpty);
      expect((await hist.recentForScope(b.id)).single.thread.title, 't2',
          reason: 'clear A must not wipe B history');

      await fx.repo.switchAccount(b.id);
      expect((await fx.repo.loadThreadReadPosition(_thread('9')))!.page, 7);
      expect((await fx.repo.browsingHistory()).single.thread.title, 't2');

      await fx.repo.logoutCurrent();
      expect(AccountScope.isGuest(fx.repo.localDataScope), isTrue);
      await fx.repo.saveThreadReadPosition(
          _thread('9'), const ThreadReadPosition(page: 1));
      expect((await fx.repo.loadThreadReadPosition(_thread('9')))!.page, 1);
      expect(fx.repo.localDataScope, isNot(a.id));
      expect(fx.repo.localDataScope, isNot(b.id));
    });
  });

  test('repository task cache and notes follow the stable account scope',
      () async {
    await _withCp2Fixture((fx) async {
      final store = const ForumTaskStateStore();
      final unownedAt = DateTime.utc(2025, 1, 1);
      await store
          .save(ForumTaskSnapshot(tasks: const [], updatedAt: unownedAt));

      final a = await fx.addAccount(username: 'userA', uid: '101');
      final scopeA = fx.repo.localPreferenceAccount;
      expect(scopeA, a.id);
      expect(scopeA.contains('userA'), isFalse);
      expect(await fx.repo.loadCachedForumTaskSnapshot(), isNull);

      final updatedA = DateTime.utc(2026, 1, 1);
      await store.save(
        ForumTaskSnapshot(tasks: const [], updatedAt: updatedA),
        scope: a.id,
      );
      expect(
          (await fx.repo.loadCachedForumTaskSnapshot())!.updatedAt, updatedA);
      expect(await store.load(scope: 'userA'), isNull);

      await UserNoteStore.save('404', 'only-A', account: scopeA);
      expect((await UserNoteStore.load(account: scopeA))['404'], 'only-A');

      final b = await fx.addAccount(username: 'userB', uid: '102');
      final scopeB = fx.repo.localPreferenceAccount;
      expect(scopeB, b.id);
      expect(await fx.repo.loadCachedForumTaskSnapshot(), isNull);
      final updatedB = DateTime.utc(2026, 2, 1);
      await store.save(
        ForumTaskSnapshot(tasks: const [], updatedAt: updatedB),
        scope: b.id,
      );
      expect(
          (await fx.repo.loadCachedForumTaskSnapshot())!.updatedAt, updatedB);
      expect(await UserNoteStore.load(account: scopeB), isEmpty);
      await UserNoteStore.save('404', 'only-B', account: scopeB);

      await fx.repo.switchAccount(a.id);
      expect(
          (await UserNoteStore.load(
              account: fx.repo.localPreferenceAccount))['404'],
          'only-A');
      expect(
          (await fx.repo.loadCachedForumTaskSnapshot())!.updatedAt, updatedA);
      expect((await store.load())!.updatedAt, unownedAt);
    });
  });

  test(
      'repository blocking isolates local keys and native requests for A and B',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final settings = fx.repo.blocking;
      await settings.load();
      await settings.setContent('noise-a', blocked: true);
      await settings.setUser('901', 'Blocked by A', blocked: true);
      expect(settings.notifier.value.isUserBlocked('901'), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('blocking.local.${a.id}')!)['content'],
        ['noise-a'],
      );
      expect(prefs.getString('blocking.local.101'), isNull);

      final b = await fx.addAccount(username: 'userB', uid: '102');
      await settings.load();
      expect(settings.notifier.value.contentKeys, isEmpty);
      expect(settings.notifier.value.isUserBlocked('901'), isFalse);
      await settings.setContent('noise-b', blocked: true);
      await settings.setUser('902', 'Blocked by B', blocked: true);
      expect(
        jsonDecode(prefs.getString('blocking.local.${b.id}')!)['content'],
        ['noise-b'],
      );
      expect(prefs.getString('blocking.local.102'), isNull);

      await fx.repo.switchAccount(a.id);
      await settings.load();
      expect(settings.notifier.value.isContentBlocked('noise-a'), isTrue);
      expect(settings.notifier.value.isContentBlocked('noise-b'), isFalse);
      expect(settings.notifier.value.isUserBlocked('901'), isTrue);
      expect(settings.notifier.value.isUserBlocked('902'), isFalse);
      expect(
        fx.server.blockRequests,
        containsAll([
          ('101', 'getblocklist'),
          ('101', 'updateblocklist'),
          ('102', 'getblocklist'),
          ('102', 'updateblocklist'),
        ]),
      );
    });
  });

  test(
      'repository profile fetches and cache preserve viewer isolation and unowned data',
      () async {
    await _withCp2Fixture((fx) async {
      const url = 'https://fixture.invalid/u.php?action-show-uid-999.html';
      await fx.profileCache.saveOverview(
        url,
        UserProfile(
          uid: '999',
          name: 'Legacy profile',
          url: url,
          tagline: 'unowned profile',
        ),
      );

      final a = await fx.addAccount(username: 'userA', uid: '101');
      expect(await fx.repo.cachedUserProfileOverview(url), isNull);
      final profileA = await fx.repo.fetchUserProfileOverview(url);
      expect(profileA.tagline, 'viewer 101');
      expect((await fx.repo.cachedUserProfileOverview(url))!.tagline,
          'viewer 101');

      await fx.addAccount(username: 'userB', uid: '102');
      expect(await fx.repo.cachedUserProfileOverview(url), isNull);
      final profileB = await fx.repo.fetchUserProfileOverview(url);
      expect(profileB.tagline, 'viewer 102');
      expect((await fx.repo.cachedUserProfileOverview(url))!.tagline,
          'viewer 102');

      await fx.repo.switchAccount(a.id);
      expect((await fx.repo.cachedUserProfileOverview(url))!.tagline,
          'viewer 101');
      await fx.repo.logoutCurrent();
      expect(await fx.repo.cachedUserProfileOverview(url), isNull);
      expect((await fx.profileCache.loadOverview(url))!.tagline,
          'unowned profile');
      expect(fx.server.profileViewers, ['101', '102']);
    });
  });

  test('same uid different origin scopes stay independent via AccountScope',
      () {
    final a = AccountScope.accountFrom(
        origin: Uri.parse('https://forum-a.example/'), uid: '101');
    final b = AccountScope.accountFrom(
        origin: Uri.parse('https://forum-b.example/'), uid: '101');
    expect(a, isNot(b));
    expect(AccountScope.guest(Uri.parse('https://forum-a.example/')),
        isNot(AccountScope.guest(Uri.parse('https://forum-b.example/'))));
  });
}

Future<void> _withCp2Fixture(Future<void> Function(_Cp2Fixture fx) body) async {
  final context = SecurityContext()
    ..useCertificateChain('test/support/proxy_fixture_cert.pem')
    ..usePrivateKey('test/support/proxy_fixture_key.pem');
  final trust = SecurityContext()
    ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');
  final server =
      await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  final overrides = _LoopbackOverrides(server.port, trust);
  final handler = _Cp2Http();
  server.listen(handler.handle);
  try {
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = ForumClient(config: _config, delay: (_) async {});
      final historyDb = LocalDatabase.openForTesting();
      final profileCache = UserProfileCache(
        urls: ForumUrlResolver(baseUri: _config.baseUri),
        databaseProvider: () async => historyDb,
      );
      final repo = ForumRepository(
        client: client,
        config: _config,
        profileCache: profileCache,
        historyStore: BrowsingHistoryStore(
          databaseProvider: () async => historyDb,
        ),
      );
      final fx = _Cp2Fixture(
          client, repo, handler, overrides, historyDb, profileCache);
      try {
        await body(fx);
      } finally {
        await repo.cancelAddAccount();
        await repo.cancelReauthAccount();
        client.close(force: true);
        historyDb.close();
      }
    }, overrides);
  } finally {
    for (final c in overrides.clients) {
      c.close(force: true);
    }
    await server.close(force: true);
  }
}

class _Cp2Fixture {
  _Cp2Fixture(this.client, this.repo, this.server, this.overrides,
      this.historyDb, this.profileCache);
  final ForumClient client;
  final ForumRepository repo;
  final _Cp2Http server;
  final _LoopbackOverrides overrides;
  final LocalDatabase historyDb;
  final UserProfileCache profileCache;

  Future<AccountSummary> addAccount({
    required String username,
    required String uid,
  }) async {
    server.expectUid[username] = uid;
    final challenge = await repo.fetchAddAccountChallenge();
    return repo.submitAddAccount(
      username: username,
      password: 'pw',
      captcha: '1234',
      fields: challenge.fields,
    );
  }

  Future<String?> cookieSnapshot(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(ForumSessionSlots.cookiesPrefsKey(accountId)!);
  }
}

class _Cp2Http {
  String? failUser;
  Completer<void>? holdLogin;
  Completer<void>? loginHeld;
  bool omitUid = false;
  bool failIndex = false;
  String? forceUid;
  final expectUid = <String, String>{};
  final blockRequests = <(String, String)>[];
  final nativeBlocks = <String, Map<String, dynamic>>{};
  final profileViewers = <String>[];

  String? _requestUid(HttpRequest request) {
    final cookies = request.headers.value(HttpHeaders.cookieHeader) ?? '';
    return RegExp(r'token-([1-9]\d*)').firstMatch(cookies)?.group(1);
  }

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    try {
      if (request.method == 'GET' && path == '/login.php') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><body>'
          '<form name="login" action="login.php">'
          '<input type="hidden" name="step" value="2">'
          '<input type="hidden" name="lgt" value="0">'
          '<input type="hidden" name="cktime" value="31536000">'
          '<input name="pwuser">'
          '<input type="password" name="pwpwd">'
          '<input name="gdcode">'
          '<img id="ckcode" src="ck.php?nowtime=1">'
          '</form></body></html>',
        );
      } else if (request.method == 'GET' && path == '/ck.php') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([1, 2, 3, 4]);
      } else if (request.method == 'POST' && path == '/login.php') {
        final body = await utf8.decoder.bind(request).join();
        final fields = Uri.splitQueryString(body);
        final user = fields['pwuser'] ?? '';
        if (holdLogin != null) {
          if (loginHeld != null && !loginHeld!.isCompleted) {
            loginHeld!.complete();
          }
          await holdLogin!.future;
        }
        if (user == failUser) {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html><body>验证码不正确</body></html>');
        } else {
          final uid = expectUid[user] ??
              (user == 'userA'
                  ? '101'
                  : user == 'userB'
                      ? '102'
                      : '199');
          request.response.headers
              .set(HttpHeaders.setCookieHeader, 'winduser=token-$uid; Path=/');
          request.response.headers.contentType = ContentType.html;
          request.response.write('登录成功');
        }
      } else if (path == '/index.php' || path == '/' || path.isEmpty) {
        if (failIndex) {
          final socket = await request.response.detachSocket();
          await socket.close();
          return;
        }
        final cookie = request.headers.value(HttpHeaders.cookieHeader) ?? '';
        final match = RegExp(r'token-([1-9]\d*)').firstMatch(cookie);
        String? uid = forceUid;
        if (!omitUid) {
          uid ??= match?.group(1) ?? '101';
        }
        final name = uid == null
            ? 'LegacyUser'
            : (uid == '101'
                ? 'Synthetic A'
                : uid == '102'
                    ? 'Synthetic B'
                    : 'User $uid');
        request.response.headers.contentType = ContentType.html;
        final uidLink = uid == null
            ? ''
            : '<div id="menu_profile"><div class="ul2">'
                '<a href="u.php?action-show-uid-$uid.html">个人资料</a></div></div>'
                '<div id="showface"><span class="user-infoWraptwo">UID: $uid</span></div>';
        request.response.write(
          '<html><head><script>var verifyhash="TEST0$uid";</script></head><body>'
          '<div id="user-login"><a href="u.php">$name</a></div>'
          '$uidLink'
          '</body></html>',
        );
      } else if (request.method == 'POST' && path == '/pw_ajax.php') {
        final uid = _requestUid(request);
        final action = request.uri.queryParameters['action'];
        final body = await utf8.decoder.bind(request).join();
        final fields = Uri.splitQueryString(body);
        if (uid == null ||
            request.uri.queryParameters['verify'] != 'TEST0$uid') {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write('invalid session');
        } else if (action == 'getblocklist') {
          blockRequests.add((uid, 'getblocklist'));
          final config = nativeBlocks.putIfAbsent(
            uid,
            () => {
              'version': '3.1',
              'blist': <String, dynamic>{},
              'curiosity': false,
              'showBTN': true,
            },
          );
          request.response
              .write('<ajax><![CDATA[${jsonEncode(config)}]]></ajax>');
        } else if (action == 'updateblocklist' &&
            fields['blocklistconfig'] != null) {
          blockRequests.add((uid, 'updateblocklist'));
          nativeBlocks[uid] =
              jsonDecode(fields['blocklistconfig']!) as Map<String, dynamic>;
          request.response.write('<ajax><![CDATA[success]]></ajax>');
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('unsupported blocking action');
        }
      } else if (request.method == 'GET' &&
          path == '/u.php' &&
          request.uri.query == 'action-show-uid-999.html') {
        final uid = _requestUid(request);
        if (uid == null) {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write('login required');
        } else {
          profileViewers.add(uid);
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<html><body><div id="u-top"><h1 class="u-h1">Profile 999</h1>'
            '<span id="honor">viewer $uid</span></div></body></html>',
          );
        }
      } else if (path == '/simple/index.php') {
        request.response.write('<html></html>');
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('missing $path');
      }
      await request.response.close();
    } on SocketException {
      /* peer closed */
    } on HttpException {
      /* peer closed */
    }
  }
}

class _LoopbackOverrides extends ForumHttpOverrides {
  _LoopbackOverrides(this.port, this.trust);
  final int port;
  final SecurityContext trust;
  final clients = <HttpClient>[];

  @override
  HttpClient createUnroutedClient(SecurityContext? context) {
    final client = super.createUnroutedClient(trust);
    clients.add(client);
    client.badCertificateCallback = (_, __, ___) => true;
    client.connectionFactory = (uri, _, __) async {
      final task =
          await Socket.startConnect(InternetAddress.loopbackIPv4, port);
      return ConnectionTask.fromSocket<Socket>(
        task.socket.then(
          (socket) => SecureSocket.secure(
            socket,
            host: uri.host,
            context: trust,
          ),
        ),
        task.cancel,
      );
    };
    return client;
  }
}
