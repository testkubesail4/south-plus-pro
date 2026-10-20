import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:south_plus_rewrite/services/forum_http_routing.dart';

List<int> dnsName(String host) => [
      for (final label in host.split('.')) ...[
        label.length,
        ...ascii.encode(label),
      ],
      0,
    ];
int dnsQueryType(List<int> query) =>
    (query[query.length - 4] << 8) | query[query.length - 3];
List<int> dnsRecord(
  String owner,
  int type,
  List<int> data, {
  int ttl = 60,
  int recordClass = 1,
}) =>
    [
      ...dnsName(owner),
      type >> 8,
      type & 255,
      recordClass >> 8,
      recordClass & 255,
      (ttl >> 24) & 255,
      (ttl >> 16) & 255,
      (ttl >> 8) & 255,
      ttl & 255,
      data.length >> 8,
      data.length & 255,
      ...data,
    ];
List<int> dnsReply(
  List<int> query,
  List<List<int>> answers, {
  int status = 0,
}) =>
    [
      query[0],
      query[1],
      0x81,
      0x80 | status,
      0,
      1,
      answers.length >> 8,
      answers.length & 255,
      0,
      0,
      0,
      0,
      ...query.skip(12),
      ...answers.expand((a) => a),
    ];

/// Real HTTP transport for the DNS protocol boundary; resolver TLS/bootstrap is
/// independently exercised by the socket transport tests.
class DohWireFixture {
  DohWireFixture._(this.server, this.client);
  final HttpServer server;
  final HttpClient client;
  int hits = 0;
  final firstQuery = Completer<void>();
  static Future<DohWireFixture> start(
    FutureOr<List<int>> Function(List<int>) reply,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final raw = ForumHttpOverrides().createUnroutedClient(null)
      ..findProxy = (_) => 'DIRECT';
    final fixture = DohWireFixture._(
      server,
      _LocalWireClient(raw, server.port),
    );
    server.listen((request) async {
      fixture.hits++;
      if (!fixture.firstQuery.isCompleted) fixture.firstQuery.complete();
      final encoded = request.uri.queryParameters['dns']!;
      final query = base64Url.decode(base64Url.normalize(encoded));
      try {
        final bytes = await reply(query);
        request.response.headers.contentType = ContentType(
          'application',
          'dns-message',
        );
        request.response.add(bytes);
        await request.response.close();
      } on Object {
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
    return fixture;
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close(force: true);
  }
}

// Inject only DNS HTTP responses; the target client and its RawSocket path are real.
class DohHttpOverrides extends ForumHttpOverrides {
  DohHttpOverrides(this.wire);
  final HttpClient wire;
  var first = true;
  @override
  HttpClient createUnroutedClient(SecurityContext? context) {
    if (first) {
      first = false;
      return super.createUnroutedClient(context);
    }
    return _InjectedWireClient(wire);
  }
}

class _InjectedWireClient implements HttpClient {
  _InjectedWireClient(this.wire);
  final HttpClient wire;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) => wire.getUrl(uri);
  @override
  set findProxy(String Function(Uri)? value) {}
  @override
  set connectionTimeout(Duration? value) {}
  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value) {}
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LocalWireClient implements HttpClient {
  _LocalWireClient(this.client, this.port);
  final HttpClient client;
  final int port;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) =>
      client.getUrl(Uri.http('127.0.0.1:$port', uri.path, uri.queryParameters));
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
