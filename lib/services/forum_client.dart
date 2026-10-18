import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'forum_network_config.dart';
import 'forum_request_exception.dart';
import 'forum_session_store.dart';
import 'forum_trace_logger.dart';

enum ForumReadRedirectPolicy { none, board }

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

class ForumFormFile {
  ForumFormFile({
    required this.name,
    required this.fileName,
    required this.mimeType,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String name;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
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
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  })  : config = config ??
            const ForumNetworkConfig(
              site: ForumNetworkConfig.defaultSite,
              dohEnabled: true,
              dohProvider: ForumNetworkConfig.defaultProvider,
            ),
        _sessionStore = sessionStore ?? ForumSessionStore(),
        _ownsHttpClient = httpClient == null,
        _pacer = _ForumRequestPacer(
          clock ?? DateTime.now,
          delay ?? _waitForForumGap,
        ),
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
  final _ForumRequestPacer _pacer;
  Future<void>? _restoreFuture;
  // Every client shares ForumSessionStore's single persisted session key.
  static Future<void>? _cookieWrites;
  static int _cookieStoreGeneration = 0;
  int _cookieGeneration = 0;

  Future<void> restoreCookies() {
    return _restoreFuture ??= _restoreCookies();
  }

  Future<String> get(String path) {
    return _readText('GET', path, retryCooldown: true);
  }

