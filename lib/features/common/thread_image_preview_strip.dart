import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import 'cached_forum_image.dart';

const double _previewThumbWidth = 125;
const double _previewThumbHeight = 94;
const double _previewThumbSpacing = 7;

class ThreadImagePreviewStrip extends StatefulWidget {
  const ThreadImagePreviewStrip({
    super.key,
    required this.thread,
    required this.repository,
    this.topPadding = 8,
  });

  final ForumThread thread;
  final ForumRepository repository;
  final double topPadding;

  @override
  State<ThreadImagePreviewStrip> createState() =>
      _ThreadImagePreviewStripState();
}

class _ThreadImagePreviewStripState extends State<ThreadImagePreviewStrip> {
  late Future<ThreadImagePreview> _previewFuture;
  final Set<String> _failedMediaUrls = <String>{};

  @override
  void initState() {
    super.initState();
    _previewFuture = widget.repository.fetchThreadImagePreview(widget.thread);
  }

  @override
  void didUpdateWidget(covariant ThreadImagePreviewStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thread.url != widget.thread.url ||
        oldWidget.repository != widget.repository) {
      _failedMediaUrls.clear();
      _previewFuture = widget.repository.fetchThreadImagePreview(widget.thread);
    }
  }

  void _hideFailedMedia(String url) {
    if (!mounted) return;
    if (_failedMediaUrls.add(url)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ThreadImagePreview>(
      future: _previewFuture,
      builder: (context, snapshot) {
        final preview = snapshot.data;
        final media = preview?.media
                .where((item) => !_failedMediaUrls.contains(item.displayUrl))
                .toList() ??
            const <ThreadPreviewMedia>[];
        if (preview == null || media.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: EdgeInsets.only(top: widget.topPadding),
          child: SizedBox(
            width: double.infinity,
            child: ClipRect(
              child: SizedBox(
                height: _previewThumbHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: media.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: _previewThumbSpacing),
                  itemBuilder: (context, index) {
                    final item = media[index];
                    return _ThreadPreviewThumb(
                      media: item,
                      onMediaError: () => _hideFailedMedia(item.displayUrl),
                      onTap: () {
                        if (item.type == ThreadPreviewMediaType.video) {
                          _showVideoDialog(context, item);
                          return;
                        }
                        _showPreviewDialog(
                          context,
                          media: media
                              .where(
                                (item) =>
                                    item.type ==
                                    ThreadPreviewMediaType.image,
                              )
                              .toList(),
                          initialMedia: item,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThreadPreviewThumb extends StatelessWidget {
  const _ThreadPreviewThumb({
    required this.media,
    required this.onTap,
    required this.onMediaError,
  });

  final ThreadPreviewMedia media;
  final VoidCallback onTap;
  final VoidCallback onMediaError;

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (_previewThumbWidth * pixelRatio).round();

    return Semantics(
      button: true,
      label: '预览图片',
      child: Material(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: _previewThumbWidth,
            height: _previewThumbHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (media.displayUrl.isNotEmpty)
                  CachedForumImage(
                    url: media.displayUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: cacheWidth,
                    placeholder: (context) => const _PreviewLoadingThumb(),
                    errorWidget: (context) => media.type ==
                            ThreadPreviewMediaType.video
                        ? const _VideoFallbackThumb()
                        : const SizedBox.shrink(),
                    onError: (_) {
                      if (media.type == ThreadPreviewMediaType.image) {
                        onMediaError();
                      }
                    },
                  )
                else
                  const _VideoFallbackThumb(),
                if (media.type == ThreadPreviewMediaType.video)
                  const _VideoPlayBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewLoadingThumb extends StatelessWidget {
  const _PreviewLoadingThumb();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: AppColors.inkSoft);
  }
}

class _VideoFallbackThumb extends StatelessWidget {
  const _VideoFallbackThumb();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171717),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: Colors.white70,
          size: 24,
        ),
      ),
    );
  }
}

class _VideoPlayBadge extends StatelessWidget {
  const _VideoPlayBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.all(7),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

Future<void> _openVideoSource(
  BuildContext context,
  ThreadPreviewMedia media,
) async {
  try {
    await ExternalLinkLauncher.open(media.openUrl);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }
}

class _ThreadVideoDialog extends StatefulWidget {
  const _ThreadVideoDialog({required this.media});

  final ThreadPreviewMedia media;

  @override
  State<_ThreadVideoDialog> createState() => _ThreadVideoDialogState();
}

class _ThreadVideoDialogState extends State<_ThreadVideoDialog> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _initialize() {
    final videoUrl = widget.media.videoUrl;
    final uri = videoUrl == null ? null : Uri.tryParse(videoUrl);
    if (uri == null) {
      _error = '视频地址无效';
      return;
    }

    final oldController = _controller;
    oldController?.removeListener(_handleVideoChanged);
    oldController?.dispose();

    final controller = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: widget.media.videoHeaders,
    );
    controller.addListener(_handleVideoChanged);
    _controller = controller;
    _error = null;
    _initializeFuture = controller.initialize().then((_) async {
      await controller.play();
      if (mounted) setState(() {});
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    });
  }

  void _handleVideoChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final description = controller.value.errorDescription;
    if (description != null && description != _error) {
      setState(() => _error = description);
      return;
    }
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  void _retry() {
    setState(_initialize);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return _FloatingPreviewShell(
      child: Stack(
        children: [
          Center(
            child: _error != null
                ? _VideoErrorPanel(
                    error: _error!,
                    onRetry: _retry,
                    onOpenSource: () => _openVideoSource(
                      context,
                      widget.media,
                    ),
                  )
                : FutureBuilder<void>(
                    future: _initializeFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done ||
                          controller == null ||
                          !controller.value.isInitialized) {
                        return const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        );
                      }
                      return _VideoSurface(
                        controller: controller,
                        onTogglePlayback: _togglePlayback,
                      );
                    },
                  ),
          ),
          Positioned(
            right: 6,
            top: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: '关闭',
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: TextButton.icon(
              onPressed: () => _openVideoSource(context, widget.media),
              style: TextButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('来源'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingPreviewShell extends StatelessWidget {
  const _FloatingPreviewShell({
    required this.child,
    this.dismissOnBackgroundTap = false,
  });

  final Widget child;
  final bool dismissOnBackgroundTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(child: child),
    );
  }
}

class _FloatingMediaBox extends StatelessWidget {
  const _FloatingMediaBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _LargeVideoProgress extends StatelessWidget {
  const _LargeVideoProgress({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Center(
        child: SizedBox(
          height: 18,
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 7),
            colors: const VideoProgressColors(
              playedColor: Colors.white,
              bufferedColor: Colors.white38,
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTimeLabel extends StatelessWidget {
  const _VideoTimeLabel({required this.value});

  final VideoPlayerValue value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Text(
        '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
        textAlign: TextAlign.right,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({
    required this.controller,
    required this.onTogglePlayback,
  });

  final VideoPlayerController controller;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: _FloatingMediaBox(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTogglePlayback,
                child: AspectRatio(
                  aspectRatio:
                      value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Row(
              children: [
                IconButton(
                  onPressed: onTogglePlayback,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  tooltip: value.isPlaying ? '暂停' : '播放',
                ),
                Expanded(
                  child: _LargeVideoProgress(controller: controller),
                ),
                const SizedBox(width: 10),
                _VideoTimeLabel(value: value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoErrorPanel extends StatelessWidget {
  const _VideoErrorPanel({
    required this.error,
    required this.onRetry,
    required this.onOpenSource,
  });

  final String error;
  final VoidCallback onRetry;
  final VoidCallback onOpenSource;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_disabled_outlined,
              color: Colors.white70,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              '视频加载失败',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                ),
                TextButton.icon(
                  onPressed: onOpenSource,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('来源'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '$minutes:${two(seconds)}';
}

class _ThreadPreviewDialog extends StatefulWidget {
  const _ThreadPreviewDialog({
    required this.media,
    required this.initialIndex,
  });

  final List<ThreadPreviewMedia> media;
  final int initialIndex;

  @override
  State<_ThreadPreviewDialog> createState() => _ThreadPreviewDialogState();
}

class _ThreadPreviewDialogState extends State<_ThreadPreviewDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCurrentImage() async {
    try {
      await ExternalLinkLauncher.open(widget.media[_index].openUrl);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final previewMaxWidth = math.max(
      0.0,
      size.width - 36,
    );
    final previewMaxHeight = math.max(
      0.0,
      size.height - 36,
    );
    return _FloatingPreviewShell(
      dismissOnBackgroundTap: true,
      child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.media.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Center(
                        child: GestureDetector(
                          onTap: () {},
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: previewMaxWidth,
                                maxHeight: previewMaxHeight,
                              ),
                              child: _FloatingMediaBox(
                                child: CachedForumImage(
                                  url: widget.media[index].displayUrl,
                                  fit: BoxFit.contain,
                                  placeholder: (context) => const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  errorWidget: (context) => const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white70,
                                      size: 36,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 12,
                top: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      '${_index + 1} / ${widget.media.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: '关闭',
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: TextButton.icon(
                  onPressed: _openCurrentImage,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('原图'),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

void _showPreviewDialog(
  BuildContext context, {
  required List<ThreadPreviewMedia> media,
  required ThreadPreviewMedia initialMedia,
}) {
  final initialIndex = media.indexOf(initialMedia);
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    barrierDismissible: true,
    builder: (context) => _ThreadPreviewDialog(
      media: media,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    ),
  );
}

void _showVideoDialog(BuildContext context, ThreadPreviewMedia media) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _ThreadVideoDialog(media: media),
  );
}
