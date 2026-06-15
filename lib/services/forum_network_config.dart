import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class ForumSite {
  const ForumSite(this.host);

  final String host;

  Uri get baseUri => Uri.https(host, '/');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumSite &&
          runtimeType == other.runtimeType &&
          host == other.host;

  @override
  int get hashCode => host.hashCode;
}

class ForumNetworkConfig {
  const ForumNetworkConfig({
    required this.site,
    required this.dohEnabled,
    required this.dohProvider,
    this.fixedAddress,
    this.customDohUri,
  });

  static const defaultSite = ForumSite('south-plus.net');
  static const defaultProvider = DohProvider.doh090227Sb;

  static const List<ForumSite> sites = [
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

  static const Map<String, String> routeLabels = {
    '104.18.26.110': '低丢包通道',
    '172.67.74.152': 'Anycast 通道',
    '141.101.115.10': '稳定性通道 1',
    '104.17.147.40': '稳定性通道 2',
    '198.41.219.125': '稳定性通道 3',
  };

  static List<InternetAddress> defaultRouteAddresses() {
    return routeLabels.keys.map(InternetAddress.new).toList(growable: false);
  }

  static String routeLabelForAddress(String address, int fallbackIndex) {
    return routeLabels[address] ?? '专属线路 $fallbackIndex';
  }

  final ForumSite site;
  final bool dohEnabled;
  final DohProvider dohProvider;
  final String? fixedAddress;
  final String? customDohUri;

  Uri get baseUri => site.baseUri;

  Uri get dohEndpoint {
    final custom = customDohUri?.trim();
    if (custom != null && custom.isNotEmpty) {
      return Uri.parse(custom);
    }
    return dohProvider.endpoint;
  }

  String get dohLabel {
    final custom = customDohUri?.trim();
    if (custom != null && custom.isNotEmpty) return '自定义加密 DNS';
    return dohProvider.label;
  }

  String? get normalizedCustomDohUri => _normalizeDohUri(customDohUri);

  InternetAddress? get fixedInternetAddress {
    final value = fixedAddress?.trim();
    if (value == null || value.isEmpty) return null;
    try {
      final address = InternetAddress(value);
      return ForumResolvedAddressStore._isUsableCachedIpv4(address)
          ? address
          : null;
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumNetworkConfig &&
          runtimeType == other.runtimeType &&
          site == other.site &&
          dohEnabled == other.dohEnabled &&
          dohProvider == other.dohProvider &&
          fixedAddress == other.fixedAddress &&
          customDohUri == other.customDohUri;

  @override
  int get hashCode =>
      Object.hash(site, dohEnabled, dohProvider, fixedAddress, customDohUri);

  ForumNetworkConfig copyWith({
    ForumSite? site,
    bool? dohEnabled,
    DohProvider? dohProvider,
    String? fixedAddress,
    String? customDohUri,
    bool clearFixedAddress = false,
    bool clearCustomDohUri = false,
  }) {
    return ForumNetworkConfig(
      site: site ?? this.site,
      dohEnabled: dohEnabled ?? this.dohEnabled,
      dohProvider: dohProvider ?? this.dohProvider,
      fixedAddress: clearFixedAddress
          ? null
          : fixedAddress?.trim().isEmpty == true
              ? null
              : fixedAddress ?? this.fixedAddress,
      customDohUri: clearCustomDohUri
          ? null
          : _normalizeDohUri(customDohUri) ?? this.customDohUri,
    );
  }

  static ForumSite siteForHost(String? host) {
    final normalized = _normalizeHost(host);
    if (normalized != null && !sites.any((site) => site.host == normalized)) {
      return ForumSite(normalized);
    }
    return sites.firstWhere(
      (site) => site.host == normalized,
      orElse: () => defaultSite,
    );
  }

  static String? _normalizeHost(String? host) {
    final value = host?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    final withoutScheme = value
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .split(':')
        .first;
    if (withoutScheme.isEmpty || withoutScheme.contains(' ')) return null;
    return withoutScheme;
  }

  static String? _normalizeDohUri(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'https') return null;
    return uri.toString();
  }
}

enum DohProvider {
  cmliuCloudflare(
    label: 'cmliu Cloudflare 镜像',
    uri: 'https://doh.cm.edu.kg/CMLiussss',
  ),
  doh090227Sb(
    label: '090227 SB-query',
    uri: 'https://doh.090227.xyz/SB-query',
  ),
  cloudflareGateway(
    label: 'Cloudflare Gateway',
    uri: 'https://frd4wvnobp.cloudflare-gateway.com/dns-query',
  ),
  tiarap(
    label: 'Tiarap',
    uri: 'https://doh.tiarap.org/dns-query',
  ),
  ;

  const DohProvider({required this.label, required this.uri});

  final String label;
  final String uri;

  Uri get endpoint => Uri.parse(uri);

  static DohProvider fromName(String? name) {
    return values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => ForumNetworkConfig.defaultProvider,
    );
  }
}

class ForumNetworkSettings {
  ForumNetworkSettings._();

