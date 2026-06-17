import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/board/thread_preview_image_layout.dart';

void main() {
  test('uses contain and follows normal image ratio', () {
    final layout = ThreadPreviewImageLayout.resolve(
      imageSize: const Size(800, 600),
      maxWidth: 300,
    );

    expect(layout.fit, BoxFit.contain);
    expect(layout.size.width, 160);
    expect(layout.size.height, ThreadPreviewImageLayout.maxHeight);
  });

  test('crops very tall images into a compact portrait preview', () {
    final layout = ThreadPreviewImageLayout.resolve(
      imageSize: const Size(400, 1000),
      maxWidth: 300,
    );

    expect(layout.fit, BoxFit.cover);
    expect(layout.size.width, ThreadPreviewImageLayout.tallCropWidth);
    expect(layout.size.height, ThreadPreviewImageLayout.maxHeight);
  });

  test('keeps very wide images readable without exceeding max height', () {
    final layout = ThreadPreviewImageLayout.resolve(
      imageSize: const Size(1800, 500),
      maxWidth: 300,
    );

    expect(layout.fit, BoxFit.contain);
    expect(layout.size.width, 300);
    expect(layout.size.height, closeTo(83.33, 0.01));
  });

  test('uses a conservative fallback for unknown image size', () {
    final layout = ThreadPreviewImageLayout.fallback(300);

    expect(layout.fit, BoxFit.contain);
    expect(layout.size.width, ThreadPreviewImageLayout.fallbackWidth);
    expect(layout.size.height, ThreadPreviewImageLayout.fallbackHeight);
  });
}
