import 'dart:async';
import 'dart:io';

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

  test(
      'all supported native view endpoints enter through registered Android paths',
      () async {
    final links = <String>[];
    await service.start(
        onLink: links.add, onRejected: (_) => fail('supported view rejected'));
    service.setReady(true);
    final registered = RegExp(r'<data android:path="([^"]*)"\s*/>')
        .allMatches(
            File('android/app/src/main/AndroidManifest.xml').readAsStringSync())
        .map((match) => match.group(1))
        .toSet();
    final urls = [
      'https://south-plus.net',
      'https://south-plus.net/',
      'https://south-plus.net/index.php',
      'https://south-plus.net/simple/index.php',
      'https://south-plus.net/simple/index.php?t701_2.html',
      'https://south-plus.net/u.php',
      'https://south-plus.net/u.php?action-friend-o-check-fuid-202.html',
      'https://south-plus.net/u.php?action-friend-uid-101-o-check-page-2.html',
      'https://south-plus.net/profile.php',
      'https://south-plus.net/profile.php?action-bbsset-info_type-friend.html',
      'https://south-plus.net/profile.php?action=modify',
      'https://south-plus.net/message.php?action=sendbox&page=2',
      'https://south-plus.net/message.php?action-read-mid-701.html',
      'https://south-plus.net/message.php?action-write-remid-701.html',
      'https://south-plus.net/message.php?action-chatlog-withuid-202.html',
      'https://south-plus.net/plugin.php?H_name-tasks-actions-errotasks.html.html',
      'https://south-plus.net/job.php?action-topost-tid-701-pid-42.html',
      'https://south-plus.net/search.php?keyword=fixture',
    ];
    for (var index = 0; index < urls.length; index++) {
      expect(registered, contains(Uri.parse(urls[index]).path),
          reason: 'OS intent path ${urls[index]}');
      await send(index + 1, urls[index]);
    }
    expect(links, urls);
    expect(acknowledged, List.generate(urls.length, (index) => index + 1));
  });

  test('management mutation payloads cannot be dispatched or copied as views',
      () async {
    final rejected = <String?>[];
    await service.start(
        onLink: (_) => fail('mutation dispatch'), onRejected: rejected.add);
    service.setReady(true);
    final urls = [
      'https://south-plus.net/profile.php?action=bbsset&step=2',
      'https://south-plus.net/u.php?action=friend&job=delete',
      'https://south-plus.net/plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'https://south-plus.net/message.php?action=send&step=2',
    ];
    for (var index = 0; index < urls.length; index++) {
      await send(index + 1, urls[index]);
    }
    expect(rejected, List.filled(urls.length, null));
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