  static const _siteHostKey = 'forum_network_site_host_v1';
  static const _dohEnabledKey = 'forum_network_doh_enabled_v1';
  static const _dohProviderKey = 'forum_network_doh_provider_v1';
  static const _fixedAddressKey = 'forum_network_fixed_address_v1';
  static const _customDohUriKey = 'forum_network_custom_doh_uri_v1';
  static const _customSiteHostsKey = 'forum_network_custom_site_hosts_v1';
  static const _customDohUrisKey = 'forum_network_custom_doh_uris_v1';

  static Future<ForumNetworkConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ForumNetworkConfig(
      site: ForumNetworkConfig.siteForHost(prefs.getString(_siteHostKey)),
      dohEnabled: prefs.getBool(_dohEnabledKey) ?? true,
      dohProvider: DohProvider.fromName(prefs.getString(_dohProviderKey)),
      fixedAddress: _normalizeAddress(prefs.getString(_fixedAddressKey)),
      customDohUri: ForumNetworkConfig._normalizeDohUri(
          prefs.getString(_customDohUriKey)),
    );
  }

  static Future<void> save(ForumNetworkConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_siteHostKey, config.site.host);
    await prefs.setBool(_dohEnabledKey, config.dohEnabled);
    await prefs.setString(_dohProviderKey, config.dohProvider.name);
    final customDohUri = config.normalizedCustomDohUri;
    if (customDohUri == null) {
      await prefs.remove(_customDohUriKey);
    } else {
      await prefs.setString(_customDohUriKey, customDohUri);
    }
    final fixedAddress = _normalizeAddress(config.fixedAddress);
    if (fixedAddress == null) {
      await prefs.remove(_fixedAddressKey);
    } else {
      await prefs.setString(_fixedAddressKey, fixedAddress);
    }
  }

  static Future<List<ForumSite>> loadCustomSites() async {
    final prefs = await SharedPreferences.getInstance();
    final hosts = prefs
            .getStringList(_customSiteHostsKey)
            ?.map(ForumNetworkConfig._normalizeHost)
            .nonNulls
            .where((host) =>
                !ForumNetworkConfig.sites.any((site) => site.host == host))
            .toList() ??
        const <String>[];
    return _unique(hosts).map(ForumSite.new).toList(growable: false);
  }

  static Future<List<ForumSite>> addCustomSite(ForumSite site) async {
    final normalized = ForumNetworkConfig._normalizeHost(site.host);
    if (normalized == null ||
        ForumNetworkConfig.sites.any((item) => item.host == normalized)) {
      return loadCustomSites();
    }
    final prefs = await SharedPreferences.getInstance();
    final hosts = _unique([
      normalized,
      ...(prefs.getStringList(_customSiteHostsKey) ?? const <String>[]),
    ]);
    await prefs.setStringList(_customSiteHostsKey, hosts);
    return hosts.map(ForumSite.new).toList(growable: false);
  }

  static Future<List<String>> loadCustomDohUris() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs
            .getStringList(_customDohUrisKey)
            ?.map(ForumNetworkConfig._normalizeDohUri)
            .nonNulls
            .toList() ??
        const <String>[];
    return _unique(values);
  }

  static Future<List<String>> addCustomDohUri(String uri) async {
    final normalized = ForumNetworkConfig._normalizeDohUri(uri);
    if (normalized == null) return loadCustomDohUris();
    final prefs = await SharedPreferences.getInstance();
    final values = _unique([
      normalized,
      ...(prefs.getStringList(_customDohUrisKey) ?? const <String>[]),
    ]);
    await prefs.setStringList(_customDohUrisKey, values);
    return values;
  }

  static List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }

  static String? _normalizeAddress(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      final address = InternetAddress(trimmed);
      return ForumResolvedAddressStore._isUsableCachedIpv4(address)
          ? address.address
          : null;
    } on ArgumentError {
      return null;
    }
  }
}

