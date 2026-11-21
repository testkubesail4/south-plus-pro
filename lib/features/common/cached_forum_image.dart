import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  static final _manager = _ForumImageCacheManager();
  static CacheManager get manager => _manager;
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

class CachedForumImage extends StatefulWidget {
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
    this.privateMemoryOnly = false,
    this.decodeToFit = false,
    this.scrollAwareAnimation = false,
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

  /// Private content (PMs): cookie-less, memory-only, untraced, and evicted
  /// from the in-memory image cache when the widget goes away.
  final bool privateMemoryOnly;

  /// Decodes to fit inside both memory bounds, keeping the image's ratio
  /// (the default stretches to both bounds when both are given).
  final bool decodeToFit;
  final bool scrollAwareAnimation;

  @override
  State<CachedForumImage> createState() => _CachedForumImageState();
}

class _CachedForumImageState extends State<CachedForumImage> {
  bool _forcedLoad = false;
  int _retry = 0;
  String? _lastLoggedDecision;
  ImageProvider? _privateProvider;

  @override
  void initState() {
    super.initState();
    ImageLoadingSettings.notifier.addListener(_policyChanged);
  }

  void _policyChanged() {
    setState(() {
      _forcedLoad = false;
    });
  }

  @override
  void dispose() {
    ImageLoadingSettings.notifier.removeListener(_policyChanged);
    _privateProvider?.evict();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CachedForumImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _privateProvider?.evict();
      _privateProvider = null;
      _forcedLoad = false;
      _retry = 0;
      _lastLoggedDecision = null;
    }
  }

  void _loadNow() {
    if (!widget.privateMemoryOnly) {
      ForumTraceLogger.log(
        'ImageLoad',
        'manual load requested url=${widget.url} nextRetry=${_retry + 1}',
      );
    }
    setState(() {
      _privateProvider?.evict();
      _privateProvider = null;
      _forcedLoad = true;
      _retry++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = ImageLoadingSettings.notifier.value;
    if (mode == null || mode == ImageLoadMode.noImages) {
      return const SizedBox.shrink();
    }
    final bypass = widget.bypassLoadPolicy || _forcedLoad || _isTinyInlineImage;
    Widget deferred() => _DeferredImagePlaceholder(
          width: widget.width,
          height: widget.height,
          onLoad: _loadNow,
        );
    if (mode == ImageLoadMode.manual && !bypass) {
      _logDecision('deferred');
      return deferred();
    }
    _logDecision(bypass ? 'bypass' : mode.name);
    Widget admitted(bool visible, Size? previousSize) {
      Widget image() => _image(visible, previousSize);
      if (mode == ImageLoadMode.wifiOnly && !bypass) {
        return _WifiImage(
          key: ValueKey(widget.url),
          image: image,
          deferred: deferred,
        );
      }
      return image();
    }

    if (widget.scrollAwareAnimation && !widget.privateMemoryOnly) {
      return _ViewportImage(
        key: ValueKey('${widget.url}.$_retry'),
        builder: admitted,
      );
    }
    return admitted(true, null);
  }

  bool get _isTinyInlineImage {
    final width = widget.width;
    final height = widget.height;
    return width != null && height != null && width <= 32 && height <= 32;
  }

  Widget _image(bool visible, Size? previousSize) {
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
            if (!widget.privateMemoryOnly) {
              debugPrint(
                'CachedForumImage asset load failed for $assetName, '
                'falling back to network: ${widget.url}',
              );
            }
            return true;
          }());
          return _networkImage(visible, previousSize);
        },
      );
    }
    return _networkImage(visible, previousSize);
  }

  Widget _networkImage(bool visible, Size? previousSize) {
    if (widget.privateMemoryOnly) return _privateNetworkImage();
    ForumTraceLogger.log(
      'ImageLoad',
      'request url=${widget.url} '
          'mem=${widget.memCacheWidth}x${widget.memCacheHeight} '
          'disk=${widget.maxWidthDiskCache}x${widget.maxHeightDiskCache} '
          'retry=$_retry cacheManager=${ForumImageCache.manager.runtimeType}',
    );
    final fitWidth = widget.memCacheWidth;
    final fitHeight = widget.memCacheHeight;
    if (widget.decodeToFit && fitWidth != null && fitHeight != null) {
      return _fittedNetworkImage(fitWidth, fitHeight, visible, previousSize);
    }
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
      // A fading placeholder stays in the image's centering Stack and sizes
      // it, so a narrower image would sit centered and then jump left.
      fadeOutDuration: Duration.zero,
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

  // Same cache and disk bounds as CachedNetworkImage, decoded with the fit
  // policy that CachedNetworkImage's own memory resize does not offer.
  Widget _fittedNetworkImage(
      int width, int height, bool visible, Size? previousSize) {
    final provider = ResizeImage(
      CachedNetworkImageProvider(
        widget.url,
        cacheManager: ForumImageCache.manager,
        maxWidth: widget.scrollAwareAnimation ? null : widget.maxWidthDiskCache,
        maxHeight:
            widget.scrollAwareAnimation ? null : widget.maxHeightDiskCache,
      ),
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
    );
    Widget show(ImageProvider image, bool hasPreview,
            [ImageProvider? fallback, Size? previousSize]) =>
        Image(
          key: ValueKey('${widget.url}.$_retry'),
          image: image,
          gaplessPlayback: widget.scrollAwareAnimation,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          frameBuilder: widget.placeholder == null || hasPreview
              ? null
              : (context, child, frame, _) => frame != null
                  ? child
                  : previousSize == null
                      ? widget.placeholder!(context)
                      : SizedBox.fromSize(size: previousSize),
          errorBuilder: (context, error, stackTrace) {
            ForumTraceLogger.log(
              'ImageLoad',
              'error url=${widget.url} error=${error.runtimeType}: $error',
            );
            if (fallback != null) return show(fallback, hasPreview);
            return widget.errorWidget?.call(context) ??
                _ImageErrorPlaceholder(
                  width: widget.width,
                  height: widget.height,
                  onRetry: _loadNow,
                );
          },
        );
    if (!widget.scrollAwareAnimation) return show(provider, false);
    final preview = _ForumImagePreview((
      url: widget.url,
      width: width,
      height: height,
    ));
    return ValueListenableBuilder<bool>(
      valueListenable: ImageLoadingSettings.playInline,
      builder: (context, playInline, _) {
        if (!playInline) return show(preview, false, null, previousSize);
        return _InlineForumPlayback(
          visible: visible,
          preview: preview,
          animation: provider,
          builder: (image, hasPreview) => show(image, hasPreview,
              image == provider ? preview : null, previousSize),
        );
      },
    );
  }

  // Image.network sends no cookies and keeps bytes only in the in-memory
  // ImageCache, which dispose() evicts.
  Widget _privateNetworkImage() {
    final width = widget.memCacheWidth;
    final height = widget.memCacheHeight;
    // Fit keeps the image's ratio inside both bounds; exact would stretch it.
    _privateProvider ??= width == null && height == null
        ? NetworkImage(widget.url)
        : ResizeImage(
            NetworkImage(widget.url),
            width: width,
            height: height,
            policy: ResizeImagePolicy.fit,
          );
    final provider = _privateProvider!;
    return Image(
      key: ValueKey(_retry),
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      loadingBuilder: widget.placeholder == null
          ? null
          : (context, child, progress) =>
              progress == null ? child : widget.placeholder!(context),
      errorBuilder: (context, error, stackTrace) =>
          widget.errorWidget?.call(context) ??
          _ImageErrorPlaceholder(
            width: widget.width,
            height: widget.height,
            onRetry: _loadNow,
          ),
    );
  }

  void _logDecision(String decision) {
    if (widget.privateMemoryOnly) return;
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

class _WifiImage extends StatefulWidget {
  const _WifiImage({super.key, required this.image, required this.deferred});
  final Widget Function() image;
  final Widget Function() deferred;

  @override
  State<_WifiImage> createState() => _WifiImageState();
}

class _WifiImageState extends State<_WifiImage> {
  late final _onWifi = ImageLoadingSettings.canAutoLoadImages();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _onWifi,
        builder: (context, snapshot) =>
            snapshot.data == true ? widget.image() : widget.deferred(),
      );
}

enum _Proximity { far, near, visible }

class _ViewportImage extends StatefulWidget {
  const _ViewportImage({super.key, required this.builder});

  final Widget Function(bool visible, Size? previousSize) builder;

  @override
  State<_ViewportImage> createState() => _ViewportImageState();
}

class _ViewportImageState extends State<_ViewportImage> {
  _Proximity _proximity = _Proximity.far;
  Size? _previousSize;

  void _update(_Proximity proximity, Size size) {
    if (!mounted || proximity == _proximity) return;
    setState(() {
      if (proximity == _Proximity.far) _previousSize = size;
      _proximity = proximity;
    });
  }

  @override
  Widget build(BuildContext context) => _ImageViewportProbe(
        onChange: _update,
        child: _proximity == _Proximity.far
            ? LimitedBox(
                maxWidth: _previousSize?.width ?? 160,
                child: SizedBox(
                  width: _previousSize?.width ?? double.infinity,
                  height: _previousSize?.height ?? 160,
                ),
              )
            : widget.builder(_proximity == _Proximity.visible, _previousSize),
      );
}

class _ImageViewportProbe extends SingleChildRenderObjectWidget {
  const _ImageViewportProbe({required this.onChange, required super.child});

  final void Function(_Proximity, Size) onChange;

  @override
  _RenderImageViewportProbe createRenderObject(BuildContext context) =>
      _RenderImageViewportProbe(onChange);

  @override
  void updateRenderObject(
      BuildContext context, _RenderImageViewportProbe renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderImageViewportProbe extends RenderProxyBox {
  _RenderImageViewportProbe(this.onChange);

  void Function(_Proximity, Size) onChange;
  VoidCallback? _removeCallback;
  _Proximity _last = _Proximity.far;

  @override
  void paint(PaintingContext context, Offset offset) {
    _removeCallback?.call();
    // Retained floor layers can scroll into view without painting again.
    _removeCallback = context.addCompositionCallback((layer) {
      if (!attached || !hasSize) return;
      final proximity = layer.attached ? _proximity() : _Proximity.far;
      if (proximity == _last) return;
      _last = proximity;
      final measured = size;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached && _last == proximity) onChange(proximity, measured);
      });
    });
    super.paint(context, offset);
  }

  _Proximity _proximity() {
    RenderObject source = this;
    var visible = Offset.zero & size;
    var nearby = visible;
    for (var viewport = RenderAbstractViewport.maybeOf(this);
        viewport != null;
        viewport = RenderAbstractViewport.maybeOf(viewport.parent)) {
      final transform = source.getTransformTo(viewport);
      nearby = MatrixUtils.transformRect(transform, nearby)
          .intersect(viewport.paintBounds.inflate(250));
      if (nearby.isEmpty) return _Proximity.far;
      if (!visible.isEmpty) {
        visible = MatrixUtils.transformRect(transform, visible)
            .intersect(viewport.paintBounds);
      }
      source = viewport;
    }
    return visible.isEmpty ? _Proximity.near : _Proximity.visible;
  }

  @override
  void dispose() {
    _removeCallback?.call();
    super.dispose();
  }
}

