import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/account_scoped_keys.dart';
import 'package:south_plus_rewrite/services/forum_account_id.dart';
import 'package:south_plus_rewrite/services/forum_account_registry.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_session_slots.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';

import 'support/forum_route_fixture.dart';

const _siteA = ForumNetworkConfig(
    site: ForumSite('fixture.invalid'), mode: ForumNetworkMode.native);
const _siteB = ForumNetworkConfig(
    site: ForumSite('localhost'), mode: ForumNetworkMode.native);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectConfig = false;
  var configWrites = 0;
  Completer<void>? configEntered;
  Completer<void>? configAck;
  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectConfig = false;
    configWrites = 0;
    configEntered = null;
    configAck = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final args = call.arguments as Map;
      final key = args['key'] as String;
      if (key == 'flutter.forum_network_config_v2') {
        configWrites++;
        if (rejectConfig) return false;
        persisted[key] = args['value'] as Object;
        if (configAck != null &&
            (jsonDecode(args['value'] as String) as Map)['mode'] ==
                'optimized') {
          if (!configEntered!.isCompleted) configEntered!.complete();
          await configAck!.future;
        }
        return true;
      }
      if (call.method == 'remove') {
        persisted.remove(key);
      } else {
        persisted[key] = args['value'] as Object;
      }
      return true;
    });
  });
  tearDown(() {
    selectProxyTestRoute(null);
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> withFixture(Future<void> Function(_Fixture) action) async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/proxy_fixture_cert.pem')
      ..usePrivateKey('test/support/proxy_fixture_key.pem');
    final trust = SecurityContext()
      ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');
    final server =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    final overrides = _NativeOverrides(server.port, trust);
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = ForumClient(config: _siteA, delay: (_) async {});
        final fixture = _Fixture(client, ForumRepository(client: client));
        server.listen(fixture.handle);
        try {
          await client.getOnce('fixture-session?owner=A');
          expect(await fixture.repository.restoreSession(), isTrue);
          await action(fixture);
        } finally {
          fixture.unblock();
        }
      }, overrides);
    } finally {
      for (final client in overrides.clients) {
        client.close(force: true);
      }
      await server.close(force: true);
    }
  }

  bool canUseOwner(ForumRepository repository, String uid) {
    final url = repository.networkConfig.baseUri
        .resolve('u.php?action=friend&uid=$uid')
        .toString();
    final target = repository.forumLinkTarget(url);
    expect(target, isA<ForumAppPageLinkTarget>());
    return repository.canOpenForumAppPage(target as ForumAppPageLinkTarget);
  }

  test(
      'same-origin modes keep confirmed identity and cookies, but revoke the old client and epoch',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      final identity = repository.accountIdentity.value;
      expect(identity?.uid, '901');
      expect(canUseOwner(repository, '901'), isTrue);
      final initialEpoch = repository.sessionEpoch.value;
      fixture.holdPath = '/held';
      final heldEpoch = repository.sessionEpoch.value;
      final oldRequest = fixture.initialClient.getOnceGuarded('held',
          requireCurrentSession: () {
        if (repository.sessionEpoch.value != heldEpoch)
          throw const ForumRequestException(
              ForumRequestKind.loginRequired, 'stale fixture epoch');
      });
      final cancelled =
          expectLater(oldRequest, throwsA(isA<ForumRequestException>()));
      await fixture.received.future;
      final hits = fixture.requests.length;
      final proxy = ForumProxy(
          type: ForumProxyType.http,
          host: 'offline.fixture.invalid',
          port: 8080);
      for (final mode in [
        ForumNetworkMode.optimized,
        ForumNetworkMode.proxy,
        ForumNetworkMode.native
      ]) {
        await repository.updateNetworkConfig(
            repository.networkConfig.copyWith(mode: mode, proxy: proxy));
        expect(repository.currentUsername, 'Synthetic A');
        expect(repository.isLoggedIn, isTrue);
        expect(repository.accountIdentity.value, same(identity));
        expect(canUseOwner(repository, '901'), isTrue);
        expect(fixture.requests.length, hits,
            reason: 'route changes never verify identity over HTTP');
      }
      expect(repository.sessionEpoch.value, initialEpoch + 3);
      expect(
          fixture.initialClient
              .isCredentialCurrent(identity!.credentialGeneration!),
          isFalse);
      await expectLater(fixture.initialClient.clearSession(),
          throwsA(isA<ForumRequestException>()));
      await cancelled;
      fixture.unblock();
      expect(await repository.restoreSession(), isTrue);
      expect(fixture.requests.last.$2, 'winduser=synthetic-A');
      expect(repository.currentUsername, 'Synthetic A');
    });
  });

  test(
      'origins restore only their own known identity and credential scope without implicit HTTP',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      final accountA = repository.activeAccount.value;
      expect(accountA, isNotNull);
      // Pure legacy origin jar for B (not an account-slot mirror).
      await ForumSessionStore(origin: _siteB.baseUri).saveCookies({
        'B': ForumStoredCookie.session(
            name: 'winduser', value: 'synthetic-B', origin: _siteB.baseUri),
      });
      var hits = fixture.requests.length;
      await repository.updateNetworkConfig(_siteB);
      expect(fixture.requests.length, hits);
      expect(repository.activeAccount.value, isNull);
      expect(repository.currentUsername, isNull);
      expect(repository.accountIdentity.value, isNull);
      expect(repository.isLoggedIn, isTrue,
          reason:
              'legacy origin jar may restore cookies without selecting an account');
      expect(canUseOwner(repository, '901'), isFalse);
      await repository.ensureAccountIdentity();
      expect(fixture.requests.last, ('localhost', 'winduser=synthetic-B'));
      expect(repository.currentUsername, isNull);
      expect(canUseOwner(repository, '903'), isTrue);
      final knownB = repository.accountIdentity.value;
      hits = fixture.requests.length;
      await repository.updateNetworkConfig(
          _siteB.copyWith(mode: ForumNetworkMode.optimized));
      expect(repository.currentUsername, 'Synthetic B');
      expect(repository.accountIdentity.value, same(knownB));
      expect(canUseOwner(repository, '903'), isTrue);
      await repository.updateNetworkConfig(_siteB);
      expect(fixture.requests.length, hits);
      expect(repository.accountIdentity.value, same(knownB));
      hits = fixture.requests.length;
      await repository.updateNetworkConfig(_siteA);
      expect(fixture.requests.length, hits);
      // No account→origin mirror: returning to A as guest must not republish
      // A's identity or remint account cookies without explicit select/reauth.
      expect(repository.activeAccount.value, isNull);
      expect(repository.currentUsername, isNull);
      expect(repository.accountIdentity.value, isNull);
      expect(canUseOwner(repository, '901'), isFalse);
      expect(repository.isLoggedIn, isFalse);
      expect(
        repository.accounts.value.any((a) => a.id == accountA!.id),
        isTrue,
      );
      expect(await repository.restoreSession(), isFalse);
      hits = fixture.requests.length;
      await repository.updateNetworkConfig(_siteB);
      expect(fixture.requests.length, hits);
      // Cross-origin guest: legacy B cookies may remain, but cached identity
      // is not republished without an explicit active account.
      expect(repository.activeAccount.value, isNull);
      expect(repository.currentUsername, isNull);
      expect(repository.accountIdentity.value, isNull);
      expect(repository.isLoggedIn, isTrue);
      expect(canUseOwner(repository, '903'), isFalse);
      await repository.clearSession();
      await repository.updateNetworkConfig(_siteA);
      expect(repository.currentUsername, isNull);
      expect(repository.accountIdentity.value, isNull);
      expect(repository.isLoggedIn, isFalse);
      await repository.updateNetworkConfig(_siteB);
      expect(repository.currentUsername, isNull);
      expect(repository.accountIdentity.value, isNull);
      expect(repository.isLoggedIn, isFalse);
    });
  });

  for (final action in ['remove', 'logout']) {
    test(
        'non-active $action on foreign origin cannot resurrect A cookies or identity',
        () async {
      await withFixture((fixture) async {
        final repository = fixture.repository;
        final accountA = repository.activeAccount.value;
        expect(accountA, isNotNull);
        final accountIdA = accountA!.id;
        // Sibling account jar on A (not active): scrub(A) must leave it intact.
        final otherId = ForumAccountId(
          origin: _siteA.baseUri,
          uid: '902',
        ).value;
        await ForumSessionStore.forSlot(
          slotId: ForumSessionSlots.account(otherId),
          origin: _siteA.baseUri,
        ).saveCookies({
          'peer': ForumStoredCookie.session(
              name: 'winduser',
              value: 'synthetic-peer',
              origin: _siteA.baseUri),
        });
        await ForumSessionStore(origin: _siteB.baseUri).saveCookies({
          'B': ForumStoredCookie.session(
              name: 'winduser', value: 'synthetic-B', origin: _siteB.baseUri),
        });
        await repository.updateNetworkConfig(_siteB);
        expect(repository.activeAccount.value, isNull);
        expect(
          repository.accounts.value.any((a) => a.id == accountIdA),
          isTrue,
        );
        final originSlot = ForumSessionSlots.origin(_siteA.baseUri);
        if (action == 'remove') {
          await repository.removeAccount(accountIdA);
          expect(
            repository.accounts.value.any((a) => a.id == accountIdA),
            isFalse,
          );
        } else {
          await repository.logoutAccount(accountIdA);
          expect(
            repository.accounts.value.any((a) =>
                a.id == accountIdA &&
                a.status == AccountReadyState.needsReauth),
            isTrue,
          );
        }
        final aJar = await ForumSessionStore.forSlot(
          slotId: ForumSessionSlots.account(accountIdA),
          origin: _siteA.baseUri,
        ).loadCookies();
        expect(aJar, isEmpty);
        final originA =
            await ForumSessionStore(origin: _siteA.baseUri).loadCookies();
        expect(originA, isEmpty,
            reason: 'origin jar must be tombstoned with the scrubbed account');
        final peerJar = await ForumSessionStore.forSlot(
          slotId: ForumSessionSlots.account(otherId),
          origin: _siteA.baseUri,
        ).loadCookies();
        expect(
          peerJar.values.where((c) => c.name == 'winduser').single.value,
          'synthetic-peer',
          reason: 'sibling account jar on same origin must survive',
        );
        await repository.updateNetworkConfig(_siteA);
        expect(repository.activeAccount.value, isNull);
        expect(repository.currentUsername, isNull);
        expect(repository.accountIdentity.value, isNull);
        expect(repository.isLoggedIn, isFalse);
        expect(canUseOwner(repository, '901'), isFalse);
        expect(await repository.restoreSession(), isFalse);
        expect(repository.isLoggedIn, isFalse);
        expect(repository.currentUsername, isNull);
        // Cold-ish return after another origin hop still cannot remint A.
        await repository.updateNetworkConfig(_siteB);
        await repository.updateNetworkConfig(_siteA);
        expect(repository.activeAccount.value, isNull);
        expect(await repository.restoreSession(), isFalse);
        expect(repository.isLoggedIn, isFalse);
        expect(repository.currentUsername, isNull);
        expect(canUseOwner(repository, '901'), isFalse);
        expect(originSlot, startsWith('origin:'));
      });
    });
  }

  test(
      'pending durable settings reject reentry until route and identity publication finishes',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      final identity = repository.accountIdentity.value;
      final epoch = repository.sessionEpoch.value;
      final optimized = _siteA.copyWith(mode: ForumNetworkMode.optimized);
      final proxy =
          ForumProxy(type: ForumProxyType.http, host: '127.0.0.1', port: 1080);
      final requested =
          _siteA.copyWith(mode: ForumNetworkMode.proxy, proxy: proxy);
      configEntered = Completer<void>();
      configAck = Completer<void>();
      final first = repository.updateNetworkConfig(optimized);
      try {
        await configEntered!.future.timeout(const Duration(seconds: 2));
        expect(
            (jsonDecode(persisted['flutter.forum_network_config_v2'] as String)
                as Map)['mode'],
            'optimized');
        await expectLater(
            repository
                .updateNetworkConfig(requested)
                .timeout(const Duration(seconds: 1)),
            throwsStateError);
        await expectLater(
            repository
                .updateNetworkConfig(_siteA)
                .timeout(const Duration(seconds: 1)),
            throwsStateError);
        expect(configWrites, 1);
        expect(repository.networkConfig, _siteA);
        expect(repository.sessionEpoch.value, epoch);
        expect(repository.currentUsername, 'Synthetic A');
        expect(repository.accountIdentity.value, same(identity));
        expect(canUseOwner(repository, '901'), isTrue);
        await expectProxyTestRoute(null);
      } finally {
        if (!configAck!.isCompleted) configAck!.complete();
        await first;
      }
      expect(await ForumNetworkSettings.load(), optimized);
      expect(repository.networkConfig, optimized);
      expect(repository.sessionEpoch.value, epoch + 1);
      expect(repository.accountIdentity.value, same(identity));
      configAck = null;
      await repository.updateNetworkConfig(requested);
      expect(configWrites, 2);
      expect(await ForumNetworkSettings.load(), requested);
      expect(repository.networkConfig, requested);
      expect(repository.sessionEpoch.value, epoch + 2);
      expect(repository.currentUsername, 'Synthetic A');
      expect(repository.accountIdentity.value, same(identity));
      expect(canUseOwner(repository, '901'), isTrue);
      await expectProxyTestRoute(proxy.host);
    });
  });

  test(
      'failed configuration persistence preserves live identity, client and route',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      final identity = repository.accountIdentity.value;
      final epoch = repository.sessionEpoch.value;
      final hits = fixture.requests.length;
      rejectConfig = true;
      final proxy = ForumProxy(
          type: ForumProxyType.http,
          host: 'offline.fixture.invalid',
          port: 8080);
      await expectLater(
          repository.updateNetworkConfig(
              _siteA.copyWith(mode: ForumNetworkMode.proxy, proxy: proxy)),
          throwsA(isA<Exception>()));
      expect(repository.networkConfig, _siteA);
      expect(repository.sessionEpoch.value, epoch);
      expect(repository.currentUsername, 'Synthetic A');
      expect(repository.accountIdentity.value, same(identity));
      expect(repository.isLoggedIn, isTrue);
      expect(
          fixture.initialClient
              .isCredentialCurrent(identity!.credentialGeneration!),
          isTrue);
      expect(fixture.requests.length, hits);
      await expectProxyTestRoute(null);
      expect(
          await fixture.initialClient.getOnce('echo'), 'winduser=synthetic-A');
      expect(canUseOwner(repository, '901'), isTrue);
      rejectConfig = false;
      await repository.updateNetworkConfig(
          _siteA.copyWith(mode: ForumNetworkMode.optimized));
      expect(repository.sessionEpoch.value, epoch + 1);
      expect(repository.accountIdentity.value, same(identity));
      expect(repository.currentUsername, 'Synthetic A');
      expect(canUseOwner(repository, '901'), isTrue);
    });
  });

  test(
      'a cookie admitted before replacement persists after a different origin unblocks the write queue',
      () async {
    await withFixture((fixture) async {
      configEntered = Completer<void>();
      configAck = Completer<void>();
      final changed = fixture.repository.updateNetworkConfig(
          _siteA.copyWith(mode: ForumNetworkMode.optimized));
      await configEntered!.future.timeout(const Duration(seconds: 2));
      final blocker = _BlockingStore(_siteB.baseUri);
      final other = ForumClient(
          config: _siteB, sessionStore: blocker, delay: (_) async {});
      final otherRequest = other.getOnce('fixture-session?owner=other');
      final otherDone = otherRequest.then((_) {}, onError: (Object _) {});
      Future<void>? cancelled;
      try {
        await blocker.started.future.timeout(const Duration(seconds: 2));
        final before = fixture.initialClient.credentialGeneration;
        final login = fixture.initialClient.postLogin({
          'pwuser': 'Synthetic B',
          'pwpwd': 'synthetic-password',
          'gdcode': '1234'
        });
        cancelled = expectLater(login, throwsA(isA<ForumRequestException>()));
        final watch = Stopwatch()..start();
        while (fixture.initialClient.credentialGeneration == before) {
          if (watch.elapsed > const Duration(seconds: 2))
            throw TimeoutException('Login cookie was not admitted');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        configAck!.complete();
        await changed;
        expect(fixture.repository.isLoggedIn, isTrue);
        expect(fixture.repository.currentUsername, isNull);
        blocker.release.complete();
        await otherRequest;
        await cancelled;
        // Fixture restore promotes A to a v3 account slot; admitted B
        // cookies land on the live client slot, not the retired origin jar.
        final stored = await ForumSessionStore.forSlot(
          slotId: fixture.initialClient.slotId,
          origin: _siteA.baseUri,
        ).loadCookies();
        expect(stored.values.where((c) => c.name == 'winduser').single.value,
            'synthetic-B');
        expect(fixture.loginHits, 1);
      } finally {
        if (!configAck!.isCompleted) configAck!.complete();
        if (!blocker.release.isCompleted) blocker.release.complete();
        await changed;
        await otherDone;
        await cancelled;
        other.close(force: true);
      }
    });
  });

  test(
      'watch waits for identity refresh when client credentials rotate independently',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      addTearDown(repository.watch.dispose);
      await repository.watch.addRule(WatchRule(
          id: 'ownerA',
          scope: WatchScope.thread,
          subjectId: '70',
          label: 'Synthetic A target'));
      final oldIdentity = repository.accountIdentity.value!;
      await fixture.initialClient.postLogin({
        'pwuser': 'Synthetic B',
        'pwpwd': 'synthetic-password',
        'gdcode': '1234'
      });
      expect(
          fixture.initialClient
              .isCredentialCurrent(oldIdentity.credentialGeneration!),
          isFalse);
      expect(repository.accountIdentity.value, same(oldIdentity));
      final requests = fixture.requests.length;
      await repository.watch.checkNow();
      expect(fixture.requests.length, requests,
          reason: 'stale UID must not poll using replacement credentials');
      expect(repository.watch.events, isEmpty);
      expect(repository.watch.rules, isEmpty);
      expect(await repository.restoreSession(), isTrue);
      expect(repository.accountIdentity.value!.uid, '903');
      await repository.watch.addRule(WatchRule(
          id: 'ownerB',
          scope: WatchScope.thread,
          subjectId: '70',
          label: 'Synthetic B target'));
      await repository.watch.checkNow();
      expect(repository.watch.statuses['ownerB']!.phase, WatchPhase.current);
      final noticeProbe =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? 1 : 0;
      expect(fixture.requests.length, requests + 2 + noticeProbe,
          reason:
              'identity refresh, Android native-header probe, then watched-thread baseline');
    });
  });

  test(
      'an unpublished login cannot attach the previous username or uid to replacement credentials',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      final accountA = repository.activeAccount.value!.id;
      final scopeA = repository.localDataScope;
      final epochA = repository.sessionEpoch.value;
      fixture.holdBHeader = true;
      final login = repository.submitLogin(
          username: 'Synthetic B',
          password: 'synthetic-password',
          captcha: '1234',
          fields: const {});
      final cancelled =
          expectLater(login, throwsA(isA<ForumRequestException>()));
      await fixture.received.future;
      expect(fixture.requests.last.$2, 'winduser=synthetic-B',
          reason: 'the isolated login has received B credentials');
      expect(repository.activeAccount.value!.id, accountA);
      expect(repository.localDataScope, scopeA);
      expect(repository.sessionEpoch.value, epochA);
      expect(repository.currentUsername, 'Synthetic A');
      expect(repository.accountIdentity.value!.uid, '901');
      expect(
          await fixture.initialClient.getOnce('echo'), 'winduser=synthetic-A');
      final hits = fixture.requests.length;
      await repository.updateNetworkConfig(
          _siteA.copyWith(mode: ForumNetworkMode.optimized));
      expect(fixture.requests.length, hits);
      expect(repository.isLoggedIn, isTrue);
      expect(repository.currentUsername, 'Synthetic A');
      expect(repository.accountIdentity.value!.uid, '901');
      expect(repository.activeAccount.value!.id, accountA);
      expect(repository.localDataScope, scopeA);
      expect(canUseOwner(repository, '901'), isTrue);
      expect(canUseOwner(repository, '903'), isFalse);
      fixture.unblock();
      await cancelled;
      fixture.holdBHeader = false;
      await repository.updateNetworkConfig(_siteA);
      expect(await repository.restoreSession(), isTrue);
      expect(repository.currentUsername, 'Synthetic A');
      expect(fixture.requests.last.$2, 'winduser=synthetic-A');
      expect(
          repository.accounts.value.map((account) => account.id), [accountA]);
      expect(repository.activeAccount.value!.id, accountA);
      expect(repository.localDataScope, scopeA);
      expect(
          (await ForumSessionStore.forSlot(
                      slotId: accountA, origin: _siteA.baseUri)
                  .loadCookies())
              .values
              .map((cookie) => cookie.value),
          ['synthetic-A']);
      expect(canUseOwner(repository, '901'), isTrue);
      expect(canUseOwner(repository, '903'), isFalse);
      expect(fixture.loginHits, 1);
    });
  });

  test(
      'cross-origin switch clears foreign active and keeps restored origin jar',
      () async {
    await withFixture((fixture) async {
      final repository = fixture.repository;
      final activeA = repository.activeAccount.value;
      expect(activeA, isNotNull, reason: 'fixture starts signed-in on site A');
      await ForumSessionStore(origin: _siteB.baseUri).saveCookies({
        'B': ForumStoredCookie.session(
            name: 'winduser', value: 'synthetic-B', origin: _siteB.baseUri),
      });
      final hits = fixture.requests.length;
      await repository.updateNetworkConfig(_siteB);
      expect(fixture.requests.length, hits,
          reason: 'network config must not implicit-HTTP');
      expect(repository.activeAccount.value, isNull);
      expect(repository.localPreferenceAccount,
          AccountScope.guest(_siteB.baseUri));
      expect(repository.networkConfig.baseUri.origin, _siteB.baseUri.origin);
      expect(
        repository.accounts.value.any((a) => a.id == activeA!.id),
        isTrue,
        reason: 'cross-origin must not delete the previous origin account',
      );
      final stored =
          await ForumSessionStore(origin: _siteB.baseUri).loadCookies();
      expect(
        stored.values.where((c) => c.name == 'winduser').single.value,
        'synthetic-B',
      );
      expect(repository.isLoggedIn, isTrue);
    });
  });
}

