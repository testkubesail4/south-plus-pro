import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'forum_session_slots.dart';

class ForumSessionStore {
  ForumSessionStore({this.origin})
      : slotId = origin == null ? null : ForumSessionSlots.origin(origin);

  ForumSessionStore.forSlot({
    required String this.slotId,
    required Uri this.origin,
  });

  final Uri? origin;
  final String? slotId;

  static const _legacyKey = 'forum_session_cookies_v1';

  bool get isMemoryOnly =>
      slotId != null && ForumSessionSlots.isStaging(slotId!);

  String? get _cookiesKey {
    final id = slotId;
    if (id != null) {
      return ForumSessionSlots.cookiesPrefsKey(id, origin: origin);
    }
    return origin == null
        ? _legacyKey
        : 'forum_session_cookies_v2:${origin!.host.toLowerCase()}';
  }

  Future<Map<String, ForumStoredCookie>> loadCookies() async {
    if (isMemoryOnly) return {};
    final key = _cookiesKey;
    if (key == null) return {};
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(key);
    // Legacy v1 fallback only for origin-scoped / unscoped stores.
    if ((raw == null || raw.isEmpty) &&
        (slotId == null || ForumSessionSlots.isOrigin(slotId!)) &&
        origin != null) {
      raw = prefs.getString(_legacyKey);
    }
    if (raw == null || raw.isEmpty) return {};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (decoded is! Map<String, dynamic>) return {};
    final cookies = <String, ForumStoredCookie>{};
    for (final entry in decoded.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final cookie =
          ForumStoredCookie.fromJson(entry.value as Map<String, dynamic>);
      if (cookie == null ||
          cookie.isExpired ||
          (origin != null && !cookie.appliesToHost(origin!.host))) continue;
      cookies[entry.key] = cookie;
    }
    return cookies;
  }

  Future<void> saveCookies(Map<String, ForumStoredCookie> cookies) async {
    if (isMemoryOnly) return;
    final key = _cookiesKey;
    if (key == null) return;
    final active = Map<String, ForumStoredCookie>.from(cookies)
      ..removeWhere((_, cookie) =>
          cookie.isExpired ||
          (origin != null && !cookie.appliesToHost(origin!.host)));
    final prefs = await SharedPreferences.getInstance();
    // Empty scoped records are tombstones: logout must not re-import legacy auth.
    await _checkedWrite(
        prefs,
        prefs.setString(
            key,
            jsonEncode(
                active.map((key, cookie) => MapEntry(key, cookie.toJson())))));
  }

  Future<void> clear() async {
    if (isMemoryOnly) return;
    final key = _cookiesKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await _checkedWrite(
        prefs,
        // Unscoped legacy remove; scoped keys get `{}` tombstones.
        key == _legacyKey ? prefs.remove(key) : prefs.setString(key, '{}'));
  }

  /// Save and verify the account jar before its registry entry is committed.
  static Future<void> promoteToAccount({
    required String accountId,
    required Uri origin,
    required Map<String, ForumStoredCookie> cookies,
  }) async {
    final target = ForumSessionStore.forSlot(
      slotId: ForumSessionSlots.account(accountId),
      origin: origin,
    );
    await target.saveCookies(cookies);
    final verified = await target.loadCookies();
    if (!_sameCookiePayload(verified, cookies)) {
      throw const FileSystemException('会话保存校验失败');
    }
  }

