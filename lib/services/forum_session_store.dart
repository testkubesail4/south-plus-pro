import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class ForumSessionStore {
  ForumSessionStore({this.origin});
  final Uri? origin;
  static const _legacyKey = 'forum_session_cookies_v1';
  String get _cookiesKey => origin == null
      ? _legacyKey
      : 'forum_session_cookies_v2:${origin!.host.toLowerCase()}';

  Future<Map<String, ForumStoredCookie>> loadCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cookiesKey) ??
        (origin == null ? null : prefs.getString(_legacyKey));
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
    final active = Map<String, ForumStoredCookie>.from(cookies)
      ..removeWhere((_, cookie) =>
          cookie.isExpired ||
          (origin != null && !cookie.appliesToHost(origin!.host)));
    final prefs = await SharedPreferences.getInstance();
    // Empty scoped records are tombstones: logout must not re-import legacy auth.
    await _checkedWrite(
        prefs,
        prefs.setString(
            _cookiesKey,
            jsonEncode(
                active.map((key, cookie) => MapEntry(key, cookie.toJson())))));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _checkedWrite(
        prefs,
        origin == null
            ? prefs.remove(_cookiesKey)
            : prefs.setString(_cookiesKey, '{}'));
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
