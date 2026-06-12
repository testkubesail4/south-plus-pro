import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';

void main() {
  test('ForumUrlResolver rewrites forum mirror URLs to selected host', () {
    final resolver = ForumUrlResolver(
      baseUri: Uri.https('east-plus.net', '/'),
    );

    expect(
      resolver.absoluteUrl('https://south-plus.net/read.php?tid-123.html'),
      'https://east-plus.net/read.php?tid-123.html',
    );
    expect(
      resolver.absoluteUrl('//north-plus.net/simple/index.php?f2.html'),
      'https://east-plus.net/simple/index.php?f2.html',
    );
    expect(
      resolver.relativePath('https://snow-plus.net/simple/index.php?f1.html'),
      'simple/index.php?f1.html',
    );
  });

  test('ForumUrlResolver builds desktop thread detail page paths', () {
    final resolver = ForumUrlResolver(
      baseUri: Uri.https('east-plus.net', '/'),
    );

    expect(
      resolver.threadDetailPath('https://south-plus.net/read.php?tid-123.html'),
      'read.php?tid-123.html',
    );
    expect(
      resolver.threadDetailPath(
        'https://south-plus.net/simple/index.php?t123.html',
        page: 9,
      ),
      'read.php?tid-123-fpage-0-toread--page-9.html',
    );
    expect(
      resolver.threadDetailPath(
        'https://south-plus.net/read.php?tid-123-uid-456.html',
      ),
      'read.php?tid-123-uid-456.html',
    );
    expect(
      resolver.threadDetailPath(
        'https://south-plus.net/read.php?tid-123-uid-456.html',
        page: 3,
      ),
      'read.php?tid-123-uid-456-fpage-0-toread--page-3.html',
    );
  });

  test('ForumUrlResolver builds desktop board paths for list and wall modes',
      () {
    final resolver = ForumUrlResolver(
      baseUri: Uri.https('east-plus.net', '/'),
    );

    expect(
      resolver.boardDesktopPath(
        const ForumCategory(
          name: 'C103',
          slug: 'fid-218',
          url: 'https://south-plus.net/thread.php?fid-218.html',
        ),
      ),
      'thread.php?fid-218.html',
    );
    expect(
      resolver.boardDesktopPath(
        const ForumCategory(
          name: '图墙模式',
          slug: 'fid=218',
          url: 'https://south-plus.net/thread_new.php?fid=218',
        ),
        page: 2,
      ),
      'thread_new.php?fid=218&page=2',
    );
  });

  test('ForumNetworkSettings persists selected site and DoH provider',
      () async {
    SharedPreferences.setMockInitialValues({});

    const config = ForumNetworkConfig(
      site: ForumSite('blue-plus.net'),
      dohEnabled: false,
      dohProvider: DohProvider.tiarap,
      fixedAddress: '203.0.113.7',
    );

    await ForumNetworkSettings.save(config);
    final loaded = await ForumNetworkSettings.load();

    expect(loaded.site.host, 'blue-plus.net');
    expect(loaded.dohEnabled, false);
    expect(loaded.dohProvider, DohProvider.tiarap);
    expect(loaded.fixedAddress, '203.0.113.7');
  });

  test('ForumNetworkSettings persists custom site and custom encrypted DNS',
      () async {
    SharedPreferences.setMockInitialValues({});

    const config = ForumNetworkConfig(
      site: ForumSite('example.com'),
      dohEnabled: true,
      dohProvider: DohProvider.cloudflareGateway,
      customDohUri: 'https://dns.example.com/dns-query',
    );

    await ForumNetworkSettings.save(config);
    final loaded = await ForumNetworkSettings.load();

    expect(loaded.site.host, 'example.com');
    expect(loaded.customDohUri, 'https://dns.example.com/dns-query');
    expect(loaded.normalizedCustomDohUri, 'https://dns.example.com/dns-query');
    expect(loaded.dohLabel, '自定义加密 DNS');
  });

  test('ForumNetworkSettings keeps multiple custom connection options',
      () async {
    SharedPreferences.setMockInitialValues({});

    await ForumNetworkSettings.addCustomSite(const ForumSite('one.example'));
    await ForumNetworkSettings.addCustomSite(const ForumSite('two.example'));
    await ForumNetworkSettings.addCustomDohUri('https://dns.one/dns-query');
    await ForumNetworkSettings.addCustomDohUri('https://dns.two/dns-query');

    final sites = await ForumNetworkSettings.loadCustomSites();
    final dohUris = await ForumNetworkSettings.loadCustomDohUris();

    expect(sites.map((site) => site.host), ['two.example', 'one.example']);
    expect(dohUris, [
      'https://dns.two/dns-query',
      'https://dns.one/dns-query',
    ]);
  });

  test('ForumResolvedAddressStore includes built-in route addresses', () async {
    SharedPreferences.setMockInitialValues({});

    final loaded = await ForumResolvedAddressStore.load();

    expect(
      loaded.map((address) => address.address),
      [
        '104.18.26.110',
        '172.67.74.152',
        '141.101.115.10',
        '104.17.147.40',
        '198.41.219.125',
      ],
    );
    expect(
      ForumNetworkConfig.routeLabelForAddress('104.18.26.110', 1),
      '低丢包通道',
    );
  });

  test('ForumResolvedAddressStore persists unique fallback addresses',
      () async {
    SharedPreferences.setMockInitialValues({});

    await ForumResolvedAddressStore.save([
      InternetAddress('198.18.0.1'),
      InternetAddress('10.0.0.1'),
      InternetAddress('203.0.113.7'),
      InternetAddress('203.0.113.7'),
      InternetAddress('198.51.100.23'),
      InternetAddress('192.0.2.14'),
      InternetAddress('192.0.2.15'),
    ]);

    final loaded = await ForumResolvedAddressStore.load();

    expect(
      loaded.map((address) => address.address),
      [
        '104.18.26.110',
        '172.67.74.152',
        '141.101.115.10',
        '104.17.147.40',
        '198.41.219.125',
        '203.0.113.7',
        '198.51.100.23',
        '192.0.2.14',
      ],
    );
  });

  test('ForumNetworkSettings ignores non-routable fixed address', () async {
    SharedPreferences.setMockInitialValues({});

    const config = ForumNetworkConfig(
      site: ForumSite('south-plus.net'),
      dohEnabled: true,
      dohProvider: DohProvider.doh090227Sb,
      fixedAddress: '198.18.0.1',
    );

    await ForumNetworkSettings.save(config);
    final loaded = await ForumNetworkSettings.load();

    expect(loaded.fixedAddress, isNull);
    expect(loaded.fixedInternetAddress, isNull);
  });
}
