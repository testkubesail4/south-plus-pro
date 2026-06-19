import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/image_saver.dart';
import '../../services/whats_link_preview_service.dart';
import '../../theme/app_theme.dart';
import '../common/cached_forum_image.dart';
import '../common/forum_emoji_assets.dart';

class ThreadRichContent extends StatelessWidget {
  const ThreadRichContent({
    super.key,
    required this.segments,
  });

  final List<ThreadContentSegment> segments;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    final children = <Widget>[];
    final inlineSpans = <InlineSpan>[];

    void flushInline() {
      if (inlineSpans.isEmpty) return;
      children.add(
        RichText(
          text: TextSpan(style: baseStyle, children: List.of(inlineSpans)),
        ),
      );
      inlineSpans.clear();
    }

    for (final segment in segments) {
      switch (segment.type) {
        case ThreadContentSegmentType.text:
          final href = segment.href;
          if (href != null && _isPreviewableDownloadLink(href)) {
            flushInline();
            children.add(
              Padding(
                padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10),
                child: _DownloadLinkPanel(
                  label: _downloadLinkLabel(segment.text, href),
                  url: href,
                ),
              ),
            );
          } else if (href == null &&
              _appendPlainDownloadLinks(
                context,
                segment,
                baseStyle,
                children,
                inlineSpans,
                flushInline,
              )) {
            break;
          } else {
            inlineSpans.add(_textSpan(context, segment, baseStyle));
          }
        case ThreadContentSegmentType.image:
          if (segment.isEmoji) {
            inlineSpans.add(_emojiSpan(segment));
          } else {
            flushInline();
            final topPadding = children.isEmpty ? 0.0 : 10.0;
            children.add(
              Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: ThreadInlineImage(
                  image: ThreadImage(url: segment.url!, alt: segment.alt),
                ),
              ),
            );
          }
        case ThreadContentSegmentType.quote:
          flushInline();
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _RichQuoteBlock(segments: segment.children),
            ),
          );
      }
    }
    flushInline();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  InlineSpan _textSpan(
    BuildContext context,
    ThreadContentSegment segment,
    TextStyle? baseStyle,
  ) {
    final href = segment.href;
    final color =
        segment.colorValue == null ? null : Color(segment.colorValue!);
    final background = segment.backgroundColorValue == null
        ? null
        : Color(segment.backgroundColorValue!);
    var style = baseStyle?.copyWith(
      color: href == null ? color : AppColors.link,
      backgroundColor: background,
      fontWeight: segment.isBold ? FontWeight.w800 : baseStyle.fontWeight,
      fontStyle: segment.isItalic ? FontStyle.italic : baseStyle.fontStyle,
      decoration: _decoration(
        underline: segment.isUnderline || href != null,
        strike: segment.isStrike,
      ),
      fontSize: (baseStyle.fontSize ?? 16) * segment.fontScale,
    );

    style ??= TextStyle(
      color: href == null ? color : AppColors.link,
      backgroundColor: background,
      fontWeight: segment.isBold ? FontWeight.w800 : FontWeight.normal,
      fontStyle: segment.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: _decoration(
        underline: segment.isUnderline || href != null,
        strike: segment.isStrike,
      ),
      fontSize: 16 * segment.fontScale,
    );

    if (href == null) {
      return TextSpan(text: segment.text, style: style);
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: () => _openInlineLink(context, href),
        onLongPress: () => _copyInlineLink(context, href),
        child: Text(segment.text ?? href, style: style),
      ),
    );
  }

  bool _appendPlainDownloadLinks(
    BuildContext context,
    ThreadContentSegment segment,
    TextStyle? baseStyle,
    List<Widget> children,
    List<InlineSpan> inlineSpans,
    VoidCallback flushInline,
  ) {
    final text = segment.text ?? '';
    final matches = _downloadLinkPattern.allMatches(text).toList();
    if (matches.isEmpty) return false;

    var cursor = 0;
    for (final match in matches) {
      final rawUrl = match.group(0);
      if (rawUrl == null) continue;
      final url = _trimDownloadUrl(rawUrl);
      if (!_isPreviewableDownloadLink(url)) continue;

      final before = text.substring(cursor, match.start);
      if (before.isNotEmpty) {
        inlineSpans.add(
          _textSpan(context, _textSegmentWithText(segment, before), baseStyle),
        );
      }
      flushInline();
      children.add(
        Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10),
          child: _DownloadLinkPanel(
              label: _downloadLinkLabel(null, url), url: url),
        ),
      );
      cursor = match.start + url.length;
    }

    final after = text.substring(cursor);
    if (after.isNotEmpty) {
      inlineSpans.add(
        _textSpan(context, _textSegmentWithText(segment, after), baseStyle),
      );
    }
    return true;
  }

  ThreadContentSegment _textSegmentWithText(
    ThreadContentSegment segment,
    String text,
  ) {
    return ThreadContentSegment.text(
      text,
      colorValue: segment.colorValue,
      backgroundColorValue: segment.backgroundColorValue,
      isBold: segment.isBold,
      isItalic: segment.isItalic,
      isUnderline: segment.isUnderline,
      isStrike: segment.isStrike,
      fontScale: segment.fontScale,
      href: segment.href,
    );
  }

  InlineSpan _emojiSpan(ThreadContentSegment segment) {
    const emojiMaxHeight = 70.0;
    const emojiMaxWidth = 191.0;
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: emojiMaxWidth,
            maxHeight: emojiMaxHeight,
          ),
          child: CachedForumImage(
            url: segment.url!,
            assetName: forumEmojiAssetNameForUrl(segment.url!),
            fit: BoxFit.scaleDown,
            maxHeightDiskCache: emojiMaxHeight.toInt(),
            maxWidthDiskCache: emojiMaxWidth.toInt(),
            bypassLoadPolicy: true,
            errorWidget: (context) => const SizedBox(width: 0, height: 0),
          ),
        ),
      ),
    );
  }

  TextDecoration _decoration({
    required bool underline,
    required bool strike,
  }) {
    final decorations = <TextDecoration>[
      if (underline) TextDecoration.underline,
      if (strike) TextDecoration.lineThrough,
    ];
    if (decorations.isEmpty) return TextDecoration.none;
    if (decorations.length == 1) return decorations.first;
    return TextDecoration.combine(decorations);
  }
}

