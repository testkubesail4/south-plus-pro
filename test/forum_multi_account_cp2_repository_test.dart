import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_account_id.dart';
import 'package:south_plus_rewrite/services/forum_account_registry.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_slots.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';

const _config = ForumNetworkConfig(
  site: ForumSite('fixture.invalid'),
  mode: ForumNetworkMode.native,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  for (final remove in [false, true]) {
    test(
        'late ${remove ? 'remove' : 'logout'} A must retain explicitly selected B',
        () async {
      SharedPreferences.resetStatic();
      final gate = _RetirementGateStore();
      SharedPreferencesStorePlatform.instance = gate;
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        final b = await fx.addAccount(username: 'userB', uid: '102');
        await fx.repo.switchAccount(a.id);
        gate.accountKey = 'flutter.${ForumSessionSlots.cookiesPrefsKey(a.id)}';
        gate.armed = true;
        final retiring =
            (remove ? fx.repo.removeAccount(a.id) : fx.repo.logoutAccount(a.id))
                .then<Object?>((_) => null, onError: (Object error) => error);
        Future<Object?>? switching;
        try {
          await gate.accountStarted.future.timeout(const Duration(seconds: 2));
          switching = fx.repo
              .switchAccount(b.id)
              .then<Object?>((_) => null, onError: (Object error) => error);
          gate.releaseAccount.complete();
          await gate.originStarted.future.timeout(const Duration(seconds: 2));
          final switched = await switching.timeout(const Duration(seconds: 2));
          expect(switched, isNull);
          expect(fx.repo.activeAccount.value?.id, b.id);
          expect(fx.repo.accountIdentity.value?.uid, '102');
          final epochB = fx.repo.sessionEpoch.value;
          gate.releaseOrigin.complete();
          final retired = await retiring;
          expect(retired, isNull);
          expect(fx.repo.activeAccount.value?.id, b.id);
          expect(fx.repo.accountIdentity.value?.uid, '102');
          expect(fx.repo.currentUsername, 'Synthetic B');
          expect(fx.repo.localDataScope, b.id);
          expect(fx.repo.isLoggedIn, isTrue);
          expect(fx.repo.sessionEpoch.value, epochB);
          expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-102');
          if (remove) {
            expect(
                fx.repo.accounts.value.any((row) => row.id == a.id), isFalse);
          } else {
            expect(
                fx.repo.accounts.value
                    .singleWhere((row) => row.id == a.id)
                    .status,
                AccountReadyState.needsReauth);
          }
        } finally {
          if (!gate.releaseAccount.isCompleted) gate.releaseAccount.complete();
          if (!gate.releaseOrigin.isCompleted) gate.releaseOrigin.complete();
          await switching;
          await retiring;
        }
      });
    });
  }

  for (final remove in [false, true]) {
    test(
        'late ${remove ? 'remove' : 'logout'} cannot retire a re-added same uid',
        () async {
      SharedPreferences.resetStatic();
      final gate = _RetirementGateStore();
      SharedPreferencesStorePlatform.instance = gate;
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        final challenge = await fx.repo.fetchAddAccountChallenge();
        fx.server.tokenSuffix = '-fresh';
        fx.server.holdIdentity = Completer<void>();
        fx.server.identitySeen = Completer<void>();
        fx.overrides.identityConsumed = Completer<void>();
        final adding = fx.repo
            .submitAddAccount(
                username: 'userA',
                password: 'pw',
                captcha: '1234',
                fields: challenge.fields)
            .then<Object>((value) => value, onError: (Object error) => error);
        Future<Object?>? retiring;
        try {
          await fx.server.identitySeen!.future
              .timeout(const Duration(seconds: 5));
          gate.accountKey =
              'flutter.${ForumSessionSlots.cookiesPrefsKey(a.id)}';
          gate.holdFreshJar = true;
          gate.armed = true;
          retiring = (remove
                  ? fx.repo.removeAccount(a.id)
                  : fx.repo.logoutAccount(a.id))
              .then<Object?>((_) => null, onError: (Object error) => error);
          await gate.accountStarted.future.timeout(const Duration(seconds: 2));
          fx.server.holdIdentity!.complete();
          await fx.overrides.identityConsumed!.future
              .timeout(const Duration(seconds: 2));
          // Drain the completed response's continuations before releasing storage.
          await Future<void>.delayed(Duration.zero);
          gate.releaseAccount.complete();
          await gate.freshStarted.future.timeout(const Duration(seconds: 2));
          expect(gate.originStarted.isCompleted, isFalse,
              reason:
                  'the authenticated commit precedes the old origin cleanup');
          gate.releaseFresh.complete();
          await gate.originStarted.future.timeout(const Duration(seconds: 2));
          expect(await adding, isA<AccountSummary>());
          final epoch = fx.repo.sessionEpoch.value;
          final generation = fx.client.credentialGeneration;
          expect(fx.repo.activeAccount.value?.id, a.id);
          expect(fx.repo.activeAccount.value?.status, AccountReadyState.ready);
          final freshJar = await fx.cookieSnapshot(a.id);
          gate.releaseOrigin.complete();
          expect(await retiring, isNull);
          expect(fx.repo.activeAccount.value?.id, a.id);
          expect(fx.repo.activeAccount.value?.status, AccountReadyState.ready);
          expect(fx.repo.accounts.value.map((row) => row.id), [a.id]);
          expect(fx.repo.accountIdentity.value?.uid, '101');
          expect(fx.repo.currentUsername, 'Synthetic A');
          expect(fx.repo.sessionEpoch.value, epoch);
          expect(fx.client.isCredentialCurrent(generation), isTrue);
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          expect(await fx.cookieSnapshot(a.id), freshJar);
          expect(await fx.client.getOnce('cookie-echo'),
              'winduser=token-101-fresh');
        } finally {
          if (fx.server.holdIdentity != null &&
              !fx.server.holdIdentity!.isCompleted) {
            fx.server.holdIdentity!.complete();
          }
          if (!gate.releaseAccount.isCompleted) gate.releaseAccount.complete();
          if (!gate.releaseFresh.isCompleted) gate.releaseFresh.complete();
          if (!gate.releaseOrigin.isCompleted) gate.releaseOrigin.complete();
          await adding;
          await retiring;
        }
      });
    });
  }

  test('pending guest logout cannot change a later site session', () async {
    SharedPreferences.resetStatic();
    final gate = _RetirementGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final other = _config.copyWith(site: const ForumSite('localhost'));
      await fx.repo.updateNetworkConfig(other);
      await fx.addAccount(username: 'userB', uid: '102');
      await fx.repo.updateNetworkConfig(_config);
      expect(fx.repo.activeAccount.value, isNull);
      expect(fx.repo.isLoggedIn, isFalse);
      gate.armed = true;
      final retiring = fx.repo
          .logoutCurrent()
          .then<Object?>((_) => null, onError: (Object error) => error);
      try {
        await gate.originStarted.future.timeout(const Duration(seconds: 2));
        await fx.repo.updateNetworkConfig(other);
        final epoch = fx.repo.sessionEpoch.value;
        expect(fx.repo.localDataScope, 'guest:https://localhost');
        gate.releaseOrigin.complete();
        expect(await retiring, isNull);
        expect(fx.repo.networkConfig, other);
        expect(fx.repo.localDataScope, 'guest:https://localhost');
        expect(fx.repo.sessionEpoch.value, epoch);
        expect(fx.repo.activeAccount.value, isNull);
        expect(fx.repo.isLoggedIn, isFalse);
      } finally {
        if (!gate.releaseOrigin.isCompleted) gate.releaseOrigin.complete();
        await retiring;
      }
    });
  });

  test(
      'incomplete saved summary cannot publish an old header after another switch',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final b = await fx.addAccount(username: 'userB', uid: '102');
      final c = await fx.addAccount(username: 'userC', uid: '103');
      await fx.repo.switchAccount(a.id);
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString(ForumAccountRegistry.prefsKey)!)
          as Map<String, dynamic>;
      for (final row in raw['accounts'] as List) {
        if ((row as Map)['id'] == b.id) row['uid'] = null;
      }
      await prefs.setString(ForumAccountRegistry.prefsKey, jsonEncode(raw));
      await fx.repo.restoreSession();
      expect(fx.repo.accounts.value.singleWhere((row) => row.id == b.id).uid,
          isNull);
      fx.server.headerUidToHold = '102';
      fx.server.headerStarted = Completer<void>();
      fx.server.releaseHeader = Completer<void>();
      final first = fx.repo
          .switchAccount(b.id)
          .then<Object?>((_) => null, onError: (Object error) => error);
      try {
        await fx.server.headerStarted!.future
            .timeout(const Duration(seconds: 2));
        await fx.repo.switchAccount(c.id);
        final epochC = fx.repo.sessionEpoch.value;
        expect(fx.repo.accountIdentity.value?.uid, '103');
        fx.server.releaseHeader!.complete();
        await first;
        expect(fx.repo.activeAccount.value?.id, c.id);
        expect(fx.repo.accountIdentity.value?.uid, '103');
        expect(fx.repo.currentUsername, 'User 103');
        expect(fx.repo.sessionEpoch.value, epochC);
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-103');
      } finally {
        if (!fx.server.releaseHeader!.isCompleted)
          fx.server.releaseHeader!.complete();
        await first;
      }
    });
  });

  for (final readd in [false, true]) {
    test(
        'pending reauth cannot revive a ${readd ? 're-added' : 'removed'} target',
        () async {
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        final challenge = await fx.repo.fetchReauthChallenge(a.id);
        final oldPost = Completer<void>();
        fx.server.holdLogin = oldPost;
        fx.server.loginHeld = Completer<void>();
        final reauth = fx.repo
            .submitReauthAccount(a.id,
                username: 'userA',
                password: 'pw',
                captcha: '1234',
                fields: challenge.fields)
            .then<Object>((value) => value, onError: (Object error) => error);
        try {
          await fx.server.loginHeld!.future.timeout(const Duration(seconds: 2));
          fx.server.holdLogin = null;
          fx.server.loginHeld = null;
          await fx.repo.removeAccount(a.id);
          if (readd) {
            fx.server.tokenSuffix = '-fresh';
            await fx.addAccount(username: 'userA', uid: '101');
          }
          final epoch = fx.repo.sessionEpoch.value;
          final generation = fx.client.credentialGeneration;
          final jar = await fx.cookieSnapshot(a.id);
          fx.server.tokenSuffix = '-stale';
          oldPost.complete();
          expect(await reauth, isA<ForumRepositoryException>());
          expect(fx.repo.sessionEpoch.value, epoch);
          expect(fx.client.isCredentialCurrent(generation), isTrue);
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          expect(await fx.cookieSnapshot(a.id), jar);
          if (readd) {
            expect(fx.repo.activeAccount.value?.id, a.id);
            expect(fx.repo.accounts.value.map((row) => row.id), [a.id]);
            expect(fx.repo.accountIdentity.value?.uid, '101');
            expect(await fx.client.getOnce('cookie-echo'),
                'winduser=token-101-fresh');
          } else {
            expect(fx.repo.activeAccount.value, isNull);
            expect(fx.repo.accounts.value, isEmpty);
            expect(fx.repo.isLoggedIn, isFalse);
          }
        } finally {
          if (!oldPost.isCompleted) oldPost.complete();
          await reauth;
        }
      });
    });
  }

  test(
      'a reauth challenge from before removal cannot submit into a new incarnation',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final challenge = await fx.repo.fetchReauthChallenge(a.id);
      await fx.repo.removeAccount(a.id);
      fx.server.tokenSuffix = '-fresh';
      await fx.addAccount(username: 'userA', uid: '101');
      final hits = fx.server.requests.length;
      final epoch = fx.repo.sessionEpoch.value;
      final jar = await fx.cookieSnapshot(a.id);
      fx.server.tokenSuffix = '-stale';
      await expectLater(
          fx.repo.submitReauthAccount(a.id,
              username: 'userA',
              password: 'pw',
              captcha: '1234',
              fields: challenge.fields),
          throwsA(isA<ForumRepositoryException>()));
      expect(fx.server.requests.length, hits);
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.accounts.value.map((row) => row.id), [a.id]);
      expect(await fx.cookieSnapshot(a.id), jar);
      expect(
          await fx.client.getOnce('cookie-echo'), 'winduser=token-101-fresh');
    });
  });

  test('reauth challenge admitted during removal cannot outlive the record',
      () async {
    SharedPreferences.resetStatic();
    final gate = _RetirementGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      gate.accountKey = 'flutter.${ForumSessionSlots.cookiesPrefsKey(a.id)}';
      gate.armed = true;
      final removing = fx.repo
          .removeAccount(a.id)
          .then<Object?>((_) => null, onError: (Object error) => error);
      Future<Object>? fetching;
      try {
        await gate.accountStarted.future.timeout(const Duration(seconds: 2));
        fetching = fx.repo
            .fetchReauthChallenge(a.id)
            .then<Object>((value) => value, onError: (Object error) => error);
        await Future<void>.delayed(Duration.zero);
        expect(fx.repo.accounts.value.any((row) => row.id == a.id), isTrue);
        gate.releaseOrigin.complete();
        gate.releaseAccount.complete();
        expect(await removing, isNull);
        expect(await fetching, isA<ForumRepositoryException>());
        expect(fx.repo.accounts.value, isEmpty);
        expect(fx.repo.activeAccount.value, isNull);
        expect(fx.repo.isLoggedIn, isFalse);
      } finally {
        if (!gate.releaseAccount.isCompleted) gate.releaseAccount.complete();
        if (!gate.releaseOrigin.isCompleted) gate.releaseOrigin.complete();
        await removing;
        await fetching;
      }
    });
  });

  test('foreign select rejects before changing either account', () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final origin = Uri.https('localhost', '/');
      final foreign = ForumAccountId(origin: origin, uid: '401').value;
      final store = ForumSessionStore.forSlot(slotId: foreign, origin: origin);
      await store.saveCookies({
        'winduser': ForumStoredCookie.session(
            name: 'winduser', value: 'foreign', origin: origin),
      });
      final registry = ForumAccountRegistry();
      await registry.load();
      await registry.upsert(accountId: foreign, systemName: 'Foreign');
      registry.dispose();
      await fx.repo.restoreSession();
      final epoch = fx.repo.sessionEpoch.value;
      final hits = fx.server.requests.length;
      final aCookies = await fx.cookieSnapshot(a.id);
      await expectLater(fx.repo.selectAccount(foreign),
          throwsA(isA<ForumRepositoryException>()));
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(fx.repo.accounts.value.singleWhere((a) => a.id == foreign).status,
          AccountReadyState.ready);
      expect(fx.server.requests.length, hits);
      expect(await fx.cookieSnapshot(a.id), aCookies);
      expect((await store.loadCookies()).values.single.value, 'foreign');
    });
  });

  test('foreign reauth rejects even when the current site has the same uid',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final origin = Uri.https('localhost', '/');
      final foreign = ForumAccountId(origin: origin, uid: '101').value;
      final registry = ForumAccountRegistry();
      await registry.load();
      await registry.upsert(
          accountId: foreign,
          systemName: 'Foreign',
          status: AccountReadyState.needsReauth);
      registry.dispose();
      await fx.repo.restoreSession();
      final epoch = fx.repo.sessionEpoch.value;
      final hits = fx.server.requests.length;
      final original = await fx.cookieSnapshot(a.id);
      await expectLater(fx.repo.fetchReauthChallenge(foreign),
          throwsA(isA<ForumRepositoryException>()));
      await expectLater(
          fx.repo.submitReauthAccount(foreign,
              username: 'userA', password: 'pw', captcha: '1234'),
          throwsA(isA<ForumRepositoryException>()));
      expect(fx.server.requests.length, hits);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(await fx.cookieSnapshot(a.id), original);
      expect(await fx.cookieSnapshot(foreign), isNull);
      expect(fx.repo.accounts.value.singleWhere((a) => a.id == foreign).status,
          AccountReadyState.needsReauth);
    });
  });

  for (final reauth in [false, true]) {
    for (final active in [false, true]) {
      test(
          'same uid ${reauth ? 'reauth' : 'add'} installs fresh credentials '
          'for ${active ? 'active' : 'inactive'} A and rejects its old response',
          () async {
        await _withCp2Fixture((fx) async {
          final a = await fx.addAccount(username: 'userA', uid: '101');
          final oldGeneration = fx.client.credentialGeneration;
          fx.server.rotateReceived = Completer<void>();
          fx.server.releaseRotation = Completer<void>();
          fx.server.rotationToken = 'token-101-stale';
          final oldRead = fx.client.getOnce('cookie-rotate').then<Object?>(
              (value) => value,
              onError: (Object error) => error);
          try {
            await fx.server.rotateReceived!.future
                .timeout(const Duration(seconds: 2));
            if (!active) {
              await fx.addAccount(username: 'userB', uid: '102');
            }
            final epoch = fx.repo.sessionEpoch.value;
            fx.server.tokenSuffix = '-fresh';
            final AccountSummary refreshed;
            if (reauth) {
              final challenge = await fx.repo.fetchReauthChallenge(a.id);
              refreshed = await fx.repo.submitReauthAccount(a.id,
                  username: 'userA',
                  password: 'pw',
                  captcha: '1234',
                  fields: challenge.fields);
            } else {
              refreshed = await fx.addAccount(username: 'userA', uid: '101');
            }
            fx.server.releaseRotation!.complete();
            await oldRead;
            expect(refreshed.id, a.id);
            expect(fx.repo.accounts.value.where((row) => row.id == a.id),
                hasLength(1));
            expect(fx.repo.activeAccount.value?.id, a.id);
            expect(fx.repo.sessionEpoch.value, epoch + 1);
            expect(fx.client.isCredentialCurrent(oldGeneration), isFalse);
            expect(await fx.client.getOnce('cookie-echo'),
                'winduser=token-101-fresh');
            final cookies = await ForumSessionStore.forSlot(
                    slotId: a.id, origin: fx.client.baseUri)
                .loadCookies();
            expect(cookies.values.single.value, 'token-101-fresh');
          } finally {
            if (!fx.server.releaseRotation!.isCompleted) {
              fx.server.releaseRotation!.complete();
            }
            await oldRead;
          }
        });
      });
    }
  }

  test('promotion retires an admitted origin write queued behind another jar',
      () async {
    await _withCp2Fixture((fx) async {
      final origin = fx.client.baseUri;
      final originStore = ForumSessionStore(origin: origin);
      await originStore.saveCookies({
        'winduser': ForumStoredCookie.session(
            name: 'winduser', value: 'token-101', origin: origin),
      });
      await fx.client.restoreCookies();
      final otherConfig = _config.copyWith(site: const ForumSite('localhost'));
      final blocker = _MigrationBlockingStore(otherConfig.baseUri);
      final other = ForumClient(
          config: otherConfig, sessionStore: blocker, delay: (_) async {});
      final otherResponse = other
          .getOnce('cookie-rotate')
          .then<Object?>((value) => value, onError: (Object error) => error);
      Future<Object?>? rotation;
      Future<bool>? migration;
      try {
        await blocker.started.future.timeout(const Duration(seconds: 2));
        rotation = fx.client
            .getOnce('cookie-rotate')
            .then<Object?>((value) => value, onError: (Object error) => error);
        final watch = Stopwatch()..start();
        while (!fx.client
            .exportCookies()
            .values
            .any((cookie) => cookie.value == 'token-101-fresh')) {
          if (watch.elapsed > const Duration(seconds: 2)) {
            throw TimeoutException('Origin cookie was not admitted');
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        migration = fx.repo.restoreSession();
        while (fx.repo.currentUsername != 'Synthetic A') {
          if (watch.elapsed > const Duration(seconds: 3)) {
            throw TimeoutException('Migration identity was not published');
          }
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await Future<void>.delayed(Duration.zero);
        blocker.release.complete();
        expect(await migration, isTrue);
        await rotation;
        await otherResponse;
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(await originStore.loadCookies(), isEmpty);
        expect(fx.repo.activeAccount.value?.uid, '101');
        expect(
            await fx.client.getOnce('cookie-echo'), 'winduser=token-101-fresh');
      } finally {
        if (!blocker.release.isCompleted) blocker.release.complete();
        await otherResponse;
        await rotation;
        await migration;
        other.close(force: true);
      }
    });
  });

  test('expired restore enters guest and keeps an account needing reauth',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      fx.server.expired = true;
      expect(await fx.repo.restoreSession(), isFalse);
      expect(fx.repo.isLoggedIn, isFalse);
      expect(fx.repo.activeAccount.value, isNull);
      expect(fx.repo.accounts.value.singleWhere((row) => row.id == a.id).status,
          AccountReadyState.needsReauth);
      expect(fx.repo.localDataScope, 'guest:https://fixture.invalid');
    });
  });

  for (final reject in [false, true]) {
    test(
        'account switch preserves A until registry ${reject ? 'failure' : 'acknowledgement'}',
        () async {
      SharedPreferences.resetStatic();
      final gate = _RegistryGateStore();
      SharedPreferencesStorePlatform.instance = gate;
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        final b = await fx.addAccount(username: 'userB', uid: '102');
        await fx.repo.switchAccount(a.id);
        final epoch = fx.repo.sessionEpoch.value;
        final generation = fx.client.credentialGeneration;
        final observations = <(String?, String, int)>[];
        void observe() {
          observations.add((
            fx.repo.activeAccount.value?.uid,
            fx.client.exportCookies().values.single.value,
            fx.repo.sessionEpoch.value
          ));
        }

        fx.repo.accounts.addListener(observe);
        fx.repo.activeAccount.addListener(observe);
        fx.repo.sessionEpoch.addListener(observe);
        gate.blockNext = true;
        gate.reject = reject;
        final switching = fx.repo
            .switchAccount(b.id)
            .then<Object?>((_) => null, onError: (Object error) => error);
        try {
          await gate.started.future.timeout(const Duration(seconds: 2));
          expect(fx.repo.activeAccount.value?.id, a.id);
          expect(fx.repo.localDataScope, a.id);
          expect(fx.repo.sessionEpoch.value, epoch);
          expect(fx.repo.isLoggedIn, isTrue);
          expect(fx.repo.accountIdentity.value?.uid, '101');
          expect(fx.client.credentialGeneration, generation);
          expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-101');
          expect(observations, isEmpty);
          gate.release.complete();
          final outcome = await switching;
          if (reject) {
            expect(outcome, isA<FileSystemException>());
            expect(fx.repo.activeAccount.value?.id, a.id);
            expect(fx.repo.sessionEpoch.value, epoch);
            expect(
                await fx.client.getOnce('cookie-echo'), 'winduser=token-101');
            expect(observations, isEmpty);
          } else {
            expect(outcome, isNull);
            expect(fx.repo.activeAccount.value?.id, b.id);
            expect(fx.repo.sessionEpoch.value, epoch + 1);
            expect(
                await fx.client.getOnce('cookie-echo'), 'winduser=token-102');
            expect(observations, isNotEmpty);
            expect(observations, everyElement(('102', 'token-102', epoch + 1)));
          }
        } finally {
          if (!gate.release.isCompleted) gate.release.complete();
          await switching;
          fx.repo.accounts.removeListener(observe);
          fx.repo.activeAccount.removeListener(observe);
          fx.repo.sessionEpoch.removeListener(observe);
        }
      });
    });
  }

  test(
      'network replacement cannot publish optimistic account data before switch acknowledgement',
      () async {
    SharedPreferences.resetStatic();
    final gate = _RegistryGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final b = await fx.addAccount(username: 'userB', uid: '102');
      await fx.repo.switchAccount(a.id);
      final observations = <(String?, String)>[];
      void observe() => observations.add((
            fx.repo.activeAccount.value?.uid,
            fx.client.exportCookies().values.single.value
          ));
      fx.repo.accounts.addListener(observe);
      fx.repo.activeAccount.addListener(observe);
      gate.blockNext = true;
      final switching = fx.repo
          .switchAccount(b.id)
          .then<Object?>((_) => null, onError: (Object e) => e);
      Future<Object?>? networking;
      try {
        await gate.started.future.timeout(const Duration(seconds: 2));
        networking = fx.repo
            .updateNetworkConfig(
                _config.copyWith(mode: ForumNetworkMode.optimized))
            .then<Object?>((_) => null, onError: (Object e) => e);
        // Let the new operation reach its awaited registry load; a queued load
        // stays pending, while an unguarded load publishes optimistic prefs.
        await Future<void>.delayed(Duration.zero);
        gate.release.complete();
        final switched = await switching;
        final networked = await networking;
        expect(
            observations.every((row) =>
                (row.$1 == '101' && row.$2 == 'token-101') ||
                (row.$1 == '102' && row.$2 == 'token-102')),
            isTrue);
        expect(switched, isNull);
        expect(networked, isNull);
        expect(fx.repo.activeAccount.value?.id, b.id);
        expect(fx.repo.accountIdentity.value?.uid, '102');
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        await switching;
        await networking;
        fx.repo.accounts.removeListener(observe);
        fx.repo.activeAccount.removeListener(observe);
      }
    });
  });

  test('guest site switch publishes the new scope before notifying listeners',
      () async {
    await _withCp2Fixture((fx) async {
      expect(fx.repo.localDataScope, 'guest:https://fixture.invalid');
      final observed = <String>[];
      void capture() => observed.add(fx.repo.localDataScope);
      fx.repo.sessionEpoch.addListener(capture);
      try {
        await fx.repo.updateNetworkConfig(
            _config.copyWith(site: const ForumSite('localhost')));
      } finally {
        fx.repo.sessionEpoch.removeListener(capture);
      }
      expect(fx.repo.localDataScope, 'guest:https://localhost');
      expect(observed, isNotEmpty);
      expect(observed, everyElement('guest:https://localhost'));
    });
  });

  for (final sameAccount in [false, true]) {
    for (final cancel in [false, true]) {
      test(
          'authenticated commit ${cancel ? 'cancellation' : 'failure'} '
          'preserves A while ${sameAccount ? 'A' : 'B'} awaits registry acknowledgement',
          () async {
        SharedPreferences.resetStatic();
        final gate = _RegistryGateStore();
        SharedPreferencesStorePlatform.instance = gate;
        await _withCp2Fixture((fx) async {
          final a = await fx.addAccount(username: 'userA', uid: '101');
          final targetId = ForumAccountId(
                  origin: fx.client.baseUri, uid: sameAccount ? '101' : '102')
              .value;
          final originalJar = await fx.cookieSnapshot(a.id);
          final epoch = fx.repo.sessionEpoch.value;
          final generation = fx.client.credentialGeneration;
          final challenge = await fx.repo.fetchAddAccountChallenge();
          fx.server.tokenSuffix = '-fresh';
          gate.activeIdToBlock = targetId;
          gate.blockNext = true;
          gate.reject = !cancel;
          final submitting = fx.repo
              .submitAddAccount(
                  username: sameAccount ? 'userA' : 'userB',
                  password: 'pw',
                  captcha: '1234',
                  fields: challenge.fields)
              .then<Object>((value) => value, onError: (Object error) => error);
          try {
            await gate.started.future.timeout(const Duration(seconds: 5));
            expect(fx.repo.activeAccount.value?.id, a.id);
            expect(fx.repo.localDataScope, a.id);
            expect(fx.repo.sessionEpoch.value, epoch);
            expect(fx.client.isCredentialCurrent(generation), isTrue);
            expect(
                await fx.client.getOnce('cookie-echo'), 'winduser=token-101');
            if (cancel) await fx.repo.cancelAddAccount();
            gate.release.complete();
            final result = await submitting;
            expect(result, isA<Exception>());
            expect(fx.repo.activeAccount.value?.id, a.id);
            expect(fx.repo.accounts.value.map((row) => row.id), [a.id]);
            expect(fx.repo.sessionEpoch.value, epoch);
            expect(fx.client.isCredentialCurrent(generation), isTrue);
            expect(
                await fx.client.getOnce('cookie-echo'), 'winduser=token-101');
            final prefs = await SharedPreferences.getInstance();
            await prefs.reload();
            expect(await fx.cookieSnapshot(a.id), originalJar);
            if (!sameAccount) {
              expect(
                  await ForumSessionStore.forSlot(
                          slotId: targetId, origin: fx.client.baseUri)
                      .loadCookies(),
                  isEmpty);
            }
          } finally {
            if (!gate.release.isCompleted) gate.release.complete();
            await submitting;
          }
        });
      });
    }
  }

  test(
      'source cleanup failure keeps the committed account and cannot restore legacy',
      () async {
    SharedPreferences.resetStatic();
    final gate = _RegistryGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final origin = fx.client.baseUri;
      final source = ForumSessionStore(origin: origin);
      await source.saveCookies({
        'winduser': ForumStoredCookie.session(
            name: 'winduser', value: 'token-101', origin: origin),
      });
      gate.rejectOriginClear = true;
      expect(await fx.repo.restoreSession(), isTrue);
      final active = fx.repo.activeAccount.value!;
      expect(active.uid, '101');
      expect(fx.client.isLoggedIn, isTrue);
      expect((await source.loadCookies()).values.single.value, 'token-101');
      await _withFreshRepo(fx.overrides, (fresh, client) async {
        expect(await fresh.restoreSession(), isTrue);
        expect(fresh.activeAccount.value?.id, active.id);
        expect(client.slotId, active.id);
        expect(await client.getOnce('cookie-echo'), 'winduser=token-101');
        client.close(force: true);
      });
      gate.rejectOriginClear = false;
      await fx.repo.updateNetworkConfig(
          _config.copyWith(site: const ForumSite('localhost')));
      await fx.repo.updateNetworkConfig(_config);
      expect(fx.repo.activeAccount.value, isNull);
      expect(fx.repo.isLoggedIn, isFalse);
      expect(fx.repo.localDataScope, 'guest:https://fixture.invalid');
      expect((await source.loadCookies()).values.single.value, 'token-101');
    });
  });

  for (final reauth in [false, true]) {
    test(
        'superseded ${reauth ? 'reauth' : 'add'} challenge failure preserves its replacement',
        () async {
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        fx.server.holdFirstChallenge = Completer<void>();
        fx.server.firstChallengeSeen = Completer<void>();
        fx.server.challengeCount = 0;
        Future<LoginChallenge> fetch() => reauth
            ? fx.repo.fetchReauthChallenge(a.id)
            : fx.repo.fetchAddAccountChallenge();
        final old = fetch()
            .then<Object>((value) => value, onError: (Object error) => error);
        Future<Object>? replacement;
        try {
          await fx.server.firstChallengeSeen!.future
              .timeout(const Duration(seconds: 2));
          replacement = fetch()
              .then<Object>((value) => value, onError: (Object error) => error);
          expect(
              await old.timeout(const Duration(seconds: 5)), isA<Exception>());
          fx.server.holdFirstChallenge!.complete();
          final result = await replacement.timeout(const Duration(seconds: 10));
          expect(result, isA<LoginChallenge>());
          final challenge = result as LoginChallenge;
          final account = reauth
              ? await fx.repo.submitReauthAccount(a.id,
                  username: 'userA',
                  password: 'pw',
                  captcha: '1234',
                  fields: challenge.fields)
              : await fx.repo.submitAddAccount(
                  username: 'userA',
                  password: 'pw',
                  captcha: '1234',
                  fields: challenge.fields);
          expect(account.id, a.id);
        } finally {
          if (!fx.server.holdFirstChallenge!.isCompleted) {
            fx.server.holdFirstChallenge!.complete();
          }
          await old;
          await replacement;
        }
      });
    });

    test(
        'failed ${reauth ? 'reauth' : 'add'} preserves a later explicit account switch',
        () async {
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        final c = await fx.addAccount(username: 'userC', uid: '103');
        await fx.repo.switchAccount(a.id);
        final challenge = reauth
            ? await fx.repo.fetchReauthChallenge(a.id)
            : await fx.repo.fetchAddAccountChallenge();
        fx.server.holdLogin = Completer<void>();
        fx.server.loginHeld = Completer<void>();
        fx.server.failUser = 'userBad';
        final submitting = (reauth
                ? fx.repo.submitReauthAccount(a.id,
                    username: 'userBad',
                    password: 'pw',
                    captcha: '1234',
                    fields: challenge.fields)
                : fx.repo.submitAddAccount(
                    username: 'userBad',
                    password: 'pw',
                    captcha: '1234',
                    fields: challenge.fields))
            .then<Object>((value) => value, onError: (Object error) => error);
        try {
          await fx.server.loginHeld!.future.timeout(const Duration(seconds: 2));
          await fx.repo.switchAccount(c.id);
          final epoch = fx.repo.sessionEpoch.value;
          fx.server.holdLogin!.complete();
          expect(await submitting, isA<ForumRepositoryException>());
          expect(fx.repo.activeAccount.value?.id, c.id);
          expect(fx.repo.sessionEpoch.value, epoch);
          expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-103');
        } finally {
          if (!fx.server.holdLogin!.isCompleted)
            fx.server.holdLogin!.complete();
          await submitting;
        }
      });
    });
  }

  test('add challenge/cancel/fail leave account A cookies epoch identity alone',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final epoch = fx.repo.sessionEpoch.value;
      final cookies = await fx.cookieSnapshot(a.id);
      final identityUid = fx.repo.accountIdentity.value?.uid;

      final challenge = await fx.repo.fetchAddAccountChallenge();
      expect(challenge.captchaBytes, isNotEmpty);
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(await fx.cookieSnapshot(a.id), cookies);

      await fx.repo.cancelAddAccount();
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.accountIdentity.value?.uid, identityUid);
      expect(await fx.cookieSnapshot(a.id), cookies);

      final challenge2 = await fx.repo.fetchAddAccountChallenge();
      fx.server.failUser = 'userBad';
      await expectLater(
        fx.repo.submitAddAccount(
          username: 'userBad',
          password: 'pw',
          captcha: '1234',
          fields: challenge2.fields,
        ),
        throwsA(isA<ForumRepositoryException>()),
      );
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.accountIdentity.value?.uid, identityUid);
      expect(await fx.cookieSnapshot(a.id), cookies);
      expect(fx.repo.isLoggedIn, isTrue);
    });
  });

  test('successful add B auto-switches and A can switch back', () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final epochBefore = fx.repo.sessionEpoch.value;
      final b = await fx.addAccount(username: 'userB', uid: '102');
      expect(b.uid, '102');
      expect(fx.repo.activeAccount.value?.id, b.id);
      expect(fx.repo.accountIdentity.value?.uid, '102');
      expect(fx.repo.sessionEpoch.value, greaterThan(epochBefore));
      expect(fx.repo.accounts.value.map((e) => e.uid),
          containsAll(['101', '102']));

      await fx.repo.switchAccount(a.id);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.accountIdentity.value?.uid, '101');
      expect(fx.repo.isLoggedIn, isTrue);
    });
  });

  test('reauth uid mismatch leaves active epoch and cookies unchanged',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final epoch = fx.repo.sessionEpoch.value;
      final cookies = await fx.cookieSnapshot(a.id);

      final challenge = await fx.repo.fetchReauthChallenge(a.id);
      await expectLater(
        fx.repo.submitReauthAccount(
          a.id,
          username: 'userB',
          password: 'pw',
          captcha: '1234',
          fields: challenge.fields,
        ),
        throwsA(
          isA<ForumAccountUidMismatchException>()
              .having((e) => e.expectedUid, 'expectedUid', '101')
              .having((e) => e.actualUid, 'actualUid', '102'),
        ),
      );
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(await fx.cookieSnapshot(a.id), cookies);
      expect(fx.repo.accountIdentity.value?.uid, '101');
    });
  });

  test('cancel during delayed login does not commit abandoned staging',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final epoch = fx.repo.sessionEpoch.value;
      final challenge = await fx.repo.fetchAddAccountChallenge();

      fx.server.holdLogin = Completer<void>();
      fx.server.loginHeld = Completer<void>();
      final pending = fx.repo.submitAddAccount(
        username: 'userB',
        password: 'pw',
        captcha: '1234',
        fields: challenge.fields,
      );
      await fx.server.loginHeld!.future;
      final pendingDone =
          expectLater(pending, throwsA(isA<ForumRepositoryException>()));
      await fx.repo.cancelAddAccount();
      fx.server.holdLogin!.complete();
      await pendingDone;

      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.sessionEpoch.value, epoch);
      expect(fx.repo.accounts.value.where((e) => e.uid == '102'), isEmpty);
      expect(fx.repo.accountIdentity.value?.uid, '101');
    });
  });

  test(
      'second fetchAdd cancels first staging; late first submit does not commit',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final epoch = fx.repo.sessionEpoch.value;
      final firstFields = (await fx.repo.fetchAddAccountChallenge()).fields;

      fx.server.holdLogin = Completer<void>();
      fx.server.loginHeld = Completer<void>();
      final lateFirst = fx.repo.submitAddAccount(
        username: 'userB',
        password: 'pw',
        captcha: '1234',
        fields: firstFields,
      );
      await fx.server.loginHeld!.future;
      // Listen before cancel so the abandoned error is not unhandled.
      final lateFirstDone =
          expectLater(lateFirst, throwsA(isA<ForumRepositoryException>()));

      // Cancels the held staging client; release the gate afterwards.
      final second = await fx.repo.fetchAddAccountChallenge();
      final hold = fx.server.holdLogin!;
      fx.server.holdLogin = null;
      fx.server.loginHeld = null;
      hold.complete();
      await lateFirstDone;
      expect(fx.repo.accounts.value.where((e) => e.uid == '102'), isEmpty);

      final b = await fx.repo.submitAddAccount(
        username: 'userB',
        password: 'pw',
        captcha: '1234',
        fields: second.fields,
      );
      expect(b.uid, '102');
      expect(fx.repo.accounts.value.where((e) => e.uid == '102').length, 1);
      expect(fx.repo.sessionEpoch.value, greaterThan(epoch));
      expect(fx.repo.activeAccount.value?.id, b.id);
      expect(fx.repo.accounts.value.any((e) => e.id == a.id), isTrue);
    });
  });

  test('cold restore without uid does not mint account; with uid migrates v2',
      () async {
    await _withCp2Fixture((fx) async {
      final origin = fx.client.baseUri;
      final v2Key = 'forum_session_cookies_v2:${origin.host}';
      final cookie = ForumStoredCookie.session(
          name: 'winduser', value: 'legacy-token', origin: origin);

      final seedPrefs = await SharedPreferences.getInstance();
      await seedPrefs.clear();
      await seedPrefs.setString(
          v2Key, jsonEncode({'winduser': cookie.toJson()}));
      await _withFreshRepo(fx.overrides, (repo, client) async {
        fx.server.omitUid = true;
        fx.server.forceUid = null;
        final ok = await repo.restoreSession();
        expect(ok, isTrue);
        expect(repo.isLoggedIn, isTrue);
        expect(repo.accounts.value, isEmpty);
        expect(repo.activeAccount.value, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(v2Key), isNotEmpty);
        expect(
          prefs
              .getKeys()
              .where((k) => k.startsWith('forum_session_cookies_v3:')),
          isEmpty,
        );
        client.close();
      });

      await seedPrefs.clear();
      await seedPrefs.setString(
          v2Key, jsonEncode({'winduser': cookie.toJson()}));
      await _withFreshRepo(fx.overrides, (repo, client) async {
        fx.server.omitUid = false;
        fx.server.forceUid = '201';
        final ok = await repo.restoreSession();
        expect(ok, isTrue);
        expect(repo.isLoggedIn, isTrue);
        expect(repo.accountIdentity.value?.uid, '201',
            reason: 'header must expose uid before promotion');
        final expected = ForumAccountId(
          origin: ForumAccountId.normalizeOrigin(origin),
          uid: '201',
        ).value;
        expect(repo.activeAccount.value?.id, expected);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(v2Key), '{}');
        final v3 =
            prefs.getString(ForumSessionSlots.cookiesPrefsKey(expected)!);
        expect(v3, isNotNull);
        expect(v3, isNot('{}'));
        client.close();
      });
    });
  });

  test(
      'legacy restore keeps v2 and rolls back target when registry persistence fails',
      () async {
    SharedPreferences.resetStatic();
    final gate = _RegistryGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final origin = _config.baseUri;
      final accountId = ForumAccountId(origin: origin, uid: '301').value;
      final v2Key = 'forum_session_cookies_v2:${origin.host}';
      final v3Key = ForumSessionSlots.cookiesPrefsKey(accountId)!;
      final legacyCookie = ForumStoredCookie.session(
          name: 'winduser', value: 'legacy-keep', origin: origin);
      final legacyPayload = jsonEncode({'winduser': legacyCookie.toJson()});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(v2Key, legacyPayload);
      await ForumSessionStore.forSlot(slotId: accountId, origin: origin)
          .saveCookies({
        'winduser': ForumStoredCookie.session(
            name: 'winduser', value: 'orphan-before-restore', origin: origin),
      });
      final targetBefore = prefs.getString(v3Key);
      await fx.client.restoreCookies();
      final sourceSlot = fx.client.slotId;
      final sourceGeneration = fx.client.credentialGeneration;
      fx.server.forceUid = '301';
      gate.blockNext = true;
      gate.reject = true;
      final restoring = fx.repo.restoreSession();
      try {
        await gate.started.future.timeout(const Duration(seconds: 2));
        expect(fx.repo.activeAccount.value, isNull);
        expect(fx.repo.accounts.value, isEmpty);
        expect(fx.client.slotId, sourceSlot);
        expect(ForumSessionSlots.isOrigin(sourceSlot), isTrue);
        expect(fx.client.isCredentialCurrent(sourceGeneration), isTrue);
        expect(prefs.getString(v2Key), legacyPayload);
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=legacy-keep');
        gate.release.complete();
        expect(await restoring, isTrue,
            reason:
                'a rejected migration keeps the authenticated legacy session');
        await prefs.reload();
        expect(fx.repo.activeAccount.value, isNull);
        expect(fx.repo.accounts.value, isEmpty);
        expect(prefs.getString(ForumAccountRegistry.prefsKey), isNull);
        expect(prefs.getString(v2Key), legacyPayload);
        expect(prefs.getString(v3Key), targetBefore);
        expect(fx.client.slotId, sourceSlot);
        expect(fx.client.isCredentialCurrent(sourceGeneration), isTrue);
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=legacy-keep');

        gate.reject = false;
        expect(await fx.repo.restoreSession(), isTrue);
        expect(fx.repo.activeAccount.value?.id, accountId);
        expect(fx.repo.accounts.value, hasLength(1));
        expect(fx.repo.activeAccount.value?.status, AccountReadyState.ready);
        expect(fx.client.slotId, accountId);
        expect(prefs.getString(v2Key), '{}');
        expect(prefs.getString(v3Key), isNot(targetBefore));
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=legacy-keep');
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        await restoring;
      }
    });
  });

  test('ready v3 active cold start restores when origin jar empty', () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final accountId = a.id;
      final prefs = await SharedPreferences.getInstance();
      final regBefore =
          jsonDecode(prefs.getString(ForumAccountRegistry.prefsKey)!)
              as Map<String, dynamic>;
      expect(regBefore['activeAccountId'], accountId);

      await _withFreshRepo(fx.overrides, (repo, client) async {
        // Fresh client starts on origin; origin jar stays empty after add flow.
        expect(client.isLoggedIn, isFalse);
        final ok = await repo.restoreSession();
        expect(ok, isTrue, reason: 'bootstrap must restore ready v3 active');
        expect(repo.activeAccount.value?.id, accountId);
        expect(repo.isLoggedIn, isTrue);
        expect(repo.sessionUser.value, isNotNull);
        final prefsAfter = await SharedPreferences.getInstance();
        final regAfter =
            jsonDecode(prefsAfter.getString(ForumAccountRegistry.prefsKey)!)
                as Map<String, dynamic>;
        expect(regAfter['activeAccountId'], accountId,
            reason: 'must not persist active=null over ready v3');
      });
    });
  });

  test('switch with header failure aligns sessionUser to active summary',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final b = await fx.addAccount(username: 'userB', uid: '102');
      expect(fx.repo.activeAccount.value?.id, b.id);
      expect(fx.repo.sessionUser.value, 'Synthetic B');

      fx.server.failIndex = true;
      await fx.repo.switchAccount(a.id);
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.sessionEpoch.value, greaterThan(0));
      expect(fx.repo.sessionUser.value, isNot('Synthetic B'),
          reason: 'failed header must not leave previous username');
      expect(
        fx.repo.sessionUser.value,
        anyOf('Synthetic A', a.systemName, a.displayName),
      );
      expect(fx.repo.accountIdentity.value?.uid, '101');
      expect(fx.repo.accounts.value.map((e) => e.uid),
          containsAll(['101', '102']));
      expect(fx.repo.localPreferenceAccount, isNot(contains('Synthetic B')));
    });
  });

  // test-audit: the real login owner must keep A intact until B's registry
  // write commits. These cases cover both the expired-cookie UI entry point
  // and direct legacy use, with a real TLS response and storage rejection.
  for (final expired in [false, true]) {
    for (final reject in [false, true]) {
      test(
          'legacy login preserves source before registry ACK '
          '(expired=$expired, reject=$reject)', () async {
        SharedPreferences.resetStatic();
        final gate = _RegistryGateStore();
        SharedPreferencesStorePlatform.instance = gate;
        await _withCp2Fixture((fx) async {
          final a = await fx.addAccount(username: 'userA', uid: '101');
          if (expired) {
            await fx.client.getOnce('cookie-expire');
            expect(fx.repo.isLoggedIn, isFalse,
                reason: 'expired cookies expose the ordinary login prompt');
          }
          expect(fx.repo.activeAccount.value?.id, a.id);
          final beforeIdentity = fx.repo.accountIdentity.value?.uid;
          final beforeUsername = fx.repo.sessionUser.value;
          final beforeCookie = await fx.client.getOnce('cookie-echo');
          final beforeJar = await _persistedCp2Cookie(a.id);
          final beforeEpoch = fx.repo.sessionEpoch.value;
          final beforeGeneration = fx.client.credentialGeneration;
          final challenge = await fx.repo.fetchLoginChallenge();
          gate.blockNext = true;
          gate.reject = reject;
          final login = fx.repo
              .submitLogin(
                username: 'userB',
                password: 'pw',
                captcha: '1234',
                fields: challenge.fields,
              )
              .then<Object>((value) => value, onError: (Object error) => error);
          try {
            await gate.started.future.timeout(const Duration(seconds: 2));
            final pendingActive = fx.repo.activeAccount.value?.id;
            final pendingScope = fx.repo.localDataScope;
            final pendingIdentity = fx.repo.accountIdentity.value?.uid;
            final pendingUsername = fx.repo.sessionUser.value;
            final pendingCookie = await fx.client.getOnce('cookie-echo');
            final pendingJar = await _persistedCp2Cookie(a.id);
            final pendingEpoch = fx.repo.sessionEpoch.value;
            final pendingGenerationCurrent =
                fx.client.isCredentialCurrent(beforeGeneration);
            gate.release.complete();
            final result = await login;

            expect(pendingActive, a.id);
            expect(pendingScope, a.id);
            expect(pendingCookie, beforeCookie,
                reason: 'B cookies must never be sent under A scope');
            expect(pendingJar, beforeJar,
                reason: 'A durable jar must not contain B credentials');
            expect(pendingIdentity, beforeIdentity);
            expect(pendingUsername, beforeUsername);
            expect(pendingEpoch, beforeEpoch);
            expect(pendingGenerationCurrent, isTrue);
            if (reject) {
              expect(result is LoginResult && result.success, isFalse);
              expect(fx.repo.activeAccount.value?.id, a.id);
              expect(fx.repo.localDataScope, a.id);
              expect(fx.repo.accountIdentity.value?.uid, beforeIdentity);
              expect(fx.repo.sessionUser.value, beforeUsername);
              expect(await fx.client.getOnce('cookie-echo'), beforeCookie);
              expect(await _persistedCp2Cookie(a.id), beforeJar);
              expect(fx.repo.sessionEpoch.value, beforeEpoch);
              expect(fx.client.isCredentialCurrent(beforeGeneration), isTrue);
              expect(fx.repo.accounts.value.map((row) => row.uid), ['101']);
              final reopened = ForumAccountRegistry();
              await reopened.load();
              expect(reopened.activeAccount.value?.id, a.id);
              expect(reopened.accounts.value.map((row) => row.uid), ['101']);
            } else {
              expect(result, isA<LoginResult>());
              expect((result as LoginResult).success, isTrue);
              final b = fx.repo.activeAccount.value!;
              expect(b.uid, '102');
              expect(fx.repo.localDataScope, b.id);
              expect(fx.repo.accountIdentity.value?.uid, '102');
              expect(
                  await fx.client.getOnce('cookie-echo'), 'winduser=token-102');
              expect(await _persistedCp2Cookie(a.id), '{}');
              expect(await _persistedCp2Cookie(b.id), contains('token-102'));
              expect(
                  fx.repo.accounts.value
                      .singleWhere((row) => row.id == a.id)
                      .status,
                  AccountReadyState.needsReauth);
              await expectLater(fx.repo.switchAccount(a.id),
                  throwsA(isA<ForumRepositoryException>()));
              expect(fx.repo.activeAccount.value?.id, b.id);
            }
          } finally {
            if (!gate.release.isCompleted) gate.release.complete();
            await login;
          }
        });
      });
    }
  }

  // Cancellation is checked at the actual registry acknowledgement boundary,
  // after the target jar was prepared, so a UI callback cannot hide a commit.
  test('cancelLogin during registry ACK preserves the source and removes B',
      () async {
    SharedPreferences.resetStatic();
    final gate = _RegistryGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      await fx.client.getOnce('cookie-expire');
      final beforeIdentity = fx.repo.accountIdentity.value?.uid;
      final beforeCookie = await fx.client.getOnce('cookie-echo');
      final beforeJar = await _persistedCp2Cookie(a.id);
      final beforeEpoch = fx.repo.sessionEpoch.value;
      final beforeGeneration = fx.client.credentialGeneration;
      final challenge = await fx.repo.fetchLoginChallenge();
      gate.blockNext = true;
      final login = fx.repo
          .submitLogin(
              username: 'userB',
              password: 'pw',
              captcha: '1234',
              fields: challenge.fields)
          .then<Object>((value) => value, onError: (Object error) => error);
      try {
        await gate.started.future.timeout(const Duration(seconds: 2));
        await fx.repo.cancelLogin().timeout(const Duration(seconds: 2));
        expect(fx.repo.activeAccount.value?.id, a.id);
        expect(fx.repo.localDataScope, a.id);
        expect(fx.repo.accountIdentity.value?.uid, beforeIdentity);
        expect(await fx.client.getOnce('cookie-echo'), beforeCookie,
            reason: 'closing staging must not close the source transport');
        expect(await _persistedCp2Cookie(a.id), beforeJar);
        expect(fx.repo.sessionEpoch.value, beforeEpoch);
        gate.release.complete();
        final result = await login;
        expect(result is LoginResult && result.success, isFalse);
        expect(fx.repo.activeAccount.value?.id, a.id);
        expect(fx.repo.localDataScope, a.id);
        expect(fx.repo.accountIdentity.value?.uid, beforeIdentity);
        expect(await fx.client.getOnce('cookie-echo'), beforeCookie);
        expect(await _persistedCp2Cookie(a.id), beforeJar);
        expect(fx.repo.sessionEpoch.value, beforeEpoch);
        expect(fx.client.isCredentialCurrent(beforeGeneration), isTrue);
        expect(fx.repo.accounts.value.map((row) => row.uid), ['101']);
        final bId = ForumAccountId(
                origin: Uri.parse('https://fixture.invalid'), uid: '102')
            .value;
        expect(await _persistedCp2Cookie(bId), isNot(contains('token-102')));
        final reopened = ForumAccountRegistry();
        await reopened.load();
        expect(reopened.activeAccount.value?.id, a.id);
        expect(reopened.accounts.value.map((row) => row.uid), ['101']);
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        await login;
      }
    });
  });

  // A late failure from a superseded challenge must not close the current
  // challenge's staging session. The second challenge is used to finish login.
  test('late legacy challenge failure preserves the replacement challenge',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      fx.server.holdFirstChallenge = Completer<void>();
      fx.server.firstChallengeSeen = Completer<void>();
      fx.server.challengeCount = 0;
      fx.server.failHeldChallenge = true;
      final old = fx.repo
          .fetchLoginChallenge()
          .then<Object>((value) => value, onError: (Object error) => error);
      Future<Object>? replacement;
      try {
        await fx.server.firstChallengeSeen!.future
            .timeout(const Duration(seconds: 2));
        replacement = fx.repo
            .fetchLoginChallenge()
            .then<Object>((value) => value, onError: (Object error) => error);
        final second = await replacement.timeout(const Duration(seconds: 2));
        expect(second, isA<LoginChallenge>());
        fx.server.holdFirstChallenge!.complete();
        expect(await old, isNot(isA<LoginChallenge>()));
        expect(fx.repo.activeAccount.value?.id, a.id);
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-101');
        final result = await fx.repo.submitLogin(
          username: 'userB',
          password: 'pw',
          captcha: '1234',
          fields: (second as LoginChallenge).fields,
        );
        expect(result.success, isTrue);
        expect(fx.repo.activeAccount.value?.uid, '102');
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-102');
        expect(await _persistedCp2Cookie(a.id), '{}');
      } finally {
        if (!fx.server.holdFirstChallenge!.isCompleted) {
          fx.server.holdFirstChallenge!.complete();
        }
        await old;
        await replacement;
      }
    });
  });

  test('legacy same uid refresh publishes fresh credentials after registry ACK',
      () async {
    SharedPreferences.resetStatic();
    final gate = _RegistryGateStore();
    SharedPreferencesStorePlatform.instance = gate;
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final beforeEpoch = fx.repo.sessionEpoch.value;
      fx.server.tokenSuffix = '-fresh';
      final challenge = await fx.repo.fetchLoginChallenge();
      gate.blockNext = true;
      final login = fx.repo
          .submitLogin(
            username: 'userA',
            password: 'pw',
            captcha: '1234',
            fields: challenge.fields,
          )
          .then<Object>((value) => value, onError: (Object error) => error);
      try {
        await gate.started.future.timeout(const Duration(seconds: 2));
        expect(fx.repo.activeAccount.value?.id, a.id);
        expect(await fx.client.getOnce('cookie-echo'), 'winduser=token-101');
        expect(fx.repo.sessionEpoch.value, beforeEpoch);
        gate.release.complete();
        final result = await login;
        expect(result, isA<LoginResult>());
        expect((result as LoginResult).success, isTrue);
        expect(fx.repo.accounts.value.length, 1);
        expect(fx.repo.activeAccount.value?.id, a.id);
        expect(fx.repo.activeAccount.value?.status, AccountReadyState.ready);
        expect(fx.repo.accountIdentity.value?.uid, '101');
        expect(
            await fx.client.getOnce('cookie-echo'), 'winduser=token-101-fresh');
        expect(await _persistedCp2Cookie(a.id), contains('token-101-fresh'));
        await fx.repo.cancelLogin();
        expect(
            await fx.client.getOnce('cookie-echo'), 'winduser=token-101-fresh');
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        await login;
      }
    });
  });

  test('legacy submitLogin promotes v3 so add B can switch back to A',
      () async {
    await _withCp2Fixture((fx) async {
      fx.server.expectUid['userA'] = '101';
      final challenge = await fx.repo.fetchLoginChallenge();
      final result = await fx.repo.submitLogin(
        username: 'userA',
        password: 'pw',
        captcha: '1234',
        fields: challenge.fields,
      );
      expect(result.success, isTrue);
      expect(fx.repo.accounts.value.any((e) => e.uid == '101'), isTrue);
      final aId = fx.repo.activeAccount.value?.id;
      expect(aId, isNotNull);
      expect(ForumSessionSlots.isAccount(fx.client.slotId), isTrue);

      final b = await fx.addAccount(username: 'userB', uid: '102');
      expect(fx.repo.activeAccount.value?.id, b.id);
      await fx.repo.switchAccount(aId!);
      expect(fx.repo.activeAccount.value?.id, aId);
      expect(fx.repo.accountIdentity.value?.uid, '101');
      expect(fx.repo.isLoggedIn, isTrue);
    });
  });

  // test-audit authoring gate:
  // 1) Protects legacy submitLogin uid change: old account slot must not keep
  //    the new SetCookie; switch to old must not become the new identity.
  // 2) Credible regression: A101 then B202 left A ready with token-202.
  // 3) Distinct from addAccount staging and reauth mismatch (typed error).
  // 4) Real TLS loopback fixture; cookie prefs + switchAccount fail-closed.
  test(
      'legacy re-login as different uid retires old jar so switch cannot become B',
      () async {
    await _withCp2Fixture((fx) async {
      fx.server.expectUid['userA'] = '101';
      final challengeA = await fx.repo.fetchLoginChallenge();
      final loginA = await fx.repo.submitLogin(
        username: 'userA',
        password: 'pw',
        captcha: '1234',
        fields: challengeA.fields,
      );
      expect(loginA.success, isTrue);
      final aId = fx.repo.activeAccount.value!.id;
      expect(ForumAccountId.parse(aId).uid, '101');
      final aCookiesBefore = await fx.cookieSnapshot(aId);
      expect(aCookiesBefore, contains('token-101'));

      fx.server.expectUid['userB'] = '202';
      final challengeB = await fx.repo.fetchLoginChallenge();
      final loginB = await fx.repo.submitLogin(
        username: 'userB',
        password: 'pw',
        captcha: '1234',
        fields: challengeB.fields,
      );
      expect(loginB.success, isTrue);
      final bId = fx.repo.activeAccount.value!.id;
      expect(ForumAccountId.parse(bId).uid, '202');
      expect(bId, isNot(aId));
      expect(fx.repo.accountIdentity.value?.uid, '202');
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == aId).status,
        AccountReadyState.needsReauth,
      );
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == bId).status,
        AccountReadyState.ready,
      );

      final aCookiesAfter = await fx.cookieSnapshot(aId);
      expect(aCookiesAfter, '{}',
          reason: 'old slot cleared to tombstone; no B cookies');
      expect(aCookiesAfter!.contains('token-202'), isFalse);
      final bCookies = await fx.cookieSnapshot(bId);
      expect(bCookies, contains('token-202'));
      expect(bCookies!.contains('token-101'), isFalse);

      // needsReauth rejects before jar load; current B session stays put.
      // The Medium was A jar holding B cookies so "switch A" became B.
      await expectLater(
        fx.repo.switchAccount(aId),
        throwsA(isA<ForumRepositoryException>()),
      );
      expect(fx.repo.activeAccount.value?.id, bId);
      expect(fx.repo.accountIdentity.value?.uid, '202');
      expect(fx.repo.isLoggedIn, isTrue);
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == aId).status,
        AccountReadyState.needsReauth,
      );
      expect(await fx.cookieSnapshot(aId), '{}');
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == bId).status,
        AccountReadyState.ready,
      );
    });
  });

  test('reauth uid mismatch error stays specific not cancelled', () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final challenge = await fx.repo.fetchReauthChallenge(a.id);
      try {
        await fx.repo.submitReauthAccount(
          a.id,
          username: 'userB',
          password: 'pw',
          captcha: '1234',
          fields: challenge.fields,
        );
        fail('expected mismatch');
      } on ForumAccountUidMismatchException catch (e) {
        expect(e.expectedUid, '101');
        expect(e.actualUid, '102');
        expect(e.message, isNot(contains('已取消')));
      }
      expect(fx.repo.activeAccount.value?.id, a.id);
    });
  });

  test('ready active with empty v3 cookie cold start becomes needsReauth guest',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final accountId = a.id;
      final prefs = await SharedPreferences.getInstance();
      final cookieKey = ForumSessionSlots.cookiesPrefsKey(accountId)!;
      // Empty / invalid jar while registry still says ready+active.
      await prefs.setString(cookieKey, '{}');

      await _withFreshRepo(fx.overrides, (repo, client) async {
        final ok = await repo.restoreSession();
        expect(ok, isFalse);
        expect(repo.activeAccount.value, isNull,
            reason: 'must not leave ready+active with empty jar');
        expect(repo.isLoggedIn, isFalse);
        final row = repo.accounts.value.singleWhere((e) => e.id == accountId);
        expect(row.status, AccountReadyState.needsReauth);
        final reg = jsonDecode((await SharedPreferences.getInstance())
            .getString(ForumAccountRegistry.prefsKey)!) as Map;
        expect(reg['activeAccountId'], isNull);
      });
    });
  });

  test('needsReauth active cold start enters guest without selecting ready',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      await fx.repo.logoutCurrent();
      expect(fx.repo.activeAccount.value, isNull);
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == a.id).status,
        AccountReadyState.needsReauth,
      );

      await _withFreshRepo(fx.overrides, (repo, client) async {
        final ok = await repo.restoreSession();
        expect(ok, isFalse);
        expect(repo.activeAccount.value, isNull);
        expect(repo.isLoggedIn, isFalse);
        expect(
          repo.accounts.value.singleWhere((e) => e.id == a.id).status,
          AccountReadyState.needsReauth,
        );
      });
    });
  });

  test('switchAccount to empty jar fail-closes to needsReauth guest', () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final b = await fx.addAccount(username: 'userB', uid: '102');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ForumSessionSlots.cookiesPrefsKey(a.id)!, '{}');
      await expectLater(
        fx.repo.switchAccount(a.id),
        throwsA(isA<ForumRepositoryException>()),
      );
      expect(fx.repo.activeAccount.value, isNull);
      expect(fx.repo.isLoggedIn, isFalse);
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == a.id).status,
        AccountReadyState.needsReauth,
      );
      // B row remains ready but not active.
      expect(
        fx.repo.accounts.value.singleWhere((e) => e.id == b.id).status,
        AccountReadyState.ready,
      );
    });
  });

  test('logoutCurrent and removeAccount facades sync epoch and guest',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final b = await fx.addAccount(username: 'userB', uid: '102');
      final epochNonActive = fx.repo.sessionEpoch.value;
      await fx.repo.logoutAccount(a.id);
      expect(fx.repo.sessionEpoch.value, epochNonActive);
      expect(fx.repo.activeAccount.value?.id, b.id);
      expect(
        fx.repo.accounts.value.firstWhere((e) => e.id == a.id).status,
        AccountReadyState.needsReauth,
      );

      final epochBeforeLogout = fx.repo.sessionEpoch.value;
      await fx.repo.logoutCurrent();
      expect(fx.repo.activeAccount.value, isNull);
      expect(fx.repo.isLoggedIn, isFalse);
      expect(fx.repo.sessionEpoch.value, greaterThan(epochBeforeLogout));

      await fx.repo.removeAccount(a.id);
      expect(fx.repo.accounts.value.any((e) => e.id == a.id), isFalse);

      final challenge = await fx.repo.fetchReauthChallenge(b.id);
      fx.server.expectUid['userB'] = '102';
      await fx.repo.submitReauthAccount(
        b.id,
        username: 'userB',
        password: 'pw',
        captcha: '1234',
        fields: challenge.fields,
      );
      expect(fx.repo.activeAccount.value?.id, b.id);
      final epochBeforeRemove = fx.repo.sessionEpoch.value;
      await fx.repo.removeAccount(b.id);
      expect(fx.repo.activeAccount.value, isNull);
      expect(fx.repo.isLoggedIn, isFalse);
      expect(fx.repo.sessionEpoch.value, greaterThan(epochBeforeRemove));
      expect(fx.repo.accounts.value.any((e) => e.id == b.id), isFalse);
    });
  });

  test('network change cancels in-flight add so late submit cannot commit',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final challenge = await fx.repo.fetchAddAccountChallenge();
      fx.server.expectUid['userB'] = '102';
      fx.server.holdLogin = Completer<void>();
      fx.server.loginHeld = Completer<void>();
      final pending = fx.repo.submitAddAccount(
        username: 'userB',
        password: 'pw',
        captcha: '1234',
        fields: challenge.fields,
      );
      final cancelled = expectLater(
        pending,
        throwsA(isA<ForumRepositoryException>()),
      );
      await fx.server.loginHeld!.future;
      await fx.repo.updateNetworkConfig(
          _config.copyWith(mode: ForumNetworkMode.optimized));
      fx.server.holdLogin!.complete();
      await cancelled;
      expect(fx.repo.accounts.value.any((e) => e.uid == '102'), isFalse,
          reason: 'late staging must not promote onto the new client');
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.accountIdentity.value?.uid, '101');
      expect(fx.repo.isLoggedIn, isTrue);
    });
  });

  test('network change cancels in-flight reauth so late submit cannot commit',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final cookies = await fx.cookieSnapshot(a.id);
      final challenge = await fx.repo.fetchReauthChallenge(a.id);
      fx.server.holdLogin = Completer<void>();
      fx.server.loginHeld = Completer<void>();
      final pending = fx.repo.submitReauthAccount(
        a.id,
        username: 'userA',
        password: 'pw',
        captcha: '1234',
        fields: challenge.fields,
      );
      final cancelled = expectLater(
        pending,
        throwsA(isA<ForumRepositoryException>()),
      );
      await fx.server.loginHeld!.future;
      await fx.repo.updateNetworkConfig(
          _config.copyWith(mode: ForumNetworkMode.optimized));
      fx.server.holdLogin!.complete();
      await cancelled;
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(await fx.cookieSnapshot(a.id), cookies,
          reason: 'cancelled reauth must not rewrite the jar');
      expect(fx.repo.accountIdentity.value?.uid, '101');
    });
  });

  test(
      'same-origin network mode change keeps active account slot and generation',
      () async {
    await _withCp2Fixture((fx) async {
      final a = await fx.addAccount(username: 'userA', uid: '101');
      final cookies = await fx.cookieSnapshot(a.id);
      final epoch = fx.repo.sessionEpoch.value;
      final scope = fx.repo.localPreferenceAccount;
      await fx.repo.updateNetworkConfig(
          _config.copyWith(mode: ForumNetworkMode.optimized));
      expect(fx.repo.activeAccount.value?.id, a.id);
      expect(fx.repo.localPreferenceAccount, scope);
      expect(fx.repo.accountIdentity.value?.uid, '101');
      expect(await fx.cookieSnapshot(a.id), cookies);
      expect(fx.repo.sessionEpoch.value, greaterThan(epoch));
      expect(fx.repo.networkConfig.mode, ForumNetworkMode.optimized);
    });
  });

  for (final action in ['logout', 'remove']) {
    test(
        'same-origin non-active $action A keeps active B identity through mode change',
        () async {
      await _withCp2Fixture((fx) async {
        final a = await fx.addAccount(username: 'userA', uid: '101');
        final b = await fx.addAccount(username: 'userB', uid: '102');
        expect(fx.repo.activeAccount.value?.id, b.id);
        expect(fx.repo.accountIdentity.value?.uid, '102');
        final bCookies = await fx.cookieSnapshot(b.id);
        final epochBefore = fx.repo.sessionEpoch.value;
        // Seed origin identity cache as B via same-origin mode hop.
        await fx.repo.updateNetworkConfig(
            _config.copyWith(mode: ForumNetworkMode.optimized));
        expect(fx.repo.accountIdentity.value?.uid, '102');
        expect(fx.repo.currentUsername, isNotNull);
        expect(fx.repo.currentUsername, isNot('userA'));
        await fx.repo.updateNetworkConfig(_config);
        expect(fx.repo.accountIdentity.value?.uid, '102');

        if (action == 'logout') {
          await fx.repo.logoutAccount(a.id);
          expect(
            fx.repo.accounts.value.any((e) =>
                e.id == a.id && e.status == AccountReadyState.needsReauth),
            isTrue,
          );
        } else {
          await fx.repo.removeAccount(a.id);
          expect(fx.repo.accounts.value.any((e) => e.id == a.id), isFalse);
        }

        expect(fx.repo.activeAccount.value?.id, b.id);
        expect(fx.repo.accountIdentity.value?.uid, '102');
        expect(fx.repo.currentUsername, isNotNull);
        expect(fx.repo.currentUsername, isNot('userA'));
        expect(fx.repo.isLoggedIn, isTrue);
        expect(await fx.cookieSnapshot(b.id), bCookies);

        final epochAfterScrub = fx.repo.sessionEpoch.value;
        await fx.repo.updateNetworkConfig(
            _config.copyWith(mode: ForumNetworkMode.optimized));
        expect(fx.repo.activeAccount.value?.id, b.id);
        expect(fx.repo.accountIdentity.value?.uid, '102');
        expect(fx.repo.currentUsername, isNotNull);
        expect(fx.repo.currentUsername, isNot('userA'));
        expect(fx.repo.isLoggedIn, isTrue);
        expect(await fx.cookieSnapshot(b.id), bCookies);
        expect(fx.repo.sessionEpoch.value, greaterThan(epochAfterScrub));
        expect(fx.repo.sessionEpoch.value, greaterThan(epochBefore));
        // Deleted/logged-out A must not reappear as published identity.
        expect(fx.repo.accountIdentity.value?.uid, isNot('101'));
      });
    });
  }
}

