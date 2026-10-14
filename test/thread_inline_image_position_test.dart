import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

import 'support/image_http_fixture.dart';

const _portraitUrl = 'https://fixture.invalid/position-portrait.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImageHttpFixture fixture;
  HttpOverrides? oldOverrides;

  setUpAll(() async {
    oldOverrides = HttpOverrides.current;
    fixture = await ImageHttpFixture.start(
      images: {_portraitUrl: await _png(400, 1200)},
    );
    HttpOverrides.global = fixture;
    PathProviderLinux.registerWith();
    await ForumImageCache.manager.emptyCache();
  });
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await fixture.close();
  });

  testWidgets('a narrow post image keeps its left edge while it loads in',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThreadInlineImage(image: ThreadImage(url: _portraitUrl)),
                ],
              ),
            ),
          ),
        ),
      );
      final lefts = <double>[];
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump(const Duration(milliseconds: 16));
        final images = find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        );
        if (images.evaluate().isNotEmpty) {
          lefts.add(tester.getTopLeft(images.first).dx);
          // Past the 500 ms fade-in and the 1 s placeholder fade-out.
          if (lefts.length > 120) break;
        }
      }
      expect(lefts, isNotEmpty, reason: 'image never decoded');
      // Portrait 400x1200 shown at the 360 max height is 120 wide.
      expect(
        lefts.toSet(),
        {0.0},
        reason: 'left edge per frame from first paint to settled: $lefts',
      );
    });
  });
}

Future<List<int>> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