class ForumResolvedAddressStore {
  ForumResolvedAddressStore._();

  static const _addressesKey = 'forum_network_cached_addresses_v1';
  static const _savedAtKey = 'forum_network_cached_addresses_saved_at_v1';
  static const _ttl = Duration(days: 30);
  static const _maxAddresses = 3;

  static Future<List<InternetAddress>> load() async {
    final defaultAddresses = ForumNetworkConfig.defaultRouteAddresses();
    final prefs = await SharedPreferences.getInstance();
    final savedAt = prefs.getInt(_savedAtKey);
    if (savedAt == null ||
        DateTime.now().millisecondsSinceEpoch - savedAt > _ttl.inMilliseconds) {
      return defaultAddresses;
    }

    return _uniqueAddresses([
      ...defaultAddresses,
      ..._parseAddresses(prefs.getStringList(_addressesKey) ?? const []),
    ]);
  }

  static Future<List<InternetAddress>> mergeAndSave(
    Iterable<InternetAddress> addresses,
  ) async {
    final merged = _uniqueAddresses([
      ...addresses,
      ...await load(),
    ]);
    await save(merged);
    return merged;
  }

  static Future<void> save(Iterable<InternetAddress> addresses) async {
    final values = _uniqueAddresses(addresses)
        .where(_isUsableCachedIpv4)
        .take(_maxAddresses)
        .map((address) => address.address)
        .toList(growable: false);
    if (values.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_addressesKey, values);
    await prefs.setInt(
      _savedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static List<InternetAddress> _parseAddresses(List<String> values) {
    final addresses = <InternetAddress>[];
    for (final value in values) {
      try {
        final address = InternetAddress(value);
        if (_isUsableCachedIpv4(address)) {
          addresses.add(address);
        }
      } on ArgumentError {
        // Ignore stale malformed cache values.
      }
    }
    return _uniqueAddresses(addresses);
  }

  static List<InternetAddress> _uniqueAddresses(
    Iterable<InternetAddress> addresses,
  ) {
    final seen = <String>{};
    final unique = <InternetAddress>[];
    for (final address in addresses) {
      if (seen.add(address.address)) unique.add(address);
    }
    return List.unmodifiable(unique);
  }

  static bool _isUsableCachedIpv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final octets = address.address.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    if (first == 0 || first == 10 || first == 127) return false;
    if (first == 100 && second >= 64 && second <= 127) return false;
    if (first == 169 && second == 254) return false;
    if (first == 172 && second >= 16 && second <= 31) return false;
    if (first == 192 && second == 168) return false;
    if (first == 198 && (second == 18 || second == 19)) return false;
    if (first >= 224) return false;
    return true;
  }
}

class DohResolver {
  DohResolver({
    required DohProvider provider,
    HttpClient? client,
    this.timeout = const Duration(seconds: 5),
  })  : endpoint = provider.endpoint,
        _client = client;

