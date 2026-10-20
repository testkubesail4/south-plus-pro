import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late List<String> responseCookies;
  late List<(String?, String, String?)> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    responseCookies = [];
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add((
        request.headers.host,
        request.uri.path,
        request.headers.value(HttpHeaders.cookieHeader)
      ));
      if (request.uri.path.endsWith('/seed')) {
        for (final cookie in responseCookies) {
          request.response.headers.add(HttpHeaders.setCookieHeader, cookie);
        }
      }
      request.response.write('fixture response');
      await request.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  ForumClient client(String host) {
    final transport =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp())
          ..connectionFactory = (uri, proxyHost, proxyPort) =>
              Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
    final client = _OriginClient(host, transport);
    addTearDown(() {
      client.close(force: true);
      transport.close(force: true);
    });
    return client;
  }

  test('host-only cookie survives reload but stays at its exact origin',
      () async {
    responseCookies = ['session=synthetic-origin; Path=/'];
    await client('forum.fixture.invalid').getOnce('/seed');
    final restored = client('forum.fixture.invalid');
    await restored.getOnce('/check');
    expect(requests.last.$3, 'session=synthetic-origin');
    for (final host in [
      'child.forum.fixture.invalid',
      'sibling.fixture.invalid',
      'other.invalid'
    ]) {
      await restored.getOnce('http://$host/check');
      expect(requests.last.$3, isNull, reason: host);
    }
  });

  test('explicit leading-dot domain reaches apex and children, not lookalikes',
      () async {
    responseCookies = [
      'session=synthetic-domain; Domain=.fixture.invalid; Path=/'
    ];
    final origin = client('fixture.invalid');
    await origin.getOnce('/seed');
    for (final host in ['fixture.invalid', 'child.fixture.invalid']) {
      await origin.getOnce('http://$host/check');
      expect(requests.last.$3, 'session=synthetic-domain', reason: host);
    }
    for (final host in ['notfixture.invalid', 'fixture.invalid.evil.invalid']) {
      await origin.getOnce('http://$host/check');
      expect(requests.last.$3, isNull, reason: host);
    }
  });

  test('Secure cookie survives reload over HTTPS but never travels over HTTP',
      () async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/proxy_fixture_cert.pem')
      ..usePrivateKey('test/support/proxy_fixture_key.pem');
    final trust = SecurityContext()
      ..setTrustedCertificates('test/support/proxy_fixture_cert.pem');
    final secure =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    addTearDown(() => secure.close(force: true));
    secure.listen((request) async {
      if (request.uri.path == '/seed') {
        request.response.headers.add(HttpHeaders.setCookieHeader,
            'session=synthetic-secure; Secure; Path=/');
      }
      request.response.write(
          request.headers.value(HttpHeaders.cookieHeader) ?? 'no cookie');
      await request.response.close();
    });
    final transport = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(context: trust), _RealHttp());
    addTearDown(() => transport.close(force: true));
    final origin =
        _OriginClient('localhost:${secure.port}', transport, scheme: 'https');
    await origin.getOnce('/seed');
    final restored =
        _OriginClient('localhost:${secure.port}', transport, scheme: 'https');
    expect(await restored.getOnce('/check'), 'session=synthetic-secure');
    await restored.getOnce('http://localhost:${server.port}/check');
    expect(requests.last.$3, isNull);
  });

  test('cookie path matches a slash boundary, not a textual prefix', () async {
    responseCookies = ['session=synthetic-path; Path=/foo'];
    final origin = client('forum.fixture.invalid');
    await origin.getOnce('/seed');
    for (final path in ['/foo', '/foo/bar']) {
      await origin.getOnce(path);
      expect(requests.last.$3, 'session=synthetic-path', reason: path);
    }
    for (final path in ['/foobar', '/fo', '/']) {
      await origin.getOnce(path);
      expect(requests.last.$3, isNull, reason: path);
    }
  });

  test('absent Path defaults to the response directory', () async {
    responseCookies = ['session=synthetic-directory'];
    final origin = client('forum.fixture.invalid');
    await origin.getOnce('/account/seed');
    await origin.getOnce('/account/check');
    expect(requests.last.$3, 'session=synthetic-directory');
    await origin.getOnce('/elsewhere/check');
    expect(requests.last.$3, isNull);
  });

  for (final domain in ['other.invalid', 'invalid', '.invalid']) {
    test('origin cannot inject a cookie for Domain=$domain', () async {
      responseCookies = ['session=synthetic-injection; Domain=$domain; Path=/'];
      final origin = client('forum.fixture.invalid');
      await origin.getOnce('/seed');
      for (final host in ['other.invalid', 'forum.fixture.invalid']) {
        await origin.getOnce('http://$host/check');
        expect(requests.last.$3, isNull, reason: 'same client: $host');
      }
      await client('other.invalid').getOnce('/check');
      expect(requests.last.$3, isNull, reason: 'reloaded client');
    });
  }

  test('custom site cannot plant a cookie on a multi-label public suffix',
      () async {
    responseCookies = ['session=synthetic-suffix; Domain=co.uk; Path=/'];
    final origin = client('forum.example.co.uk');
    await origin.getOnce('/seed');
    await origin.getOnce('http://other.co.uk/check');
    expect(requests.last.$3, isNull, reason: 'same client');
    await client('other.co.uk').getOnce('/check');
    expect(requests.last.$3, isNull, reason: 'reloaded client');
  });

  test('malformed attributes cannot downgrade an invalid Domain to a session',
      () async {
    responseCookies = [
      'session=synthetic-malformed; Domain=other.invalid; Max-Age=not-a-number'
    ];
    final origin = client('forum.fixture.invalid');
    await origin.getOnce('/seed');
    await origin.getOnce('/check');
    expect(requests.last.$3, isNull);
    await origin.getOnce('http://other.invalid/check');
    expect(requests.last.$3, isNull);
  });

  test('switching independent site clients retains only each site cookies',
      () async {
    responseCookies = ['first=synthetic-first; Path=/'];
    await client('first.fixture.invalid').getOnce('/seed');
    responseCookies = ['second=synthetic-second; Path=/'];
    await client('second.fixture.invalid').getOnce('/seed');
    await client('first.fixture.invalid').getOnce('/check');
    expect(requests.last.$3, 'first=synthetic-first');
    await client('second.fixture.invalid').getOnce('/check');
    expect(requests.last.$3, 'second=synthetic-second');
  });

  for (final domain in [null, 'fixture.invalid']) {
    test('legacy cookie with domain=$domain fails closed on ambiguous scope',
        () async {
      SharedPreferences.setMockInitialValues({
        'forum_session_cookies_v1': jsonEncode({
          'legacy': {
            'name': 'legacy',
            'value': 'synthetic-legacy',
            if (domain != null) 'domain': domain,
            'path': '/',
          }
        })
      });
      await client('child.fixture.invalid').getOnce('/check');
      expect(requests.last.$3, isNull);
      if (domain != null) {
        await client(domain).getOnce('/check');
        expect(requests.last.$3, 'legacy=synthetic-legacy');
      }
    });
  }
}

class _RealHttp extends HttpOverrides {}

class _OriginClient extends ForumClient {
  _OriginClient(this.host, HttpClient transport, {this.scheme = 'http'})
      : super(httpClient: transport, delay: (_) async {});
  final String host;
  final String scheme;
  @override
  Uri get baseUri =>
      scheme == 'https' ? Uri.https(host, '/') : Uri.http(host, '/');
}
