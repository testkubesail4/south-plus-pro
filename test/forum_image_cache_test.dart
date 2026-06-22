import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forum image cache manager supports resized image requests', () {
    expect(ForumImageCache.manager, isA<ImageCacheManager>());
  });
}