  Future<String> getOnce(String path) => _readText('GET', path);

  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy = ForumReadRedirectPolicy.none}) {
    if (!_sameOrigin(baseUri.resolve(path))) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '不能读取其他站点的页面');
    }
    return _readText('GET', path,
        requireCurrentSession: requireCurrentSession,
        requireOk: true,
        invalidPageStatus: true,
        redirectPolicy: redirectPolicy);
  }

  Future<String> getForm(String path,
          {void Function()? requireCurrentSession,
          bool followRedirects = true}) =>
      _readText('GET', path,
          requireCurrentSession: requireCurrentSession,
          requireOk: true,
          sensitiveAccount: true,
          followRedirects: followRedirects);

  Future<Uint8List> getBytes(String path) {
    return _readBytes(path);
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
      final response = await _pacer.send(uri, request.close);
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

  Future<String> post(String path, Map<String, String> form) {
    return _readText('POST', path, form: form);
  }

  Future<String> postForm(
    String path,
    List<MapEntry<String, String>> fields, {
    bool multipart = false,
    List<ForumFormFile> files = const [],
    void Function()? requireCurrentSession,
  }) async {
    final uri = baseUri.resolve(path).removeFragment();
    if (!_sameOrigin(uri)) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '不能向其他站点提交表单');
    }
    if (!multipart && files.isNotEmpty) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '文件需要使用 multipart 表单');
    }
    String normalize(String value) =>
        value.replaceAll(RegExp(r'\r\n|\r|\n'), '\r\n');
    final random = Random.secure();
    final boundary =
        'forum-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final body = BytesBuilder(copy: false);
    if (multipart) {
      String quoted(String value) => value
          .replaceAll('\r', '%0D')
          .replaceAll('\n', '%0A')
          .replaceAll('"', '%22');
      void text(String value) => body.add(utf8.encode(value));
      for (final field in fields) {
        text('--$boundary\r\nContent-Disposition: form-data; '
            'name="${quoted(field.key)}"\r\n\r\n${normalize(field.value)}\r\n');
      }
      for (final file in files) {
        if (!RegExp(r'^[a-zA-Z0-9!#$&^_.+-]+/[a-zA-Z0-9!#$&^_.+-]+$')
            .hasMatch(file.mimeType)) {
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '文件类型无效');
        }
        text('--$boundary\r\nContent-Disposition: form-data; '
            'name="${quoted(file.name)}"; filename="${quoted(file.fileName)}"\r\n'
            'Content-Type: ${file.mimeType}\r\n\r\n');
        body.add(file.bytes);
        text('\r\n');
      }
      text('--$boundary--\r\n');
    } else {
      body.add(utf8.encode(fields
          .map((field) => '${Uri.encodeQueryComponent(normalize(field.key))}='
              '${Uri.encodeQueryComponent(normalize(field.value))}')
          .join('&')));
    }
    try {
      final result = await _exchange('POST', uri,
          body: body.takeBytes(),
          contentType: multipart
              ? ContentType('multipart', 'form-data',
                  parameters: {'boundary': boundary})
              : ContentType('application', 'x-www-form-urlencoded',
                  charset: 'utf-8'),
          requireCurrentSession: requireCurrentSession);
      _throwForHttpStatus(result.status);
      if (result.status != HttpStatus.ok) {
        throw const ForumRequestException(
            ForumRequestKind.server, '表单请求返回了非预期状态，请刷新确认结果');
      }
      final response = utf8.decode(result.bytes);
      if (forumTextIsRateLimited(response)) {
        throw const ForumRequestException(
            ForumRequestKind.rateLimited, '请求过于频繁');
      }
      return response;
    } on ForumRequestException {
      rethrow;
    } on IOException {
      throw const ForumRequestException(
          ForumRequestKind.network, '表单提交失败，请检查网络后刷新确认');
    } on TimeoutException {
      throw const ForumRequestException(
          ForumRequestKind.network, '表单提交超时，请刷新确认结果');
    }
  }

  Future<String> _readText(
    String method,
    String path, {
    Map<String, String>? form,
    bool retryCooldown = false,
    void Function()? requireCurrentSession,
    bool requireOk = false,
    bool invalidPageStatus = false,
    ForumReadRedirectPolicy redirectPolicy = ForumReadRedirectPolicy.none,
    bool sensitiveAccount = false,
    bool followRedirects = true,
  }) async {
    final uri = baseUri.resolve(path).removeFragment();
    try {
      final result = await _exchange(method, uri,
          form: form,
          requireCurrentSession: requireCurrentSession,
          sensitiveAccount: sensitiveAccount,
          guardedRead: invalidPageStatus,
          redirectPolicy: redirectPolicy,
          followRedirects: followRedirects);
      if (result.status >= 500) {
        throw const ForumRequestException(
          ForumRequestKind.server,
          '论坛服务器错误',
        );
      }
      final body = utf8.decode(result.bytes);
      final cooled = result.status == HttpStatus.tooManyRequests ||
          forumTextIsRateLimited(body);
      if (_isForumSearch(uri) && cooled) {
        _pacer.escalateSearch();
        if (retryCooldown && method == 'GET') {
          return _readText(method, path, form: form);
        }
        throw const ForumRequestException(
          ForumRequestKind.rateLimited,
          '请求过于频繁',
        );
      }
      if (retryCooldown && cooled) {
        return _readText(method, path, form: form);
      }
      _throwForHttpStatus(result.status);
      if (requireOk && result.status != HttpStatus.ok) {
        throw ForumRequestException(
            invalidPageStatus
                ? ForumRequestKind.invalidInput
                : ForumRequestKind.server,
            invalidPageStatus ? '页面请求返回了非预期状态' : '表单请求返回了非预期状态');
      }
      if ((uri.path == '/message.php' || uri.path == '/sendemail.php') &&
          result.status != HttpStatus.ok) {
        throw ForumRequestException(
          ForumRequestKind.server,
          uri.path == '/sendemail.php' ? '登录名称查询请求返回了非预期状态' : '私讯请求返回了非预期状态',
        );
      }
      return body;
    } on ForumRequestException {
      rethrow;
    } on SocketException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message),
      );
    } on HttpException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message),
      );
    } on TlsException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message),
      );
    } on TimeoutException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message ?? ''),
      );
    }
  }

  Future<Uint8List> _readBytes(String path) async {
    try {
      final result =
          await _exchange('GET', baseUri.resolve(path).removeFragment());
      _throwForHttpStatus(result.status);
      return result.bytes;
    } on ForumRequestException {
      rethrow;
    } on SocketException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message),
      );
    } on HttpException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message),
      );
    } on TlsException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message),
      );
    } on TimeoutException catch (error) {
      throw ForumRequestException(
        ForumRequestKind.network,
        _networkMessage(error.message ?? ''),
      );
    }
  }

  Future<({int status, Uint8List bytes})> _exchange(
    String method,
    Uri uri, {
    Map<String, String>? form,
    int redirectsLeft = 5,
    bool sensitiveSearch = false,
    bool identityLookup = false,
    bool sensitiveBlocking = false,
    bool sensitiveAccount = false,
    bool guardedRead = false,
    ForumReadRedirectPolicy redirectPolicy = ForumReadRedirectPolicy.none,
    bool followRedirects = true,
    Uint8List? body,
    ContentType? contentType,
    void Function()? requireCurrentSession,
  }) async {
    final storeGeneration = _cookieStoreGeneration;
    await restoreCookies();
    requireCurrentSession?.call();
    final isFavorites = uri.path == '/u.php' &&
        (uri.queryParameters['action'] == 'favor' ||
            RegExp(r'^action(?:=|-)favor(?:-|\.html$)').hasMatch(uri.query));
    sensitiveAccount =
        sensitiveAccount || uri.path == '/profile.php' || isFavorites;
    final isAccount = sensitiveAccount;
    final startedAt = DateTime.now();
    final isPm = uri.path == '/message.php';
    identityLookup = identityLookup || uri.path == '/sendemail.php';
    sensitiveSearch = sensitiveSearch || _isForumSearch(uri);
    sensitiveBlocking = sensitiveBlocking ||
        (uri.path == '/pw_ajax.php' &&
            {'getblocklist', 'updateblocklist'}
                .contains(uri.queryParameters['action']));
    final tracePath = isFavorites
        ? 'u.php (favorites)'
        : isAccount
            ? 'profile.php (account)'
            : sensitiveBlocking
                ? 'pw_ajax.php (blocking)'
                : identityLookup
                    ? 'sendemail.php'
                    : isPm
                        ? 'message.php'
                        : sensitiveSearch
                            ? 'search.php'
                            : uri.toString();
    ForumTraceLogger.log(
      'HTTP',
      isAccount ||
              isPm ||
              sensitiveSearch ||
              identityLookup ||
              sensitiveBlocking
          ? '$method $tracePath'
          : method == 'POST'
              ? 'POST $uri form=${ForumTraceLogger.sanitizeForm(form ?? const {})}'
              : 'GET $uri',
    );
    final request = method == 'POST'
        ? await _httpClient.postUrl(uri)
        : await _httpClient.getUrl(uri);
    request.followRedirects = false;
    if (method == 'POST') {
      if (body != null) request.contentLength = body.length;
      request.headers.contentType = contentType ??
          ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'utf-8',
          );
    }
    _applyCookies(request);
    final response = await _pacer.send(uri, () {
      try {
        requireCurrentSession?.call();
      } catch (error) {
        request.abort();
        rethrow;
      }
      if (method == 'POST') {
        if (body != null) {
          request.add(body);
        } else {
          request.write(Uri(queryParameters: form ?? const {}).query);
        }
      }
      return request.close();
    });
    try {
      requireCurrentSession?.call();
      await _storeCookies(response, uri,
          requireCurrentSession: requireCurrentSession,
          storeGeneration: storeGeneration);
      requireCurrentSession?.call();
    } catch (_) {
      await response.listen(null).cancel();
      rethrow;
    }
    if (_redirectStatuses.contains(response.statusCode)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (guardedRead) {
        final parsed = location == null ? null : Uri.tryParse(location);
        final target = parsed == null ? null : uri.resolveUri(parsed);
        final sameOrigin = target != null && _sameOrigin(target);
        if (sameOrigin && target.path == '/login.php') {
          throw const ForumRequestException(
              ForumRequestKind.loginRequired, '请重新登录后再搜索');
        }
        if (redirectPolicy != ForumReadRedirectPolicy.board ||
            !sameOrigin ||
            !_isReadOnlyBoardRedirect(target)) {
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '页面跳转不在允许的只读范围内');
        }
      }
      if (!followRedirects || isPm || (isAccount && method == 'POST')) {
        throw const ForumRequestException(
          ForumRequestKind.server,
          '此提交不能自动跟随跳转，请刷新确认结果',
        );
      }
      final next =
          location == null ? null : uri.resolve(location).removeFragment();
      if (redirectsLeft <= 0 || next == null) {
        throw ForumRequestException(
          guardedRead
              ? ForumRequestKind.invalidInput
              : ForumRequestKind.network,
          '重定向次数过多',
        );
      }
      if ((isAccount || identityLookup || sensitiveBlocking || guardedRead) &&
          !_sameOrigin(next)) {
        throw ForumRequestException(
          guardedRead ? ForumRequestKind.invalidInput : ForumRequestKind.server,
          guardedRead
              ? '扫描页面跳转到不安全的地址'
              : sensitiveBlocking
                  ? '屏蔽配置不能跳转到其他站点'
                  : '登录名称查询跳转到不安全的地址',
        );
      }
      if (method == 'POST' &&
          (response.statusCode == HttpStatus.temporaryRedirect ||
              response.statusCode == HttpStatus.permanentRedirect)) {
        throw const ForumRequestException(
          ForumRequestKind.server,
          '不能自动重送提交',
        );
      }
      final keepMethod = response.statusCode == HttpStatus.temporaryRedirect ||
          response.statusCode == HttpStatus.permanentRedirect;
      return _exchange(
        keepMethod ? method : 'GET',
        next,
        form: keepMethod ? form : null,
        redirectsLeft: redirectsLeft - 1,
        sensitiveSearch: sensitiveSearch,
        identityLookup: identityLookup,
        sensitiveBlocking: sensitiveBlocking,
        sensitiveAccount: sensitiveAccount,
        guardedRead: guardedRead,
        redirectPolicy: redirectPolicy,
        followRedirects: followRedirects,
        requireCurrentSession: requireCurrentSession,
      );
    }
    final bytes = Uint8List.fromList(
      await response
          .fold<List<int>>(<int>[], (body, data) => body..addAll(data)),
    );
    requireCurrentSession?.call();
    final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
    ForumTraceLogger.log(
      'HTTP',
      '$method $tracePath -> status=${response.statusCode} bytes=${bytes.length} elapsedMs=$elapsed',
    );
    if (!isAccount &&
        !isPm &&
        !sensitiveSearch &&
        !identityLookup &&
        !sensitiveBlocking &&
        ForumTraceLogger.shouldLogFullBody(uri)) {
      ForumTraceLogger.logBlock(
        'HTTP',
        '$method $uri response',
        utf8.decode(bytes, allowMalformed: true),
      );
    }
    return (status: response.statusCode, bytes: bytes);
  }

  bool _isReadOnlyBoardRedirect(Uri uri) {
    final fields = uri.queryParametersAll;
    return {'/thread.php', '/thread_new.php'}.contains(uri.path) &&
        !uri.hasFragment &&
        fields.length == 1 &&
        fields['fid']?.length == 1 &&
        RegExp(r'^[1-9]\d*$').hasMatch(fields['fid']!.single);
  }

  void _throwForHttpStatus(int status) {
    if (status >= 500) {
      throw const ForumRequestException(
        ForumRequestKind.server,
        '论坛服务器错误',
      );
    }
    if (status == HttpStatus.unauthorized) {
      throw const ForumRequestException(
        ForumRequestKind.loginRequired,
        '需要登录',
      );
    }
    if (status == HttpStatus.forbidden) {
      throw const ForumRequestException(
        ForumRequestKind.forbidden,
        '没有权限',
      );
    }
    if (status == HttpStatus.tooManyRequests) {
      throw const ForumRequestException(
        ForumRequestKind.rateLimited,
        '请求过于频繁',
      );
    }
  }

  Future<void> clearSession() async {
    _cookieGeneration++;
    _cookieStoreGeneration++;
    _cookies.clear();
    await _writeCookies(() async {
      await _sessionStore?.clear();
    });
  }

  Future<void> _restoreCookies() async {
    final generation = _cookieGeneration;
    final storeGeneration = _cookieStoreGeneration;
    Map<String, ForumStoredCookie>? restored;
    await _writeCookies(() async {
      restored = await _sessionStore?.loadCookies();
    });
    if (generation != _cookieGeneration ||
        storeGeneration != _cookieStoreGeneration ||
        restored == null ||
        restored!.isEmpty) return;
    _cookies
      ..clear()
      ..addAll(restored!);
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

  Future<void> _storeCookies(HttpClientResponse response, Uri origin,
      {void Function()? requireCurrentSession, int? storeGeneration}) async {
    requireCurrentSession?.call();
    if (storeGeneration != null && storeGeneration != _cookieStoreGeneration)
      return;
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
    if (changed)
      await _persistCookies(
          requireCurrentSession: requireCurrentSession,
          storeGeneration: storeGeneration);
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

  Future<void> _persistCookies(
      {void Function()? requireCurrentSession, int? storeGeneration}) {
    final generation = storeGeneration ?? _cookieStoreGeneration;
    _cookies.removeWhere((_, cookie) => cookie.isExpired);
    final snapshot = Map<String, ForumStoredCookie>.of(_cookies);
    return _writeCookies(() async {
      requireCurrentSession?.call();
      if (generation != _cookieStoreGeneration) return;
      await _sessionStore?.saveCookies(snapshot);
      requireCurrentSession?.call();
    });
  }

  Future<void> _writeCookies(Future<void> Function() write) {
    final previous = _cookieWrites;
    final tail = Completer<void>();
    _cookieWrites = tail.future;
    Future<void> run() async {
      try {
        if (previous != null) await previous;
        await write();
      } finally {
        // An idle queue must not retain a completed Future's scheduling zone.
        if (identical(_cookieWrites, tail.future)) _cookieWrites = null;
        tail.complete();
      }
    }

    return run();
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

const _redirectStatuses = <int>{
  HttpStatus.movedPermanently,
  HttpStatus.found,
  HttpStatus.seeOther,
  HttpStatus.temporaryRedirect,
  HttpStatus.permanentRedirect,
};

Future<void> _waitForForumGap(Duration duration) {
  return Future<void>.delayed(duration);
}

String _networkMessage(String message) {
  return message.isEmpty ? '网络连接失败' : message;
}

bool _isForumSearch(Uri uri) {
  final segments = uri.pathSegments;
  return segments.isNotEmpty && segments.last.toLowerCase() == 'search.php';
}

class _ForumRequestPacer {
  _ForumRequestPacer(this._clock, this._delay);

  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;
  Future<void> _tail = Future<void>.value();
  DateTime _nextAny = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _nextSearch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSearchStart;
  Duration _searchGap = const Duration(milliseconds: 3334);

  Completer<void>? _wake;
  Timer? _timer;

  Future<T> send<T>(Uri uri, Future<T> Function() writeAndClose) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    return previous.then((_) async {
      final Future<T> pending;
      try {
        await _wait(uri);
        _stamp(uri);
        pending = writeAndClose();
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
      return pending;
    });
  }

  Future<void> _wait(Uri uri) async {
    final search = _isForumSearch(uri);
    while (true) {
      final now = _clock();
      var ready = _nextAny;
      if (search && _nextSearch.isAfter(ready)) ready = _nextSearch;
      final wait = ready.difference(now);
      if (wait <= Duration.zero) return;
      final wake = Completer<void>();
      _wake = wake;
      var woken = false;
      try {
        woken = await Future.any<bool>([
          _sleep(wait).then((_) => false),
          wake.future.then((_) => true),
        ]);
      } finally {
        if (identical(_wake, wake)) _wake = null;
      }
      if (!woken) return;
    }
  }

  Future<void> _sleep(Duration duration) {
    if (!identical(_delay, _waitForForumGap)) return _delay(duration);
    final done = Completer<void>();
    final timer = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    _timer = timer;
    return done.future;
  }

  void _stamp(Uri uri) {
    final started = _clock();
    _nextAny = started.add(const Duration(seconds: 1));
    if (!_isForumSearch(uri)) return;
    _lastSearchStart = started;
    final next = started.add(_searchGap);
    if (next.isAfter(_nextSearch)) _nextSearch = next;
  }

  void escalateSearch() {
    _searchGap = const Duration(seconds: 10);
    final last = _lastSearchStart;
    if (last != null) {
      final raised = last.add(_searchGap);
      if (raised.isAfter(_nextSearch)) _nextSearch = raised;
    }
    _timer?.cancel();
    _timer = null;
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }
}
