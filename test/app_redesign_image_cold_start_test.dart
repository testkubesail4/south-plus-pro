import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

import 'support/image_http_fixture.dart';

void main() {
  // This file is the sole cold-policy case: its test isolate starts uncached.
  testWidgets('persisted strict policy blocks every image owner on cold start',
      (tester) async {
    await tester.runAsync(() async {
      expect(ImageLoadingSettings.notifier.value, isNull);
      SharedPreferences.setMockInitialValues(
          {'settings.imageLoadMode': 'noImages'});
      final fixture = await ImageHttpFixture.start();
      final previous = HttpOverrides.current;
      HttpOverrides.global = fixture;
      try {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: Column(children: [
              CachedForumImage(
                  url: ImageHttpFixture.emojiUrl, width: 24, height: 24),
              CachedForumImage(
                  url: ImageHttpFixture.avatarUrl,
                  width: 48,
                  height: 48,
                  bypassLoadPolicy: true),
              SizedBox(
                width: 360,
                child: ThreadInlineImage(
                    image: ThreadImage(url: ImageHttpFixture.imageUrl)),
              ),
            ]),
          ),
        ));
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(await ImageLoadingSettings.loadMode(), ImageLoadMode.noImages);
        await tester.pumpAndSettle();
        expect(find.byType(CachedNetworkImage), findsNothing);
        expect(fixture.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        HttpOverrides.global = previous;
        await fixture.close();
      }
    });
  });
}
