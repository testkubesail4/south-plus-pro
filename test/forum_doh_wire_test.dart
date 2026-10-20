import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

import 'support/doh_wire_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const host = 'query.fixture.invalid';
  const alias = 'canonical.fixture.invalid';
  const address = [104, 21, 43, 10];
  Future<(DohResolver, DohWireFixture)> resolver(
    FutureOr<List<int>> Function(List<int>) reply, {
    bool ipv6 = false,
  }) async {
    final fixture = await DohWireFixture.start(reply);
    final resolver = DohResolver.custom(
      endpoint: Uri.parse('https://dns.fixture.invalid/query'),
      client: fixture.client,
      ipv6Enabled: ipv6,
      timeout: const Duration(seconds: 2),
    );
    addTearDown(() async {
      resolver.close();
      await fixture.close();
    });
    return (resolver, fixture);
  }

  test(
    'wire follows only the queried CNAME chain and keeps A/AAAA families distinct',
    () async {
      final (dns, fixture) = await resolver((query) {
        final type = dnsQueryType(query);
        return dnsReply(query, [
          dnsRecord(host, 5, dnsName(alias)),
          dnsRecord(
            alias,
            type,
            type == 1
                ? address
                : InternetAddress('2606:4700:3036::6815:2b0a').rawAddress,
          ),
          dnsRecord('unrelated.fixture.invalid', 1, [1, 1, 1, 1]),
        ]);
      }, ipv6: true);
      final result =
          (await dns.lookupCandidates(host).toList()).expand((v) => v).toList();
      expect(
        result.map((a) => a.address),
        unorderedEquals(['2606:4700:3036::6815:2b0a', '104.21.43.10']),
      );
      expect(fixture.hits, 2);
      await dns.lookupCandidates(host).drain<void>();
      expect(fixture.hits, 2);
    },
  );

  for (final ttlOn in ['address', 'CNAME']) {
    test('TTL zero on $ttlOn is not cached', () async {
      final (dns, fixture) = await resolver(
        (query) => dnsReply(query, [
          dnsRecord(host, 5, dnsName(alias), ttl: ttlOn == 'CNAME' ? 0 : 60),
          dnsRecord(alias, 1, address, ttl: ttlOn == 'address' ? 0 : 60),
        ]),
      );
      await dns.lookup(host);
      await dns.lookup(host);
      expect(fixture.hits, 2);
    });
  }

  test(
    'CNAME minimum TTL expires and concurrent queries share one inflight request',
    () async {
      final gate = Completer<void>();
      final (dns, fixture) = await resolver((query) async {
        await gate.future;
        return dnsReply(query, [
          dnsRecord(host, 5, dnsName(alias), ttl: 1),
          dnsRecord(alias, 1, address),
        ]);
      });
      final first = dns.lookup(host);
      final second = dns.lookup(host);
      await fixture.firstQuery.future;
      gate.complete();
      expect(await first, await second);
      expect(fixture.hits, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await dns.lookup(host);
      expect(fixture.hits, 2);
    },
  );

  final invalid = <String, List<int> Function(List<int>)>{
    'SERVFAIL despite address Answer': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)], status: 2),
    'NXDOMAIN despite address Answer': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)], status: 3),
    'wrong transaction': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)])..[0] ^= 1,
    'extended BADVERS status': (q) =>
        (dnsReply(q, [dnsRecord(host, 1, address)])..[11] = 1)
          ..addAll([0, 0, 41, 4, 208, 1, 0, 0, 0, 0, 0]),
    'reserved header bit': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)])..[3] |= 0x40,
    'not a response': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)])..[2] = 0x01,
    'truncated flag': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)])..[2] |= 2,
    'wrong question': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)])..[13] = 120,
    'unrelated owner': (q) =>
        dnsReply(q, [dnsRecord('other.fixture.invalid', 1, address)]),
    'address class': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address, recordClass: 3)]),
    'A with IPv6 bytes': (q) =>
        dnsReply(q, [dnsRecord(host, 1, List.filled(16, 1))]),
    'CNAME cycle': (q) => dnsReply(q, [
          dnsRecord(host, 5, dnsName(alias)),
          dnsRecord(alias, 5, dnsName(host)),
          dnsRecord('other.fixture.invalid', 1, address),
        ]),
    'conflicting CNAME': (q) => dnsReply(q, [
          dnsRecord(host, 5, dnsName(alias)),
          dnsRecord(host, 5, dnsName('other.fixture.invalid')),
          dnsRecord(alias, 1, address),
        ]),
    'compression loop': (q) => [
          q[0],
          q[1],
          0x81,
          0x80,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0xc0,
          12,
          0,
          1,
          0,
          1,
        ],
    'truncated bytes': (q) =>
        dnsReply(q, [dnsRecord(host, 1, address)])..removeLast(),
    'private address': (q) => dnsReply(q, [
          dnsRecord(host, 1, [127, 0, 0, 1]),
        ]),
  };
  for (final entry in invalid.entries) {
    test('wire rejects ${entry.key}', () async {
      final (dns, fixture) = await resolver(entry.value);
      await expectLater(dns.lookup(host), throwsA(isA<SocketException>()));
      expect(fixture.hits, 1);
    });
  }

  test('AAAA failure does not discard a successful IPv4 answer', () async {
    final (dns, fixture) = await resolver(
      (q) => dnsQueryType(q) == 28
          ? dnsReply(q, [], status: 2)
          : dnsReply(q, [dnsRecord(host, 1, address)]),
      ipv6: true,
    );
    expect((await dns.lookup(host)).map((a) => a.address), ['104.21.43.10']);
    expect(fixture.hits, 2);
  });
}
