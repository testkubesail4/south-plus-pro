import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

import 'support/doh_wire_fixture.dart';

final class _RealIo extends IOOverrides {}

class _SocketRoutes {
  final real = _RealIo();
  final attempts = <String>[];
  int cancels = 0;
  int resolverPort = 0;
  Future<ConnectionTask<Socket>> start(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) async {
    final name = host is InternetAddress ? host.address : '$host';
    if (port != resolverPort && port != 443) attempts.add(name);
    if (port == 443)
      throw const SocketException('Other resolver is offline in fixture');
    final address = name == '172.67.215.174' || name == '127.0.0.2'
        ? '127.0.0.2'
        : '127.0.0.1';
    final task = await real.socketStartConnect(
      InternetAddress(address),
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
    );
    return ConnectionTask.fromSocket(task.socket, () {
      cancels++;
      task.cancel();
    });
  }
}

class _Blackhole {
  _Blackhole(this.server) {
    server.listen((socket) {
      sockets.add(socket);
      subscription = socket.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (!hello.isCompleted) hello.complete();
        },
        onDone: finish,
        onError: (Object _) => finish(),
      );
    });
  }
  final ServerSocket server;
  final sockets = <Socket>[];
  final bytes = <int>[];
  final hello = Completer<void>();
  final closed = Completer<void>();
  StreamSubscription<List<int>>? subscription;
  SecureSocket? secure;
  void finish() {
    if (!closed.isCompleted) closed.complete();
  }

  Future<void> release(SecurityContext context) async {
    subscription?.pause();
    try {
      secure = await SecureSocket.secureServer(
        sockets.single,
        context,
        bufferedData: List<int>.of(bytes),
      );
      secure!.listen((_) {}, onDone: finish, onError: (Object _) => finish());
    } on HandshakeException {
      finish();
    } on SocketException {
      finish();
    }
  }

  Future<void> dispose() async {
    secure?.destroy();
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory certificates;
  late SecurityContext serverContext;
  setUpAll(() async {
    certificates = await Directory.systemTemp.createTemp('forum_tls_fixture_');
    final cert = '${certificates.path}/cert.pem';
    final key = '${certificates.path}/key.pem';
    final result = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      key,
      '-out',
      cert,
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost',
    ]);
    expect(result.exitCode, 0, reason: 'ephemeral Docker OpenSSL fixture');
    serverContext = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    SecurityContext.defaultContext.setTrustedCertificates(cert);
  });
  tearDownAll(() => certificates.delete(recursive: true));

  Future<void> withClient(
    _SocketRoutes routes,
    Future<void> Function(HttpClient) action,
  ) async {
    final resolver = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext,
    );
    routes.resolverPort = resolver.port;
    resolver.listen((request) {
      final query = base64Url.decode(
        base64Url.normalize(request.uri.queryParameters['dns']!),
      );
      request.response.headers.contentType = ContentType(
        'application',
        'dns-message',
      );
      request.response.add(
        dnsReply(query, [
          dnsRecord('localhost', 1, [104, 21, 43, 10]),
          dnsRecord('localhost', 1, [172, 67, 215, 174]),
        ]),
      );
      request.response.close();
    });
    try {
      await IOOverrides.runZoned(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final client = createForumHttpClient(
            ForumNetworkConfig(
              site: const ForumSite('localhost'),
              mode: ForumNetworkMode.optimized,
              customDohUri: 'https://localhost:${resolver.port}/dns-query',
              dohBootstrapAddresses: const ['1.1.1.1'],
            ),
          );
          try {
            await action(client);
          } finally {
            client.close(force: true);
          }
        }, ForumHttpOverrides()),
        socketStartConnect: routes.start,
      );
    } finally {
      await resolver.close(force: true);
    }
  }

  test('refused resolved address falls through to a working address', () async {
    final server = await HttpServer.bind(InternetAddress('127.0.0.2'), 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.write('fixture ok');
      request.response.close();
    });
    final routes = _SocketRoutes();
    await withClient(routes, (client) async {
      final response = await (await client.getUrl(
        Uri.http('localhost:${server.port}', '/'),
      ))
          .close();
      expect(await utf8.decoder.bind(response).join(), 'fixture ok');
    });
    expect(routes.attempts.take(2), ['104.21.43.10', '172.67.215.174']);
  });

  test(
    'failed TLS handshake falls through without relaxing hostname checks',
    () async {
      final good = await HttpServer.bindSecure(
        InternetAddress('127.0.0.2'),
        0,
        serverContext,
      );
      final bad = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        good.port,
      );
      addTearDown(() async {
        await bad.close();
        await good.close(force: true);
      });
      bad.listen((socket) => socket.destroy());
      good.listen((request) {
        request.response.write('fixture secure');
        request.response.close();
      }, onError: (Object _) {});
      final routes = _SocketRoutes();
      await withClient(routes, (client) async {
        final response = await (await client.getUrl(
          Uri.https('localhost:${good.port}', '/'),
        ))
            .close();
        expect(await utf8.decoder.bind(response).join(), 'fixture secure');
      });
      expect(routes.attempts.take(2), ['104.21.43.10', '172.67.215.174']);
      await withClient(_SocketRoutes(), (client) async {
        await expectLater(
          client.getUrl(Uri.https('127.0.0.2:${good.port}', '/')),
          throwsA(isA<HandshakeException>()),
        );
      });
    },
  );

  test(
    'exhausted optimized candidates never substitute target system DNS',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final routes = _SocketRoutes();
      await withClient(routes, (client) async {
        await expectLater(
          client.getUrl(Uri.http('localhost:$port', '/')),
          throwsA(isA<SocketException>()),
        );
      });
      expect(routes.attempts, isNot(contains('localhost')));
      expect(routes.attempts, containsAll(['104.21.43.10', '172.67.215.174']));
    },
  );

  for (final cancelBy in ['timeout', 'force close']) {
    test(
      '$cancelBy ends a TLS blackhole promptly and destroys late sockets',
      () async {
        final hole = _Blackhole(
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        );
        addTearDown(hole.dispose);
        final routes = _SocketRoutes();
        await withClient(routes, (client) async {
          client.connectionTimeout = cancelBy == 'timeout'
              ? const Duration(milliseconds: 120)
              : const Duration(seconds: 2);
          final watch = Stopwatch()..start();
          final request = client.getUrl(
            Uri.https('localhost:${hole.server.port}', '/'),
          );
          final rejected = expectLater(
            request.timeout(const Duration(seconds: 1)),
            throwsA(
              anyOf(
                isA<SocketException>(),
                isA<HttpException>(),
                isA<TimeoutException>(),
              ),
            ),
          );
          await hole.hello.future.timeout(const Duration(seconds: 1));
          if (cancelBy == 'force close') client.close(force: true);
          await rejected;
          expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
          expect(routes.cancels, greaterThan(0));
          await hole.release(serverContext).timeout(const Duration(seconds: 1));
          await hole.closed.future.timeout(const Duration(seconds: 1));
        });
      },
    );
  }
}