Future<void> _openInlineLink(BuildContext context, String url) async {
  try {
    await ExternalLinkLauncher.open(url);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }
}

Future<void> _copyInlineLink(BuildContext context, String url) async {
  await _copyDownloadLink(context, url);
}

class _DownloadLinkPanel extends StatelessWidget {
  const _DownloadLinkPanel({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DownloadActionButton(
                onPressed: () => _copyDownloadLink(context, url),
                icon: Icon(Icons.copy_outlined),
                label: '复制',
              ),
              _DownloadActionButton(
                onPressed: () => _showWhatsLinkPreview(context, url),
                icon: Icon(Icons.visibility_outlined),
                label: '预览',
              ),
              _DownloadActionButton(
                filled: true,
                onPressed: () => _openDownloadLink(context, url),
                icon: Icon(Icons.download_outlined),
                label: '下载',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadActionButton extends StatelessWidget {
  const _DownloadActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : AppColors.link;
    final background = filled ? AppColors.brand : Colors.transparent;
    final borderColor = filled ? AppColors.brand : AppColors.border;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground, size: 16),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 5),
                    Text(label),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatsLinkPreviewDialog extends StatefulWidget {
  const _WhatsLinkPreviewDialog({required this.url});

  final String url;

  @override
  State<_WhatsLinkPreviewDialog> createState() =>
      _WhatsLinkPreviewDialogState();
}

class _WhatsLinkPreviewDialogState extends State<_WhatsLinkPreviewDialog> {
  late Future<WhatsLinkPreview> _future = _fetch();

  Future<WhatsLinkPreview> _fetch() {
    return const WhatsLinkPreviewService().fetch(widget.url);
  }

  void _retry() {
    setState(() {
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('链接预览'),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<WhatsLinkPreview>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('正在查询 whatslink.info...'),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '预览失败：${snapshot.error}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              );
            }
            return SingleChildScrollView(
              child: _WhatsLinkPreviewView(preview: snapshot.data!),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        TextButton.icon(
          onPressed: () => _copyDownloadLink(context, widget.url),
          icon: Icon(Icons.copy_outlined),
          label: const Text('复制'),
        ),
        FilledButton.icon(
          onPressed: () => _openDownloadLink(context, widget.url),
          icon: Icon(Icons.download_outlined),
          label: const Text('下载'),
        ),
      ],
    );
  }
}

class _WhatsLinkPreviewView extends StatelessWidget {
  const _WhatsLinkPreviewView({required this.preview});

  final WhatsLinkPreview preview;

  @override
  Widget build(BuildContext context) {
    if (!preview.hasData) {
      return const Text('whatslink.info 没有返回可展示的预览信息。');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.screenshotUrls.isNotEmpty) ...[
          _PreviewScreenshotStrip(urls: preview.screenshotUrls),
          const SizedBox(height: 12),
        ],
        if (preview.name != null)
          Text(
            preview.name!,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        const SizedBox(height: 10),
        _PreviewInfoRow(label: '类型', value: _previewType(preview)),
        _PreviewInfoRow(
          label: '大小',
          value: preview.sizeBytes == null
              ? null
              : _formatBytes(preview.sizeBytes!),
        ),
        _PreviewInfoRow(
          label: '文件数',
          value: preview.fileCount == null ? null : '${preview.fileCount}',
        ),
      ],
    );
  }

  String? _previewType(WhatsLinkPreview preview) {
    final values = [
      if (preview.type != null) preview.type,
      if (preview.fileType != null) preview.fileType,
    ];
    return values.isEmpty ? null : values.join(' / ');
  }
}

class _PreviewScreenshotStrip extends StatelessWidget {
  const _PreviewScreenshotStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showPreviewScreenshotViewer(
                context,
                urls,
                initialIndex: index,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: urls[index],
                    cacheManager: ForumImageCache.manager,
                    fit: BoxFit.cover,
                    memCacheWidth: 480,
                    memCacheHeight: 270,
                    placeholder: (context, url) => ColoredBox(
                      color: AppColors.surfaceTint,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => ColoredBox(
                      color: AppColors.surfaceTint,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
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
    );
  }
}

class _PreviewScreenshotViewer extends StatefulWidget {
  const _PreviewScreenshotViewer({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PreviewScreenshotViewer> createState() =>
      _PreviewScreenshotViewerState();
}

class _PreviewScreenshotViewerState extends State<_PreviewScreenshotViewer> {
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: SizedBox(
        width: size.width * 0.96,
        height: size.height * 0.84,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (index) {
                setState(() {
                  _index = index;
                });
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.urls[index],
                      cacheManager: ForumImageCache.manager,
                      fit: BoxFit.contain,
                      memCacheWidth: 1600,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 12,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    '${_index + 1} / ${widget.urls.length}',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: Colors.white),
                tooltip: '关闭',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showPreviewScreenshotViewer(
  BuildContext context,
  List<String> urls, {
  required int initialIndex,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => _PreviewScreenshotViewer(
      urls: urls,
      initialIndex: initialIndex,
    ),
  );
}

class _PreviewInfoRow extends StatelessWidget {
  const _PreviewInfoRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value!, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

void _showWhatsLinkPreview(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (context) => _WhatsLinkPreviewDialog(url: url),
  );
}

Future<void> _openDownloadLink(BuildContext context, String url) async {
  try {
    await ExternalLinkLauncher.open(url);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }
}

Future<void> _copyDownloadLink(BuildContext context, String url) async {
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('链接已复制')),
  );
}

String _downloadLinkLabel(String? label, String url) {
  final text = label?.trim();
  if (text != null && text.isNotEmpty && text != url) return text;
  if (url.startsWith('magnet:?')) return url;
  if (url.startsWith('ed2k://')) return 'Ed2k 链接';
  return url;
}

bool _isPreviewableDownloadLink(String url) {
  final lower = url.toLowerCase();
  return lower.startsWith('magnet:?') ||
      lower.startsWith('ed2k://') ||
      _downloadFilePattern.hasMatch(lower);
}

String _trimDownloadUrl(String url) {
  return url.replaceFirst(RegExp(r'[\]\),.，。；;]+$'), '');
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final precision = unitIndex == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

final _downloadFilePattern = RegExp(
  r'\.(torrent|zip|rar|7z|iso|mkv|mp4|avi|wmv|mov|apk|exe)(?:[?#]|$)',
  caseSensitive: false,
);

final _downloadLinkPattern = RegExp(
  "(magnet:\\?[^\\s<>\"']+|ed2k://[^\\s<>\"']+|https?://[^\\s<>\"']+\\.(?:torrent|zip|rar|7z|iso|mkv|mp4|avi|wmv|mov|apk|exe)(?:[?#][^\\s<>\"']*)?)",
  caseSensitive: false,
);

class _RichQuoteBlock extends StatelessWidget {
  const _RichQuoteBlock({required this.segments});

  final List<ThreadContentSegment> segments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        border: Border(
          left: BorderSide(color: AppColors.brand, width: 4),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              height: 1.55,
            ),
        child: ThreadRichContent(segments: segments),
      ),
    );
  }
}

class ThreadInlineImage extends StatefulWidget {
  const ThreadInlineImage({super.key, required this.image});

  final ThreadImage image;

  @override
  State<ThreadInlineImage> createState() => _ThreadInlineImageState();
}

class _ThreadInlineImageState extends State<ThreadInlineImage> {
  bool _saving = false;

  Future<void> _saveImage() async {
    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final file = await ForumImageCache.manager.getSingleFile(
        widget.image.url,
      );
      final bytes = await file.readAsBytes();
      await ImageSaver.saveImage(bytes, sourceUrl: widget.image.url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片已保存到相册')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存图片失败：$error')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  void _openImageViewer() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          child: SizedBox(
            width: size.width * 0.92,
            height: size.height * 0.82,
            child: Column(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    child: CachedForumImage(
                      url: widget.image.url,
                      fit: BoxFit.contain,
                      memCacheWidth: 1600,
                      // Opening the viewer is already an explicit load intent,
                      // so the zoomed image should not require a second tap.
                      bypassLoadPolicy: true,
                    ),
                  ),
                ),
                Divider(height: 1),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                    child: TextButton.icon(
                      onPressed: _saveImage,
                      icon: Icon(Icons.download_outlined),
                      label: const Text('保存图片'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _openImageViewer,
      onLongPress: _saveImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          key: const ValueKey('thread-inline-image-container'),
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 360),
          child: CachedForumImage(
            url: widget.image.url,
            fit: BoxFit.contain,
            // Providing both cache dimensions makes Flutter decode to that
            // exact size, which squashes non-square post images.
            memCacheWidth: 720,
            placeholder: (context) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ),
      ),
    );
  }
}