  static bool _sameCookiePayload(Map<String, ForumStoredCookie> loaded,
      Map<String, ForumStoredCookie> expected) {
    final activeExpected = Map<String, ForumStoredCookie>.from(expected)
      ..removeWhere((_, c) => c.isExpired);
    if (loaded.length != activeExpected.length) return false;
    for (final entry in activeExpected.entries) {
      final got = loaded[entry.key];
      if (got == null ||
          got.value != entry.value.value ||
          got.name != entry.value.name) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkedWrite(
      SharedPreferences prefs, Future<bool> write) async {
    try {
      if (!await write) throw const FileSystemException('会话保存失败');
    } catch (_) {
      try {
        await prefs.reload();
      } catch (_) {/* Preserve the original error. */}
      rethrow;
    }
  }
}

class ForumStoredCookie {
  const ForumStoredCookie(
      {required this.name,
      required this.value,
      this.domain,
      this.path,
      this.expiresAt,
      this.secure = false,
      this.httpOnly = false,
      this.hostOnly = true});

  factory ForumStoredCookie.fromCookie(Cookie cookie, Uri origin) {
    final host = origin.host.toLowerCase();
    final rawDomain = cookie.domain;
    final domain = rawDomain == null ? host : _domain(rawDomain);
    // Forum origins may set their own domain, never expand to arbitrary parents.
    if (domain == null ||
        domain != host ||
        (cookie.secure && origin.scheme != 'https'))
      throw const FormatException('Invalid cookie scope');
    if ((cookie.name.startsWith('__Secure-') &&
            (!cookie.secure || origin.scheme != 'https')) ||
        (cookie.name.startsWith('__Host-') &&
            (!cookie.secure ||
                origin.scheme != 'https' ||
                rawDomain != null ||
                cookie.path != '/')))
      throw const FormatException('Invalid cookie prefix');
    final path = cookie.path;
    final maxAge = cookie.maxAge;
    return ForumStoredCookie(
        name: cookie.name,
        value: cookie.value,
        domain: domain,
        hostOnly: rawDomain == null || InternetAddress.tryParse(domain) != null,
        path: path != null && path.startsWith('/')
            ? path
            : _defaultPath(origin.path),
        expiresAt: maxAge == null
            ? cookie.expires?.toUtc()
            : DateTime.now().toUtc().add(Duration(
                seconds: maxAge <= 0
                    ? -1
                    : math.min(maxAge, const Duration(days: 400).inSeconds))),
        secure: cookie.secure,
        httpOnly: cookie.httpOnly);
  }

  factory ForumStoredCookie.session(
          {required String name, required String value, required Uri origin}) =>
      ForumStoredCookie(
          name: name,
          value: value,
          domain: origin.host.toLowerCase(),
          path: '/',
          hostOnly: true);

  final String name;
  final String value;
  final String? domain;
  final String? path;
  final DateTime? expiresAt;
  final bool secure;
  final bool httpOnly;
  final bool hostOnly;
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());

  bool appliesToHost(String host) {
    host = host.toLowerCase();
    final domain = this.domain;
    if (domain == null) return false;
    return host == domain || (!hostOnly && host.endsWith('.$domain'));
  }

  bool matches(Uri uri) {
    if (isExpired ||
        (secure && uri.scheme != 'https') ||
        !appliesToHost(uri.host)) return false;
    final cookiePath = path ?? '/';
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath == cookiePath ||
        (requestPath.startsWith(cookiePath) &&
            (cookiePath.endsWith('/') ||
                requestPath[cookiePath.length] == '/'));
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expiresAt': expiresAt?.toIso8601String(),
        'secure': secure,
        'httpOnly': httpOnly,
        'hostOnly': hostOnly
      };

  static ForumStoredCookie? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final value = json['value'];
    final domain =
        json['domain'] is String ? _domain(json['domain'] as String) : null;
    if (name is! String ||
        name.isEmpty ||
        value is! String ||
        value.isEmpty ||
        domain == null ||
        !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
        RegExp(r'[\x00-\x20\x7f;,]').hasMatch(value)) return null;
    final expires = json['expiresAt'];
    final expiresAt =
        expires is String ? DateTime.tryParse(expires)?.toUtc() : null;
    if (expires != null && expiresAt == null) return null;
    final path = json['path'];
    if (path != null && (path is! String || !path.startsWith('/'))) return null;
    return ForumStoredCookie(
        name: name,
        value: value,
        domain: domain,
        path: path as String? ?? '/',
        expiresAt: expiresAt,
        secure: json['secure'] == true,
        httpOnly: json['httpOnly'] == true,
        hostOnly: json['hostOnly'] != false);
  }

  static String _defaultPath(String path) {
    final slash = path.lastIndexOf('/');
    return !path.startsWith('/') || slash <= 0 ? '/' : path.substring(0, slash);
  }

  static String? _domain(String value) {
    value = value.toLowerCase();
    if (value.startsWith('.')) value = value.substring(1);
    if (value.isEmpty ||
        value.length > 253 ||
        !value.split('.').every((label) =>
            RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(label)))
      return null;
    return value;
  }
}
