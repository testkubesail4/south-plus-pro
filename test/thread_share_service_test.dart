import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/thread_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('south_plus_rewrite/image_saver');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final shared = <MethodCall>[];
  final copied = <String>[];
  const title = 'Synthetic thread';
  const url = 'https://south-plus.net/read.php?tid-701.html';

  setUp(() {
    shared.clear();
    copied.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('Android shares the title and URL through the existing native channel',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      shared.add(call);
      return true;
    });
    expect(await ThreadShareService.share(title: title, url: url), isTrue);
    expect(shared.single.method, 'shareText');
    expect(shared.single.arguments, {'text': '$title\n$url'});
    expect(copied, isEmpty);
  });

  test('unsupported platforms and native failures copy only the canonical URL',
      () async {
    for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      for (final error in [
        MissingPluginException(),
        PlatformException(code: 'share_failed'),
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          shared.add(call);
          throw error;
        });
        expect(await ThreadShareService.share(title: title, url: url), isFalse);
      }
    }
    expect(shared, hasLength(2));
    expect(copied, [url, url, url, url]);
  });
}
