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

  for (final ipv6Enabled in [false, true]) {
    test('optimized IPv6 enabled=$ipv6Enabled controls actual family attempts',
        () async {
      final context = SecurityContext()
        ..useCertificateChain('test/support/proxy_fixture_cert.pem')
        ..usePrivateKey('test/support/proxy_fixture_key.pem');
      final origin =
          await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
      addTearDown(() => origin.close(force: true));
      late ServerSocket hole;
      try {
        hole =
            await ServerSocket.bind(InternetAddress.loopbackIPv6, origin.port);
      } on SocketException catch (error) {
        if (!{47, 49, 97, 99, 10047, 10049}
            .contains(error.osError?.errorCode)) {
          rethrow;
        }
        markTestSkipped(
            'IPv6 loopback unavailable (${error.osError?.errorCode})');
        return;
      }
      final peers = <Socket>[];
      final hello = Completer<void>();
      final closed = Completer<void>();
      addTearDown(() async {
        for (final peer in peers) {
          peer.destroy();
        }
        await hole.close();
      });
      void peerClosed() {
        if (!closed.isCompleted) closed.complete();
      }

      hole.listen((socket) {
        peers.add(socket);
        socket.listen((_) {
          if (!hello.isCompleted) hello.complete();
        }, onDone: peerClosed, onError: (Object _) => peerClosed());
      });
      var originHits = 0;
      origin.listen((request) async {
        originHits++;
        request.response.write('IPv4 rescue');
        await request.response.close();
      });
      final dns =
          await DohWireFixture.start((query) => dnsReply(query, [], status: 3));
      addTearDown(dns.close);
      await HttpOverrides.runWithHttpOverrides(() async {
        // Constructor-only loopback candidates keep saved-config validation intact.
        final client = createForumHttpClient(ForumNetworkConfig(
          site: const ForumSite('localhost'),
          mode: ForumNetworkMode.optimized,
          ipv6Enabled: ipv6Enabled,
          hostAddresses: const {
            'localhost': ['::1', '127.0.0.2', '127.0.0.1'],
          },
        ));
        client.connectionTimeout = const Duration(seconds: 3);
        try {
          final response = await (await client
                  .getUrl(Uri.https('localhost:${origin.port}', '/')))
              .close();
          expect(await utf8.decoder.bind(response).join(), 'IPv4 rescue');
          expect(originHits, 1);
          expect(peers, hasLength(ipv6Enabled ? 1 : 0));
          expect(hello.isCompleted, ipv6Enabled);
          if (ipv6Enabled) {
            await closed.future.timeout(const Duration(seconds: 1));
          }
        } finally {
          client.close(force: true);
        }
      }, DohHttpOverrides(dns.client));
    });
  }
}
