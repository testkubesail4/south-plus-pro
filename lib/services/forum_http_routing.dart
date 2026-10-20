import 'dart:io';

import 'forum_network_config.dart';
import 'forum_optimized_transport.dart';
import 'forum_proxy_connection.dart';

/// Also covers HttpClients retained by Flutter images, the cache and updates.
class ForumHttpRouting {
  ForumHttpRouting._();
  static ForumNetworkConfig _config = const ForumNetworkConfig(
    site: ForumNetworkConfig.defaultSite,
    mode: ForumNetworkMode.native,
  );
  static final _clients = <_RoutedClient>{};
  static final _transports = <SecurityContext?, ForumOptimizedTransport>{};

  static void install() => HttpOverrides.global = ForumHttpOverrides();

  static void updateConfig(ForumNetworkConfig config) {
    config.validate();
    if (config == _config) return;
    // Detach caller-owned mutable collections before publishing the route.
    _config = ForumNetworkConfig.fromJson(config.toJson());
    for (final transport in _transports.values) {
      transport.close();
    }
    _transports.clear();
    for (final client in _clients.toList()) {
      client.invalidate();
    }
  }
}

class ForumHttpOverrides extends HttpOverrides {
  HttpClient createUnroutedClient(SecurityContext? context) =>
      super.createHttpClient(context);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RoutedClient(() => createUnroutedClient(context), context);
}

HttpClient createUnroutedHttpClient({SecurityContext? context}) {
  final overrides = HttpOverrides.current;
  return overrides is ForumHttpOverrides
      ? overrides.createUnroutedClient(context)
      : HttpClient(context: context);
}

HttpClient createConfiguredForumHttpClient(
  ForumNetworkConfig config, {
  SecurityContext? context,
}) {
  final overrides = HttpOverrides.current;
  HttpClient create() => overrides is ForumHttpOverrides
      ? overrides.createUnroutedClient(context)
      : overrides?.createHttpClient(context) ??
          ForumHttpOverrides().createUnroutedClient(context);
  return _RoutedClient(create, context, config: config);
}

void configureForumProxy(
  HttpClient client,
  ForumProxy proxy, {
  SecurityContext? context,
}) {
  // Keep proxy credentials out of HttpClient, including automatic redirects.
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, _, __) => connectForumProxy(
        proxy,
        uri,
        context: context,
        timeout: client.connectionTimeout ?? const Duration(seconds: 8),
      );
}

class _RoutedClient implements HttpClient {
  _RoutedClient(this._create, this._context, {ForumNetworkConfig? config})
      : _fixedConfig = config {
    if (config == null) ForumHttpRouting._clients.add(this);
  }
  final HttpClient Function() _create;
  final SecurityContext? _context;
  final ForumNetworkConfig? _fixedConfig;
  final _settings = <String, void Function(HttpClient)>{};
  final _credentials = <void Function(HttpClient)>[];
  HttpClient? _delegate;
  ForumOptimizedTransport? _ownedTransport;
  bool _closed = false;
  ForumNetworkConfig get _config => _fixedConfig ?? ForumHttpRouting._config;

  HttpClient get _client {
    if (_closed) throw StateError('HttpClient is closed');
    return _delegate ??= _newClient();
  }

  HttpClient _newClient() {
    final client = _create();
    for (final setting in _settings.values) {
      setting(client);
    }
    for (final credential in _credentials) {
      credential(client);
    }
    // Native deliberately has no connectionFactory or IP fallback.
    if (_config.mode == ForumNetworkMode.proxy) {
      final proxy = _config.proxy;
      if (proxy == null) {
        client.close(force: true);
        throw const FormatException('请先配置代理');
      }
      configureForumProxy(client, proxy, context: _context);
    } else if (_config.mode == ForumNetworkMode.optimized) {
      final transport = _fixedConfig != null
          ? (_ownedTransport ??= ForumOptimizedTransport(
              _config,
              context: _context,
            ))
          : ForumHttpRouting._transports.putIfAbsent(
              _context,
              () => ForumOptimizedTransport(_config, context: _context),
            );
      client.findProxy = (_) => 'DIRECT';
      client.connectionFactory = (uri, _, __) => transport.connect(
            uri,
            timeout: client.connectionTimeout ?? const Duration(seconds: 8),
          );
    } else {
      client.findProxy = (_) => 'DIRECT';
    }
    return client;
  }

  void invalidate() {
    _delegate?.close(force: true);
    _delegate = null;
    _ownedTransport?.close();
    _ownedTransport = null;
  }

  void _set(String key, void Function(HttpClient) setting) {
    _settings[key] = setting;
    setting(_client);
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    ForumHttpRouting._clients.remove(this);
    _ownedTransport?.close(force: force);
    _delegate?.close(force: force);
    _delegate = null;
  }

  @override
  Duration get idleTimeout => _client.idleTimeout;
  @override
  set idleTimeout(Duration value) =>
      _set('idleTimeout', (c) => c.idleTimeout = value);
  @override
  Duration? get connectionTimeout => _client.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) =>
      _set('connectionTimeout', (c) => c.connectionTimeout = value);
  @override
  int? get maxConnectionsPerHost => _client.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) =>
      _set('maxConnectionsPerHost', (c) => c.maxConnectionsPerHost = value);
  @override
  bool get autoUncompress => _client.autoUncompress;
  @override
  set autoUncompress(bool value) =>
      _set('autoUncompress', (c) => c.autoUncompress = value);
  @override
  String? get userAgent => _client.userAgent;
  @override
  set userAgent(String? value) => _set('userAgent', (c) => c.userAgent = value);
  @override
  set authenticate(Future<bool> Function(Uri, String, String?)? f) =>
      _set('authenticate', (c) => c.authenticate = f);
  @override
  set authenticateProxy(
    Future<bool> Function(String, int, String, String?)? f,
  ) =>
      _set('authenticateProxy', (c) => c.authenticateProxy = f);
  @override
  set badCertificateCallback(bool Function(X509Certificate, String, int)? f) =>
      _set('badCertificateCallback', (c) => c.badCertificateCallback = f);
  @override
  set keyLog(Function(String)? f) => _set('keyLog', (c) => c.keyLog = f);
  @override
  set findProxy(String Function(Uri)? f) {
    _settings['findProxy'] = (c) => c.findProxy = f;
    if (_config.mode == ForumNetworkMode.native) _client.findProxy = f;
  }

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f,
  ) {
    _settings['connectionFactory'] = (c) => c.connectionFactory = f;
    if (_config.mode == ForumNetworkMode.native) _client.connectionFactory = f;
  }

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {
    void add(HttpClient c) => c.addCredentials(url, realm, credentials);
    final client = _client;
    _credentials.add(add);
    add(client);
  }

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {
    void add(HttpClient c) =>
        c.addProxyCredentials(host, port, realm, credentials);
    final client = _client;
    _credentials.add(add);
    add(client);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _client.open(method, host, port, path);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _client.openUrl(method, url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
}
