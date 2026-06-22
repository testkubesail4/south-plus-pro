import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../services/forum_trace_logger.dart';
import '../../services/image_loading_settings.dart';
import '../../theme/app_theme.dart';

class _ForumImageCacheManager extends CacheManager with ImageCacheManager {
  _ForumImageCacheManager()
      : super(
          Config(
            'southPlusForumImages',
            stalePeriod: ForumImageCache.stalePeriod,
            maxNrOfCacheObjects: 2000,
          ),
        );
}

class ForumImageCache {
  ForumImageCache._();

  static const stalePeriod = Duration(days: 180);

  static final CacheManager manager = _ForumImageCacheManager();
}

class ForumImageMetadataCache {
  ForumImageMetadataCache._();

  static final ForumImageMetadataCache instance = ForumImageMetadataCache._();

  final Map<String, Size> _resolved = <String, Size>{};
  final Map<String, Future<Size?>> _inFlight = <String, Future<Size?>>{};

  Future<Size?> get(String url, ImageProvider provider) {
    final cached = _resolved[url];
    if (cached != null) {
      ForumTraceLogger.log(
        'ImageMeta',
        'cache hit url=$url size=${cached.width}x${cached.height}',
      );
      return Future<Size?>.value(cached);
    }
    final pending = _inFlight[url];
    if (pending != null) {
      ForumTraceLogger.log('ImageMeta', 'reuse in-flight url=$url');
      return pending;
    }

    ForumTraceLogger.log('ImageMeta', 'resolve start url=$url');
    final future = _resolve(url, provider);
    _inFlight[url] = future;
    future.whenComplete(() {
      if (identical(_inFlight[url], future)) {
        _inFlight.remove(url);
      }
    });
    return future;
  }

  Size? peek(String url) => _resolved[url];

  void clearFor(String url) {
    _resolved.remove(url);
    _inFlight.remove(url);
  }

  Future<Size?> _resolve(String url, ImageProvider provider) {
    final completer = Completer<Size?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;

    void complete(Size? size) {
      if (size != null) {
        _resolved[url] = size;
        ForumTraceLogger.log(
          'ImageMeta',
          'resolve success url=$url size=${size.width}x${size.height}',
        );
      } else {
        ForumTraceLogger.log('ImageMeta', 'resolve failed url=$url');
      }
      stream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(size);
      }
    }

    listener = ImageStreamListener(
      (info, synchronousCall) {
        final image = info.image;
        final width = image.width.toDouble();
        final height = image.height.toDouble();
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          complete(null);
          return;
        }
        complete(Size(width, height));
      },
      onError: (exception, stackTrace) {
        complete(null);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }
}

class ForumImageDecodeSpec {
  const ForumImageDecodeSpec({
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
  });

  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;

  factory ForumImageDecodeSpec.forDisplay({
    required Size logicalSize,
    required double devicePixelRatio,
    bool includeMemWidth = true,
    bool includeMemHeight = true,
    bool includeDiskWidth = true,
    bool includeDiskHeight = true,
    double memoryScale = 1,
    double diskScale = 1,
    int maxLongEdge = 2048,
  }) {
    return ForumImageDecodeSpec(
      memCacheWidth: includeMemWidth
          ? _scaledDimension(
              logicalSize.width,
              devicePixelRatio,
              scale: memoryScale,
              maxLongEdge: maxLongEdge,
            )
          : null,
      memCacheHeight: includeMemHeight
          ? _scaledDimension(
              logicalSize.height,
              devicePixelRatio,
              scale: memoryScale,
              maxLongEdge: maxLongEdge,
            )
          : null,
      maxWidthDiskCache: includeDiskWidth
          ? _scaledDimension(
              logicalSize.width,
              devicePixelRatio,
              scale: diskScale,
              maxLongEdge: maxLongEdge,
            )
          : null,
      maxHeightDiskCache: includeDiskHeight
          ? _scaledDimension(
              logicalSize.height,
              devicePixelRatio,
              scale: diskScale,
              maxLongEdge: maxLongEdge,
            )
          : null,
    );
  }

  static int? _scaledDimension(
    double logicalDimension,
    double devicePixelRatio, {
    required double scale,
    required int maxLongEdge,
  }) {
    if (!logicalDimension.isFinite || logicalDimension <= 0) return null;
    final ratio = !devicePixelRatio.isFinite || devicePixelRatio <= 0
        ? 1.0
        : devicePixelRatio;
    final pixels = (logicalDimension * ratio * scale).ceil();
    return pixels.clamp(1, maxLongEdge);
  }
}

class CachedForumImage extends StatelessWidget {
  const CachedForumImage({
    super.key,
    required this.url,
    this.assetName,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.bypassLoadPolicy = false,
  });

  final String url;
  final String? assetName;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final ImageWidgetBuilder? imageBuilder;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final bool bypassLoadPolicy;

  @override
  Widget build(BuildContext context) {
    return _PolicyAwareCachedImage(
      url: url,
      assetName: assetName,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      placeholder: placeholder,
      errorWidget: errorWidget,
      imageBuilder: imageBuilder,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      maxWidthDiskCache: maxWidthDiskCache,
      maxHeightDiskCache: maxHeightDiskCache,
      bypassLoadPolicy: bypassLoadPolicy,
    );
  }
}

class _PolicyAwareCachedImage extends StatefulWidget {
  const _PolicyAwareCachedImage({
    required this.url,
    this.assetName,
    this.width,
    this.height,
    this.fit,
    required this.alignment,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.memCacheWidth,
    this.memCacheHeight,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    required this.bypassLoadPolicy,
  });

  final String url;
  final String? assetName;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final ImageWidgetBuilder? imageBuilder;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final bool bypassLoadPolicy;

