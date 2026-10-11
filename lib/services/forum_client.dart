import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'forum_network_config.dart';
import 'forum_session_store.dart';
import 'forum_trace_logger.dart';

class ForumAttachment {
  const ForumAttachment({
    required this.file,
    required this.fileName,
    required this.mimeType,
  });
  final File file;
  final String fileName;
  final String mimeType;
}

class AttachmentDownloadException implements Exception {
  const AttachmentDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  bool _sameOrigin(Uri uri) =>
      uri.scheme == baseUri.scheme &&
      uri.host == baseUri.host &&
      uri.port == baseUri.port &&
      uri.userInfo.isEmpty;

  bool isAttachmentUrl(String url) {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null) return false;
    final uri = baseUri.resolveUri(parsed);
    if (!_sameOrigin(uri) || uri.path != '/job.php') return false;
    return RegExp(
          r'^action-download-pid-(?:tpc|\d+)-tid-\d+-aid-[1-9]\d*\.html$',
        ).hasMatch(uri.query) ||
        (uri.queryParameters['action'] == 'download' &&
            RegExp(r'^[1-9]\d*$').hasMatch(uri.queryParameters['aid'] ?? ''));
  }

  Future<ForumAttachment> downloadAttachment(
    String url, {
    required Directory directory,
    String? suggestedName,
  }) async {
    if (!isAttachmentUrl(url)) {
      throw const AttachmentDownloadException('不是当前论坛的附件链接');
    }
    await restoreCookies();
    var uri = baseUri.resolve(url.trim());
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await _httpClient.getUrl(uri);
      request.followRedirects = false;
      _applyCookies(request);
      final response = await request.close();
      await _storeCookies(response, uri);
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.listen(null).cancel();
        final next = location == null ? null : Uri.tryParse(location);
        if (next == null || !_sameOrigin(uri.resolveUri(next))) {
          throw const AttachmentDownloadException('附件跳转到不安全的地址');
        }
        uri = uri.resolveUri(next);
        continue;
      }
      final mimeType =
          response.headers.contentType?.mimeType ?? 'application/octet-stream';
      if (response.statusCode != HttpStatus.ok ||
          mimeType == 'text/html' ||
          mimeType == 'application/xhtml+xml') {
        await response.listen(null).cancel();
        throw const AttachmentDownloadException('附件下载失败，请检查登录状态或下载权限');
      }
      final temporary = await directory.createTemp('forum_attachment_');
      final file = File('${temporary.path}/download');
      RandomAccessFile? output;
      try {
        output = await file.open(mode: FileMode.write);
        final prefix = <int>[];
        var checked = false;
        var size = 0;
        await for (final chunk in response) {
          size += chunk.length;
          if (!checked) {
            prefix.addAll(chunk);
            if (prefix.length < 512) continue;
            _checkAttachmentPrefix(prefix);
            await output.writeFrom(prefix);
            prefix.clear();
            checked = true;
          } else {
            await output.writeFrom(chunk);
          }
        }
        if (!checked) {
          _checkAttachmentPrefix(prefix);
          await output.writeFrom(prefix);
        }
        if (size == 0) throw const AttachmentDownloadException('附件数据为空');
        await output.close();
        output = null;
        return ForumAttachment(
          file: file,
          fileName: _attachmentFileName(
            response.headers.value('content-disposition'),
            suggestedName,
          ),
          mimeType: mimeType,
        );
      } catch (_) {
        try {
          await output?.close();
        } finally {
          await temporary.delete(recursive: true);
        }
        rethrow;
      }
    }
    throw const AttachmentDownloadException('附件跳转次数过多');
  }

  void _checkAttachmentPrefix(List<int> bytes) {
    final offset = bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? 3
        : 0;
    final prefix =
        latin1.decode(bytes.skip(offset).take(512).toList()).trimLeft();
    if (RegExp(
      r'^<(?:!doctype\s+html|html\b|head\b|body\b|script\b|form\b|title\b|meta\b)',
      caseSensitive: false,
    ).hasMatch(prefix)) {
      throw const AttachmentDownloadException('附件返回了网页，请检查登录状态或下载权限');
    }
  }

  String _attachmentFileName(String? disposition, String? suggestedName) {
    var name = RegExp(
      r'''filename\s*=\s*(?:"([^"]*)"|([^;]*))''',
      caseSensitive: false,
    ).firstMatch(disposition ?? '');
    var value =
        name?.group(1) ?? name?.group(2) ?? suggestedName ?? 'attachment.bin';
    final encoded = RegExp(
      r"filename\*\s*=\s*utf-8'[^']*'([^;]*)",
      caseSensitive: false,
    ).firstMatch(disposition ?? '');
    if (encoded != null) {
      try {
        value = Uri.decodeComponent(encoded.group(1)!.trim());
      } on FormatException {
        /* Use the plain filename. */
      }
    }
    value = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_').trim();
    value = value.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (value.isEmpty) value = 'attachment.bin';
    return value.length > 180 ? value.substring(0, 180) : value;
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
