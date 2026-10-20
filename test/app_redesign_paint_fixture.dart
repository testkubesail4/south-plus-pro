import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Measure only the changing region: permanent app bars cannot hide a blank body.
Future<(Uint8List, double)> captureRedesignPaint(WidgetTester tester,
    Finder repaintBoundary, Rect region, Color background) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(repaintBoundary);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 0.5);
    final bytes = (await image.toByteData())!;
    final pixels = <int>[];
    var ink = 0.0;
    for (var y = (region.top / 2).ceil();
        y < (region.bottom / 2).floor();
        y++) {
      for (var x = (region.left / 2).ceil();
          x < (region.right / 2).floor();
          x++) {
        final offset = (y * image.width + x) * 4;
        for (final (channel, base) in [
          (0, background.r),
          (1, background.g),
          (2, background.b)
        ]) {
          final value = bytes.getUint8(offset + channel);
          pixels.add(value);
          ink += (value - base * 255).abs() / 255;
        }
      }
    }
    image.dispose();
    expect(pixels, isNotEmpty);
    return (Uint8List.fromList(pixels), ink / pixels.length);
  }))!;
}

double redesignPaintDifference(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length / 255;
}