  @override
  State<_PolicyAwareCachedImage> createState() =>
      _PolicyAwareCachedImageState();
}

class _PolicyAwareCachedImageState extends State<_PolicyAwareCachedImage> {
  late Future<bool> _canLoad = ImageLoadingSettings.canAutoLoadImages();
  bool _forcedLoad = false;
  int _retry = 0;
  String? _lastLoggedDecision;

  @override
  void didUpdateWidget(covariant _PolicyAwareCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _forcedLoad = false;
      _retry = 0;
      _lastLoggedDecision = null;
      _canLoad = ImageLoadingSettings.canAutoLoadImages();
    }
  }

  void _loadNow() {
    ForumTraceLogger.log(
      'ImageLoad',
      'manual load requested url=${widget.url} nextRetry=${_retry + 1}',
    );
    setState(() {
      _forcedLoad = true;
      _retry++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bypassLoadPolicy) {
      _logDecision('bypass');
      return _image();
    }
    if (_forcedLoad) {
      _logDecision('forced');
      return _image();
    }
    if (_isTinyInlineImage) {
      _logDecision('tiny-inline');
      return _image();
    }

    return FutureBuilder<bool>(
      future: _canLoad,
      builder: (context, snapshot) {
        if (snapshot.data ?? false) {
          _logDecision('auto');
          return _image();
        }
        _logDecision(
          snapshot.connectionState == ConnectionState.waiting
              ? 'await-policy'
              : 'deferred',
        );
        return _DeferredImagePlaceholder(
          width: widget.width,
          height: widget.height,
          onLoad: _loadNow,
        );
      },
    );
  }

  bool get _isTinyInlineImage {
    final width = widget.width;
    final height = widget.height;
    return width != null && height != null && width <= 32 && height <= 32;
  }

  Widget _image() {
    final assetName = widget.assetName;
    if (assetName != null) {
      return Image.asset(
        assetName,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        errorBuilder: (context, error, stackTrace) {
          assert(() {
            debugPrint(
              'CachedForumImage asset load failed for $assetName, '
              'falling back to network: ${widget.url}',
            );
            return true;
          }());
          return _networkImage();
        },
      );
    }
    return _networkImage();
  }

  Widget _networkImage() {
    ForumTraceLogger.log(
      'ImageLoad',
      'request url=${widget.url} '
          'mem=${widget.memCacheWidth}x${widget.memCacheHeight} '
          'disk=${widget.maxWidthDiskCache}x${widget.maxHeightDiskCache} '
          'retry=$_retry cacheManager=${ForumImageCache.manager.runtimeType}',
    );
    return CachedNetworkImage(
      key: ValueKey('${widget.url}.$_retry'),
      imageUrl: widget.url,
      cacheManager: ForumImageCache.manager,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      imageBuilder: widget.imageBuilder,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
      maxWidthDiskCache: widget.maxWidthDiskCache,
      maxHeightDiskCache: widget.maxHeightDiskCache,
      placeholder: widget.placeholder == null
          ? null
          : (context, url) {
              ForumTraceLogger.log('ImageLoad', 'placeholder url=$url');
              return widget.placeholder!(context);
            },
      errorWidget: widget.errorWidget == null
          ? (context, url, error) {
              ForumTraceLogger.log(
                'ImageLoad',
                'error url=$url error=${error.runtimeType}: $error',
              );
              return _ImageErrorPlaceholder(
                width: widget.width,
                height: widget.height,
                onRetry: _loadNow,
              );
            }
          : (context, url, error) {
              ForumTraceLogger.log(
                'ImageLoad',
                'error url=$url error=${error.runtimeType}: $error',
              );
              return widget.errorWidget!(context);
            },
    );
  }

  void _logDecision(String decision) {
    if (_lastLoggedDecision == decision) return;
    _lastLoggedDecision = decision;
    ForumTraceLogger.log(
      'ImageLoad',
      'decision=$decision url=${widget.url} '
          'view=${widget.width}x${widget.height} fit=${widget.fit} '
          'mem=${widget.memCacheWidth}x${widget.memCacheHeight} '
          'disk=${widget.maxWidthDiskCache}x${widget.maxHeightDiskCache} '
          'retry=$_retry',
    );
  }
}

class _DeferredImagePlaceholder extends StatelessWidget {
  const _DeferredImagePlaceholder({
    required this.onLoad,
    this.width,
    this.height,
  });

  final VoidCallback onLoad;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return _ImageActionPlaceholder(
      width: width,
      height: height,
      icon: Icons.image_outlined,
      label: '点击加载图片',
      onPressed: onLoad,
    );
  }
}

class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder({
    required this.onRetry,
    this.width,
    this.height,
  });

  final VoidCallback onRetry;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return _ImageActionPlaceholder(
      width: width,
      height: height,
      icon: Icons.broken_image_outlined,
      label: '图片加载失败，点按重试',
      onPressed: onRetry,
    );
  }
}

class _ImageActionPlaceholder extends StatelessWidget {
  const _ImageActionPlaceholder({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.width,
    this.height,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.maxWidth.isFinite;
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final resolvedWidth =
            width ?? (hasBoundedWidth ? constraints.maxWidth : double.infinity);
        final resolvedHeight = height ??
            (hasBoundedHeight ? math.min(constraints.maxHeight, 160.0) : 120.0);
        final compact = (hasBoundedWidth && constraints.maxWidth < 64) ||
            (hasBoundedHeight && constraints.maxHeight < 64) ||
            (width != null && width! < 64) ||
            (height != null && height! < 64);

        return Material(
          color: AppColors.surfaceTint,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: resolvedWidth,
              height: resolvedHeight,
              child: Center(
                child: compact
                    ? Icon(icon, color: AppColors.textMuted, size: 18)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: AppColors.textMuted),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
