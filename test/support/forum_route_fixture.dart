import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

void selectProxyTestRoute(ForumProxy? proxy) =>
    ForumHttpRouting.updateConfig(ForumNetworkConfig(
        site: ForumNetworkConfig.defaultSite,
        mode: proxy == null ? ForumNetworkMode.native : ForumNetworkMode.proxy,
        proxy: proxy));

// Observe the actual native/proxy connector without opening an external socket.
Future<void> expectProxyTestRoute(String? proxyHost) async {
  final attempted = <String>[];
  await IOOverrides.runZoned(
      () => HttpOverrides.runWithHttpOverrides(() async {
            final client = HttpClient();
            try {
              await expectLater(
                  client.getUrl(Uri.http('route.fixture.invalid', '/')),
                  throwsA(isA<SocketException>()));
            } finally {
              client.close(force: true);
            }
          }, ForumHttpOverrides()),
      socketStartConnect: (dynamic host, int port,
          {dynamic sourceAddress, int sourcePort = 0}) async {
    attempted.add(host is InternetAddress ? host.address : '$host');
    throw const SocketException('Fixture route observed');
  });
  expect(attempted, [proxyHost ?? 'route.fixture.invalid']);
}
