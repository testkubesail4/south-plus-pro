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
      images: {
        _portraitUrl: await _png(400, 1200),
        for (final (url, width, height, _) in _decodeCases)
          url: await _png(width, height),
      },
    );
    HttpOverrides.global = fixture;
    PathProviderLinux.registerWith();
    await ForumImageCache.manager.emptyCache();
  });
  tearDownAll(() async {
    HttpOverrides.global = oldOverrides;
    await fixture.close();
  });

  // Decoded pixels match the painted size × DPR, whichever side bounds it.
  for (final (url, width, height, box) in _decodeCases) {
    testWidgets(
        'a ${width}x$height post image in a $box-wide post decodes '
        'at its on-screen size', (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        await ImageLoadingSettings.saveMode(ImageLoadMode.automatic);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // A post column: full width offered, image keeps its own size.
              child: SizedBox(
                width: box,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThreadInlineImage(image: ThreadImage(url: url)),
                  ],
                ),
              ),
            ),
          ),
        ));
        final decoded = find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        );
        for (var i = 0; i < 200 && decoded.evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final image = tester.widget<RawImage>(decoded).image!;
        final shown = tester.getSize(decoded);
        expect(
          Size(image.width.toDouble(), image.height.toDouble()),
          _within(shown * 2),
          reason: 'decoded ${image.width}x${image.height} for $shown on screen',
        );
        await tester.pumpWidget(const SizedBox());
      });
    });
  }

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

// (url, source width, source height, post width); posts cap images at 360.
const _decodeCases = [
  ('https://fixture.invalid/decode-landscape.png', 1200, 900, 800.0),
  ('https://fixture.invalid/decode-portrait.png', 400, 1200, 800.0),
  ('https://fixture.invalid/decode-panorama.png', 3000, 375, 320.0),
];

Matcher _within(Size size) => predicate<Size>(
      (s) =>
          (s.width - size.width).abs() <= 2 &&
          (s.height - size.height).abs() <= 2,
      'within 2px of $size',
    );

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