class _InlineForumPlayback extends StatefulWidget {
  const _InlineForumPlayback({
    required this.visible,
    required this.preview,
    required this.animation,
    required this.builder,
  });

  final bool visible;
  final _ForumImagePreview preview;
  final ImageProvider animation;
  final Widget Function(ImageProvider, bool hasPreview) builder;

  @override
  State<_InlineForumPlayback> createState() => _InlineForumPlaybackState();
}

class _InlineForumPlaybackState extends State<_InlineForumPlayback> {
  late final _scrollAwareContext = DisposableBuildContext(this);
  List<ScrollPosition> _positions = const [];
  ImageStream? _stream;
  Timer? _resume;
  bool _animated = false;
  bool _hasPreview = false;
  bool _playing = false;
  bool _onstage = false;

  late final _listener = ImageStreamListener((image, _) {
    image.dispose();
    _hasPreview = true;
    final stream = _stream?.completer;
    _animated = stream is _ForumImagePreviewStream && stream.animated;
    _updatePlayback();
  }, onError: (error, stack) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onstage = TickerMode.of(context) &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    for (final position in _positions) {
      position.isScrollingNotifier.removeListener(_updatePlayback);
    }
    _positions = [
      for (var scrollable = Scrollable.maybeOf(context);
          scrollable != null;
          scrollable = Scrollable.maybeOf(scrollable.context))
        scrollable.position,
    ];
    for (final position in _positions) {
      position.isScrollingNotifier.addListener(_updatePlayback);
    }
    if (_stream == null) _listenToPreview();
    _updatePlayback();
  }

