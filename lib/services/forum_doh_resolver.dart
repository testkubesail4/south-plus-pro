import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'forum_connection_race.dart';
import 'forum_http_routing.dart';
import 'forum_network_config.dart';
import 'forum_network_defaults.dart';

class DohResolver {
  DohResolver({
    required DohProvider provider,
    HttpClient? client,
    this.timeout = const Duration(seconds: 4),
    this.ipv6Enabled = false,
    this.context,
  })  : endpoint = provider.endpoint,
        bootstrapAddresses =
            forumDohBootstrap[provider.endpoint.host] ?? const [],
        _injectedClient = client;

  DohResolver.custom({
    required this.endpoint,
    HttpClient? client,
    this.bootstrapAddresses = const [],
    this.ipv6Enabled = false,
    this.timeout = const Duration(seconds: 4),
    this.context,
  }) : _injectedClient = client;

  final Uri endpoint;
  final List<String> bootstrapAddresses;
  final bool ipv6Enabled;
  final Duration timeout;
  final SecurityContext? context;
  final HttpClient? _injectedClient;
  HttpClient? _ownedClient;
  final _cache = <String, _CachedAnswer>{};
  final _inflight = <String, Future<_DnsAnswer>>{};
  final _requests = <HttpClientRequest>{};
  final _connections = <ForumConnectionRace>{};
  bool _closed = false;

  Future<List<InternetAddress>> lookup(String host) =>
      lookupCandidates(host).first;

  /// Families complete independently; cancelling a waiter never cancels shared DNS.
  Stream<List<InternetAddress>> lookupCandidates(String host) {
    if (_closed) throw StateError('Resolver is closed');
    host = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (ForumNetworkConfig.normalizeHost(host) != host)
      throw const FormatException('Invalid DNS hostname');
    var remaining = ipv6Enabled ? 2 : 1;
    var emitted = false;
    var cancelled = false;
    final controller = StreamController<List<InternetAddress>>(
      onCancel: () {
        cancelled = true;
      },
    );
    for (final type in [if (ipv6Enabled) 28, 1]) {
      unawaited(
        _answer(host, type).then((answer) {
          if (!cancelled && answer.addresses.isNotEmpty) {
            emitted = true;
            controller.add(answer.addresses);
          }
        }, onError: (Object _) {}).whenComplete(() {
          if (--remaining == 0) {
            if (!cancelled && !emitted)
              controller.addError(
                const SocketException(
                  'DoH returned no usable address records',
                ),
              );
            unawaited(controller.close());
          }
        }),
      );
    }
    return controller.stream;
  }

  Future<_DnsAnswer> _answer(String host, int type) {
    final key = '$host/$type';
    final cached = _cache[key];
    if (cached != null && cached.expires.isAfter(DateTime.now()))
      return Future.value(cached.answer);
    _cache.remove(key);
    return _inflight.putIfAbsent(
      key,
      () => _fetch(host, type).then((answer) {
        if (!_closed && answer.ttl > 0 && answer.addresses.isNotEmpty) {
          if (_cache.length >= 128) _cache.remove(_cache.keys.first);
          _cache[key] = _CachedAnswer(
            answer,
            DateTime.now().add(
              Duration(seconds: math.min(answer.ttl, 3600)),
            ),
          );
        }
        return answer;
      }).whenComplete(() {
        _inflight.remove(key);
      }),
    );
  }

  HttpClient get _client =>
      _injectedClient ?? (_ownedClient ??= _createClient());

