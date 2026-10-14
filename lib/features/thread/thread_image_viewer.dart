import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../services/image_loading_settings.dart';
import '../../services/image_saver.dart';
import '../common/cached_forum_image.dart';
import 'thread_render_models.dart';

/// The images of one post, so the viewer can page through all of them.
class ThreadImageGallery extends InheritedWidget {
  const ThreadImageGallery({
    super.key,
    required this.renderModel,
    this.extraImages = const [],
    required super.child,
  });

  final ThreadPostRenderModel renderModel;

  /// Images shown after the rich content (posts without segments).
  final List<ThreadImage> extraImages;

  /// Read on tap only, so no widget depends on it.
  static ThreadImageGallery? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ThreadImageGallery>();

  List<ThreadImageRenderBlock> get images {
    final images = <ThreadImageRenderBlock>[];
    void collect(ThreadPostRenderModel model) {
      for (final block in model.blocks) {
        switch (block) {
          case ThreadImageRenderBlock():
            images.add(block);
          case ThreadQuoteRenderBlock(:final renderModel) ||
                ThreadBlockRenderBlock(:final renderModel):
            collect(renderModel);
          case ThreadListRenderBlock(:final items):
            items.forEach(collect);
          case ThreadTableRenderBlock(:final rows):
            for (final row in rows) {
              for (final cell in row) {
                collect(cell.renderModel);
              }
            }
          default:
        }
      }
    }

    collect(renderModel);
    return [
      ...images,
      for (final image in extraImages) ThreadImageRenderBlock(image),
    ];
  }

  @override
  bool updateShouldNotify(ThreadImageGallery oldWidget) => false;
}

/// Opens or copies [url], with feedback shown through [context].
typedef ForumImageLinkAction = void Function(BuildContext context, String url);

final _savingImages = <String>{};

/// Saves a forum image from the shared cache to the gallery, once at a time
/// per image, with feedback through [context]'s messenger while it exists.
Future<void> saveForumImage(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!_savingImages.add(url)) return;
  String? message;
  try {
    if (await ImageLoadingSettings.loadMode() == ImageLoadMode.noImages) return;
    final file = await ForumImageCache.manager.getSingleFile(url);
    await ImageSaver.saveImage(await file.readAsBytes(), sourceUrl: url);
    message = '图片已保存到相册';
  } catch (error) {
    message = '保存图片失败：$error';
  } finally {
    _savingImages.remove(url);
  }
  if (messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Long-press actions for one image: save, copy, open, and its link.
/// [context] opens the sheet and receives the actions' feedback.
void showForumImageMenu(
  BuildContext context, {
  required String url,
  String? href,
  required bool privateMedia,
  required ForumImageLinkAction onOpen,
  required ForumImageLinkAction onCopy,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void run(VoidCallback action) {
        Navigator.of(sheetContext).pop();
        action();
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!privateMedia)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('保存图片'),
                onTap: () => run(() => saveForumImage(context, url)),
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制图片链接'),
              onTap: () => run(() => onCopy(context, url)),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('在浏览器打开图片'),
              onTap: () => run(() => onOpen(context, url)),
            ),
            if (href != null)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('打开链接'),
                subtitle: Text(href, maxLines: 2),
                onTap: () => run(() => onOpen(context, href)),
              ),
          ],
        ),
      );
    },
  );
}

/// Full-screen viewer over [images], starting at [initialIndex].
Future<void> showThreadImageViewer(
  BuildContext context, {
  required List<ThreadImageRenderBlock> images,
  required int initialIndex,
  required bool privateMedia,
  required ForumImageLinkAction onOpen,
  required ForumImageLinkAction onCopy,
}) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: ThreadImageViewer(
        images: images,
        initialIndex: initialIndex,
        privateMedia: privateMedia,
        onOpen: onOpen,
        onCopy: onCopy,
      ),
    ),
  );
}