class _Fixture {
  _Fixture(this.initialClient, this.repository);
  final ForumClient initialClient;
  final ForumRepository repository;
  final requests = <(String?, String?)>[];
  String? holdPath;
  bool holdBHeader = false;
  int loginHits = 0;
  final received = Completer<void>();
  final _release = Completer<void>();
  void unblock() {
    if (!_release.isCompleted) _release.complete();
  }

  Future<void> handle(HttpRequest request) async {
    final cookie = request.headers.value(HttpHeaders.cookieHeader);
    requests.add((request.headers.host, cookie));
    final body = await utf8.decoder.bind(request).join();
    try {
      if (request.uri.path == holdPath ||
          (holdBHeader &&
              request.uri.path == '/index.php' &&
              cookie == 'winduser=synthetic-B')) {
        if (!received.isCompleted) received.complete();
        await _release.future;
      }
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/fixture-session') {
        request.response.headers.add(HttpHeaders.setCookieHeader,
            'winduser=synthetic-${request.uri.queryParameters['owner']}; Path=/');
      } else if (request.uri.path == '/login.php') {
        loginHits++;
        expect(Uri.splitQueryString(body)['pwuser'], 'Synthetic B');
        request.response.headers
            .add(HttpHeaders.setCookieHeader, 'winduser=synthetic-B; Path=/');
        request.response.write('登录成功');
      } else if (request.uri.path == '/index.php') {
        final owner = cookie == 'winduser=synthetic-B' ? 'B' : 'A';
        request.response.write('''<html><body>
<div id="user-login"><a href="u.php">Synthetic $owner</a></div>
<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-${owner == 'A' ? '901' : '903'}.html">个人资料</a></div></div>
</body></html>''');
      } else if (request.uri.path == '/read.php') {
        request.response.write(
            '''<h1 id="subject_tpc">Synthetic thread</h1><a href="read.php?tid-70.html">Thread</a>
<div class="pages">Pages: 1/1</div><table class="js-post"><tr>
<th class="r_two"><a href="u.php?action-show-uid-903.html"><strong>Synthetic B</strong></a></th>
<th class="r_one" id="td_tpc"><div id="read_tpc">Synthetic body</div></th></tr></table>''');
      } else if (request.uri.path == '/held') {
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=synthetic-stale; Path=/');
      } else if (request.uri.path == '/echo') {
        request.response.write(cookie ?? 'guest');
      }
      await request.response.close();
    } on SocketException {
      /* The route change deliberately closes this peer. */
    } on HttpException {/* The route change deliberately closes this peer. */}
  }
}

class _NativeOverrides extends ForumHttpOverrides {
  _NativeOverrides(this.port, this.trust);
  final int port;
  final SecurityContext trust;
  final clients = <HttpClient>[];
  @override
  HttpClient createUnroutedClient(SecurityContext? context) {
    final client = super.createUnroutedClient(trust);
    clients.add(client);
    client.connectionFactory = (uri, _, __) async {
      final task =
          await Socket.startConnect(InternetAddress.loopbackIPv4, port);
      return ConnectionTask.fromSocket<Socket>(
          task.socket.then((socket) =>
              SecureSocket.secure(socket, host: uri.host, context: trust)),
          task.cancel);
    };
    return client;
  }
}

class _BlockingStore extends ForumSessionStore {
  _BlockingStore(Uri origin) : super(origin: origin);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> saveCookies(Map<String, ForumStoredCookie> cookies) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.saveCookies(cookies);
  }
}