  HttpClient _createClient() {
    final client = createUnroutedHttpClient(context: context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = timeout;
    client.connectionFactory = (uri, _, __) async {
      final race = ForumConnectionRace(uri, timeout: timeout, context: context);
      _connections.add(race);
      unawaited(
        race.socket
            .then((_) {}, onError: (Object _) {})
            .whenComplete(() => _connections.remove(race)),
      );
      Future<void> resolve() async {
        try {
          final addresses = bootstrapAddresses.isNotEmpty
              ? bootstrapAddresses.map(InternetAddress.new).toList()
              : await InternetAddress.lookup(
                  uri.host,
                  type: ipv6Enabled
                      ? InternetAddressType.any
                      : InternetAddressType.IPv4,
                ).timeout(timeout);
          race.add(_ordered(addresses));
        } catch (_) {
          // The race still owns its deadline and cancellation, including late DNS.
        } finally {
          race.finishAdding();
        }
      }

      if (_closed) {
        race.cancel();
      } else {
        unawaited(resolve());
      }
      return ConnectionTask.fromSocket(race.socket, race.cancel);
    };
    return client;
  }

  List<InternetAddress> _ordered(List<InternetAddress> values) {
    final v4 = values.where((a) => a.type == InternetAddressType.IPv4).toList();
    final v6 = ipv6Enabled
        ? values.where((a) => a.type == InternetAddressType.IPv6).toList()
        : <InternetAddress>[];
    return [
      for (var i = 0; i < math.max(v4.length, v6.length); i++) ...[
        if (i < v6.length) v6[i],
        if (i < v4.length) v4[i],
      ],
    ];
  }

  Future<_DnsAnswer> _fetch(String host, int type) async {
    if (ForumNetworkConfig.normalizeDohUri(endpoint.toString()) == null)
      throw const FormatException('Invalid HTTPS DoH endpoint');
    final id = math.Random.secure().nextInt(65536);
    final query = _query(host, type, id);
    final uri = endpoint.replace(
      queryParameters: {
        ...endpoint.queryParameters,
        'dns': base64UrlEncode(query).replaceAll('=', ''),
      },
    );
    HttpClientRequest? request;
    StreamSubscription<List<int>>? bodySubscription;
    final body = Completer<List<int>>();
    final watch = Stopwatch()..start();
    var expired = false;
    final timer = Timer(timeout, () {
      expired = true;
      request?.abort(const SocketException('DoH deadline exceeded'));
      unawaited(bodySubscription?.cancel());
      if (bodySubscription != null && !body.isCompleted)
        body.completeError(TimeoutException('DoH deadline exceeded'));
    });
    try {
      request = await _client.getUrl(uri).then((value) {
        if (expired || _closed)
          value.abort(const SocketException('DoH request cancelled'));
        return value;
      }).timeout(timeout);
      if (expired || _closed)
        throw const SocketException('DoH request cancelled');
      _requests.add(request);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-message');
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero)
        throw TimeoutException('DoH deadline exceeded');
      final response = await request.close().timeout(remaining);
      if (response.statusCode != HttpStatus.ok ||
          response.headers.contentType?.mimeType != 'application/dns-message') {
        request.abort();
        throw const SocketException('DoH HTTP or content type failure');
      }
      final bytes = <int>[];
      bodySubscription = response.listen(
        (chunk) {
          if (body.isCompleted) return;
          if (bytes.length + chunk.length > 65535) {
            body.completeError(const FormatException('Oversized DNS response'));
            unawaited(bodySubscription?.cancel());
          } else {
            bytes.addAll(chunk);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!body.isCompleted) body.completeError(error, stack);
        },
        onDone: () {
          if (!body.isCompleted) body.complete(bytes);
        },
      );
      return _parse(Uint8List.fromList(await body.future), host, type, id);
    } finally {
      timer.cancel();
      await bodySubscription?.cancel();
      if (request != null) _requests.remove(request);
    }
  }

  void close() {
    _closed = true;
    for (final request in _requests.toList()) {
      request.abort(const SocketException('Resolver closed'));
    }
    for (final connection in _connections.toList()) {
      connection.cancel();
    }
    _ownedClient?.close(force: true);
    _cache.clear();
  }
}

class _CachedAnswer {
  const _CachedAnswer(this.answer, this.expires);
  final _DnsAnswer answer;
  final DateTime expires;
}

class _DnsAnswer {
  const _DnsAnswer(this.addresses, this.ttl);
  final List<InternetAddress> addresses;
  final int ttl;
}

Uint8List _query(String host, int type, int id) {
  final bytes = <int>[id >> 8, id & 255, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0];
  for (final label in host.split('.')) {
    final encoded = ascii.encode(label);
    if (encoded.isEmpty || encoded.length > 63)
      throw const FormatException('Invalid DNS label');
    bytes
      ..add(encoded.length)
      ..addAll(encoded);
  }
  bytes.addAll([0, type >> 8, type & 255, 0, 1]);
  return Uint8List.fromList(bytes);
}

