import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_raw_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChain('test/support/proxy_fixture_cert.pem')
    ..usePrivateKey('test/support/proxy_fixture_key.pem');
  SecurityContext trust() => SecurityContext()
    ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');

  test(
      'raw TLS facade streams a large POST and a paused response without losing bytes',
      () async {
    final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4, 0, serverContext());
    const size = 8 * 1024 * 1024;
    final responseChunk =
        Uint8List.fromList(List.generate(16384, (i) => i % 251));
    server.listen((request) async {
      expect(request.headers.host, 'fixture.invalid');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      var offset = 0;
      var valid = true;
      await for (final data in request) {
        for (final byte in data) {
          if (byte != offset % 251) valid = false;
          offset++;
        }
      }
      request.response.headers.set('x-bytes', '$offset');
      request.response.headers.set('x-pattern-valid', '$valid');
      for (var i = 0; i < 64; i++) {
        request.response.add(responseChunk);
      }
      await request.response.close();
    });
    final attempts = <ForumSocketAttempt>[];
    final client = ForumHttpOverrides().createUnroutedClient(trust());
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, _, __) async {
      final attempt = ForumSocketAttempt(uri,
          address: InternetAddress.loopbackIPv4, context: trust());
      attempts.add(attempt);
      return ConnectionTask.fromSocket(attempt.socket, attempt.cancel);
    };
    try {
      final request = await client
          .postUrl(Uri.https('fixture.invalid:${server.port}', '/upload'));
      request.contentLength = size;
      final payload = Uint8List.fromList(List.generate(size, (i) => i % 251));
      request.add(payload);
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.value('x-bytes'), '$size');
      expect(response.headers.value('x-pattern-valid'), 'true');
      var received = 0;
      var validResponse = true;
      final done = Completer<void>();
      final subscription = response.listen((data) {
        for (final byte in data) {
          if (byte != (received % responseChunk.length) % 251)
            validResponse = false;
          received++;
        }
      }, onError: done.completeError, onDone: done.complete);
      subscription
          .pause(Future<void>.delayed(const Duration(milliseconds: 100)));
      await done.future;
      expect(received, responseChunk.length * 64);
      expect(validResponse, isTrue);
    } finally {
      client.close(force: true);
      for (final attempt in attempts) {
        attempt.cancel();
      }
      await server.close(force: true);
    }
  });

  test('plain raw POST with an ambiguous closed response fails without replay',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    var body = '';
    server.listen((request) async {
      hits++;
      body = await utf8.decoder.bind(request).join();
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    });
    final attempts = <ForumSocketAttempt>[];
    final client = ForumHttpOverrides().createUnroutedClient(null);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, _, __) async {
      final attempt =
          ForumSocketAttempt(uri, address: InternetAddress.loopbackIPv4);
      attempts.add(attempt);
      return ConnectionTask.fromSocket(attempt.socket, attempt.cancel);
    };
    try {
      final request = await client
          .postUrl(Uri.http('fixture.invalid:${server.port}', '/post'));
      request.write('synthetic-ambiguous-body');
      await expectLater(request.close().timeout(const Duration(seconds: 2)),
          throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
      expect(hits, 1);
      expect(body, 'synthetic-ambiguous-body');
    } finally {
      client.close(force: true);
      for (final attempt in attempts) {
        attempt.cancel();
      }
      await server.close(force: true);
    }
  });

  for (final operation in ['addStream', 'flush']) {
    test('destroy aborts a bound $operation before its producer closes',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final connected = Completer<void>();
      final peerClosed = Completer<void>();
      Socket? peer;
      server.listen((socket) {
        peer = socket;
        connected.complete();
        socket.listen((_) {}, onDone: () {
          if (!peerClosed.isCompleted) peerClosed.complete();
        }, onError: (Object _) {
          if (!peerClosed.isCompleted) peerClosed.complete();
        });
      });
      final attempt =
          ForumSocketAttempt(Uri.http('localhost:${server.port}', '/'));
      final sourceCancelled = Completer<void>();
      final producer = operation == 'addStream'
          ? StreamController<List<int>>(onCancel: () {
              if (!sourceCancelled.isCompleted) sourceCancelled.complete();
            })
          : null;
      try {
        final socket = await attempt.socket;
        await connected.future;
        final socketDone = socket.done.then((_) {}, onError: (Object _) {});
        final Future<void> pending;
        if (operation == 'addStream') {
          pending = socket.addStream(producer!.stream).then<void>((_) {});
        } else {
          socket.add([1, 2, 3]);
          pending = socket.flush();
        }
        final failed = expectLater(pending, throwsA(isA<SocketException>()));
        expect(socket.destroy, returnsNormally);
        await failed.timeout(const Duration(seconds: 1));
        await peerClosed.future.timeout(const Duration(seconds: 1));
        await socketDone.timeout(const Duration(seconds: 1));
        if (operation == 'addStream')
          await sourceCancelled.future.timeout(const Duration(seconds: 1));
        // The source is deliberately still open until all abort assertions pass.
        if (producer != null) expect(producer.isClosed, isFalse);
      } finally {
        await producer?.close();
        attempt.cancel();
        peer?.destroy();
        await server.close();
      }
    });
  }

  test('raw TLS validates the original hostname, not the selected IP',
      () async {
    final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4, 0, serverContext());
    var requests = 0;
    server.listen((request) {
      requests++;
      request.response.close();
    }, onError: (Object _) {});
    final attempt = ForumSocketAttempt(
        Uri.https('wrong.fixture.invalid:${server.port}', '/'),
        address: InternetAddress.loopbackIPv4,
        context: trust());
    try {
      await expectLater(attempt.socket, throwsA(isA<HandshakeException>()));
      expect(requests, 0);
    } finally {
      attempt.cancel();
      await server.close(force: true);
    }
  });

  for (final cancelBy in ['cancel', 'deadline']) {
    test('raw TLS $cancelBy closes the actual blackhole peer before teardown',
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
      final attempt = ForumSocketAttempt(
          Uri.https('localhost:${server.port}', '/'),
          address: InternetAddress.loopbackIPv4,
          timeout: cancelBy == 'deadline'
              ? const Duration(milliseconds: 300)
              : const Duration(seconds: 5));
      final failure =
          expectLater(attempt.socket, throwsA(isA<SocketException>()));
      try {
        await hello.future.timeout(const Duration(seconds: 1));
        if (cancelBy == 'cancel') attempt.cancel();
        await failure.timeout(const Duration(seconds: 1));
        await closed.future.timeout(const Duration(seconds: 1));
      } finally {
        attempt.cancel();
        peer?.destroy();
        await server.close();
      }
    });
  }
}
