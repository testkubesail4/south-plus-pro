import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_probe.dart';

void main() {
  tearDown(() => ForumHttpRouting.updateProxy(null));
  for (final type in ForumProxyType.values) {
    test(
        'optimization probes make no requests while ${type.name} proxy is active',
        () async {
      final network = _RejectNetwork();
      ForumHttpRouting.updateProxy(
          ForumProxy(type: type, host: 'proxy.fixture.invalid', port: 8080));
      await HttpOverrides.runWithHttpOverrides(() async {
        const probe = ForumNetworkProbe();
        final site = await probe.testSite(const ForumSite('fixture.invalid'),
            dohEnabled: true, dohProvider: ForumNetworkConfig.defaultProvider);
        expect(site.success, isFalse);
        expect(site.message, '停用代理后再优化网络');
        final doh = await probe.testDoh(ForumNetworkConfig.defaultProvider);
        expect(doh.success, isFalse);
        expect(doh.message, site.message);
        final custom =
            await probe.testCustomDoh('https://dns.fixture.invalid/query');
        expect(custom.success, isFalse);
        expect(custom.message, site.message);
        final address = await probe.testAddress(
            const ForumSite('fixture.invalid'), InternetAddress('203.0.113.8'));
        expect(address.success, isFalse);
        expect(address.message, site.message);
        expect(network.clients, 0);
      }, network);
    });
  }
}

class _RejectNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('Unexpected network client in blocked optimization probe');
  }
}
