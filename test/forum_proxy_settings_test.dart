import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final type in ForumProxyType.values) {
    test('${type.name} proxy persists and excludes optimization', () async {
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
        fixedAddress: '203.0.113.7',
        customDohUri: 'https://dns.fixture.invalid/query',
        proxy: proxy,
      );
      expect(config.dohEnabled, isFalse);
      expect(config.fixedAddress, isNull);
      expect(config.customDohUri, isNull);
      await ForumNetworkSettings.save(config);
      expect(await ForumNetworkSettings.load(), config);
      expect(config.copyWith(dohEnabled: true).proxy, isNull);
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

  testWidgets('corrupt proxy startup never offers guest direct continuation',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'forum_network_proxy_v1': '{invalid'});
    await tester.pumpWidget(const MaterialApp(home: SessionGate()));
    await tester.pumpAndSettle();
    expect(find.textContaining('代理设置无效'), findsOneWidget);
    expect(find.text('先浏览公开内容'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });

  for (final choice in ForumNetworkSetupChoice.values) {
    test('onboarding persists ${choice.name} choice and resets it', () async {
      await ForumNetworkSetupStore.markCompleted(choice: choice);
      expect(await ForumNetworkSetupStore.isCompleted(), isTrue);
      expect(await ForumNetworkSetupStore.loadChoice(), choice);
      await ForumNetworkSetupStore.reset();
      expect(await ForumNetworkSetupStore.isCompleted(), isFalse);
      expect(await ForumNetworkSetupStore.loadChoice(), isNull);
    });
  }
}
