import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_proxy_connection.dart';
import 'package:south_plus_rewrite/services/update_checker.dart';
import 'package:south_plus_rewrite/services/whats_link_preview_service.dart';

import 'support/forum_route_fixture.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ProxyFixture fixture;
  late Directory directory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = await _ProxyFixture.start();
    directory = await Directory.systemTemp.createTemp('proxy_fixture_');
  });
  tearDown(() async {
    selectProxyTestRoute(null);
    await fixture.close();
    await directory.delete(recursive: true);
  });

  test(
      'HTTP proxy routes API, attachment, image cache, private image and update clients',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    fixture.requireAuth = true;
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final proxy = ForumProxy(
            type: ForumProxyType.http,
            host: '127.0.0.1',
            port: fixture.proxy.port,
            username: 'fixture',
            password: 'synthetic-secret');
        selectProxyTestRoute(proxy);
        final client = _ForumClient(ForumNetworkConfig(
          site: const ForumSite('fixture.invalid'),
          mode: ForumNetworkMode.proxy,
          dohProvider: ForumNetworkConfig.defaultProvider,
          proxy: proxy,
        ));
        try {
          expect(
              await client.get('index.php').timeout(const Duration(seconds: 5)),
              'Fixture page');
          final attachment = await client
              .downloadAttachment('job.php?action=download&aid=900001',
                  directory: directory)
              .timeout(const Duration(seconds: 5));
          expect(await attachment.file.readAsBytes(),
              [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]);
        } finally {
          client.close(force: true);
        }
        final file = await ForumImageCache.manager
            .getSingleFile('https://fixture.invalid/public.png')
            .timeout(const Duration(seconds: 8));
        expect(await file.readAsBytes(), _png);
        final done = Completer<void>();
        final stream = const NetworkImage('https://fixture.invalid/private.png')
            .resolve(ImageConfiguration.empty);
        late ImageStreamListener listener;
        listener = ImageStreamListener((info, _) {
          expect(info.image.width, 1);
          stream.removeListener(listener);
          done.complete();
        }, onError: (Object error, StackTrace? stack) {
          done.completeError(error, stack);
        });
        stream.addListener(listener);
        await done.future.timeout(const Duration(seconds: 5));
        final update = await const UpdateChecker(repository: 'fixture/app')
            .check(currentVersion: '0.0.1');
        expect(update.release.version, '0.0.2');
        final preview = await const WhatsLinkPreviewService()
            .fetch('https://fixture.invalid/resource');
        expect(preview.name, 'Fixture resource');
      }, _TrustedOverrides(fixture.trust));
      expect(
          fixture.proxyHits.map((hit) => hit.$1),
          containsAll([
            'fixture.invalid:80',
            'fixture.invalid:443',
            'api.github.com:443',
            'whatslink.info:443',
          ]));
      expect(
          fixture.originHits,
          containsAll([
            '/public.png',
            '/private.png',
            '/repos/fixture/app/releases/latest',
            '/api/v1/link'
          ]));
      expect(fixture.originAuth, everyElement(isNull));
      expect(
          fixture.proxyHits.map((hit) => hit.$2),
          everyElement(
              'Basic ${base64Encode(utf8.encode('fixture:synthetic-secret'))}'));
    } finally {
      await ForumImageCache.manager.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('route changes replace pooled connections and preserve client settings',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient()
        ..userAgent = 'Fixture agent'
        ..connectionTimeout = const Duration(seconds: 2);
      final uri = Uri.parse('http://localhost:${fixture.direct.port}/switch');
      Future<void> request() async {
        final response = await (await client.getUrl(uri)).close();
        await response.drain<void>();
      }

      try {
        await request();
        selectProxyTestRoute(ForumProxy(
            type: ForumProxyType.http,
            host: '127.0.0.1',
            port: fixture.proxy.port));
        await request();
        expect(fixture.directPorts, hasLength(2));
        expect(fixture.proxyHits.single.$1, 'localhost:${fixture.direct.port}');
        selectProxyTestRoute(null);
        expect(client.userAgent, 'Fixture agent');
        expect(client.connectionTimeout, const Duration(seconds: 2));
        await request();
        expect(fixture.directPorts.toSet(), hasLength(3));
      } finally {
        client.close(force: true);
      }
    }, ForumHttpOverrides());
  });

  test('proxy rejects wrong credentials without reaching the origin', () async {
    fixture.requireAuth = true;
    final client = HttpOverrides.runWithHttpOverrides(
        () => createForumHttpClient(ForumNetworkConfig(
              site: const ForumSite('fixture.invalid'),
              mode: ForumNetworkMode.proxy,
              dohProvider: ForumNetworkConfig.defaultProvider,
              proxy: ForumProxy(
                  type: ForumProxyType.http,
                  host: '127.0.0.1',
                  port: fixture.proxy.port,
                  username: 'fixture',
                  password: 'wrong'),
            )),
        ForumHttpOverrides());
    try {
      await expectLater(
          client.getUrl(Uri.parse('http://fixture.invalid/blocked')),
          throwsA(isA<SocketException>()
              .having((e) => e.message, 'message', '代理认证失败')));
      expect(fixture.directPorts, isEmpty);
    } finally {
      client.close(force: true);
    }
  });

  test('HTTPS redirects keep credentials confined to each proxy CONNECT',
      () async {
    fixture.requireAuth = true;
    await HttpOverrides.runWithHttpOverrides(() async {
      selectProxyTestRoute(ForumProxy(
          type: ForumProxyType.http,
          host: '127.0.0.1',
          port: fixture.proxy.port,
          username: 'fixture',
          password: 'synthetic-secret'));
      final client = HttpClient();
      try {
        final response = await (await client
                .getUrl(Uri.parse('https://fixture.invalid/redirect')))
            .close();
        await response.drain<void>();
        expect(response.statusCode, 200);
        expect(fixture.originHits, ['/redirect', '/final']);
        expect(fixture.originAuth, everyElement(isNull));
        expect(fixture.proxyHits.map((hit) => hit.$1),
            ['fixture.invalid:443', 'whatslink.info:443']);
      } finally {
        client.close(force: true);
      }
    }, _TrustedOverrides(fixture.trust));
  });

  test('cancel interrupts a stalled proxy handshake and closes its socket',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    final closed = Completer<void>();
    Socket? accepted;
    server.listen((socket) {
      accepted = socket;
      socket.listen((_) {
        if (!received.isCompleted) received.complete();
      }, onDone: () {
        if (!closed.isCompleted) closed.complete();
      });
    });
    try {
      final task = await connectForumProxy(
          ForumProxy(
              type: ForumProxyType.http, host: '127.0.0.1', port: server.port),
          Uri.parse('https://fixture.invalid/'));
      final failed = expectLater(task.socket, throwsA(isA<SocketException>()));
      await received.future.timeout(const Duration(seconds: 3));
      task.cancel();
      await failed;
      await closed.future.timeout(const Duration(seconds: 3));
    } finally {
      accepted?.destroy();
      await server.close();
    }
  });

  test('HTTPS proxy encrypts CONNECT and tunnels HTTP and HTTPS origins',
      () async {
    await fixture.close();
    fixture = await _ProxyFixture.start(secureProxy: true);
    fixture.requireAuth = true;
    await HttpOverrides.runWithHttpOverrides(() async {
      selectProxyTestRoute(ForumProxy(
          type: ForumProxyType.https,
          host: 'localhost',
          port: fixture.proxy.port,
          username: 'fixture',
          password: 'synthetic-secret'));
      final client = HttpClient();
      try {
        for (final url in [
          'http://fixture.invalid/index.php',
          'https://api.github.com/final'
        ]) {
          final response = await (await client.getUrl(Uri.parse(url))).close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        }
        expect(fixture.proxyHits.map((hit) => hit.$1),
            ['fixture.invalid:80', 'api.github.com:443']);
        expect(fixture.originAuth, everyElement(isNull));
      } finally {
        client.close(force: true);
      }
    }, _TrustedOverrides(fixture.trust));
  });

  test('HTTPS proxy certificate hostname mismatch is never accepted', () async {
    await fixture.close();
    fixture = await _ProxyFixture.start(secureProxy: true);
    await HttpOverrides.runWithHttpOverrides(() async {
      selectProxyTestRoute(ForumProxy(
          type: ForumProxyType.https,
          host: '127.0.0.1',
          port: fixture.proxy.port));
      final client = HttpClient();
      try {
        await expectLater(
            client.getUrl(Uri.parse('https://fixture.invalid/blocked')),
            throwsA(isA<HandshakeException>()));
        expect(fixture.proxyHits, isEmpty);
        expect(fixture.originHits, isEmpty);
      } finally {
        client.close(force: true);
      }
    }, _TrustedOverrides(fixture.trust));
  });

  test('unreachable proxy never falls back to a reachable origin', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();
    await HttpOverrides.runWithHttpOverrides(() async {
      selectProxyTestRoute(
          ForumProxy(type: ForumProxyType.http, host: '127.0.0.1', port: port));
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 1);
      try {
        await expectLater(
            client.getUrl(
                Uri.parse('http://127.0.0.1:${fixture.direct.port}/blocked')),
            throwsA(isA<SocketException>()));
        expect(fixture.directPorts, isEmpty);
      } finally {
        client.close(force: true);
      }
    }, ForumHttpOverrides());
  });
}

