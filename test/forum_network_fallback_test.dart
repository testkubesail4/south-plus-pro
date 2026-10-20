import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_connection_race.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory certificates;
  late SecurityContext serverContext;
  late SecurityContext trust;
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
      'subjectAltName=DNS:localhost'
    ]);
    expect(result.exitCode, 0, reason: 'ephemeral Docker OpenSSL fixture');
    serverContext = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    trust = SecurityContext()..setTrustedCertificates(cert);
  });
  tearDownAll(() => certificates.delete(recursive: true));

  Future<void> withClient(
      List<String> candidates, Future<void> Function(HttpClient) action,
      {void Function(InternetAddress)? onFailure}) async {
    final races = <ForumConnectionRace>[];
    final client = ForumHttpOverrides().createUnroutedClient(trust);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, _, __) async {
      final race = ForumConnectionRace(uri,
          timeout: client.connectionTimeout ?? const Duration(seconds: 8),
          context: trust,
          onFailure: onFailure);
      races.add(race);
      race.add(candidates.map(InternetAddress.new));
      race.finishAdding();
      return ConnectionTask.fromSocket(race.socket, race.cancel);
    };
    try {
      await action(client);
    } finally {
      for (final race in races) {
        race.cancel();
      }
      client.close(force: true);
    }
  }

  test('refused resolved address falls through to a working address', () async {
    final server = await HttpServer.bind(InternetAddress('127.0.0.2'), 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.write('fixture ok');
      request.response.close();
    });
    final failed = <String>[];
    await withClient(['127.0.0.1', '127.0.0.2'], (client) async {
      final response =
          await (await client.getUrl(Uri.http('localhost:${server.port}', '/')))
              .close();
      expect(await utf8.decoder.bind(response).join(), 'fixture ok');
    }, onFailure: (address) => failed.add(address.address));
    expect(failed, ['127.0.0.1']);
  });

  test('failed TLS handshake falls through without relaxing hostname checks',
      () async {
    final good = await HttpServer.bindSecure(
        InternetAddress('127.0.0.2'), 0, serverContext);
    final bad =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, good.port);
    addTearDown(() async {
      await bad.close();
      await good.close(force: true);
    });
    bad.listen((socket) => socket.destroy());
    good.listen((request) {
      request.response.write('fixture secure');
      request.response.close();
    }, onError: (Object _) {});
    final failed = <String>[];
    await withClient(['127.0.0.1', '127.0.0.2'], (client) async {
      final response =
          await (await client.getUrl(Uri.https('localhost:${good.port}', '/')))
              .close();
      expect(await utf8.decoder.bind(response).join(), 'fixture secure');
    }, onFailure: (address) => failed.add(address.address));
    expect(failed, ['127.0.0.1']);
    await withClient(['127.0.0.2'], (client) async {
      await expectLater(client.getUrl(Uri.https('127.0.0.2:${good.port}', '/')),
          throwsA(isA<HandshakeException>()));
    });
  });

  test('exhausted candidates never substitute the original hostname', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    origin.listen((request) {
      hits++;
      request.response.close();
    });
    try {
      await withClient(['127.0.0.2', '127.0.0.3'], (client) async {
        await expectLater(
            client.getUrl(Uri.http('localhost:${origin.port}', '/')),
            throwsA(isA<SocketException>()));
      });
      expect(hits, 0,
          reason: 'system localhost is reachable but is not a candidate');
    } finally {
      await origin.close(force: true);
    }
  });

  for (final cancelBy in ['deadline', 'cancel']) {
    test(
        'candidate race $cancelBy closes every TLS blackhole peer before teardown',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final hello = Completer<void>();
      final closed = Completer<void>();
      server.listen((socket) {
        sockets.add(socket);
        socket.listen((chunk) {
          if (!hello.isCompleted) hello.complete();
        }, onDone: () {
          if (!closed.isCompleted) closed.complete();
        }, onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        });
      });
      final race = ForumConnectionRace(
          Uri.https('localhost:${server.port}', '/'),
          timeout: cancelBy == 'deadline'
              ? const Duration(milliseconds: 120)
              : const Duration(seconds: 5),
          context: trust);
      race.add([InternetAddress.loopbackIPv4]);
      race.finishAdding();
      final failure = expectLater(race.socket,
          throwsA(anyOf(isA<SocketException>(), isA<TimeoutException>())));
      try {
        await hello.future.timeout(const Duration(seconds: 1));
        if (cancelBy == 'cancel') race.cancel();
        await failure.timeout(const Duration(seconds: 1));
        await closed.future.timeout(const Duration(seconds: 1));
        expect(sockets.length, 1);
      } finally {
        race.cancel();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    });
  }
}
