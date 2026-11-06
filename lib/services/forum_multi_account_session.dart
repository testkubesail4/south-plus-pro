import 'package:flutter/foundation.dart';

import 'forum_account_id.dart';
import 'forum_account_registry.dart';
import 'forum_client.dart';
import 'forum_session_slots.dart';
import 'forum_session_store.dart';

/// Coordinates account credentials, registry state and session notifications.
class ForumMultiAccountSession {
  ForumMultiAccountSession({
    required ForumClient client,
    ForumAccountRegistry? registry,
    ValueNotifier<int>? sessionEpoch,
  })  : _client = client,
        registry = registry ?? ForumAccountRegistry(),
        _sessionEpoch = sessionEpoch ?? ValueNotifier<int>(0),
        _ownsEpoch = sessionEpoch == null;

  ForumClient _client;
  final ForumAccountRegistry registry;
  final ValueNotifier<int> _sessionEpoch;
  final bool _ownsEpoch;
  bool _switching = false;

  ValueListenable<List<AccountSummary>> get accounts => registry.accounts;
  ValueListenable<AccountSummary?> get activeAccount => registry.activeAccount;
  ValueListenable<int> get sessionEpoch => _sessionEpoch;

  /// Keep slot ops on the live [ForumClient] after network route replacement.
  void attachClient(ForumClient client) {
    _client = client;
  }

  Future<void> bootstrap() async {
    await registry.load();
    final activeId = registry.activeId;
    if (activeId == null) {
      await enterGuest(bumpEpoch: false);
      return;
    }
    final account = registry.find(activeId);
    if (account == null ||
        ForumAccountId.parse(activeId).origin !=
            ForumAccountId.normalizeOrigin(_client.baseUri) ||
        account.status == AccountReadyState.needsReauth) {
      await enterGuest(bumpEpoch: false);
      return;
    }
    await _loadAccountJar(activeId,
        bumpEpoch: false); // false => needsReauth+guest
  }

  Future<void> switchAccount(String accountId) async {
    _requireCurrentOrigin(accountId);
    final account = registry.find(accountId);
    if (account == null) {
      throw StateError('Unknown account: $accountId');
    }
    if (account.status == AccountReadyState.needsReauth) {
      throw StateError('Account needs reauth: $accountId');
    }
    if (registry.activeId == accountId &&
        _client.slotId == accountId &&
        _client.isLoggedIn &&
        _client.isCredentialCurrent(_client.credentialGeneration)) return;
    final loaded = await _loadAccountJar(accountId, bumpEpoch: true);
    if (!loaded) {
      throw StateError('Account needs reauth: $accountId');
    }
  }

  Future<void> selectAccount(String accountId) => switchAccount(accountId);

  ForumAccountId _requireCurrentOrigin(String accountId) {
    final id = ForumAccountId.parse(accountId);
    if (id.origin != ForumAccountId.normalizeOrigin(_client.baseUri)) {
      throw StateError('Account belongs to another site');
    }
    return id;
  }

  Future<AccountSummary> commitAuthenticatedAccount({
    required String accountId,
    required String systemName,
    required Map<String, ForumStoredCookie> cookies,
    String? nickname,
    String? avatarUrl,
    String? retireSourceSlot,
    String? retireAccountId,
    required void Function() requireCurrent,
  }) async {
    _requireCurrentOrigin(accountId);
    final client = _client;
    final epoch = _sessionEpoch.value;
    void requireSession() {
      requireCurrent();
      if (!identical(client, _client) || epoch != _sessionEpoch.value) {
        throw StateError('Account session changed');
      }
    }

    late AccountSummary committed;
    await client.commitAccountCookies(
      accountId: accountId,
      cookies: cookies,
      retireSourceSlot: retireSourceSlot,
      requireCurrent: requireSession,
      commitMetadata: (install) async {
        committed = await registry.upsert(
          accountId: accountId,
          systemName: systemName,
          nickname: nickname,
          avatarUrl: avatarUrl,
          status: AccountReadyState.ready,
          activate: true,
          needsReauthAccountId: retireAccountId,
          beforePublish: () {
            requireSession();
            install();
          },
          beforeNotify: () => _sessionEpoch.value++,
        );
      },
    );
    return committed;
  }

