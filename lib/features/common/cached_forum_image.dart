import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../services/image_loading_settings.dart';
import '../../theme/app_theme.dart';

class ForumImageCache {
  ForumImageCache._();

  static const stalePeriod = Duration(days: 180);

  static final CacheManager manager = CacheManager(
    Config(
      'southPlusForumImages',
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: 2000,
    ),
  );
}

class CachedForumImage extends StatelessWidget {
  const CachedForumImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.placeholder,
    this.errorWidget,
    this.onError,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final ValueChanged<Object>? onError;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  Widget build(BuildContext context) {
    return _PolicyAwareCachedImage(
      url: url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      placeholder: placeholder,
      errorWidget: errorWidget,
      onError: onError,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
    );
  }
}

class _PolicyAwareCachedImage extends StatefulWidget {
  const _PolicyAwareCachedImage({
    required this.url,
    this.width,
    this.height,
    this.fit,
    required this.alignment,
    this.placeholder,
    this.errorWidget,
    this.onError,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Alignment alignment;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final ValueChanged<Object>? onError;
  final int? memCacheWidth;
  final int? memCacheHeight;

  @override
  State<_PolicyAwareCachedImage> createState() =>
      _PolicyAwareCachedImageState();
}

class _PolicyAwareCachedImageState extends State<_PolicyAwareCachedImage> {
  late Future<bool> _canLoad = ImageLoadingSettings.canAutoLoadImages();
  bool _forcedLoad = false;
  int _retry = 0;

  @override
  void didUpdateWidget(covariant _PolicyAwareCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _forcedLoad = false;
      _retry = 0;
      _canLoad = ImageLoadingSettings.canAutoLoadImages();
    }
  }

  void _loadNow() {
    setState(() {
      _forcedLoad = true;
      _retry++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_forcedLoad) return _image();
    if (_isTinyInlineImage) return _image();

    return FutureBuilder<bool>(
      future: _canLoad,
      builder: (context, snapshot) {
        if (snapshot.data ?? false) return _image();
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
    return CachedNetworkImage(
      key: ValueKey('${widget.url}.$_retry'),
      imageUrl: widget.url,
      cacheManager: ForumImageCache.manager,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
      placeholder: widget.placeholder == null
          ? null
          : (context, url) => widget.placeholder!(context),
      errorListener: widget.onError,
      errorWidget: widget.errorWidget == null
          ? (context, url, error) => _ImageErrorPlaceholder(
                width: widget.width,
                height: widget.height,
                onRetry: _loadNow,
              )
          : (context, url, error) => widget.errorWidget!(context),
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