  @override
  void didUpdateWidget(covariant _InlineForumPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview != widget.preview) {
      _animated = _hasPreview = _playing = false;
      _listenToPreview();
    }
    _updatePlayback();
  }

  void _listenToPreview() {
    _stream?.removeListener(_listener);
    _stream = ScrollAwareImageProvider(
      context: _scrollAwareContext,
      imageProvider: widget.preview,
    ).resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  bool get _canPlay =>
      _animated &&
      widget.visible &&
      _onstage &&
      !_positions.any((position) => position.isScrollingNotifier.value);

  void _updatePlayback() {
    if (!_canPlay) {
      _resume?.cancel();
      _resume = null;
      if (_playing) setState(() => _playing = false);
    } else if (!_playing) {
      _resume ??= Timer(const Duration(milliseconds: 160), () {
        _resume = null;
        if (mounted && _canPlay) setState(() => _playing = true);
      });
    }
  }

  @override
  void dispose() {
    _resume?.cancel();
    _stream?.removeListener(_listener);
    _scrollAwareContext.dispose();
    for (final position in _positions) {
      position.isScrollingNotifier.removeListener(_updatePlayback);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.builder(
        _playing ? widget.animation : widget.preview, _hasPreview);
    return RepaintBoundary(child: image);
  }
}

class _ForumImagePreview extends ImageProvider<_ForumImagePreview> {
  const _ForumImagePreview(this.spec);

  final ({
    String url,
    int width,
    int height,
  }) spec;

  @override
  Future<_ForumImagePreview> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _ForumImagePreview key,
    ImageDecoderCallback decode,
  ) =>
      _ForumImagePreviewStream(key, decode);

  @override
  bool operator ==(Object other) =>
      other is _ForumImagePreview && other.spec == spec;

  @override
  int get hashCode => spec.hashCode;

  ui.TargetImageSize targetSize(int width, int height) {
    final fitted = applyBoxFit(
      BoxFit.scaleDown,
      Size(width.toDouble(), height.toDouble()),
      Size(spec.width.toDouble(), spec.height.toDouble()),
    ).destination;
    return ui.TargetImageSize(
      width: math.max(1, fitted.width.floor()),
      height: math.max(1, fitted.height.floor()),
    );
  }

  Future<({ui.Image image, bool animated})> firstFrame(
    FileInfo file,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await file.file.readAsBytes();
    Future<({ui.Image image, bool animated})> readFrame(Uint8List data,
        {bool animatedGif = false}) async {
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(data),
          getTargetSize: targetSize);
      try {
        return (
          image: (await codec.getNextFrame()).image,
          animated: animatedGif || codec.frameCount > 1
        );
      } finally {
        codec.dispose();
      }
    }

    // Flutter 3.38 applies the target size only to single-frame GIFs.
    final preview = _firstGifFrame(bytes);
    if (preview != null) {
      try {
        return await readFrame(preview, animatedGif: true);
      } on Exception {
        // Let the platform codec handle GIF layouts it can recover.
      }
    }
    return readFrame(bytes);
  }
}

