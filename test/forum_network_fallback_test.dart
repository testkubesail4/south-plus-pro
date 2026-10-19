import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

final class _RealIo extends IOOverrides {}

class _SocketRoutes {
  final real = _RealIo();
  final attempts = <String>[];
  int cancels = 0;
  final systemError = const SocketException('fixture system connection failed');
  bool rejectSystem = false;

  Future<ConnectionTask<Socket>> start(dynamic host, int port,
      {dynamic sourceAddress, int sourcePort = 0}) async {
    final name = host is InternetAddress ? host.address : '$host';
    attempts.add(name);
    if (rejectSystem && name == 'localhost') {
      return ConnectionTask.fromSocket(
        Future<Socket>.delayed(Duration.zero, () => throw systemError),
        () => cancels++,
      );
    }
    final address = name == '203.0.113.2' || name == '127.0.0.2'
        ? '127.0.0.2'
        : '127.0.0.1';
    final task = await real.socketStartConnect(InternetAddress(address), port,
        sourceAddress: sourceAddress, sourcePort: sourcePort);
    return ConnectionTask.fromSocket(task.socket, () {
      cancels++;
      task.cancel();
    });
  }
}

class _DohOverrides extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      clients++ == 0 ? super.createHttpClient(context) : _DohClient();
}

class _DohClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async => _DohRequest();
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DohRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => _DohResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DohResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(utf8.encode(jsonEncode({
        'Answer': [
          {'type': 1, 'data': '203.0.113.1'},
          {'type': 1, 'data': '203.0.113.2'},
        ],
      }))).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Blackhole {
  _Blackhole(this.server) {
    server.listen((socket) {
      sockets.add(socket);
      subscription = socket.listen((chunk) {
        bytes.addAll(chunk);
        if (!hello.isCompleted) hello.complete();
      }, onDone: finish, onError: (Object _) => finish());
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
      secure = await SecureSocket.secureServer(sockets.single, context,
          bufferedData: List<int>.of(bytes));
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> withClient(int port, _SocketRoutes routes,
          Future<void> Function(HttpClient) action) =>
      IOOverrides.runZoned(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final client = createForumHttpClient(ForumNetworkConfig(
            site: ForumSite('localhost:$port'),
            dohEnabled: true,
            dohProvider: DohProvider.doh090227Sb,
            customDohUri: 'https://resolver-fixture.invalid/dns-query',
          ));
          try {
            await action(client);
          } finally {
            client.close(force: true);
          }
        }, _DohOverrides()),
        socketStartConnect: routes.start,
      );

  test('refused resolved address falls through to a working address', () async {
    final server = await HttpServer.bind(InternetAddress('127.0.0.2'), 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.write('fixture ok');
      request.response.close();
    });
    final routes = _SocketRoutes();
    await withClient(server.port, routes, (client) async {
      final response =
          await (await client.getUrl(Uri.http('localhost:${server.port}', '/')))
              .close();
      expect(await utf8.decoder.bind(response).join(), 'fixture ok');
    });
    expect(routes.attempts.take(2), ['203.0.113.1', '203.0.113.2']);
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
    final routes = _SocketRoutes();
    await withClient(good.port, routes, (client) async {
      final response =
          await (await client.getUrl(Uri.https('localhost:${good.port}', '/')))
              .close();
      expect(await utf8.decoder.bind(response).join(), 'fixture secure');
    });
    expect(routes.attempts.take(2), ['203.0.113.1', '203.0.113.2']);

    await withClient(good.port, _SocketRoutes(), (client) async {
      // Reach the TLS server so rejection proves a hostname mismatch, not a reset.
      await expectLater(client.getUrl(Uri.https('127.0.0.2:${good.port}', '/')),
          throwsA(isA<HandshakeException>()));
    });
  });

  test('all failed routes retain the original system error', () async {
    final reservation =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = reservation.port;
    await reservation.close();
    final routes = _SocketRoutes()..rejectSystem = true;
    await withClient(port, routes, (client) async {
      await expectLater(client.getUrl(Uri.http('localhost:$port', '/')),
          throwsA(same(routes.systemError)));
    });
    expect(routes.attempts, contains('localhost'));
  });

  for (final cancelBy in ['timeout', 'force close']) {
    test('$cancelBy ends a TLS blackhole promptly and destroys late sockets',
        () async {
      final hole =
          _Blackhole(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
      addTearDown(hole.dispose);
      final routes = _SocketRoutes();
      await withClient(hole.server.port, routes, (client) async {
        client.connectionTimeout = cancelBy == 'timeout'
            ? const Duration(milliseconds: 200)
            : const Duration(seconds: 2);
        final watch = Stopwatch()..start();
        final request =
            client.getUrl(Uri.https('localhost:${hole.server.port}', '/'));
        final rejected = expectLater(
            request.timeout(const Duration(seconds: 1)),
            throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
        await hole.hello.future.timeout(const Duration(seconds: 1));
        if (cancelBy == 'force close') client.close(force: true);
        await rejected;
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
        expect(routes.cancels, greaterThan(0));
        await hole.release(serverContext).timeout(const Duration(seconds: 1));
        await hole.closed.future.timeout(const Duration(seconds: 1));
      });
    });
  }
}
