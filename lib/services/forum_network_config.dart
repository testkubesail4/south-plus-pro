import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'forum_http_routing.dart';
import 'forum_network_defaults.dart';
export 'forum_doh_resolver.dart';

class ForumSite {
  const ForumSite(this.host);
  final String host;
  Uri get baseUri => Uri.https(host, '/');
  @override
  bool operator ==(Object other) => other is ForumSite && host == other.host;
  @override
  int get hashCode => host.hashCode;
}

enum ForumProxyType { http, https, socks5 }

class ForumProxy {
  factory ForumProxy({
    required ForumProxyType type,
    required String host,
    required int port,
    String? username,
    String? password,
  }) {
    final error = validationError(
      type: type,
      host: host,
      port: port,
      username: username,
      password: password,
    );
    if (error != null) throw FormatException(error);
    username = username?.isEmpty == true ? null : username;
    return ForumProxy._(
      type,
      host.trim(),
      port,
      username,
      username == null ? null : password ?? '',
    );
  }
  static String? validationError({
    required ForumProxyType type,
    required String host,
    required int port,
    String? username,
    String? password,
  }) {
    host = host.trim();
    final validHost = InternetAddress.tryParse(host) != null ||
        (host.isNotEmpty &&
            host.length <= 253 &&
            host.split('.').every(
                  (label) => RegExp(
                    r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
                  ).hasMatch(label),
                ));
    if (!validHost || port < 1 || port > 65535) return '请输入有效的代理主机和端口';
    username = username?.isEmpty == true ? null : username;
    if (username == null && password != null && password.isNotEmpty)
      return '代理密码需要用户名';
    if (username != null) {
      password ??= '';
      if (type == ForumProxyType.socks5 &&
          (utf8.encode(username).length > 255 ||
              utf8.encode(password).isEmpty ||
              utf8.encode(password).length > 255))
        return 'SOCKS5 用户名和密码必须为 1–255 字节';
      if (type != ForumProxyType.socks5 && username.contains(':'))
        return 'HTTP 代理用户名不能包含冒号';
    }
    return null;
  }

  const ForumProxy._(
    this.type,
    this.host,
    this.port,
    this.username,
    this.password,
  );
  final ForumProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;
  Map<String, Object?> toJson() => {
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };
  factory ForumProxy.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['host'] is! String ||
        value['port'] is! int ||
        (value['username'] != null && value['username'] is! String) ||
        (value['password'] != null && value['password'] is! String)) {
      throw const FormatException('代理设置无效，请重新配置代理');
    }
    final type = ForumProxyType.values
        .where((type) => type.name == value['type'])
        .firstOrNull;
    if (type == null) throw const FormatException('代理类型无效');
    return ForumProxy(
      type: type,
      host: value['host'] as String,
      port: value['port'] as int,
      username: value['username'] as String?,
      password: value['password'] as String?,
    );
  }
  @override
  bool operator ==(Object other) =>
      other is ForumProxy &&
      type == other.type &&
      host == other.host &&
      port == other.port &&
      username == other.username &&
      password == other.password;
  @override
  int get hashCode => Object.hash(type, host, port, username, password);
  @override
  String toString() => 'ForumProxy(${type.name}, $host:$port)';
}

enum ForumNetworkMode { native, optimized, proxy }

class ForumNetworkConfig {
  const ForumNetworkConfig({
    required this.site,
    this.mode = ForumNetworkMode.optimized,
    this.dohProvider = defaultProvider,
    this.ipv6Enabled = false,
    this.dohBootstrapAddresses = const [],
    this.hostAddresses = const {},
    this.customDohUri,
    this.proxy,
  });

  static const defaultSite = ForumSite('south-plus.net');
  static const defaultProvider = DohProvider.cmliuCloudflare;
  static const sites = [
    ForumSite('east-plus.net'),
    ForumSite('south-plus.net'),
    ForumSite('south-plus.org'),
    ForumSite('white-plus.net'),
    ForumSite('north-plus.net'),
    ForumSite('level-plus.net'),
    ForumSite('soul-plus.net'),
    ForumSite('snow-plus.net'),
    ForumSite('spring-plus.net'),
    ForumSite('summer-plus.net'),
    ForumSite('blue-plus.net'),
    ForumSite('imoutolove.me'),
  ];
  final ForumSite site;
  final ForumNetworkMode mode;
  final DohProvider dohProvider;
  final bool ipv6Enabled;
  final String? customDohUri;
  final List<String> dohBootstrapAddresses;
  final Map<String, List<String>> hostAddresses;
  final ForumProxy? proxy;
  Uri get baseUri => site.baseUri;

  static List<String> builtInHostAddresses(String host) =>
      forumHostFallback[host.toLowerCase()] ?? const [];

