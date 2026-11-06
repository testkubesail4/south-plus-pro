import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'forum_account_id.dart';

enum AccountReadyState { ready, needsReauth }

class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.displayName,
    this.systemName,
    this.uid,
    this.avatarUrl,
    this.status = AccountReadyState.ready,
    this.isActive = false,
  });

  final String id;
  final String displayName;
  final String? systemName;
  final String? uid;
  final String? avatarUrl;
  final AccountReadyState status;
  final bool isActive;

  AccountSummary copyWith({
    String? id,
    String? displayName,
    String? systemName,
    String? uid,
    String? avatarUrl,
    AccountReadyState? status,
    bool? isActive,
  }) =>
      AccountSummary(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        systemName: systemName ?? this.systemName,
        uid: uid ?? this.uid,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        status: status ?? this.status,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'systemName': systemName,
        'uid': uid,
        'avatarUrl': avatarUrl,
        'status': status.name,
      };

  static AccountSummary? fromJson(Map<String, dynamic> json,
      {String? activeId}) {
    final id = json['id'];
    if (id is! String || ForumAccountId.tryParse(id) == null) return null;
    final statusRaw = json['status'];
    final status = statusRaw == AccountReadyState.needsReauth.name
        ? AccountReadyState.needsReauth
        : AccountReadyState.ready;
    final systemName =
        json['systemName'] is String ? json['systemName'] as String : null;
    final uid = json['uid'] is String ? json['uid'] as String : null;
    final nickname =
        json['nickname'] is String ? json['nickname'] as String : null;
    final displayName = json['displayName'] is String &&
            (json['displayName'] as String).isNotEmpty
        ? json['displayName'] as String
        : (nickname?.isNotEmpty == true
            ? nickname!
            : (systemName?.isNotEmpty == true
                ? systemName!
                : (uid?.isNotEmpty == true ? uid! : id)));
    return AccountSummary(
      id: id,
      displayName: displayName,
      systemName: systemName,
      uid: uid,
      avatarUrl:
          json['avatarUrl'] is String ? json['avatarUrl'] as String : null,
      status: status,
      isActive: activeId != null && activeId == id,
    );
  }
}

class ForumAccountRegistry {
  ForumAccountRegistry();

  static const prefsKey = 'forum_account_registry_v1';
  static const schemaVersion = 1;

  final _accounts = _RegistryValue<List<AccountSummary>>(const []);
  final _activeAccount = _RegistryValue<AccountSummary?>(null);
  final _activeAccountId = _RegistryValue<String?>(null);
  Future<void>? _operations;

  ValueListenable<List<AccountSummary>> get accounts => _accounts;
  ValueListenable<AccountSummary?> get activeAccount => _activeAccount;
  ValueListenable<String?> get activeAccountId => _activeAccountId;

  String? get activeId => _activeAccountId.value;