Future<String?> _persistedCp2Cookie(String accountId) async {
  final values = await SharedPreferencesStorePlatform.instance.getAll();
  return values['flutter.${ForumSessionSlots.cookiesPrefsKey(accountId)}']
      as String?;
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
      final repo = ForumRepository(client: client, config: _config);
      final fx = _Cp2Fixture(client, repo, handler, overrides);
      try {
        await body(fx);
      } finally {
        await repo.cancelLogin();
        await repo.cancelAddAccount();
        await repo.cancelReauthAccount();
        client.close(force: true);
      }
    }, overrides);
  } finally {
    for (final c in overrides.clients) {
      c.close(force: true);
    }
    await server.close(force: true);
  }
}

Future<void> _withFreshRepo(
  _LoopbackOverrides overrides,
  Future<void> Function(ForumRepository repo, ForumClient client) body,
) async {
  await HttpOverrides.runWithHttpOverrides(() async {
    final client = ForumClient(config: _config, delay: (_) async {});
    final repo = ForumRepository(client: client, config: _config);
    await body(repo, client);
  }, overrides);
}

class _Cp2Fixture {
  _Cp2Fixture(this.client, this.repo, this.server, this.overrides);
  final ForumClient client;
  final ForumRepository repo;
  final _Cp2Http server;
  final _LoopbackOverrides overrides;

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
  String? headerUidToHold;
  Completer<void>? headerStarted;
  Completer<void>? releaseHeader;
  String tokenSuffix = '';
  Completer<void>? holdIdentity;
  Completer<void>? identitySeen;
  Completer<void>? holdFirstChallenge;
  Completer<void>? firstChallengeSeen;
  bool failHeldChallenge = false;
  int challengeCount = 0;
  bool expired = false;
  final requests = <String>[];
  Completer<void>? rotateReceived;
  Completer<void>? releaseRotation;
  String rotationToken = 'token-101-fresh';
  String? failUser;
  Completer<void>? holdLogin;
  Completer<void>? loginHeld;
  bool omitUid = false;
  bool failIndex = false;
  String? forceUid;
  final expectUid = <String, String>{};

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    final heldIdentity = path == '/' ? holdIdentity : null;
    requests.add('${request.method} $path');
    try {
      if (expired && (path == '/index.php' || path == '/simple/index.php')) {
        request.response.write('<html><a href="login.php">登录</a></html>');
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && path == '/login.php') {
        if (holdFirstChallenge != null && challengeCount++ == 0) {
          firstChallengeSeen!.complete();
          await holdFirstChallenge!.future;
          if (failHeldChallenge) {
            request.response.headers.contentType = ContentType.html;
            request.response.write('<html>验证码暂时不可用</html>');
            await request.response.close();
            return;
          }
        }
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
          request.response.headers.set(HttpHeaders.setCookieHeader,
              'winduser=token-$uid$tokenSuffix; Path=/');
          request.response.headers.contentType = ContentType.html;
          request.response.write('登录成功');
        }
      } else if (path == '/index.php' || path == '/' || path.isEmpty) {
        if (heldIdentity != null) {
          identitySeen!.complete();
          await heldIdentity.future;
        }

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
        if (headerUidToHold == uid && headerStarted != null) {
          if (!headerStarted!.isCompleted) headerStarted!.complete();
          await releaseHeader!.future;
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
          '<html><body>'
          '<div id="user-login"><a href="u.php">$name</a></div>'
          '$uidLink'
          '</body></html>',
        );
      } else if (path == '/cookie-expire') {
        request.response.headers
            .set(HttpHeaders.setCookieHeader, 'winduser=; Max-Age=0; Path=/');
        request.response.write('expired');
      } else if (path == '/cookie-echo') {
        request.response
            .write(request.headers.value(HttpHeaders.cookieHeader) ?? '');
      } else if (path == '/cookie-rotate') {
        if (rotateReceived != null && !rotateReceived!.isCompleted) {
          rotateReceived!.complete();
        }
        if (releaseRotation != null) await releaseRotation!.future;
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=$rotationToken; Path=/');
        request.response.write('ok');
      } else if (path == '/simple/index.php') {
        request.response.write('<html></html>');
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('missing $path');
      }
      await request.response.close();
      if (heldIdentity != null) {
        holdIdentity = null;
      }
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
  Completer<void>? identityConsumed;

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
    return _ObservedIdentityClient(client, () => identityConsumed);
  }
}

