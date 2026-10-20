import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final type in ForumProxyType.values) {
    test('${type.name} proxy persists dormant optimization without using it', () async {
      final proxy = ForumProxy(
          type: type,
          host: 'proxy.fixture.invalid',
          port: 1080,
          username: 'fixture',
          password: 'synthetic-secret');
      final config = ForumNetworkConfig(
        site: ForumNetworkConfig.defaultSite,
        dohEnabled: true,
        dohProvider: ForumNetworkConfig.defaultProvider,
        hostAddresses: const {'south-plus.net': ['104.21.43.10']},
        customDohUri: 'https://dns.fixture.invalid/query',
        proxy: proxy,
      );
      expect(config.dohEnabled, isFalse);
      expect(config.mode, ForumNetworkMode.proxy);
      expect(config.hostAddresses['south-plus.net'], ['104.21.43.10']);
      expect(config.customDohUri, 'https://dns.fixture.invalid/query');
      await ForumNetworkSettings.save(config);
      expect(await ForumNetworkSettings.load(), config);
      expect(config.copyWith(mode: ForumNetworkMode.optimized).proxy, proxy);
      expect(config.copyWith(clearProxy: true).proxy, isNull);
      expect(proxy.toString(), isNot(contains('synthetic-secret')));
      expect(proxy.toString(), isNot(contains('fixture@')));
    });
  }

  test('proxy rejects routes and invalid ports at the settings boundary', () {
    for (final host in [
      '',
      'http://proxy.invalid',
      'user@proxy.invalid',
      'proxy.invalid/path',
      'proxy.invalid; DIRECT'
    ]) {
      expect(
          () => ForumProxy(type: ForumProxyType.http, host: host, port: 1080),
          throwsFormatException);
    }
    for (final port in [0, -1, 65536]) {
      expect(
          () => ForumProxy(
              type: ForumProxyType.http, host: 'proxy.invalid', port: port),
          throwsFormatException);
    }
    expect(ForumProxy(type: ForumProxyType.http, host: '::1', port: 8080).host,
        '::1');
    expect(
        () => ForumProxy(
            type: ForumProxyType.socks5,
            host: 'proxy.invalid',
            port: 1080,
            username: 'fixture',
            password: ''),
        throwsFormatException);
    expect(
        () => ForumProxy(
            type: ForumProxyType.socks5,
            host: 'proxy.invalid',
            port: 1080,
            username: 'fixture',
            password: 'x' * 256),
        throwsFormatException);
  });

  test(
      'corrupt persisted proxy fails closed instead of selecting direct routing',
      () async {
    SharedPreferences.setMockInitialValues({
      'forum_network_proxy_v1': '{"password":"synthetic-secret",',
    });
    await expectLater(
      ForumNetworkSettings.load(),
      throwsA(isA<FormatException>().having(
        (error) => error.toString(),
        'redacted error',
        isNot(contains('synthetic-secret')),
      )),
    );
  });

  test(
      'proxy repair overwrites corrupt settings and explicit disable stays direct',
      () async {
    SharedPreferences.setMockInitialValues(
        {'forum_network_proxy_v1': '{invalid'});
    final proxy = ForumProxy(
        type: ForumProxyType.http, host: 'proxy.invalid', port: 8080);
    await ForumNetworkSettings.saveProxy(proxy);
    final loaded = await ForumNetworkSettings.load();
    expect(loaded.proxy, proxy);
    expect(loaded.dohEnabled, isFalse);
    await ForumNetworkSettings.disableProxy();
    final direct = await ForumNetworkSettings.load();
    expect(direct.proxy, isNull);
    expect(direct.dohEnabled, isFalse);
    expect(direct.fixedAddress, isNull);
    expect(
        ForumProxy.validationError(
            type: ForumProxyType.http, host: 'proxy.invalid', port: 0),
        isNotNull);
  });

}
