import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

import 'support/doh_wire_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'authoritative negative answers cannot suppress an unrelated host DNS query',
      () async {
    final validQueried = Completer<void>();
    final fixture = await DohWireFixture.start((query) {
      final labels = <String>[];
      for (var offset = 12; query[offset] != 0;) {
        final length = query[offset++];
        labels.add(ascii.decode(query.sublist(offset, offset + length)));
        offset += length;
      }
      final host = labels.join('.');
      if (host == 'missing.fixture.invalid')
        return dnsReply(query, [], status: 3);
      expect(host, 'api.github.com');
      if (!validQueried.isCompleted) validQueried.complete();
      return dnsReply(query, [
        dnsRecord(host, 1, [104, 21, 43, 10])
      ]);
    });
    final overrides = DohHttpOverrides(fixture.client);
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = createForumHttpClient(const ForumNetworkConfig(
            site: ForumSite('fixture.invalid'),
            mode: ForumNetworkMode.optimized));
        try {
          await expectLater(
              client.getUrl(Uri.https('missing.fixture.invalid', '/')),
              throwsA(isA<SocketException>()));
          final pending = client.getUrl(Uri.https('api.github.com', '/'));
          final cancelled = expectLater(pending,
              throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
          // Health scope is observed at the existing HTTP boundary, independently
          // of target-IP reachability. Cancel before dialing a public target.
          await validQueried.future.timeout(const Duration(seconds: 1));
          client.close(force: true);
          await cancelled;
        } finally {
          client.close(force: true);
        }
      }, overrides);
    } finally {
      await fixture.close();
    }
  });
}
