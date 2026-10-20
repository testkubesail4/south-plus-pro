import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SecurityContext.defaultContext
      .setTrustedCertificates('test/support/proxy_fixture_cert.pem'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pre-cancelled probes never create an HTTP transport', () async {
    final cancellation = ForumProbeCancellation()..cancel();
    final network = _RejectNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      const probe = ForumNetworkProbe();
      final site = await probe.testConfig(
          const ForumNetworkConfig(
              site: ForumSite('fixture.invalid'),
              mode: ForumNetworkMode.native),
          cancellation: cancellation);
      final provider = await probe.testDoh(ForumNetworkConfig.defaultProvider,
          cancellation: cancellation);
      final custom = await probe.testCustomDoh(
          'https://fixture.invalid/dns-query',
          bootstrapAddresses: const ['9.9.9.9'],
          cancellation: cancellation);
      expect([site.success, provider.success, custom.success],
          everyElement(isFalse));
      expect([site.message, provider.message, custom.message],
          everyElement('已取消'));
    }, network);
    expect(network.clients, 0);
  });

  for (final dohOnly in [false, true]) {
    test(
        'cancel ${dohOnly ? 'DoH' : 'native'} probe closes its peer, not another batch',
        () async {
      final hole = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final context = SecurityContext()
        ..useCertificateChain('test/support/proxy_fixture_cert.pem')
        ..usePrivateKey('test/support/proxy_fixture_key.pem');
      final healthy =
          await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
      final hello = Completer<void>();
      final peerClosed = Completer<void>();
      final healthyReceived = Completer<void>();
      final releaseHealthy = Completer<void>();
      final sockets = <Socket>[];
      final cancelled = ForumProbeCancellation();
      final active = ForumProbeCancellation();
      addTearDown(() async {
        cancelled.cancel();
        active.cancel();
        if (!releaseHealthy.isCompleted) releaseHealthy.complete();
        for (final socket in sockets) {
          socket.destroy();
        }
        await hole.close();
        await healthy.close(force: true);
      });
      void closed() {
        if (!peerClosed.isCompleted) peerClosed.complete();
      }

      hole.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {
          if (!hello.isCompleted) hello.complete();
        }, onDone: closed, onError: (Object _) => closed());
      });
      healthy.listen((request) async {
        healthyReceived.complete();
        await releaseHealthy.future;
        request.response.write('healthy fixture');
        await request.response.close();
      });
      await HttpOverrides.runWithHttpOverrides(() async {
        const probe = ForumNetworkProbe(timeout: Duration(seconds: 5));
        final blocked = dohOnly
            ? probe
                .testCustomDoh(
                  'https://localhost:${hole.port}/dns-query',
                  cancellation: cancelled,
                )
                .then((r) => (r.success, r.message))
            : probe
                .testConfig(
                  ForumNetworkConfig(
                      site: _ProbeSite(hole.port),
                      mode: ForumNetworkMode.native),
                  cancellation: cancelled,
                )
                .then((r) => (r.success, r.message));
        final other = probe.testConfig(
          ForumNetworkConfig(
              site: _ProbeSite(healthy.port), mode: ForumNetworkMode.native),
          cancellation: active,
        );
        await hello.future.timeout(const Duration(seconds: 2),
            onTimeout: () => throw TimeoutException('No blackhole TLS hello'));
        await healthyReceived.future.timeout(const Duration(seconds: 2),
            onTimeout: () =>
                throw TimeoutException('No healthy probe request'));
        final openedBeforeCancel = sockets.length;
        cancelled.cancel();
        final result = await blocked.timeout(const Duration(seconds: 1),
            onTimeout: () => throw TimeoutException('Cancel result stalled'));
        expect(result, (false, '已取消'));
        await peerClosed.future.timeout(const Duration(seconds: 1),
            onTimeout: () =>
                throw TimeoutException('Cancelled peer stayed open'));
        releaseHealthy.complete();
        final healthyResult = await other.timeout(const Duration(seconds: 1),
            onTimeout: () =>
                throw TimeoutException('Other batch was disrupted'));
        expect(healthyResult.success, isTrue);
        expect(healthyResult.statusCode, HttpStatus.ok);
        expect(sockets, hasLength(openedBeforeCancel));
      }, _RealHttp());
    });
  }
}

class _ProbeSite extends ForumSite {
  _ProbeSite(this.port) : super('localhost');
  final int port;
  @override
  Uri get baseUri => Uri.https('localhost:$port', '/');
}

class _RealHttp extends HttpOverrides {}

class _RejectNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('Cancelled probe opened an HTTP transport');
  }
}