  Future<void> logoutAccount(String accountId) async {
    if (registry.find(accountId) == null) return;
    final isCurrent = await _retireAccountCookies(accountId);
    await registry.setStatus(accountId, AccountReadyState.needsReauth,
        deactivate: true,
        isCurrent: isCurrent,
        beforeDeactivate: _installGuest,
        beforeNotify: () => _sessionEpoch.value++);
  }

  Future<void> logoutCurrent() async {
    final activeId = registry.activeId;
    if (activeId != null) {
      await logoutAccount(activeId);
      return;
    }
    final client = _client;
    final epoch = _sessionEpoch.value;
    final isRetirementCurrent = await ForumClient.retireAndClearSlot(
        ForumSessionSlots.origin(client.baseUri),
        origin: client.baseUri);
    await registry.setActive(null,
        isCurrent: () =>
            isRetirementCurrent() &&
            identical(client, _client) &&
            epoch == _sessionEpoch.value &&
            registry.activeId == null,
        beforePublish: _installGuest,
        beforeNotify: () => _sessionEpoch.value++);
  }

  Future<void> removeAccount(String accountId) async {
    final isCurrent = await _retireAccountCookies(accountId);
    await registry.remove(accountId,
        isCurrent: isCurrent,
        beforeDeactivate: _installGuest,
        beforeNotify: () => _sessionEpoch.value++);
  }

  void _installGuest() {
    _client.bindSlot(ForumSessionSlots.origin(_client.baseUri));
    _client.markRestoredEmpty();
  }

  /// Retire+clear the account jar and the shared origin jar for that account's
  /// host. Other accounts on the same origin keep their v3 jars; a live client
  /// bound to another account slot is not rebound or memory-cleared here.
  Future<bool Function()> _retireAccountCookies(String accountId) async {
    final parsed = ForumAccountId.parse(accountId);
    final slotId = ForumSessionSlots.account(accountId);
    // Retire first so in-flight/queued persists admitted at gen N cannot
    // overwrite the tombstone after clear (fake logout / resurrection).
    final isCurrent =
        await ForumClient.retireAndClearSlot(slotId, origin: parsed.origin);
    await _tombstoneOriginJar(parsed.origin);
    return isCurrent;
  }

  Future<void> _tombstoneOriginJar(Uri origin) async {
    final originSlot = ForumSessionSlots.origin(origin);
    await ForumClient.retireAndClearSlot(originSlot, origin: origin);
  }

  Future<void> enterGuest({required bool bumpEpoch}) async {
    // Guest uses a fresh memory-only staging-like bind under origin slot but
    // skips prefs restore so a leftover v2 jar cannot revive auth.
    final client = _client;
    final epoch = _sessionEpoch.value;
    await registry.setActive(null, beforePublish: () {
      if (!identical(client, _client) || epoch != _sessionEpoch.value) {
        throw StateError('Account session changed');
      }
      _installGuest();
    }, beforeNotify: () {
      if (bumpEpoch) _sessionEpoch.value++;
    });
  }

  /// Loads [accountId] jar. Returns false when the jar is empty/invalid:
  /// marks needsReauth, enters guest, and never leaves ready+active+empty.
  Future<bool> _loadAccountJar(String accountId,
      {required bool bumpEpoch}) async {
    _requireCurrentOrigin(accountId);
    if (_switching) throw StateError('An account switch is already running');
    _switching = true;
    final client = _client;
    final epoch = _sessionEpoch.value;
    void requireCurrent() {
      if (!identical(client, _client) || epoch != _sessionEpoch.value) {
        throw StateError('Account session changed');
      }
    }

    try {
      final install = await client.prepareAccountSwitch(accountId);
      requireCurrent();
      if (install == null) {
        await registry.setStatus(accountId, AccountReadyState.needsReauth);
        requireCurrent();
        await _tombstoneOriginJar(ForumAccountId.parse(accountId).origin);
        requireCurrent();
        await enterGuest(bumpEpoch: bumpEpoch);
        return false;
      }
      await registry.setActive(accountId, beforePublish: () {
        requireCurrent();
        install();
      }, beforeNotify: () {
        if (bumpEpoch) _sessionEpoch.value++;
      });
      return true;
    } finally {
      _switching = false;
    }
  }

  void dispose() {
    if (_ownsEpoch) _sessionEpoch.dispose();
    registry.dispose();
  }
}
