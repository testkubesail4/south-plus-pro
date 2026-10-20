import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'v2 preserves independent site, mode and offline custom candidates',
    () async {
      final config = ForumNetworkConfig(
        site: const ForumSite('blue-plus.net'),
        mode: ForumNetworkMode.optimized,
        ipv6Enabled: true,
        customDohUri: 'https://dns.example/dns-query',
        dohBootstrapAddresses: const ['1.1.1.1', '2606:4700:4700::1111'],
        hostAddresses: const {
          'blue-plus.net': ['104.21.62.119', '2606:4700:3037::6815:3e77'],
        },
      );
      await ForumNetworkSettings.save(config);
      final loaded = await ForumNetworkSettings.load();
      expect(loaded, config);
      expect(loaded.copyWith(mode: ForumNetworkMode.native).site, config.site);
      expect(loaded.fallbackAddressesFor('unrelated.example'), isEmpty);
      expect(loaded.fallbackAddressesFor('blue-plus.net').take(2),
          config.hostAddresses['blue-plus.net']);
      expect(loaded.fallbackAddressesFor('blue-plus.net'), contains('172.67.223.131'));
      final proxy = ForumProxy(type: ForumProxyType.socks5, host: 'localhost', port: 1080);
      final dormant = loaded.copyWith(proxy: proxy).copyWith(mode: ForumNetworkMode.native);
      expect(dormant.proxy, proxy);
      expect(dormant.hostAddresses, loaded.hostAddresses);
    },
  );

  test(
    'migration preserves proxy and site but discards unscoped legacy IP',
    () async {
      SharedPreferences.setMockInitialValues({
        'forum_network_site_host_v1': 'north-plus.net',
        'forum_network_doh_enabled_v1': true,
        'forum_network_fixed_address_v1': '104.18.26.110',
        'forum_network_proxy_v1':
            '{"type":"socks5","host":"localhost","port":1080}',
      });
      final config = await ForumNetworkSettings.load();
      expect(config.mode, ForumNetworkMode.proxy);
      expect(config.site.host, 'north-plus.net');
      expect(config.fixedAddress, isNull);
      expect(config.ipv6Enabled, isFalse);
      await ForumNetworkSettings.disableProxy();
      final native = await ForumNetworkSettings.load();
      expect(native.mode, ForumNetworkMode.native);
      expect(native.site, config.site);
    },
  );

  test(
    'invalid custom endpoint or IP cannot overwrite committed config',
    () async {
      const config = ForumNetworkConfig(
        site: ForumNetworkConfig.defaultSite,
        mode: ForumNetworkMode.native,
      );
      await ForumNetworkSettings.save(config);
      await expectLater(
        ForumNetworkSettings.save(
          config.copyWith(
            customDohUri: 'https://user:secret@dns.example/dns-query',
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        ForumNetworkSettings.save(
          config.copyWith(
            hostAddresses: const {
              'south-plus.net': ['not-an-ip'],
            },
          ),
        ),
        throwsFormatException,
      );
      expect(await ForumNetworkSettings.load(), config);
    },
  );
}