  Future<void> load() => _serialize(() async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(prefsKey);
        if (raw == null || raw.isEmpty) {
          _publish(const [], null);
          return;
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          _publish(const [], null);
          return;
        }
        if (decoded is! Map<String, dynamic>) {
          _publish(const [], null);
          return;
        }
        final activeId = decoded['activeAccountId'] is String
            ? decoded['activeAccountId'] as String
            : null;
        final list = <AccountSummary>[];
        final rawAccounts = decoded['accounts'];
        if (rawAccounts is List) {
          for (final item in rawAccounts) {
            if (item is! Map<String, dynamic>) continue;
            final summary = AccountSummary.fromJson(item, activeId: activeId);
            if (summary != null) list.add(summary);
          }
        }
        final resolvedActive = activeId == null
            ? null
            : list.cast<AccountSummary?>().firstWhere(
                  (a) => a!.id == activeId,
                  orElse: () => null,
                );
        _publish(list, resolvedActive?.id);
      });

  AccountSummary? find(String accountId) {
    for (final account in _accounts.value) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  /// Upsert one row for [accountId]. Same uid never duplicates.
  Future<AccountSummary> upsert({
    required String accountId,
    required String systemName,
    String? nickname,
    String? avatarUrl,
    AccountReadyState status = AccountReadyState.ready,
    bool activate = false,
    String? needsReauthAccountId,
    void Function()? beforePublish,
    void Function()? beforeNotify,
  }) =>
      _serialize(() async {
        final id = ForumAccountId.parse(accountId);
        final displayName = (nickname != null && nickname.isNotEmpty)
            ? nickname
            : (systemName.isNotEmpty ? systemName : id.uid);
        final next = AccountSummary(
          id: accountId,
          displayName: displayName,
          systemName: systemName.isEmpty ? null : systemName,
          uid: id.uid,
          avatarUrl: avatarUrl,
          status: status,
          isActive: false,
        );
        final list = [
          for (final account in _accounts.value)
            account.id == needsReauthAccountId && account.id != accountId
                ? account.copyWith(status: AccountReadyState.needsReauth)
                : account,
        ];
        final index = list.indexWhere((a) => a.id == accountId);
        if (index >= 0) {
          list[index] = next;
        } else {
          list.add(next);
        }
        final activeId = activate ? accountId : _activeAccountId.value;
        await _commit(list, activeId,
            beforePublish: beforePublish, beforeNotify: beforeNotify);
        return find(accountId)!;
      });

  Future<void> setStatus(
    String accountId,
    AccountReadyState status, {
    bool deactivate = false,
    bool Function()? isCurrent,
    void Function()? beforeDeactivate,
    void Function()? beforeNotify,
  }) =>
      _serialize(() async {
        if (isCurrent != null && !isCurrent()) return;
        final list = [..._accounts.value];
        final index = list.indexWhere((a) => a.id == accountId);
        if (index < 0) return;
        list[index] = list[index].copyWith(status: status);
        final deactivating = deactivate && _activeAccountId.value == accountId;
        await _commit(list, deactivating ? null : _activeAccountId.value,
            isCurrent: isCurrent,
            beforePublish: deactivating ? beforeDeactivate : null,
            beforeNotify: deactivating ? beforeNotify : null);
      });

  Future<void> setActive(
    String? accountId, {
    bool Function()? isCurrent,
    void Function()? beforePublish,
    void Function()? beforeNotify,
  }) =>
      _serialize(() async {
        if (isCurrent != null && !isCurrent()) return;
        if (accountId != null && find(accountId) == null) {
          throw StateError('Unknown account: $accountId');
        }
        await _commit(_accounts.value, accountId,
            isCurrent: isCurrent,
            beforePublish: beforePublish,
            beforeNotify: beforeNotify);
      });

  Future<void> remove(
    String accountId, {
    bool Function()? isCurrent,
    void Function()? beforeDeactivate,
    void Function()? beforeNotify,
  }) =>
      _serialize(() async {
        if (isCurrent != null && !isCurrent()) return;
        final list = _accounts.value.where((a) => a.id != accountId).toList();
        final deactivating = _activeAccountId.value == accountId;
        await _commit(list, deactivating ? null : _activeAccountId.value,
            isCurrent: isCurrent,
            beforePublish: deactivating ? beforeDeactivate : null,
            beforeNotify: deactivating ? beforeNotify : null);
      });

  Future<void> _commit(
    List<AccountSummary> accounts,
    String? activeId, {
    bool Function()? isCurrent,
    void Function()? beforePublish,
    void Function()? beforeNotify,
  }) async {
    if (isCurrent != null && !isCurrent()) return;
    await _persist(accounts, activeId);
    if (isCurrent != null && !isCurrent()) {
      await _persist(_accounts.value, _activeAccountId.value);
      return;
    }
    try {
      beforePublish?.call();
    } catch (_) {
      await _persist(_accounts.value, _activeAccountId.value);
      rethrow;
    }
    _publish(accounts, activeId, beforeNotify: beforeNotify);
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _operations;
    final tail = Completer<void>();
    _operations = tail.future;
    Future<T> run() async {
      try {
        if (previous != null) await previous;
        return await operation();
      } finally {
        if (identical(_operations, tail.future)) _operations = null;
        tail.complete();
      }
    }

    return run();
  }

  Future<void> _persist(List<AccountSummary> accounts, String? activeId) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'schemaVersion': schemaVersion,
      'activeAccountId': activeId,
      'accounts': accounts
          .map((a) => {
                ...a.toJson(),
                // Keep nickname out of id; displayName is derived at read.
              })
          .toList(),
    });
    try {
      if (!await prefs.setString(prefsKey, payload)) {
        throw const FileSystemException('账号列表保存失败');
      }
      final readBack = prefs.getString(prefsKey);
      if (readBack != payload) {
        throw const FileSystemException('账号列表保存校验失败');
      }
    } catch (_) {
      await prefs.reload();
      rethrow;
    }
  }

  void _publish(List<AccountSummary> accounts, String? activeId,
      {void Function()? beforeNotify}) {
    final painted = [
      for (final account in accounts)
        account.copyWith(isActive: account.id == activeId),
    ];
    final accountsChanged = _accounts.assign(List.unmodifiable(painted));
    final idChanged = _activeAccountId.assign(activeId);
    final activeChanged = _activeAccount.assign(activeId == null
        ? null
        : painted.cast<AccountSummary?>().firstWhere(
              (a) => a!.id == activeId,
              orElse: () => null,
            ));
    beforeNotify?.call();
    if (accountsChanged) _accounts.publish();
    if (idChanged) _activeAccountId.publish();
    if (activeChanged) _activeAccount.publish();
  }

  void dispose() {
    _accounts.dispose();
    _activeAccount.dispose();
    _activeAccountId.dispose();
  }
}

class _RegistryValue<T> extends ChangeNotifier implements ValueListenable<T> {
  _RegistryValue(this._value);
  T _value;
  @override
  T get value => _value;

  bool assign(T value) {
    if (value == _value) return false;
    _value = value;
    return true;
  }

  void publish() => notifyListeners();
}
