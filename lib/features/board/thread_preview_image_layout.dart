import 'dart:math' as math;

import 'package:flutter/painting.dart';

class ThreadPreviewImageLayout {
  const ThreadPreviewImageLayout({
    required this.size,
    required this.fit,
  });

  static const minHeight = 64.0;
  static const maxHeight = 120.0;
  static const tallRatioThreshold = 0.6;
  static const wideRatioThreshold = 2.4;
  static const tallCropWidth = 84.0;
  static const fallbackWidth = 144.0;
  static const fallbackHeight = 96.0;

  final Size size;
  final BoxFit fit;

  static ThreadPreviewImageLayout fallback(double maxWidth) {
    final width = math.min(_boundedWidth(maxWidth), fallbackWidth);
    return ThreadPreviewImageLayout(
      size: Size(width, fallbackHeight),
      fit: BoxFit.contain,
    );
  }

  static ThreadPreviewImageLayout resolve({
    required Size imageSize,
    required double maxWidth,
  }) {
    final width = imageSize.width;
    final height = imageSize.height;
    if (width <= 0 || height <= 0) return fallback(maxWidth);

    final availableWidth = _boundedWidth(maxWidth);
    final ratio = width / height;
    if (!ratio.isFinite || ratio <= 0) return fallback(maxWidth);

    if (ratio < tallRatioThreshold) {
      return ThreadPreviewImageLayout(
        size: Size(math.min(availableWidth, tallCropWidth), maxHeight),
        fit: BoxFit.cover,
      );
    }

    if (ratio > wideRatioThreshold) {
      final previewHeight =
          (availableWidth / ratio).clamp(minHeight, maxHeight).toDouble();
      return ThreadPreviewImageLayout(
        size: Size(availableWidth, previewHeight),
        fit: BoxFit.contain,
      );
    }

    var previewHeight = maxHeight;
    var previewWidth = previewHeight * ratio;
    if (previewWidth > availableWidth) {
      previewWidth = availableWidth;
      previewHeight =
          (previewWidth / ratio).clamp(minHeight, maxHeight).toDouble();
    }

    return ThreadPreviewImageLayout(
      size: Size(previewWidth, previewHeight),
      fit: BoxFit.contain,
    );
  }

  static double _boundedWidth(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= 0) return 320.0;
    return maxWidth;
  }
}
