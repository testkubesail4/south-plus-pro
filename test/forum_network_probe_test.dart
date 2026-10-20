import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ForumHttpRouting.updateProxy(null));
  for (final status in [200, 403, 429]) {
    test(
      'isolated native probe reports HTTP $status without changing active proxy or retrying',
      () async {
        final context = SecurityContext()
          ..useCertificateChain('test/support/proxy_fixture_cert.pem')
          ..usePrivateKey('test/support/proxy_fixture_key.pem');
        final trust = SecurityContext()
          ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');
        final server = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          context,
        );
        var hits = 0;
        server.listen((request) {
          hits++;
          request.response.statusCode = status;
          request.response.write('fixture');
          request.response.close();
        });
        ForumHttpRouting.updateProxy(
          ForumProxy(
            type: ForumProxyType.http,
            host: 'proxy.fixture.invalid',
            port: 8080,
          ),
        );
        final before = await ForumNetworkSettings.load();
        try {
          final result = await HttpOverrides.runWithHttpOverrides(
            () => const ForumNetworkProbe().testConfig(
              const ForumNetworkConfig(
                site: ForumSite('fixture.invalid'),
                mode: ForumNetworkMode.native,
              ),
            ),
            _OriginOverrides(server.port, trust),
          );
          expect(result.statusCode, status);
          expect(result.success, status == 200);
          expect(hits, 1);
          expect(ForumHttpRouting.proxyEnabled, isTrue);
          expect(await ForumNetworkSettings.load(), before);
        } finally {
          await server.close(force: true);
        }
      },
    );
  }
}

class _OriginOverrides extends ForumHttpOverrides {
  _OriginOverrides(this.port, this.trust);
  final int port;
  final SecurityContext trust;
  @override
  HttpClient createUnroutedClient(SecurityContext? context) =>
      super.createUnroutedClient(trust)
        ..connectionFactory = (uri, _, __) async {
          final task =
              await Socket.startConnect(InternetAddress.loopbackIPv4, port);
          return ConnectionTask.fromSocket<Socket>(
              task.socket.then((socket) =>
                  SecureSocket.secure(socket, host: uri.host, context: trust)),
              task.cancel);
        };
}