  static String? normalizeHost(String value) {
    value = value.trim().toLowerCase();
    if (value.startsWith('https://') || value.startsWith('http://')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.userInfo.isNotEmpty || uri.hasPort) return null;
      value = uri.host;
    }
    if (value.isEmpty ||
        value.length > 253 ||
        !value.split('.').every(
              (label) => RegExp(
                r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
              ).hasMatch(label),
            )) return null;
    return value;
  }

  static String? normalizeDohUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) return null;
    return uri.toString();
  }

  static String? validateAddressLiteral(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null) return '请输入有效的 IPv4 或 IPv6 地址';
    final b = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      if (b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
          (b[0] == 169 && b[1] == 254) ||
          (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
          (b[0] == 192 && (b[1] == 0 || b[1] == 168)) ||
          (b[0] == 198 &&
              (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
          (b[0] == 203 && b[1] == 0 && b[2] == 113)) return '请输入公网 IP 地址';
    } else if ((b[0] & 0xe0) != 0x20 ||
        (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8)) {
      return '请输入公网 IP 地址';
    }
    return null;
  }

  void validate() {
    if (normalizeHost(site.host) != site.host)
      throw const FormatException('请输入有效的论坛域名');
    if (mode == ForumNetworkMode.proxy && proxy == null)
      throw const FormatException('请先配置代理');
    if (customDohUri != null && normalizeDohUri(customDohUri!) == null)
      throw const FormatException('请输入有效的 HTTPS DoH 地址');
    for (final host in hostAddresses.keys) {
      if (normalizeHost(host) != host)
        throw const FormatException('请输入有效的候选地址域名');
    }
    for (final ip in [
      ...dohBootstrapAddresses,
      ...hostAddresses.values.expand((v) => v),
    ]) {
      final error = validateAddressLiteral(ip);
      if (error != null) throw FormatException(error);
    }
    if (dohBootstrapAddresses.length > 8 ||
        hostAddresses.length > 64 ||
        hostAddresses.values.any((v) => v.length > 8))
      throw const FormatException('每个域名最多配置 8 个地址，最多配置 64 个域名');
  }

  Map<String, Object?> toJson() => {
        'version': 2,
        'site': site.host,
        'mode': mode.name,
        'ipv6Enabled': ipv6Enabled,
        'dohProvider': dohProvider.name,
        'customDohUri': customDohUri,
        'dohBootstrapAddresses': dohBootstrapAddresses,
        'hostAddresses': hostAddresses,
        'proxy': proxy?.toJson(),
      };
  factory ForumNetworkConfig.fromJson(Map<String, dynamic> json) {
    try {
      if (json['version'] != 2) throw const FormatException();
      final mode = ForumNetworkMode.values
          .where((m) => m.name == json['mode'])
          .firstOrNull;
      if (mode == null ||
          json['site'] is! String ||
          json['ipv6Enabled'] is! bool) throw const FormatException();
      final config = ForumNetworkConfig(
        site: ForumSite(json['site'] as String),
        mode: mode,
        ipv6Enabled: json['ipv6Enabled'] as bool,
        dohProvider: DohProvider.fromName(json['dohProvider'] as String?),
        customDohUri: json['customDohUri'] as String?,
        dohBootstrapAddresses: List<String>.unmodifiable(
          json['dohBootstrapAddresses'] as List,
        ),
        hostAddresses: Map<String, List<String>>.unmodifiable(
          (json['hostAddresses'] as Map).map(
            (key, value) => MapEntry(
              key as String,
              List<String>.unmodifiable(value as List),
            ),
          ),
        ),
        proxy:
            json['proxy'] == null ? null : ForumProxy.fromJson(json['proxy']),
      );
      config.validate();
      return config;
    } on Object {
      throw const FormatException('网络设置无法读取，请重新设置');
    }
  }
  ForumNetworkConfig copyWith({
    ForumSite? site,
    ForumNetworkMode? mode,
    DohProvider? dohProvider,
    bool? ipv6Enabled,
    String? customDohUri,
    List<String>? dohBootstrapAddresses,
    Map<String, List<String>>? hostAddresses,
    ForumProxy? proxy,
    bool clearProxy = false,
    bool clearCustomDohUri = false,
  }) =>
      ForumNetworkConfig(
        site: site ?? this.site,
        mode: mode ??
            (proxy != null
                ? ForumNetworkMode.proxy
                : clearProxy && this.mode == ForumNetworkMode.proxy
                    ? ForumNetworkMode.native
                    : this.mode),
        dohProvider: dohProvider ?? this.dohProvider,
        ipv6Enabled: ipv6Enabled ?? this.ipv6Enabled,
        customDohUri:
            clearCustomDohUri ? null : customDohUri ?? this.customDohUri,
        dohBootstrapAddresses:
            dohBootstrapAddresses ?? this.dohBootstrapAddresses,
        hostAddresses: hostAddresses ?? this.hostAddresses,
        proxy: clearProxy ? null : proxy ?? this.proxy,
      );
  static ForumSite siteForHost(String? host) =>
      ForumSite(normalizeHost(host ?? '') ?? defaultSite.host);
  String get _identity => jsonEncode(toJson());
  @override
  bool operator ==(Object other) =>
      other is ForumNetworkConfig && _identity == other._identity;
  @override
  int get hashCode => _identity.hashCode;
}