_DnsAnswer _parse(Uint8List bytes, String host, int expectedType, int id) {
  final reader = _DnsReader(bytes);
  if (bytes.length < 12 ||
      reader.u16(0) != id ||
      (reader.u16(2) & 0xfa4f) != 0x8000 ||
      reader.u16(4) != 1) {
    throw const FormatException('Invalid DNS header or status');
  }
  final question = reader.name(12);
  var offset = question.$2;
  if (question.$1 != host ||
      reader.u16(offset) != expectedType ||
      reader.u16(offset + 2) != 1)
    throw const FormatException('DNS question mismatch');
  offset += 4;
  final answers = reader.u16(6);
  final total = answers + reader.u16(8) + reader.u16(10);
  if (total > 256) throw const FormatException('Too many DNS records');
  final cnames = <String, (String, int)>{};
  final records = <String, List<(InternetAddress, int)>>{};
  for (var i = 0; i < total; i++) {
    final owner = reader.name(offset);
    offset = owner.$2;
    final type = reader.u16(offset);
    final recordClass = reader.u16(offset + 2);
    final ttl = reader.u32(offset + 4);
    final length = reader.u16(offset + 8);
    offset += 10;
    final end = offset + length;
    reader.check(offset, length);
    if (type == 41 && ((ttl >> 24) != 0 || owner.$1.isNotEmpty))
      throw const FormatException('DNS extended status failure');
    if (i < answers && recordClass == 1) {
      if (type == 5) {
        final alias = reader.name(offset);
        if (alias.$2 != end || alias.$1.isEmpty)
          throw const FormatException('Invalid DNS CNAME');
        final previous = cnames[owner.$1];
        if (previous != null && previous.$1 != alias.$1)
          throw const FormatException('Conflicting DNS CNAME');
        cnames[owner.$1] = (
          alias.$1,
          previous == null ? ttl : math.min(ttl, previous.$2),
        );
      } else if (type == 1 || type == 28) {
        if (length != (type == 1 ? 4 : 16))
          throw const FormatException('Invalid DNS address length');
        if (type == expectedType) {
          final address = InternetAddress.fromRawAddress(
            Uint8List.sublistView(bytes, offset, end),
            type:
                type == 1 ? InternetAddressType.IPv4 : InternetAddressType.IPv6,
          );
          // Resolver answers cannot redirect public requests to local services.
          if (ForumNetworkConfig.validateAddressLiteral(address.address) ==
              null) {
            (records[owner.$1] ??= []).add((address, ttl));
          }
        }
      }
    }
    offset = end;
  }
  if (offset != bytes.length) throw const FormatException('Trailing DNS data');
  var name = host;
  var ttl = 0xffffffff;
  final visited = <String>{};
  while (cnames.containsKey(name)) {
    if (!visited.add(name) || visited.length > 8 || records.containsKey(name))
      throw const FormatException('Invalid DNS CNAME chain');
    final alias = cnames[name]!;
    ttl = math.min(ttl, alias.$2);
    name = alias.$1;
  }
  if (visited.contains(name)) throw const FormatException('DNS CNAME loop');
  final result = <String, InternetAddress>{};
  for (final record in records[name] ?? <(InternetAddress, int)>[]) {
    ttl = math.min(ttl, record.$2);
    result[record.$1.address] = record.$1;
  }
  return _DnsAnswer(List.unmodifiable(result.values), result.isEmpty ? 0 : ttl);
}

class _DnsReader {
  const _DnsReader(this.bytes);
  final Uint8List bytes;
  void check(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > bytes.length)
      throw const FormatException('Truncated DNS message');
  }

  int u16(int offset) {
    check(offset, 2);
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  int u32(int offset) => (u16(offset) << 16) | u16(offset + 2);
  (String, int) name(int offset) {
    final labels = <String>[];
    final visited = <int>{};
    int? next;
    var size = 0;
    while (true) {
      check(offset, 1);
      if (!visited.add(offset) || visited.length > 128)
        throw const FormatException('DNS compression loop');
      final length = bytes[offset];
      if ((length & 0xc0) == 0xc0) {
        final pointer = u16(offset) & 0x3fff;
        if (pointer >= offset)
          throw const FormatException('Invalid DNS compression pointer');
        next ??= offset + 2;
        offset = pointer;
        continue;
      }
      if ((length & 0xc0) != 0)
        throw const FormatException('Invalid DNS label');
      offset++;
      if (length == 0) return (labels.join('.').toLowerCase(), next ?? offset);
      check(offset, length);
      size += length + 1;
      if (size > 254) throw const FormatException('DNS hostname too long');
      final label = ascii.decode(bytes.sublist(offset, offset + length));
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(label))
        throw const FormatException('Invalid DNS label');
      labels.add(label);
      offset += length;
    }
  }
}
