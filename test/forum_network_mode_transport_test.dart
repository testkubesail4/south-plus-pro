import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ForumHttpRouting.updateConfig(const ForumNetworkConfig(
        site: ForumNetworkConfig.defaultSite,
        mode: ForumNetworkMode.native,
      )));

  for (final ipv6Enabled in [false, true]) {
    test('native ignores dormant routes with IPv6 preference $ipv6Enabled',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var hits = 0;
      server.listen((request) async {
        hits++;
        request.response.persistentConnection = false;
        request.response.write('native fixture');
        await request.response.close();
      });
      final real = _RealIo();
      final attempted = <String>[];
      final systemError = const SocketException('synthetic system failure');
      var rejectSystem = false;
      await HttpOverrides.runWithHttpOverrides(
        () => IOOverrides.runZoned(() async {
          final client = createForumHttpClient(ForumNetworkConfig(
            site: const ForumSite('fixture.invalid'),
            mode: ForumNetworkMode.native,
            ipv6Enabled: ipv6Enabled,
            customDohUri: 'https://resolver.invalid/dns-query',
            dohBootstrapAddresses: const ['9.9.9.9'],
            hostAddresses: const {
              'fixture.invalid': ['1.1.1.1', '2606:4700:4700::1111'],
            },
            proxy: ForumProxy(
              type: ForumProxyType.http,
              host: 'proxy.invalid',
              port: 8080,
            ),
          ));
          try {
            final uri = Uri.http('fixture.invalid:${server.port}', '/');
            final response = await (await client.getUrl(uri)).close();
            expect(await utf8.decoder.bind(response).join(), 'native fixture');
            rejectSystem = true;
            await expectLater(
                client.getUrl(uri),
                throwsA(isA<SocketException>().having((e) => e.message,
                    'system failure', contains(systemError.message))));
          } finally {
            client.close(force: true);
          }
        }, socketStartConnect: (dynamic host, int port,
            {dynamic sourceAddress, int sourcePort = 0}) async {
          final name = host is InternetAddress ? host.address : '$host';
          attempted.add(name);
          if (name != 'fixture.invalid') {
            throw StateError('native contacted a dormant route: $name');
          }
          if (rejectSystem) throw systemError;
          return real.socketStartConnect(InternetAddress.loopbackIPv4, port,
              sourceAddress: sourceAddress, sourcePort: sourcePort);
        }),
        _RealHttp(),
      );
      expect(attempted, ['fixture.invalid', 'fixture.invalid']);
      expect(hits, 1);
    });
  }

  for (final mode in [ForumNetworkMode.native, ForumNetworkMode.optimized]) {
    test('$mode keeps a saved proxy dormant for retained app-wide clients',
        () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final proxySockets = <Socket>[];
      addTearDown(() => origin.close(force: true));
      addTearDown(() async {
        for (final socket in proxySockets) {
          socket.destroy();
        }
        await proxy.close();
      });
      var proxyHits = 0;
      var originHits = 0;
      final originProxyAuth = <String?>[];
      origin.listen((request) async {
        originHits++;
        originProxyAuth
            .add(request.headers.value(HttpHeaders.proxyAuthorizationHeader));
        request.response.write('direct fixture');
        await request.response.close();
      });
      proxy.listen((socket) {
        proxyHits++;
        proxySockets.add(socket);
        socket.listen((_) async {
          socket.write('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
          await socket.flush();
          socket.destroy();
        }, onError: (Object _) => socket.destroy());
      });
      await HttpOverrides.runWithHttpOverrides(() async {
        ForumHttpRouting.updateConfig(const ForumNetworkConfig(
          site: ForumNetworkConfig.defaultSite,
          mode: ForumNetworkMode.native,
        ));
        final retained = HttpClient();
        final config = ForumNetworkConfig(
          site: const ForumSite('fixture.invalid'),
          mode: mode,
          proxy: ForumProxy(
              type: ForumProxyType.http,
              host: '127.0.0.1',
              port: proxy.port,
              username: 'synthetic-user',
              password: 'synthetic-password'),
        );
        final forumClient = ForumClient(config: config);
        try {
          final uri = Uri.http('127.0.0.1:${origin.port}', '/retained');
          Future<void> read() async {
            final response = await (await retained.getUrl(uri)).close();
            expect(await utf8.decoder.bind(response).join(), 'direct fixture');
          }

          await read();
          ForumRepository(config: config, client: forumClient);
          try {
            await read();
          } finally {
            expect(proxyHits, 0, reason: 'Saved proxy must remain dormant');
          }
          expect(originHits, 2);
          expect(originProxyAuth, everyElement(isNull));
        } finally {
          forumClient.close(force: true);
          retained.close(force: true);
        }
      }, ForumHttpOverrides());
    });
  }
}

final class _RealIo extends IOOverrides {}

class _RealHttp extends HttpOverrides {}
