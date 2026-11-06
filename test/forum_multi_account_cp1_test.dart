import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_account_id.dart';
import 'package:south_plus_rewrite/services/forum_account_registry.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_multi_account_session.dart';
import 'package:south_plus_rewrite/services/forum_session_slots.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';

class _OriginClient extends ForumClient {
  _OriginClient(this.host)
      : super(
          httpClient: ForumHttpOverrides().createUnroutedClient(null)
            ..findProxy = ((_) => 'DIRECT')
            ..connectionFactory = (uri, _, __) async =>
                throw const SocketException('cp1-test-no-network'),
          delay: (_) async {},
        );
  final String host;
  @override
  Uri get baseUri => Uri.https(host, '/');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ForumAccountId', () {
    test('stable encoding round-trips normalized origin+uid', () {
      final id = ForumAccountId(
        origin: Uri.parse('https://South.Plus:443/path'),
        uid: '42',
      );
      expect(id.origin.toString(), 'https://south.plus');
      expect(id.value, 'https://south.plus${ForumAccountId.separator}42');
      expect(ForumAccountId.parse(id.value), id);
      expect(ForumAccountId.tryParse('nickname-only'), isNull);
      expect(
          ForumAccountId.tryParse(
              'https://south.plus${ForumAccountId.separator}0'),
          isNull);
      expect(
          () => ForumAccountId(
              origin: Uri.parse('https://south.plus'), uid: 'alice'),
          throwsFormatException);
    });
  });

  group('per-slot generations', () {
    test('bumping one slot does not revoke a sibling on the same host',
        () async {
      final a = _OriginClient('fixture.invalid');
      final b = _OriginClient('fixture.invalid');
      final origin = a.baseUri;
      final accountA = ForumAccountId(origin: origin, uid: '1').value;
      final accountB = ForumAccountId(origin: origin, uid: '2').value;
      a.bindSlot(ForumSessionSlots.account(accountA));
      b.bindSlot(ForumSessionSlots.account(accountB));
      final genB = b.credentialGeneration;
      final beforeA = a.credentialGeneration;
      await a.clearSession();
      expect(a.isCredentialCurrent(beforeA), isFalse);
      expect(b.isCredentialCurrent(genB), isTrue,
          reason: 'sibling slot on same host must keep its generation');
      a.close();
      b.close();
    });

    test('retireSlot prevents ABA reuse after remove+re-add', () {
      final client = _OriginClient('fixture.invalid');
      final accountId = ForumAccountId(origin: client.baseUri, uid: '9').value;
      final slot = ForumSessionSlots.account(accountId);
      client.bindSlot(slot);
      final first = client.credentialGeneration;
      ForumClient.retireSlot(slot);
      client.bindSlot(slot);
      expect(client.credentialGeneration, greaterThan(first));
      expect(client.isCredentialCurrent(first), isFalse);
      client.close();
    });
  });

  group('session store slots', () {
    test('staging prefs key is null (memory-only)', () {
      final origin = Uri.https('fixture.invalid', '/');
      final staging = ForumSessionSlots.staging(origin, 'abc123');
      expect(ForumSessionSlots.cookiesPrefsKey(staging), isNull);
      final store = ForumSessionStore.forSlot(slotId: staging, origin: origin);
      expect(store.isMemoryOnly, isTrue);
    });

    test('logout tombstone blocks legacy re-import for account key', () async {
      final origin = Uri.https('fixture.invalid', '/');
      final accountId = ForumAccountId(origin: origin, uid: '3').value;
      final store = ForumSessionStore.forSlot(
        slotId: ForumSessionSlots.account(accountId),
        origin: origin,
      );
      await store.saveCookies({
        'winduser': ForumStoredCookie.session(
            name: 'winduser', value: 'tok', origin: origin),
      });
      await store.clear();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ForumSessionSlots.cookiesPrefsKey(accountId)!),
        '{}',
      );
      expect(await store.loadCookies(), isEmpty);
    });
  });

  group('ForumMultiAccountSession', () {
    late _OriginClient client;
    late ForumMultiAccountSession session;
    late ValueNotifier<int> epoch;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      epoch = ValueNotifier<int>(0);
      client = _OriginClient('fixture.invalid');
      session = ForumMultiAccountSession(client: client, sessionEpoch: epoch);
    });

    tearDown(() {
      session.dispose();
      client.close();
      epoch.dispose();
    });

    Future<AccountSummary> seedAccount(String uid,
        {String token = 'tok'}) async {
      final origin = client.baseUri;
      final accountId = ForumAccountId(origin: origin, uid: uid).value;
      await ForumSessionStore.promoteToAccount(
        accountId: accountId,
        origin: origin,
        cookies: {
          'winduser': ForumStoredCookie.session(
              name: 'winduser', value: token, origin: origin),
        },
      );
      await session.registry.upsert(
        accountId: accountId,
        systemName: 'u$uid',
        nickname: 'Nick$uid',
        status: AccountReadyState.ready,
      );
      await session.switchAccount(accountId);
      return session.registry.find(accountId)!;
    }

    test('same uid upsert keeps a single registry row', () async {
      final id = ForumAccountId(origin: client.baseUri, uid: '11').value;
      await session.registry
          .upsert(accountId: id, systemName: 'a', nickname: 'One');
      await session.registry
          .upsert(accountId: id, systemName: 'a', nickname: 'Two');
      expect(session.accounts.value.where((a) => a.id == id).length, 1);
      expect(session.accounts.value.single.displayName, 'Two');
    });

    test(
        'logout active clears creds, needsReauth, enters guest and bumps epoch',
        () async {
      final account = await seedAccount('21');
      final epochBefore = epoch.value;
      expect(client.isLoggedIn, isTrue);
      await session.logoutAccount(account.id);
      expect(session.activeAccount.value, isNull);
      expect(client.isLoggedIn, isFalse);
      expect(session.registry.find(account.id)!.status,
          AccountReadyState.needsReauth);
      expect(epoch.value, greaterThan(epochBefore));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ForumSessionSlots.cookiesPrefsKey(account.id)!),
        '{}',
      );
    });

    test('remove non-active leaves current session and epoch alone', () async {
      final a = await seedAccount('31', token: 'a');
      final bId = ForumAccountId(origin: client.baseUri, uid: '32').value;
      await ForumSessionStore.promoteToAccount(
        accountId: bId,
        origin: client.baseUri,
        cookies: {
          'winduser': ForumStoredCookie.session(
              name: 'winduser', value: 'b', origin: client.baseUri),
        },
      );
      await session.registry.upsert(accountId: bId, systemName: 'b');
      final epochBefore = epoch.value;
      final gen = client.credentialGeneration;
      await session.removeAccount(bId);
      expect(session.registry.find(bId), isNull);
      expect(session.activeAccount.value?.id, a.id);
      expect(client.isCredentialCurrent(gen), isTrue);
      expect(epoch.value, epochBefore);
      expect(client.isLoggedIn, isTrue);
    });

    test('remove active enters guest and retires generation', () async {
      final account = await seedAccount('41');
      final slot = ForumSessionSlots.account(account.id);
      final genBefore = client.credentialGeneration;
      final epochBefore = epoch.value;
      await session.removeAccount(account.id);
      expect(session.activeAccount.value, isNull);
      expect(client.isLoggedIn, isFalse);
      expect(epoch.value, greaterThan(epochBefore));
      await ForumSessionStore.promoteToAccount(
        accountId: account.id,
        origin: client.baseUri,
        cookies: {
          'winduser': ForumStoredCookie.session(
              name: 'winduser', value: 'again', origin: client.baseUri),
        },
      );
      await session.registry.upsert(accountId: account.id, systemName: 'u41');
      await session.switchAccount(account.id);
      expect(client.credentialGeneration, greaterThan(genBefore));
      expect(client.isCredentialCurrent(genBefore), isFalse);
      expect(client.slotId, slot);
    });

    test('logout retires slot gen so stale admit cannot revive tombstone',
        () async {
      final account = await seedAccount('81', token: 'alive');
      final slot = ForumSessionSlots.account(account.id);
      // Keep a second client bound to the account slot across logout. The
      // session client moves to guest/origin, so only this observer still
      // evaluates the retired account generation.
      final observer = _OriginClient('fixture.invalid');
      observer.bindSlot(slot);
      final observerGen = observer.credentialGeneration;
      expect(observer.isCredentialCurrent(observerGen), isTrue);

      await session.logoutAccount(account.id);

      expect(observer.isCredentialCurrent(observerGen), isFalse,
          reason: 'retireSlot must invalidate every client on that slot');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ForumSessionSlots.cookiesPrefsKey(slot)!), '{}');
      final reloader = _OriginClient('fixture.invalid');
      reloader.bindSlot(slot);
      await reloader.restoreCookies();
      expect(reloader.isLoggedIn, isFalse);
      expect(
          await ForumSessionStore.forSlot(slotId: slot, origin: client.baseUri)
              .loadCookies(),
          isEmpty);
      observer.close();
      reloader.close();
    });

    for (final remove in [false, true]) {
      for (final saving in [false, true]) {
        test(
            '${remove ? 'remove' : 'logout'} rejects '
            '${saving ? 'an already started cookie save' : 'a delayed HTTP cookie'}',
            () async {
          final origin = Uri.http('retirement.fixture.invalid', '/');
          final accountId = ForumAccountId(origin: origin, uid: '82').value;
          final slot = ForumSessionSlots.account(accountId);
          final initial =
              ForumSessionStore.forSlot(slotId: slot, origin: origin);
          await initial.saveCookies({
            'winduser': ForumStoredCookie.session(
                name: 'winduser', value: 'initial', origin: origin),
          });
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final transport = ForumHttpOverrides().createUnroutedClient(null)
            ..findProxy = ((_) => 'DIRECT')
            ..connectionFactory = (uri, _, __) =>
                Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
          final delayed = _DelayedCookieStore(
              slotId: slot, origin: origin, holdSave: saving);
          final racer = _RacerClient(origin, transport, sessionStore: delayed);
          racer.bindSlot(slot);
          final retiring = ForumMultiAccountSession(client: racer);
          final received = Completer<void>();
          final releaseResponse = Completer<void>();
          addTearDown(() async {
            if (!releaseResponse.isCompleted) releaseResponse.complete();
            if (!delayed.release.isCompleted) delayed.release.complete();
            retiring.dispose();
            racer.close();
            transport.close(force: true);
            await server.close(force: true);
          });
          await retiring.registry
              .upsert(accountId: accountId, systemName: 'Account A');
          await retiring.switchAccount(accountId);
          server.listen((request) async {
            await request.drain<void>();
            if (!received.isCompleted) received.complete();
            if (!saving) await releaseResponse.future;
            request.response.headers
                .add(HttpHeaders.setCookieHeader, 'winduser=revived; Path=/');
            request.response.write('ok');
            await request.response.close();
          });
          final response = racer.getOnce('late').then<Object?>((value) => value,
              onError: (Object error) => error);
          await (saving ? delayed.started.future : received.future)
              .timeout(const Duration(seconds: 2));
          final retirement = remove
              ? retiring.removeAccount(accountId)
              : retiring.logoutAccount(accountId);
          await Future<void>.delayed(Duration.zero);
          releaseResponse.complete();
          delayed.release.complete();
          await retirement;
          await response;
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          expect(
              prefs.getString(ForumSessionSlots.cookiesPrefsKey(slot)!), '{}');
          expect(await initial.loadCookies(), isEmpty);
          expect(racer.isLoggedIn, isFalse);
          expect(retiring.activeAccount.value, isNull);
          if (remove) {
            expect(retiring.registry.find(accountId), isNull);
          } else {
            expect(retiring.registry.find(accountId)?.status,
                AccountReadyState.needsReauth);
          }
        });
      }
    }
  });
}

class _RacerClient extends ForumClient {
  _RacerClient(this.baseUri, HttpClient transport,
      {ForumSessionStore? sessionStore})
      : super(
            httpClient: transport,
            sessionStore: sessionStore,
            delay: (_) async {});
  @override
  final Uri baseUri;
}

class _DelayedCookieStore extends ForumSessionStore {
  _DelayedCookieStore(
      {required super.slotId, required super.origin, required this.holdSave})
      : super.forSlot();
  final bool holdSave;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> saveCookies(Map<String, ForumStoredCookie> cookies) async {
    if (holdSave) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    await super.saveCookies(cookies);
  }
}