Uint8List? _firstGifFrame(Uint8List bytes) {
  if (bytes.length < 13 ||
      bytes[0] != 0x47 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46) {
    return null;
  }

  int colorTableSize(int flags) =>
      (flags & 0x80) == 0 ? 0 : 3 << ((flags & 7) + 1);

  int? endOfBlocks(int offset) {
    while (offset < bytes.length) {
      final length = bytes[offset++];
      if (length == 0) return offset;
      offset += length;
    }
    return null;
  }

  var offset = 13 + colorTableSize(bytes[10]);
  int? firstEnd;
  while (offset < bytes.length) {
    final block = bytes[offset++];
    if (block == 0x21) {
      final end = endOfBlocks(offset + 1);
      if (end == null) return null;
      offset = end;
      continue;
    }
    if (block != 0x2c || offset + 9 > bytes.length) return null;
    if (firstEnd != null) {
      return Uint8List(firstEnd + 1)
        ..setRange(0, firstEnd, bytes)
        ..[firstEnd] = 0x3b;
    }
    final imageData = offset + 9 + colorTableSize(bytes[offset + 8]);
    final end = endOfBlocks(imageData + 1);
    if (end == null) return null;
    firstEnd = end;
    offset = end;
  }
  return null;
}

class _ForumImagePreviewStream extends ImageStreamCompleter {
  _ForumImagePreviewStream(
      _ForumImagePreview key, ImageDecoderCallback decode) {
    unawaited(_load(key, decode));
  }

  bool _disposed = false;
  bool animated = false;

  Future<void> _load(
    _ForumImagePreview key,
    ImageDecoderCallback decode,
  ) async {
    final spec = key.spec;
    try {
      await for (final file
          in ForumImageCache.manager.getFileStream(spec.url)) {
        // Let the cache stream finish even when the image stream is disposed.
        if (_disposed || file is! FileInfo) continue;
        final preview = await key.firstFrame(file, decode);
        if (_disposed) {
          preview.image.dispose();
          continue;
        }
        animated = preview.animated;
        setImage(ImageInfo(image: preview.image));
      }
    } catch (error, stack) {
      if (_disposed) return;
      reportError(exception: error, stack: stack, silent: true);
      PaintingBinding.instance.imageCache.evict(key);
    }
  }

  @override
  void onDisposed() {
    _disposed = true;
    super.onDisposed();
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
                          // Large text in a small box shows what fits.
                          Flexible(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
