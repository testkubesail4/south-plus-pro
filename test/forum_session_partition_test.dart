import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('logging out one origin preserves another and blocks legacy re-import',
      () async {
    final firstOrigin = Uri.https('first.fixture.invalid', '/');
    final secondOrigin = Uri.https('second.fixture.invalid', '/');
    SharedPreferences.setMockInitialValues({
      'forum_session_cookies_v1': jsonEncode({
        'legacy': ForumStoredCookie.session(
                name: 'winduser',
                value: 'synthetic-legacy',
                origin: firstOrigin)
            .toJson(),
      })
    });
    final first = ForumSessionStore(origin: firstOrigin);
    final second = ForumSessionStore(origin: secondOrigin);
    expect((await first.loadCookies()).values.single.value, 'synthetic-legacy');
    await second.saveCookies({
      'second': ForumStoredCookie.session(
          name: 'winduser', value: 'synthetic-second', origin: secondOrigin)
    });
    await first.clear();
    expect(await ForumSessionStore(origin: firstOrigin).loadCookies(), isEmpty);
    expect(
        (await ForumSessionStore(origin: secondOrigin).loadCookies())
            .values
            .single
            .value,
        'synthetic-second');
  });

  test(
      'a guest origin restores without spending or clearing another origin auth',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) {
      hits++;
      if (request.uri.path == '/seed')
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=synthetic-first; Path=/');
      request.response
          .write(request.headers.value(HttpHeaders.cookieHeader) ?? 'guest');
      request.response.close();
    });
    final transport = ForumHttpOverrides().createUnroutedClient(null)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = (uri, _, __) =>
          Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
    try {
      final first = _OriginClient('first.fixture.invalid', transport);
      await first.getOnce('/seed');
      expect(first.isLoggedIn, isTrue);
      final second = _OriginClient('second.fixture.invalid', transport);
      final repository = ForumRepository(client: second);
      expect(await repository.restoreSession(), isFalse);
      expect(hits, 1, reason: 'guest origin has no credentials to verify');
      final restoredFirst = _OriginClient('first.fixture.invalid', transport);
      expect(await restoredFirst.getOnce('/echo'), 'winduser=synthetic-first');
      expect(restoredFirst.isLoggedIn, isTrue);
      await second.clearSession();
      expect(first.isCredentialCurrent(first.credentialGeneration), isTrue,
          reason: 'another origin logout cannot revoke this origin epoch');
    } finally {
      transport.close(force: true);
      await server.close(force: true);
      ForumHttpRouting.updateConfig(const ForumNetworkConfig(
          site: ForumNetworkConfig.defaultSite, mode: ForumNetworkMode.native));
    }
  });

  test('bounded cookie lifetime handles extreme Max-Age without overflow', () {
    final cookie = Cookie('session', 'synthetic')
      ..maxAge = -9223372036854775807;
    final stored =
        ForumStoredCookie.fromCookie(cookie, Uri.https('fixture.invalid', '/'));
    expect(stored.isExpired, isTrue);
  });
}

class _OriginClient extends ForumClient {
  _OriginClient(this.host, HttpClient transport)
      : super(httpClient: transport, delay: (_) async {});
  final String host;
  @override
  Uri get baseUri => Uri.http(host, '/');
}
