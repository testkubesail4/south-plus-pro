import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class ForumSessionStore {
  static const _cookiesKey = 'forum_session_cookies_v1';

  Future<Map<String, ForumStoredCookie>> loadCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCookies = prefs.getString(_cookiesKey);
    if (rawCookies == null || rawCookies.isEmpty) {
      return <String, ForumStoredCookie>{};
    }

    final decoded = jsonDecode(rawCookies);
    if (decoded is! Map<String, dynamic>) {
      return <String, ForumStoredCookie>{};
    }

    final cookies = <String, ForumStoredCookie>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      final cookie = ForumStoredCookie.fromJson(value);
      if (cookie == null || cookie.isExpired) continue;
      cookies[entry.key] = cookie;
    }
    return cookies;
  }

  Future<void> saveCookies(Map<String, ForumStoredCookie> cookies) async {
    final prefs = await SharedPreferences.getInstance();
    final activeCookies = Map<String, ForumStoredCookie>.from(cookies)
      ..removeWhere((_, cookie) => cookie.isExpired);
    if (activeCookies.isEmpty) {
      await prefs.remove(_cookiesKey);
      return;
    }

    await prefs.setString(
      _cookiesKey,
      jsonEncode(
        activeCookies.map(
          (key, cookie) => MapEntry(key, cookie.toJson()),
        ),
      ),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookiesKey);
  }
}

class ForumStoredCookie {
  const ForumStoredCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.expiresAt,
    this.secure = false,
    this.httpOnly = false,
  });

  factory ForumStoredCookie.fromCookie(Cookie cookie, Uri origin) {
    final maxAge = cookie.maxAge;
    final expiresAt = maxAge == null
        ? cookie.expires
        : DateTime.now().toUtc().add(Duration(seconds: maxAge));
    return ForumStoredCookie(
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain?.toLowerCase() ?? origin.host.toLowerCase(),
      path: cookie.path?.isEmpty ?? true ? '/' : cookie.path,
      expiresAt: expiresAt?.toUtc(),
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
    );
  }

  factory ForumStoredCookie.session({
    required String name,
    required String value,
    required Uri origin,
  }) {
    return ForumStoredCookie(
      name: name,
      value: value,
      domain: origin.host.toLowerCase(),
      path: '/',
    );
  }

  final String name;
  final String value;
  final String? domain;
  final String? path;
  final DateTime? expiresAt;
  final bool secure;
  final bool httpOnly;

  bool get isExpired {
    final expiresAt = this.expiresAt;
    return expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc());
  }

  bool matches(Uri uri) {
    if (isExpired) return false;
    if (secure && uri.scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    final domain = this.domain?.toLowerCase();
    if (domain != null &&
        host != domain &&
        !host.endsWith('.${domain.replaceFirst(RegExp(r'^\.'), '')}')) {
      return false;
    }

    final cookiePath = path ?? '/';
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath.startsWith(cookiePath);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      'expiresAt': expiresAt?.toIso8601String(),
      'secure': secure,
      'httpOnly': httpOnly,
    };
  }

  static ForumStoredCookie? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final value = json['value'];
    if (name is! String || name.isEmpty || value is! String || value.isEmpty) {
      return null;
    }

    final expiresAtValue = json['expiresAt'];
    return ForumStoredCookie(
      name: name,
      value: value,
      domain: json['domain'] is String ? json['domain'] as String : null,
      path: json['path'] is String ? json['path'] as String : null,
      expiresAt: expiresAtValue is String
          ? DateTime.tryParse(expiresAtValue)?.toUtc()
          : null,
      secure: json['secure'] == true,
      httpOnly: json['httpOnly'] == true,
    );
  }
}
