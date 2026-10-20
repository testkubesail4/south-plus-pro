import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

import 'support/doh_wire_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SecurityContext.defaultContext
      .setTrustedCertificates('test/support/proxy_fixture_cert.pem'));

  Future<void> withClient(Future<void> Function(HttpClient) action) async {
    final fixture =
        await DohWireFixture.start((query) => dnsReply(query, [], status: 3));
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        // Constructor-only loopback candidates exercise real transport ownership;
        // the production saved-config public-IP validator remains unchanged.
        final client = createForumHttpClient(const ForumNetworkConfig(
            site: ForumSite('localhost'),
            mode: ForumNetworkMode.optimized,
            hostAddresses: {
              'localhost': ['127.0.0.2', '127.0.0.1']
            }));
        try {
          await action(client);
        } finally {
          client.close(force: true);
        }
      }, DohHttpOverrides(fixture.client));
    } finally {
      await fixture.close();
    }
  }

  test(
      'optimized static candidates use real Raw TLS and survive a refused first IP',
      () async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/proxy_fixture_cert.pem')
      ..usePrivateKey('test/support/proxy_fixture_key.pem');
    final server =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    var hits = 0;
    server.listen((request) {
      hits++;
      expect(request.headers.value(HttpHeaders.hostHeader),
          'localhost:${server.port}');
      request.response.write('raw optimized body');
      request.response.close();
    });
    try {
      await withClient((client) async {
        final response = await (await client
                .getUrl(Uri.https('localhost:${server.port}', '/')))
            .close();
        expect(await utf8.decoder.bind(response).join(), 'raw optimized body');
      });
      expect(hits, 1);
    } finally {
      await server.close(force: true);
    }
  });

  test('closing an optimized client cancels its pending real TLS peer',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final hello = Completer<void>();
    final closed = Completer<void>();
    Socket? peer;
    server.listen((socket) {
      peer = socket;
      socket.listen((bytes) {
        if (!hello.isCompleted) hello.complete();
      }, onDone: () {
        if (!closed.isCompleted) closed.complete();
      }, onError: (Object _) {
        if (!closed.isCompleted) closed.complete();
      });
    });
    try {
      await withClient((client) async {
        final failed = expectLater(
            client.getUrl(Uri.https('localhost:${server.port}', '/')),
            throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
        await hello.future.timeout(const Duration(seconds: 2));
        client.close(force: true);
        await failed.timeout(const Duration(seconds: 1));
        await closed.future.timeout(const Duration(seconds: 1));
      });
    } finally {
      peer?.destroy();
      await server.close();
    }
  });
}