class _MigrationBlockingStore extends ForumSessionStore {
  _MigrationBlockingStore(Uri origin) : super(origin: origin);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> saveCookies(Map<String, ForumStoredCookie> cookies) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.saveCookies(cookies);
  }
}

class _RegistryGateStore extends InMemorySharedPreferencesStore {
  _RegistryGateStore() : super.empty();
  bool blockNext = false;
  bool reject = false;
  bool rejectOriginClear = false;
  String? activeIdToBlock;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (rejectOriginClear &&
        key == 'flutter.forum_session_cookies_v2:fixture.invalid' &&
        value == '{}') return false;
    if (blockNext &&
        key == 'flutter.forum_account_registry_v1' &&
        (activeIdToBlock == null ||
            (jsonDecode(value as String) as Map)['activeAccountId'] ==
                activeIdToBlock)) {
      blockNext = false;
      started.complete();
      await release.future;
      if (reject) return false;
    }
    return super.setValue(type, key, value);
  }
}

class _RetirementGateStore extends InMemorySharedPreferencesStore {
  _RetirementGateStore() : super.empty();
  bool armed = false;
  bool holdFreshJar = false;
  String? accountKey;
  final accountStarted = Completer<void>();
  final releaseAccount = Completer<void>();
  final freshStarted = Completer<void>();
  final releaseFresh = Completer<void>();
  final originStarted = Completer<void>();
  final releaseOrigin = Completer<void>();
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (armed &&
        holdFreshJar &&
        key == accountKey &&
        value != '{}' &&
        !freshStarted.isCompleted) {
      freshStarted.complete();
      await releaseFresh.future;
    }
    if (armed && value == '{}') {
      if (key == accountKey && !accountStarted.isCompleted) {
        accountStarted.complete();
        await releaseAccount.future;
      } else if (key == 'flutter.forum_session_cookies_v2:fixture.invalid' &&
          !originStarted.isCompleted) {
        originStarted.complete();
        await releaseOrigin.future;
      }
    }
    return super.setValue(type, key, value);
  }
}