class ThreadImageViewer extends StatefulWidget {
  const ThreadImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.privateMedia,
    required this.onOpen,
    required this.onCopy,
  });

  final List<ThreadImageRenderBlock> images;
  final int initialIndex;

  /// Memory-only display without saving.
  final bool privateMedia;
  final ForumImageLinkAction onOpen;
  final ForumImageLinkAction onCopy;

  @override
  State<ThreadImageViewer> createState() => _ThreadImageViewerState();
}

class _ThreadImageViewerState extends State<ThreadImageViewer> {
  static const _maxScale = 8.0;

  /// Inside the viewer's own messenger: feedback shows above the page.
  final _scaffoldKey = GlobalKey();

  // Long images keep their full width up to the usual GPU texture limit.
  static const _maxDecodeHeight = 8192;

  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final _zoom = <int, TransformationController>{};
  final _imageKeys = <int, GlobalKey>{};
  // Fill-width scale per long image, which may exceed [_maxScale].
  final _fillScales = <int, double>{};
  Size _viewport = Size.zero;
  Offset? _doubleTapAt;

  TransformationController _zoomOf(int index) => _zoom.putIfAbsent(
      index, () => TransformationController()..addListener(_zoomChanged));

  double get _scale => _zoomOf(_index).value.getMaxScaleOnAxis();

  double _maxScaleOf(int index) => math.max(_maxScale, _fillScales[index] ?? 0);

  bool _zoomed = false;