enum DohProvider {
  cmliuCloudflare(label: 'cmliu', uri: 'https://doh.cm.edu.kg/CMLiussss'),
  cloudflareGateway(
    label: 'Cloudflare Gateway',
    uri: 'https://frd4wvnobp.cloudflare-gateway.com/dns-query',
  ),
  tiarap(label: 'Tiarap', uri: 'https://doh.tiarap.org/dns-query');

  const DohProvider({required this.label, required this.uri});
  final String label;
  final String uri;
  Uri get endpoint => Uri.parse(uri);
  static DohProvider fromName(String? name) =>
      values.where((p) => p.name == name).firstOrNull ??
      ForumNetworkConfig.defaultProvider;
}

class ForumNetworkSettings {
  ForumNetworkSettings._();
  static const _configKey = 'forum_network_config_v2';
  static const _customSitesKey = 'forum_network_custom_site_hosts_v1';
  static const _customDohKey = 'forum_network_custom_doh_uris_v1';
  static Future<ForumNetworkConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_configKey);
    if (saved != null) {
      try {
        return ForumNetworkConfig.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      } on Object {
        throw const FormatException('网络设置无法读取，请重新设置');
      }
    }
    final rawProxy = prefs.getString('forum_network_proxy_v1');
    ForumProxy? proxy;
    if (rawProxy != null) {
      try {
        proxy = ForumProxy.fromJson(jsonDecode(rawProxy));
      } on Object {
        throw const FormatException('代理设置无效，请重新配置代理');
      }
    }
    return ForumNetworkConfig(
      site: ForumNetworkConfig.siteForHost(
        prefs.getString('forum_network_site_host_v1'),
      ),
      mode: proxy != null
          ? ForumNetworkMode.proxy
          : prefs.getBool('forum_network_doh_enabled_v1') == false
              ? ForumNetworkMode.native
              : ForumNetworkMode.optimized,
      proxy: proxy,
      dohProvider: DohProvider.fromName(
        prefs.getString('forum_network_doh_provider_v1'),
      ),
      customDohUri: ForumNetworkConfig.normalizeDohUri(
        prefs.getString('forum_network_custom_doh_uri_v1') ?? '',
      ),
    );
  }

  static Future<void> save(ForumNetworkConfig config) async {
    config.validate();
    final prefs = await SharedPreferences.getInstance();
    await _checkedWrite(
      prefs,
      prefs.setString(_configKey, jsonEncode(config.toJson())),
    );
  }

  static Future<void> _checkedWrite(
    SharedPreferences prefs,
    Future<bool> write,
  ) async {
    try {
      if (!await write) throw Exception('网络设置保存失败，请重试');
    } catch (_) {
      try {
        await prefs.reload();
      } catch (_) {
        /* Preserve the write failure. */
      }
      rethrow;
    }
  }

  static Future<List<ForumSite>> loadCustomSites() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final value in prefs.getStringList(_customSitesKey) ?? <String>[])
        ForumNetworkConfig.normalizeHost(value),
    }
        .nonNulls
        .where((host) => !ForumNetworkConfig.sites.any((s) => s.host == host))
        .map(ForumSite.new)
        .toList();
  }

  static Future<List<ForumSite>> addCustomSite(ForumSite site) async {
    final host = ForumNetworkConfig.normalizeHost(site.host);
    if (host == null) throw const FormatException('请输入有效的论坛域名');
    final values = {
      host,
      ...((await loadCustomSites()).map((s) => s.host)),
    }.toList();
    final prefs = await SharedPreferences.getInstance();
    await _checkedWrite(prefs, prefs.setStringList(_customSitesKey, values));
    return loadCustomSites();
  }

  static Future<List<String>> loadCustomDohUris() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final value in prefs.getStringList(_customDohKey) ?? <String>[])
        ForumNetworkConfig.normalizeDohUri(value),
    }.nonNulls.toList();
  }

  static Future<List<String>> addCustomDohUri(String uri) async {
    final normalized = ForumNetworkConfig.normalizeDohUri(uri);
    if (normalized == null) throw const FormatException('请输入有效的 HTTPS DoH 地址');
    final values = {normalized, ...await loadCustomDohUris()}.toList();
    final prefs = await SharedPreferences.getInstance();
    await _checkedWrite(prefs, prefs.setStringList(_customDohKey, values));
    return values;
  }
}

HttpClient createForumHttpClient(ForumNetworkConfig config) =>
    createConfiguredForumHttpClient(config);