class _ObservedIdentityClient implements HttpClient {
  _ObservedIdentityClient(this.delegate, this.consumed);
  final HttpClient delegate;
  final Completer<void>? Function() consumed;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    final request = await delegate.openUrl(method, uri);
    final receipt = consumed();
    if (method == 'GET' &&
        uri.path == '/' &&
        receipt != null &&
        !receipt.isCompleted) {
      return _ObservedIdentityRequest(request, receipt);
    }
    return request;
  }

  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  set autoUncompress(bool value) => delegate.autoUncompress = value;
  @override
  set userAgent(String? value) => delegate.userAgent = value;
  @override
  set findProxy(String Function(Uri)? value) => delegate.findProxy = value;
  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value) =>
      delegate.connectionFactory = value;
  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedIdentityRequest implements HttpClientRequest {
  _ObservedIdentityRequest(this.delegate, this.consumed);
  final HttpClientRequest delegate;
  final Completer<void> consumed;
  @override
  HttpHeaders get headers => delegate.headers;
  @override
  Uri get uri => delegate.uri;
  @override
  set followRedirects(bool value) => delegate.followRedirects = value;
  @override
  Future<HttpClientResponse> close() async =>
      _ObservedIdentityResponse(await delegate.close(), consumed);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      delegate.abort(exception, stackTrace);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ObservedIdentityResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _ObservedIdentityResponse(this.delegate, this.consumed);
  final HttpClientResponse delegate;
  final Completer<void> consumed;
  @override
  int get statusCode => delegate.statusCode;
  @override
  HttpHeaders get headers => delegate.headers;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      delegate.listen(onData, onError: onError, onDone: () {
        onDone?.call();
        if (!consumed.isCompleted) consumed.complete();
      }, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