  void _zoomChanged() {
    final zoomed = _scale > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final controller in _zoom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.images.length) return;
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Scales the current image by [factor] around [focal] (default centre).
  void _zoomBy(double factor, {Offset? focal}) {
    final controller = _zoomOf(_index);
    final current = controller.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, _maxScaleOf(_index));
    if (target <= 1.0) {
      controller.value = Matrix4.identity();
      return;
    }
    final point = focal ?? _viewport.center(Offset.zero);
    final step = target / current;
    controller.value = Matrix4.identity()
      ..translateByDouble(point.dx, point.dy, 0, 1)
      ..scaleByDouble(step, step, 1, 1)
      ..translateByDouble(-point.dx, -point.dy, 0, 1)
      ..multiply(controller.value);
  }

  // Zoomed: back to fit. Narrow (long) image: fill the width from the top.
  // Otherwise: 2.5x where tapped.
  void _toggleZoom() {
    final controller = _zoomOf(_index);
    if (_scale > 1.01) {
      controller.value = Matrix4.identity();
      return;
    }
    final box = _imageKeys[_index]?.currentContext?.findRenderObject();
    final shown = box is RenderBox && box.hasSize ? box.size : null;
    if (shown != null && shown.width > 0) {
      final fill = _viewport.width / shown.width;
      if (fill > 1.2 && shown.height >= _viewport.height - 1) {
        setState(() => _fillScales[_index] = fill);
        final left = (_viewport.width - shown.width) / 2;
        final top = (_viewport.height - shown.height) / 2;
        controller.value = Matrix4.identity()
          ..translateByDouble(-left * fill, -top * fill, 0, 1)
          ..scaleByDouble(fill, fill, 1, 1);
        return;
      }
    }
    _zoomBy(2.5, focal: _doubleTapAt);
  }

  void _showMenu() {
    final image = widget.images[_index];
    showForumImageMenu(
      _scaffoldKey.currentContext!,
      url: image.image.url,
      href: image.href,
      privateMedia: widget.privateMedia,
      onOpen: widget.onOpen,
      onCopy: widget.onCopy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Memory gets a width bound (the shared cache stretches to both); the
    // disk copy and the private path cap the height.
    final spec = ForumImageDecodeSpec.forDisplay(
      logicalSize: Size.square(size.longestSide),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      includeMemHeight: false,
      includeDiskWidth: false,
      includeDiskHeight: false,
      memoryScale: 1.2,
      maxLongEdge: 2600,
    );
    final current = widget.images[_index];
    final count = widget.images.length;
    const white = Colors.white;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_index + 1),
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoomBy(1.5),
        const SingleActivator(LogicalKeyboardKey.add): () => _zoomBy(1.5),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _zoomBy(1.5),
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(1 / 1.5),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
            _zoomBy(1 / 1.5),
        const SingleActivator(LogicalKeyboardKey.digit0): () =>
            _zoomOf(_index).value = Matrix4.identity(),
      },
      child: Focus(
        autofocus: true,
        // Own messenger: the dialog covers the page's snack bars.
        child: ScaffoldMessenger(
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.black,
            body: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '${_index + 1} / $count',
                          style: const TextStyle(color: white),
                        ),
                      ),
                      if (current.href case final href?)
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: white),
                          onPressed: () {
                            final feedback = _scaffoldKey.currentContext!;
                            Navigator.of(context).pop();
                            widget.onOpen(feedback, href);
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('打开链接'),
                        ),
                      IconButton(
                        tooltip: '更多',
                        color: white,
                        onPressed: _showMenu,
                        icon: const Icon(Icons.more_vert),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        color: white,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(builder: (context, constraints) {
                    _viewport = constraints.biggest;
                    return PageView.builder(
                      controller: _pages,
                      // A zoomed image pans instead of turning the page.
                      physics:
                          _zoomed ? const NeverScrollableScrollPhysics() : null,
                      itemCount: count,
                      onPageChanged: (index) {
                        _zoomOf(_index).value = Matrix4.identity();
                        setState(() => _index = index);
                      },
                      itemBuilder: (context, index) {
                        final url = widget.images[index].image.url;
                        return GestureDetector(
                          onDoubleTapDown: (details) =>
                              _doubleTapAt = details.localPosition,
                          onDoubleTap: _toggleZoom,
                          onLongPress: _showMenu,
                          child: InteractiveViewer(
                            transformationController: _zoomOf(index),
                            maxScale: _maxScaleOf(index),
                            child: SizedBox.fromSize(
                              size: _viewport,
                              child: Center(
                                child: KeyedSubtree(
                                  key: _imageKeys.putIfAbsent(
                                      index, GlobalKey.new),
                                  child: CachedForumImage(
                                    url: url,
                                    fit: BoxFit.contain,
                                    memCacheWidth: spec.memCacheWidth,
                                    memCacheHeight: widget.privateMedia
                                        ? _maxDecodeHeight
                                        : null,
                                    maxHeightDiskCache: _maxDecodeHeight,
                                    bypassLoadPolicy: true,
                                    privateMemoryOnly: widget.privateMedia,
                                    errorWidget: (context) => Center(
                                      child: TextButton.icon(
                                        onPressed: () =>
                                            widget.onOpen(context, url),
                                        icon: const Icon(
                                            Icons.broken_image_outlined),
                                        label: const Text('图片加载失败，在浏览器打开'),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
                SafeArea(
                  top: false,
                  // Wraps the save button below at large text sizes.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: '上一张',
                          color: white,
                          onPressed:
                              _index > 0 ? () => _goTo(_index - 1) : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: '缩小',
                          color: white,
                          onPressed: () => _zoomBy(1 / 1.5),
                          icon: const Icon(Icons.zoom_out),
                        ),
                        IconButton(
                          tooltip: '放大',
                          color: white,
                          onPressed: () => _zoomBy(1.5),
                          icon: const Icon(Icons.zoom_in),
                        ),
                        IconButton(
                          tooltip: '下一张',
                          color: white,
                          onPressed: _index < count - 1
                              ? () => _goTo(_index + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ]),
                      if (!widget.privateMedia)
                        ValueListenableBuilder<ImageLoadMode?>(
                          valueListenable: ImageLoadingSettings.notifier,
                          builder: (context, mode, _) => TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: white),
                            onPressed:
                                mode == null || mode == ImageLoadMode.noImages
                                    ? null
                                    : () => saveForumImage(
                                          _scaffoldKey.currentContext!,
                                          current.image.url,
                                        ),
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('保存图片'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
