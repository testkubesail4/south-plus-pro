import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'forum_network_config.dart';
import 'forum_session_store.dart';
import 'forum_trace_logger.dart';

class ForumClient {
  ForumClient({
    HttpClient? httpClient,
    ForumNetworkConfig? config,
    ForumSessionStore? sessionStore,
  })  : config = config ??
            const ForumNetworkConfig(
              site: ForumNetworkConfig.defaultSite,
              dohEnabled: true,
              dohProvider: ForumNetworkConfig.defaultProvider,
            ),
        _sessionStore = sessionStore ?? ForumSessionStore(),
        _ownsHttpClient = httpClient == null,
        _httpClient = httpClient ??
            createForumHttpClient(
              config ??
                  const ForumNetworkConfig(
                    site: ForumNetworkConfig.defaultSite,
                    dohEnabled: true,
                    dohProvider: ForumNetworkConfig.defaultProvider,
                  ),
            );

  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final ForumSessionStore? _sessionStore;
  final ForumNetworkConfig config;
  Uri get baseUri => config.baseUri;
  final Map<String, ForumStoredCookie> _cookies = <String, ForumStoredCookie>{};
  Future<void>? _restoreFuture;

  Future<void> restoreCookies() {
    return _restoreFuture ??= _restoreCookies();
  }

  Future<String> get(String path) async {
    await restoreCookies();
    final uri = baseUri.resolve(path);
    final requestStartedAt = DateTime.now();
    ForumTraceLogger.log('HTTP', 'GET $uri');
    final request = await _httpClient.getUrl(uri);
    _applyCookies(request);
    final response = await request.close();
    await _storeCookies(response, uri);
    final bodyBytes =
        await response.fold<List<int>>(<int>[], (b, d) => b..addAll(d));
    final body = utf8.decode(bodyBytes);
    final elapsed = DateTime.now().difference(requestStartedAt).inMilliseconds;
    ForumTraceLogger.log(
      'HTTP',
      'GET $uri -> status=${response.statusCode} bytes=${bodyBytes.length} elapsedMs=$elapsed',
    );
    if (ForumTraceLogger.shouldLogFullBody(uri)) {
      ForumTraceLogger.logBlock('HTTP', 'GET $uri response', body);
    }
    return body;
  }

  Future<Uint8List> getBytes(String path) async {
    await restoreCookies();
    final uri = baseUri.resolve(path);
    final request = await _httpClient.getUrl(uri);
    _applyCookies(request);
    final response = await request.close();
    await _storeCookies(response, uri);
    final bytes =
        await response.fold<List<int>>(<int>[], (b, d) => b..addAll(d));
    return Uint8List.fromList(bytes);
  }

  Future<String> post(String path, Map<String, String> form) async {
    await restoreCookies();
    final uri = baseUri.resolve(path);
    final requestStartedAt = DateTime.now();
    ForumTraceLogger.log(
      'HTTP',
      'POST $uri form=${ForumTraceLogger.sanitizeForm(form)}',
    );
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    _applyCookies(request);
    request.write(Uri(queryParameters: form).query);
    final response = await request.close();
    await _storeCookies(response, uri);
    final bodyBytes =
        await response.fold<List<int>>(<int>[], (b, d) => b..addAll(d));
    final body = utf8.decode(bodyBytes);
    final elapsed = DateTime.now().difference(requestStartedAt).inMilliseconds;
    ForumTraceLogger.log(
      'HTTP',
      'POST $uri -> status=${response.statusCode} bytes=${bodyBytes.length} elapsedMs=$elapsed',
    );
    if (ForumTraceLogger.shouldLogFullBody(uri)) {
      ForumTraceLogger.logBlock('HTTP', 'POST $uri response', body);
    }
    return body;
  }

  Future<void> clearSession() async {
    _cookies.clear();
    await _sessionStore?.clear();
  }

  Future<void> _restoreCookies() async {
    final restored = await _sessionStore?.loadCookies();
    if (restored == null || restored.isEmpty) return;
    _cookies
      ..clear()
      ..addAll(restored);
    await _persistCookies();
  }

  void _applyCookies(HttpClientRequest request) {
    _cookies.removeWhere((_, cookie) => cookie.isExpired);
    final cookies = _cookies.values
        .where((cookie) => cookie.matches(request.uri))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .toList();
    if (cookies.isEmpty) return;
    request.headers.set(
      HttpHeaders.cookieHeader,
      cookies.join('; '),
    );
  }

  Future<void> _storeCookies(HttpClientResponse response, Uri origin) async {
    var changed = false;
    for (final header
        in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final cookie = _parseCookie(header, origin);
      if (cookie == null) continue;
      final key = _cookieKey(cookie);
      if (cookie.isExpired || cookie.value.isEmpty) {
        changed = _cookies.remove(key) != null || changed;
      } else {
        _cookies[key] = cookie;
        changed = true;
      }
    }
    if (changed) await _persistCookies();
  }

  ForumStoredCookie? _parseCookie(String header, Uri origin) {
    try {
      return ForumStoredCookie.fromCookie(
        Cookie.fromSetCookieValue(header),
        origin,
      );
    } on FormatException {
      final separator = header.indexOf(';');
      final firstPart =
          separator == -1 ? header : header.substring(0, separator);
      final equals = firstPart.indexOf('=');
      if (equals <= 0) return null;
      return ForumStoredCookie.session(
        name: firstPart.substring(0, equals).trim(),
        value: firstPart.substring(equals + 1).trim(),
        origin: origin,
      );
    }
  }

  String _cookieKey(ForumStoredCookie cookie) {
    return '${cookie.name};${cookie.domain ?? baseUri.host};${cookie.path ?? '/'}';
  }

  Future<void> _persistCookies() async {
    _cookies.removeWhere((_, cookie) => cookie.isExpired);
    await _sessionStore?.saveCookies(_cookies);
  }

  bool get isLoggedIn {
    return _cookies.values.any(
      (cookie) =>
          !cookie.isExpired && cookie.name.toLowerCase().contains('winduser'),
    );
  }

  void close({bool force = false}) {
    if (_ownsHttpClient) _httpClient.close(force: force);
  }
}
