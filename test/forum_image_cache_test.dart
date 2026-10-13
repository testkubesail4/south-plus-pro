import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forum image cache manager supports resized image requests', () async {
    final directory =
        await Directory.systemTemp.createTemp('forum-cache-test-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory' ||
          call.method == 'getApplicationSupportDirectory')
        return directory.path;
      throw MissingPluginException();
    });
    final manager = ForumImageCache.manager;
    try {
      expect(manager, isA<ImageCacheManager>());
      expect(await manager.getFileFromCache('fixture-missing-image'), isNull);
    } finally {
      await manager.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    }
  });
}
