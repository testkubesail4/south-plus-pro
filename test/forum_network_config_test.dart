import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      ['203.0.113.7', '198.51.100.23', '192.0.2.14'],
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
