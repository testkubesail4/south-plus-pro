import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/common/forum_emoji_assets.dart';

void main() {
  test('forum emoji URLs map to bundled asset names', () {
    expect(
      forumEmojiAssetNameForUrl(
        'https://south-plus.net/images/post/smile/smallface/face077.gif',
      ),
      'assets/forum_emoji/images/post/smile/smallface/face077.gif',
    );
    expect(
      forumEmojiAssetNameForUrl('https://south-plus.net/images/face/a6.gif'),
      isNull,
    );
  });

  testWidgets('bundled forum emoji asset can be loaded', (tester) async {
    final bytes = await rootBundle.load(
      'assets/forum_emoji/images/post/smile/smallface/face077.gif',
    );
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  testWidgets('asset load failure falls back to network image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CachedForumImage(
            url: 'https://example.com/missing.png',
            assetName: 'assets/forum_emoji/does-not-exist.gif',
            bypassLoadPolicy: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}