class _ForumClient extends ForumClient {
  _ForumClient(ForumNetworkConfig config)
      : super(config: config, delay: (_) async {});
  @override
  Uri get baseUri => Uri.http('fixture.invalid', '/');
}

class _TrustedOverrides extends ForumHttpOverrides {
  _TrustedOverrides(this.trust);
  final SecurityContext trust;
  @override
  HttpClient createUnroutedClient(SecurityContext? context) =>
      super.createUnroutedClient(context ?? trust);
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? trust);
}

class _ProxyFixture {
  _ProxyFixture(this.proxy, this.origin, this.direct, this.trust);
  final HttpServer proxy;
  final HttpServer origin;
  final HttpServer direct;
  final SecurityContext trust;
  final proxyHits = <(String, String?)>[];
  final originHits = <String>[];
  final originAuth = <String?>[];
  final directPorts = <int>[];
  bool requireAuth = false;
  final sockets = <Socket>[];

  static Future<_ProxyFixture> start({bool secureProxy = false}) async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/proxy_fixture_cert.pem')
      ..usePrivateKey('test/support/proxy_fixture_key.pem');
    final trust = SecurityContext()
      ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');
    final fixture = _ProxyFixture(
      secureProxy
          ? await HttpServer.bindSecure(
              InternetAddress.loopbackIPv4, 0, context)
          : await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context),
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      trust,
    );
    fixture.origin.listen((request) async {
      fixture.originHits.add(request.uri.path);
      fixture.originAuth
          .add(request.headers.value(HttpHeaders.proxyAuthorizationHeader));
      if (request.uri.path == '/redirect') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers
            .set(HttpHeaders.locationHeader, 'https://whatslink.info/final');
      } else if (request.uri.path.endsWith('.png')) {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(_png);
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(request.uri.path == '/api/v1/link'
            ? {'name': 'Fixture resource'}
            : {
                'tag_name': 'v0.0.2',
                'html_url': 'https://fixture.invalid/release',
                'assets': []
              }));
      }
      await request.response.close();
    });
    fixture.proxy.listen((request) async {
      fixture.proxyHits.add((
        request.method == 'CONNECT' ? '${request.uri}' : request.uri.path,
        request.headers.value(HttpHeaders.proxyAuthorizationHeader)
      ));
      if (fixture.requireAuth &&
          request.headers.value(HttpHeaders.proxyAuthorizationHeader) !=
              'Basic ${base64Encode(utf8.encode('fixture:synthetic-secret'))}') {
        request.response.statusCode = HttpStatus.proxyAuthenticationRequired;
        request.response.headers
            .set(HttpHeaders.proxyAuthenticateHeader, 'Basic realm="fixture"');
        await request.response.close();
        return;
      }
      if (request.method == 'CONNECT') {
        request.response.contentLength = 0;
        final downstream = await request.response.detachSocket();
        final upstream = await Socket.connect(
            InternetAddress.loopbackIPv4,
            request.headers.port == 443
                ? fixture.origin.port
                : fixture.direct.port);
        fixture.sockets.addAll([downstream, upstream]);
        downstream.listen(upstream.add,
            onDone: upstream.destroy,
            onError: (Object _) => upstream.destroy());
        upstream.listen(downstream.add,
            onDone: downstream.destroy,
            onError: (Object _) => downstream.destroy());
      } else {
        if (request.uri.path == '/job.php') {
          request.response.headers.contentType = ContentType.binary;
          request.response.add([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]);
        } else {
          request.response.write('Fixture page');
        }
        await request.response.close();
      }
    });
    fixture.direct.listen((request) async {
      fixture.directPorts.add(request.connectionInfo!.remotePort);
      fixture.originAuth
          .add(request.headers.value(HttpHeaders.proxyAuthorizationHeader));
      if (request.uri.path == '/job.php') {
        request.response.headers.contentType = ContentType.binary;
        request.response.add([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]);
      } else {
        request.response.write('Fixture page');
      }
      await request.response.close();
    });
    return fixture;
  }

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await Future.wait([
      proxy.close(force: true),
      origin.close(force: true),
      direct.close(force: true)
    ]);
  }
}
