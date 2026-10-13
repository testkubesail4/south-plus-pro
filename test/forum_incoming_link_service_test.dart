import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_incoming_link_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('south_plus_rewrite/incoming_links');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ForumIncomingLinkService service;
  late List<int> acknowledged;
  Object? initial;
  setUp(() {
    initial = null;
    acknowledged = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takeInitialLink') return initial;
      if (call.method == 'acknowledgeLink') {
        acknowledged.add(call.arguments as int);
        return null;
      }
      throw MissingPluginException();
    });
    service = ForumIncomingLinkService(channel: channel);
  });
  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> send(int id, String url) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall('openLink', {'id': id, 'url': url})),
        (_) => done.complete());
    await done.future;
  }

  test('cold/warm latest wins before readiness; event ids dedupe, not URLs',
      () async {
    const cold =
        'https://south-plus.net/read.php?tid-701.html#fixture%2Danchor';
    const warm = 'https://blue-plus.net/u.php?uid-901.html';
    initial = {'id': 1, 'url': cold};
    final links = <String>[];
    await service.start(
        onLink: links.add, onRejected: (_) => fail('unexpected rejection'));
    await send(2, warm);
    expect(links, isEmpty);
    expect(acknowledged, isEmpty);
    service.setReady(true);
    expect(links, [warm]);
    await send(1, cold);
    await send(2, warm);
    await send(3, warm);
    expect(links, [warm, warm]);
    expect(acknowledged, [2, 3]);
    service.setReady(false);
    await send(4, cold);
    service.dispose();
    service.setReady(true);
    expect(links, [warm, warm]);
  });

  test('unsupported owned pages can be copied; dangerous inputs cannot',
      () async {
    final rejected = <String?>[];
    await service.start(
        onLink: (_) => fail('unsafe dispatch'), onRejected: rejected.add);
    service.setReady(true);
    final urls = [
      'https://south-plus.net/faq.php',
      'https://south-plus.net/login.php?action=logout',
      'https://example.invalid/read.php?tid-701.html',
      'https://user:password@south-plus.net/read.php?tid-701.html',
      'javascript:alert(1)',
      'read.php?tid-701.html',
    ];
    for (var index = 0; index < urls.length; index++) {
      await send(index + 1, urls[index]);
    }
    expect(rejected, [urls.first, null, null, null, null, null]);
    expect(acknowledged, [1, 2, 3, 4, 5, 6]);
  });

  test('acknowledges callback failures and disposes pending initial replies',
      () async {
    await service.start(
        onLink: (_) => throw StateError('fixture'), onRejected: (_) {});
    service.setReady(true);
    await send(1, 'https://south-plus.net/thread.php?fid-42.html');
    expect(acknowledged, [1]);
    service.dispose();
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    service = ForumIncomingLinkService(channel: channel);
    final started = service.start(
        onLink: (_) => fail('disposed callback'),
        onRejected: (_) => fail('disposed callback'));
    service.setReady(true);
    service.dispose();
    pending.complete(
        {'id': 2, 'url': 'https://south-plus.net/search.php?keyword=fixture'});
    await started;
  });
}
