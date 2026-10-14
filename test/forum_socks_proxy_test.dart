import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_proxy_connection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final authenticated in [false, true]) {
    test(
        'SOCKS5 ${authenticated ? 'authenticated' : 'anonymous'} CONNECT resolves target at proxy',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final served = Completer<void>();
      Socket? peer;
      server.listen((socket) async {
        peer = socket;
        try {
          final reader = _Bytes(socket);
          expect(await reader.read(2), [5, authenticated ? 2 : 1]);
          expect(await reader.read(authenticated ? 2 : 1),
              authenticated ? [0, 2] : [0]);
          socket.add([5]);
          await socket.flush();
          socket.add([authenticated ? 2 : 0]);
          if (authenticated) {
            expect(await reader.read(1), [1]);
            final userLength = (await reader.read(1)).single;
            expect(utf8.decode(await reader.read(userLength)), 'fixture');
            final passwordLength = (await reader.read(1)).single;
            expect(utf8.decode(await reader.read(passwordLength)),
                'synthetic-secret');
            socket.add([1, 0]);
          }
          expect(await reader.read(4), [5, 1, 0, 3]);
          final hostLength = (await reader.read(1)).single;
          expect(utf8.decode(await reader.read(hostLength)),
              'unresolvable.fixture.invalid');
          expect(await reader.read(2), [0, 80]);
          socket.add([5, 0, 0, authenticated ? 4 : 1]);
          await socket.flush();
          socket.add([...List.filled(authenticated ? 16 : 4, 0), 0, 80]);
          final request = await reader.header();
          expect(request, startsWith('GET /fixture HTTP/1.1'));
          expect(request.toLowerCase(), isNot(contains('proxy-authorization')));
          socket.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK');
          await socket.flush();
          served.complete();
        } catch (e, s) {
          served.completeError(e, s);
        }
      });
      final client = HttpOverrides.runWithHttpOverrides(
          () => createForumHttpClient(ForumNetworkConfig(
                site: const ForumSite('fixture.invalid'),
                dohEnabled: true,
                dohProvider: ForumNetworkConfig.defaultProvider,
                proxy: ForumProxy(
                    type: ForumProxyType.socks5,
                    host: '127.0.0.1',
                    port: server.port,
                    username: authenticated ? 'fixture' : null,
                    password: authenticated ? 'synthetic-secret' : null),
              )),
          ForumHttpOverrides());
      try {
        final response = await (await client.getUrl(
                Uri.parse('http://unresolvable.fixture.invalid/fixture')))
            .close();
        expect(await utf8.decoder.bind(response).join(), 'OK');
        await served.future;
      } finally {
        client.close(force: true);
        peer?.destroy();
        await server.close();
      }
    });
  }

  for (final trustedHost in [true, false]) {
    test('SOCKS5 TLS verifies origin hostname (valid=$trustedHost)', () async {
      final context = SecurityContext()
        ..useCertificateChain('test/support/proxy_fixture_cert.pem')
        ..usePrivateKey('test/support/proxy_fixture_key.pem');
      final trust = SecurityContext()
        ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      Socket? peer;
      final served = Completer<void>();
      server.listen((socket) async {
        peer = socket;
        try {
          final reader = _Bytes(socket);
          await reader.read(3);
          socket.add([5, 0]);
          final header = await reader.read(5);
          await reader.read(header[4] + 2);
          socket.add([5, 0, 0, 3, 1, 120, 0, 0]);
          await socket.flush();
          final secure = await SecureSocket.secureServer(socket, context);
          peer = secure;
          await _Bytes(secure).header();
          secure.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK');
          await secure.flush();
          await secure.close();
          served.complete();
        } catch (e, s) {
          if (trustedHost) {
            served.completeError(e, s);
          } else {
            served.complete();
          }
        }
      });
      try {
        final task = await connectForumProxy(
            ForumProxy(
                type: ForumProxyType.socks5,
                host: '127.0.0.1',
                port: server.port),
            Uri.https(
                trustedHost ? 'fixture.invalid' : 'wrong.fixture.invalid', '/'),
            context: trust);
        if (trustedHost) {
          final socket = await task.socket;
          socket.write('GET / HTTP/1.1\r\nHost: fixture.invalid\r\n\r\n');
          expect(await utf8.decoder.bind(socket).join(), endsWith('OK'));
        } else {
          await expectLater(task.socket, throwsA(isA<HandshakeException>()));
        }
        await served.future.timeout(const Duration(seconds: 3));
      } finally {
        peer?.destroy();
        await server.close();
      }
    });
  }

  for (final reply in [
    [4, 0],
    [5, 255],
    [5, 3],
    [5, 2]
  ]) {
    test('SOCKS5 rejects unsolicited method reply $reply', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      Socket? peer;
      server.listen((socket) {
        peer = socket;
        var replied = false;
        socket.listen((_) {
          if (!replied) {
            replied = true;
            socket.add(reply);
          }
        });
      });
      try {
        final task = await connectForumProxy(
            ForumProxy(
                type: ForumProxyType.socks5,
                host: '127.0.0.1',
                port: server.port),
            Uri.parse('http://fixture.invalid/'));
        await expectLater(task.socket.timeout(const Duration(seconds: 3)),
            throwsA(isA<SocketException>()));
      } finally {
        peer?.destroy();
        await server.close();
      }
    });
  }

  for (final reply in [
    [4, 0, 0, 1, 127, 0, 0, 1, 0, 80],
    [5, 5, 0, 1, 127, 0, 0, 1, 0, 80],
    [5, 0, 1, 1, 127, 0, 0, 1, 0, 80],
    [5, 0, 0, 2],
    [5, 0, 0, 3, 0],
    [5, 0, 0],
  ]) {
    test('SOCKS5 rejects invalid or truncated CONNECT reply $reply', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      Socket? peer;
      final received = Completer<void>();
      server.listen((socket) async {
        peer = socket;
        final reader = _Bytes(socket);
        await reader.read(3);
        socket.add([5, 0]);
        final header = await reader.read(5);
        await reader.read(header[4] + 2);
        received.complete();
        socket.add(reply);
        await socket.flush();
        socket.destroy();
      });
      try {
        final task = await connectForumProxy(
            ForumProxy(
                type: ForumProxyType.socks5,
                host: '127.0.0.1',
                port: server.port),
            Uri.parse('http://fixture.invalid/'));
        await expectLater(task.socket.timeout(const Duration(seconds: 3)),
            throwsA(isA<SocketException>()));
        await received.future;
      } finally {
        peer?.destroy();
        await server.close();
      }
    });
  }

  test('SOCKS5 bad password is rejected before CONNECT', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? peer;
    final received = Completer<void>();
    server.listen((socket) async {
      peer = socket;
      final reader = _Bytes(socket);
      await reader.read(4);
      socket.add([5, 2]);
      await reader.read(1);
      await reader.read((await reader.read(1)).single);
      await reader.read((await reader.read(1)).single);
      received.complete();
      socket.add([1, 1]);
    });
    try {
      final task = await connectForumProxy(
          ForumProxy(
              type: ForumProxyType.socks5,
              host: '127.0.0.1',
              port: server.port,
              username: 'fixture',
              password: 'wrong'),
          Uri.parse('http://fixture.invalid/'));
      await expectLater(
          task.socket,
          throwsA(isA<SocketException>()
              .having((e) => e.message, 'message', '代理认证失败')));
      await received.future;
    } finally {
      peer?.destroy();
      await server.close();
    }
  });

  test('SOCKS5 cancellation closes socket while proxy stalls negotiation',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    final closed = Completer<void>();
    Socket? peer;
    server.listen((socket) {
      peer = socket;
      socket.listen((_) {
        if (!received.isCompleted) received.complete();
      }, onDone: closed.complete);
    });
    try {
      final task = await connectForumProxy(
          ForumProxy(
              type: ForumProxyType.socks5,
              host: '127.0.0.1',
              port: server.port),
          Uri.parse('http://fixture.invalid/'));
      final failed = expectLater(task.socket, throwsA(isA<SocketException>()));
      await received.future.timeout(const Duration(seconds: 3));
      task.cancel();
      await failed;
      await closed.future.timeout(const Duration(seconds: 3));
    } finally {
      peer?.destroy();
      await server.close();
    }
  });
}

class _Bytes {
  _Bytes(Stream<List<int>> stream) : chunks = StreamIterator(stream);
  final StreamIterator<List<int>> chunks;
  final bytes = <int>[];
  Future<List<int>> read(int count) async {
    while (bytes.length < count) {
      if (!await chunks.moveNext())
        throw StateError('Truncated fixture request');
      bytes.addAll(chunks.current);
    }
    final result = bytes.take(count).toList();
    bytes.removeRange(0, count);
    return result;
  }

  Future<String> header() async {
    var header = '';
    while (!header.endsWith('\r\n\r\n')) {
      header += latin1.decode(await read(1));
    }
    return header;
  }
}