  DohResolver.custom({
    required this.endpoint,
    HttpClient? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client;

  final Uri endpoint;
  final HttpClient? _client;
  final Duration timeout;

  final Map<String, List<InternetAddress>> _cache = {};

  Future<List<InternetAddress>> lookup(String host) async {
    final normalized = host.toLowerCase();
    final cached = _cache[normalized];
    if (cached != null && cached.isNotEmpty) return cached;

    final records = await _queryJson(normalized, 1);
    final resolved =
        records.isNotEmpty ? records : await _queryDnsMessage(normalized, 1);
    if (resolved.isEmpty) {
      throw SocketException(
        'DoH did not return A records',
      );
    }

    _cache[normalized] = resolved;
    return resolved;
  }

  Future<List<InternetAddress>> _queryJson(String host, int type) async {
    final client = _client ?? HttpClient();
    try {
      final uri = endpoint.replace(
        queryParameters: {
          'name': host,
          'type': '$type',
        },
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SocketException('DoH returned ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return const [];
      final answers = decoded['Answer'];
      if (answers is! List) return const [];

      final addresses = <InternetAddress>[];
      for (final answer in answers) {
        if (answer is! Map<String, dynamic>) continue;
        if (answer['type'] != type) continue;
        final data = answer['data'];
        if (data is! String) continue;
        try {
          addresses.add(InternetAddress(data));
        } on ArgumentError {
          // Ignore malformed resolver responses.
        }
      }
      return List.unmodifiable(addresses);
    } on FormatException {
      return const [];
    } on SocketException {
      return const [];
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  Future<List<InternetAddress>> _queryDnsMessage(String host, int type) async {
    final client = _client ?? HttpClient();
    try {
      final uri = endpoint.replace(
        queryParameters: {
          'dns': base64UrlEncode(_dnsQuery(host, type)).replaceAll('=', ''),
        },
      );
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-message');
      final response = await request.close().timeout(timeout);
      final bytes = await response.fold<List<int>>(
          <int>[], (buffer, data) => buffer..addAll(data)).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      return _parseDnsMessage(Uint8List.fromList(bytes), type);
    } on FormatException {
      return const [];
    } on SocketException {
      return const [];
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  Uint8List _dnsQuery(String host, int type) {
    final id = math.Random().nextInt(0xffff);
    final bytes = <int>[
      id >> 8,
      id & 0xff,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    for (final label in host.split('.')) {
      final encoded = ascii.encode(label);
      if (encoded.length > 63) {
        throw const FormatException('DNS label is too long');
      }
      bytes
        ..add(encoded.length)
        ..addAll(encoded);
    }
    bytes
      ..add(0)
      ..add(type >> 8)
      ..add(type & 0xff)
      ..add(0)
      ..add(1);
    return Uint8List.fromList(bytes);
  }

  List<InternetAddress> _parseDnsMessage(Uint8List data, int expectedType) {
    if (data.length < 12) return const [];
    final answerCount = (data[6] << 8) | data[7];
    var offset = 12;
    offset = _skipDnsName(data, offset);
    if (offset < 0 || offset + 4 > data.length) return const [];
    offset += 4;

    final addresses = <InternetAddress>[];
    for (var i = 0; i < answerCount; i++) {
      offset = _skipDnsName(data, offset);
      if (offset < 0 || offset + 10 > data.length) return addresses;
      final type = (data[offset] << 8) | data[offset + 1];
      final dataLength = (data[offset + 8] << 8) | data[offset + 9];
      offset += 10;
      if (offset + dataLength > data.length) return addresses;
      if (type == expectedType && dataLength == 4) {
        addresses.add(
          InternetAddress(
            '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}',
            type: InternetAddressType.IPv4,
          ),
        );
      }
      offset += dataLength;
    }
    return List.unmodifiable(addresses);
  }

  int _skipDnsName(Uint8List data, int offset) {
    var current = offset;
    while (current < data.length) {
      final length = data[current];
      if (length == 0) return current + 1;
      if ((length & 0xc0) == 0xc0) {
        return current + 2 <= data.length ? current + 2 : -1;
      }
      current += 1 + length;
    }
    return -1;
  }
}

HttpClient createForumHttpClient(ForumNetworkConfig config) {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.maxConnectionsPerHost = 8;

  final resolvers = {
    for (final provider in DohProvider.values)
      provider: DohResolver(provider: provider),
  };
  final customDohUri = config.normalizedCustomDohUri;
  final customResolver = customDohUri == null
      ? null
      : DohResolver.custom(endpoint: Uri.parse(customDohUri));
  var cachedAddressesFuture = ForumResolvedAddressStore.load();

  Future<void> rememberAddresses(List<InternetAddress> addresses) async {
    cachedAddressesFuture = Future.value(
      await ForumResolvedAddressStore.mergeAndSave(addresses),
    );
  }

  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (proxyHost != null || proxyPort != null) {
      return Socket.startConnect(
        proxyHost ?? uri.host,
        proxyPort ?? uri.port,
      );
    }

    final fixedAddress = config.fixedInternetAddress;
    if (fixedAddress != null) {
      return _resolvedAddressConnectionTask(uri, fixedAddress);
    }

    if (config.dohEnabled) {
      if (customResolver != null) {
        try {
          final addresses = await customResolver.lookup(uri.host);
          await rememberAddresses(addresses);
          for (final address in addresses) {
            try {
              return await _resolvedAddressConnectionTask(uri, address);
            } catch (_) {
              // Try the next custom DoH address before falling back.
            }
          }
        } catch (_) {
          // Try built-in DoH providers before falling back to system DNS.
        }
      }
      for (final provider in _orderedDohProviders(config.dohProvider)) {
        try {
          final addresses = await resolvers[provider]!.lookup(uri.host);
          await rememberAddresses(addresses);
          for (final address in addresses) {
            try {
              return await _resolvedAddressConnectionTask(uri, address);
            } catch (_) {
              // Try the next DoH address, then the next DoH provider.
            }
          }
        } catch (_) {
          // Try the next DoH provider before falling back to system DNS.
        }
      }
    }

    late Object systemError;
    try {
      return await _systemConnectionTask(uri);
    } catch (error) {
      systemError = error;
    }

    final cachedAddresses = await cachedAddressesFuture.catchError(
      (_) => const <InternetAddress>[],
    );
    for (final address in cachedAddresses) {
      try {
        return await _resolvedAddressConnectionTask(uri, address);
      } catch (_) {
        // Try the next persisted address, then surface the system DNS failure.
      }
    }

    throw systemError;
  };
  return client;
}

List<DohProvider> _orderedDohProviders(DohProvider preferred) {
  return [
    preferred,
    ...DohProvider.values.where((provider) => provider != preferred),
  ];
}

Future<ConnectionTask<Socket>> _resolvedAddressConnectionTask(
  Uri uri,
  InternetAddress address,
) async {
  final task = await Socket.startConnect(address, uri.port);
  if (uri.scheme != 'https') return task;

  return ConnectionTask.fromSocket<Socket>(
    task.socket.then(
      (socket) => SecureSocket.secure(socket, host: uri.host),
    ),
    task.cancel,
  );
}

Future<ConnectionTask<Socket>> _systemConnectionTask(Uri uri) async {
  if (uri.scheme != 'https') {
    return Socket.startConnect(uri.host, uri.port);
  }

  final task = await SecureSocket.startConnect(uri.host, uri.port);
  return ConnectionTask.fromSocket<Socket>(task.socket, task.cancel);
}
