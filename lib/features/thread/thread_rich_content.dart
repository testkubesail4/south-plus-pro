import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectionRegistrar;
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/perf_trace.dart';
import '../../services/whats_link_preview_service.dart';
import '../../theme/app_theme.dart';
import '../common/cached_forum_image.dart';
import '../common/forum_emoji_assets.dart';
import 'thread_image_viewer.dart';
import 'thread_render_models.dart';
import 'thread_sale_box_view.dart';

class ThreadRichContent extends StatelessWidget {
  ThreadRichContent({
    super.key,
    required List<ThreadContentSegment> segments,
    this.buyingSaleBoxes = const <String>{},
    this.onBuySaleBox,
    this.onOpenLink,
    this.privateMedia = false,
  })  : alignment = ThreadContentAlignment.start,
        renderModel = ThreadPostRenderModel.fromSegments(segments);

  const ThreadRichContent.renderModel({
    super.key,
    required this.renderModel,
    this.buyingSaleBoxes = const <String>{},
    this.onBuySaleBox,
    this.onOpenLink,
    this.privateMedia = false,
    this.alignment = ThreadContentAlignment.start,
  });

  final ThreadPostRenderModel renderModel;
  final Set<String> buyingSaleBoxes;
  final ValueChanged<ThreadSaleBox>? onBuySaleBox;
  final Future<void> Function(String url, String label)? onOpenLink;

  /// Private content (PMs): images stay memory-only and are never saved,
  /// and download links are not sent to the third-party preview service.
  final bool privateMedia;
  final ThreadContentAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return PerfTrace.span(
      'ThreadRichContent.build',
      () {
        final baseStyle =
            Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.62);
        final selectionRegistrar = SelectionContainer.maybeOf(context);
        final selectionColor =
            DefaultSelectionStyle.of(context).selectionColor ??
                DefaultSelectionStyle.defaultColor;
        final children = _buildChildren(
          context,
          renderModel.blocks,
          baseStyle,
          selectionRegistrar,
          selectionColor,
          buyingSaleBoxes,
          onBuySaleBox,
          onOpenLink,
          privateMedia,
          alignment,
        );

        final column = Column(
          crossAxisAlignment: switch (alignment) {
            ThreadContentAlignment.center => CrossAxisAlignment.center,
            ThreadContentAlignment.end => CrossAxisAlignment.end,
            ThreadContentAlignment.justify => CrossAxisAlignment.stretch,
            ThreadContentAlignment.start => CrossAxisAlignment.start,
          },
          children: children,
        );
        // The outermost content owns the gallery; nested parts reuse it.
        return ThreadImageGallery.maybeOf(context) == null
            ? ThreadImageGallery(renderModel: renderModel, child: column)
            : column;
      },
      arguments: {'blocks': renderModel.blocks.length},
    );
  }
}

List<Widget> _buildChildren(
  BuildContext context,
  List<ThreadRenderBlock> blocks,
  TextStyle? baseStyle,
  SelectionRegistrar? selectionRegistrar,
  Color selectionColor,
  Set<String> buyingSaleBoxes,
  ValueChanged<ThreadSaleBox>? onBuySaleBox,
  Future<void> Function(String url, String label)? onOpenLink,
  bool privateMedia,
  ThreadContentAlignment alignment,
) {
  final children = <Widget>[];
  final inlineSpans = <InlineSpan>[];

  Widget nested(
    ThreadPostRenderModel model, {
    ThreadContentAlignment alignment = ThreadContentAlignment.start,
  }) =>
      ThreadRichContent.renderModel(
        renderModel: model,
        buyingSaleBoxes: buyingSaleBoxes,
        onBuySaleBox: onBuySaleBox,
        onOpenLink: onOpenLink,
        privateMedia: privateMedia,
        alignment: alignment,
      );

  void addBlockChild(Widget child) {
    children.add(Padding(
      padding: EdgeInsets.only(top: children.isEmpty ? 0 : 8),
      child: child,
    ));
  }

  void flushInline() {
    if (inlineSpans.isEmpty) return;
    children.add(
      RichText(
        textAlign: switch (alignment) {
          ThreadContentAlignment.center => TextAlign.center,
          ThreadContentAlignment.end => TextAlign.end,
          ThreadContentAlignment.justify => TextAlign.justify,
          ThreadContentAlignment.start => TextAlign.start,
        },
        selectionRegistrar: selectionRegistrar,
        selectionColor: selectionColor,
        // RichText does not inherit MediaQuery scaling on its own.
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(
            style: baseStyle, children: List<InlineSpan>.of(inlineSpans)),
      ),
    );
    inlineSpans.clear();
  }

  for (final block in blocks) {
    switch (block.type) {
      case ThreadRenderBlockType.text:
        final textBlock = block as ThreadTextRenderBlock;
        inlineSpans.add(
          TextSpan(
            text: textBlock.text,
            style: _threadTextStyle(baseStyle, textBlock.style),
          ),
        );
      case ThreadRenderBlockType.link:
        final linkBlock = block as ThreadLinkRenderBlock;
        inlineSpans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: SelectionContainer.disabled(
              child: Semantics(
                link: true,
                child: GestureDetector(
                  onTap: () => _openContentLink(
                    context,
                    linkBlock.url,
                    linkBlock.text,
                    onOpenLink,
                  ),
                  onLongPress: () => _showLinkSheet(
                    context,
                    linkBlock.url,
                    () => _openContentLink(
                      context,
                      linkBlock.url,
                      linkBlock.text,
                      onOpenLink,
                    ),
                  ),
                  child: Text(
                    linkBlock.text,
                    // The paragraph already scales its inline widgets.
                    textScaler: TextScaler.noScaling,
                    style: _threadTextStyle(
                      baseStyle,
                      linkBlock.style,
                      forceLinkColor: true,
                      forceUnderline: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case ThreadRenderBlockType.downloadLink:
        final downloadBlock = block as ThreadDownloadLinkRenderBlock;
        flushInline();
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10),
            child: _DownloadLinkPanel(
              label: downloadBlock.label,
              url: downloadBlock.url,
              onOpenLink: onOpenLink,
              allowPreview: !privateMedia,
            ),
          ),
        );
      case ThreadRenderBlockType.image:
        final imageBlock = block as ThreadImageRenderBlock;
        flushInline();
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10),
            child: ThreadInlineImage(
              image: imageBlock.image,
              href: imageBlock.href,
              privateMedia: privateMedia,
              onOpenLink: onOpenLink,
            ),
          ),
        );
      case ThreadRenderBlockType.emoji:
        final emojiBlock = block as ThreadEmojiRenderBlock;
        inlineSpans.add(
          _emojiSpan(context, emojiBlock, privateMedia, onOpenLink),
        );
      case ThreadRenderBlockType.quote:
        final quoteBlock = block as ThreadQuoteRenderBlock;
        flushInline();
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _RichQuoteBlock(
              renderModel: quoteBlock.renderModel,
              buyingSaleBoxes: buyingSaleBoxes,
              onBuySaleBox: onBuySaleBox,
              onOpenLink: onOpenLink,
              privateMedia: privateMedia,
            ),
          ),
        );
      case ThreadRenderBlockType.saleBox:
        final saleBlock = block as ThreadSaleBoxRenderBlock;
        flushInline();
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10),
            child: ThreadSaleBoxView(
              saleBox: saleBlock.saleBox,
              isBuying: buyingSaleBoxes.contains(saleBlock.saleBox.buyPath),
              onBuy: onBuySaleBox == null
                  ? null
                  : () => onBuySaleBox(saleBlock.saleBox),
            ),
          ),
        );
      case ThreadRenderBlockType.block:
        final paragraph = block as ThreadBlockRenderBlock;
        flushInline();
        children.add(SizedBox(
          width: double.infinity,
          child: nested(paragraph.renderModel, alignment: paragraph.alignment),
        ));
      case ThreadRenderBlockType.code:
        flushInline();
        addBlockChild(_CodeBlock(text: (block as ThreadCodeRenderBlock).text));
      case ThreadRenderBlockType.list:
        final listBlock = block as ThreadListRenderBlock;
        flushInline();
        addBlockChild(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < listBlock.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 22),
                      child: Text(
                        listBlock.markerAt(i),
                        style: baseStyle?.copyWith(color: AppColors.textMuted),
                        textScaler: MediaQuery.textScalerOf(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: nested(listBlock.items[i])),
                  ],
                ),
              ),
          ],
        ));
      case ThreadRenderBlockType.table:
        flushInline();
        addBlockChild(_RichTable(
          rows: (block as ThreadTableRenderBlock).rows,
          cellBuilder: nested,
        ));
      case ThreadRenderBlockType.media:
        final media = block as ThreadMediaRenderBlock;
        flushInline();
        addBlockChild(_MediaFallbackCard(
          url: media.url,
          label: media.label,
          onOpenLink: onOpenLink,
        ));
    }
  }

  flushInline();
  return children;
}

TextStyle _threadTextStyle(
  TextStyle? baseStyle,
  ThreadTextStyleData style, {
  bool forceLinkColor = false,
  bool forceUnderline = false,
}) {
  final color = style.colorValue == null ? null : Color(style.colorValue!);
  final background = style.backgroundColorValue == null
      ? null
      : Color(style.backgroundColorValue!);
  final decoration = _decoration(
    underline: style.isUnderline || forceUnderline,
    strike: style.isStrike,
  );

  return (baseStyle ?? const TextStyle()).copyWith(
    color: forceLinkColor ? AppColors.link : color,
    backgroundColor: background,
    fontWeight: style.isBold ? FontWeight.w800 : baseStyle?.fontWeight,
    fontStyle: style.isItalic ? FontStyle.italic : baseStyle?.fontStyle,
    decoration: decoration,
    fontSize: (baseStyle?.fontSize ?? 16) * style.fontScale,
    // Fonts the device lacks fall back to the platform font.
    fontFamily: style.fontFamily ?? baseStyle?.fontFamily,
  );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '代码',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              SelectionContainer.disabled(
                child: IconButton(
                  tooltip: '复制代码',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () => _copyText(context, text, '代码已复制'),
                ),
              ),
            ],
          ),
          Divider(height: 1, color: AppColors.border),
          // Literal text: tags and whitespace inside code are shown as written.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Text(
              text,
              softWrap: false,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.text,
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier New', 'Courier'],
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RichTable extends StatelessWidget {
  const _RichTable({required this.rows, required this.cellBuilder});

  final List<List<ThreadTableRenderCell>> rows;
  final Widget Function(ThreadPostRenderModel model) cellBuilder;

  static const _minColumnWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final columns =
        rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    return LayoutBuilder(builder: (context, constraints) {
      // Columns share the width but never shrink below a readable minimum;
      // wider tables scroll sideways instead of crushing their text.
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final columnWidth = available / columns < _minColumnWidth
          ? _minColumnWidth
          : available / columns;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: FixedColumnWidth(columnWidth),
          border: TableBorder.all(color: AppColors.border),
          children: [
            for (final row in rows)
              TableRow(
                decoration: row.every((cell) => cell.isHeader)
                    ? BoxDecoration(color: AppColors.surfaceTint)
                    : null,
                children: [
                  for (var i = 0; i < columns; i++)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: i < row.length
                          ? DefaultTextStyle.merge(
                              style: row[i].isHeader
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : null,
                              child: cellBuilder(row[i].renderModel),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      );
    });
  }
}

class _MediaFallbackCard extends StatelessWidget {
  const _MediaFallbackCard({
    required this.url,
    required this.label,
    required this.onOpenLink,
  });

  final String? url;
  final String label;
  final Future<void> Function(String url, String label)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = this.url;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.play_circle_outline, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.isEmpty ? '媒体内容' : label,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            url == null ? '媒体内容无法在应用内播放' : url,
            style: theme.textTheme.bodySmall,
          ),
          if (url != null) ...[
            const SizedBox(height: 8),
            SelectionContainer.disabled(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DownloadActionButton(
                    onPressed: () => _copyDownloadLink(context, url),
                    icon: const Icon(Icons.copy_outlined),
                    label: '复制',
                  ),
                  _DownloadActionButton(
                    filled: true,
                    onPressed: () =>
                        _openContentLink(context, url, label, onOpenLink),
                    icon: const Icon(Icons.open_in_new),
                    label: '打开',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _copyText(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
}

InlineSpan _emojiSpan(
  BuildContext context,
  ThreadEmojiRenderBlock block,
  bool privateMedia,
  Future<void> Function(String url, String label)? onOpenLink,
) {
  const emojiMaxHeight = 70.0;
  const emojiMaxWidth = 191.0;
  final spec = ForumImageDecodeSpec.forDisplay(
    logicalSize: const Size(emojiMaxWidth, emojiMaxHeight),
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    maxLongEdge: 512,
  );

  final href = block.href;
  final emoji = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: emojiMaxWidth,
        maxHeight: emojiMaxHeight,
      ),
      child: CachedForumImage(
        url: block.url,
        assetName: forumEmojiAssetNameForUrl(block.url),
        fit: BoxFit.scaleDown,
        memCacheWidth: spec.memCacheWidth,
        memCacheHeight: spec.memCacheHeight,
        maxWidthDiskCache: spec.maxWidthDiskCache,
        maxHeightDiskCache: spec.maxHeightDiskCache,
        bypassLoadPolicy: true,
        privateMemoryOnly: privateMedia,
        errorWidget: (context) => const SizedBox(width: 0, height: 0),
      ),
    ),
  );
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    // A linked face has no viewer, so tapping it follows the link.
    child: href == null
        ? emoji
        : SelectionContainer.disabled(
            child: Semantics(
              link: true,
              child: GestureDetector(
                onTap: () => _openContentLink(context, href, '', onOpenLink),
                onLongPress: () => _showLinkSheet(
                  context,
                  href,
                  () => _openContentLink(context, href, '', onOpenLink),
                ),
                child: emoji,
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

Future<void> _openContentLink(
  BuildContext context,
  String url,
  String label,
  Future<void> Function(String url, String label)? onOpenLink,
) async {
  if (onOpenLink != null) {
    await onOpenLink(url, label);
    return;
  }
  try {
    await ExternalLinkLauncher.open(url);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }
}

// Shows the full destination before acting, so a disguised label can't hide it.
void _showLinkSheet(BuildContext context, String url, VoidCallback onOpen) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              url,
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _copyDownloadLink(context, url);
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制链接'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    onOpen();
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _DownloadLinkPanel extends StatelessWidget {
  const _DownloadLinkPanel({
    required this.label,
    required this.url,
    this.onOpenLink,
    this.allowPreview = true,
  });

  final String label;
  final String url;
  final Future<void> Function(String url, String label)? onOpenLink;
  final bool allowPreview;

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
          SelectionContainer.disabled(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DownloadActionButton(
                  onPressed: () => _copyDownloadLink(context, url),
                  icon: const Icon(Icons.copy_outlined),
                  label: '复制',
                ),
                if (allowPreview)
                  _DownloadActionButton(
                    onPressed: () =>
                        _showWhatsLinkPreview(context, url, onOpenLink),
                    icon: const Icon(Icons.visibility_outlined),
                    label: '预览',
                  ),
                _DownloadActionButton(
                  filled: true,
                  onPressed: () =>
                      _openContentLink(context, url, label, onOpenLink),
                  icon: const Icon(Icons.download_outlined),
                  label: '下载',
                ),
              ],
            ),
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
  const _WhatsLinkPreviewDialog({required this.url, this.onOpenLink});

  final String url;
  final Future<void> Function(String url, String label)? onOpenLink;

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
                    icon: const Icon(Icons.refresh),
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
          icon: const Icon(Icons.copy_outlined),
          label: const Text('复制'),
        ),
        FilledButton.icon(
          onPressed: () =>
              _openContentLink(context, widget.url, '', widget.onOpenLink),
          icon: const Icon(Icons.download_outlined),
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
    final spec = ForumImageDecodeSpec.forDisplay(
      logicalSize: const Size(132 * 16 / 9, 132),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      maxLongEdge: 960,
    );

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
                  child: CachedForumImage(
                    url: urls[index],
                    bypassLoadPolicy: true,
                    fit: BoxFit.cover,
                    memCacheWidth: spec.memCacheWidth,
                    memCacheHeight: spec.memCacheHeight,
                    maxWidthDiskCache: spec.maxWidthDiskCache,
                    maxHeightDiskCache: spec.maxHeightDiskCache,
                    placeholder: (context) => ColoredBox(
                      color: AppColors.surfaceTint,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context) => ThreadImageFailurePlaceholder(
                      url: urls[index],
                      onOpen: () => _openDownloadLink(context, urls[index]),
                      onCopy: () => _copyDownloadLink(context, urls[index]),
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
    final spec = ForumImageDecodeSpec.forDisplay(
      // Same bounds as the post image viewer: never stretch to the box.
      logicalSize: Size.square(size.longestSide * 0.96),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      includeMemHeight: false,
      includeDiskWidth: false,
      memoryScale: 1.15,
      diskScale: 1.15,
      maxLongEdge: 2400,
    );

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
                    child: CachedForumImage(
                      url: widget.urls[index],
                      bypassLoadPolicy: true,
                      fit: BoxFit.contain,
                      memCacheWidth: spec.memCacheWidth,
                      memCacheHeight: spec.memCacheHeight,
                      maxWidthDiskCache: spec.maxWidthDiskCache,
                      maxHeightDiskCache: spec.maxHeightDiskCache,
                      placeholder: (context) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context) => ThreadImageFailurePlaceholder(
                        url: widget.urls[index],
                        onOpen: () =>
                            _openDownloadLink(context, widget.urls[index]),
                        onCopy: () =>
                            _copyDownloadLink(context, widget.urls[index]),
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white70,
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
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
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

void _showWhatsLinkPreview(
  BuildContext context,
  String url,
  Future<void> Function(String url, String label)? onOpenLink,
) {
  showDialog<void>(
    context: context,
    builder: (context) =>
        _WhatsLinkPreviewDialog(url: url, onOpenLink: onOpenLink),
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

class _RichQuoteBlock extends StatelessWidget {
  const _RichQuoteBlock({
    required this.renderModel,
    required this.buyingSaleBoxes,
    required this.onBuySaleBox,
    required this.onOpenLink,
    required this.privateMedia,
  });

  final ThreadPostRenderModel renderModel;
  final Set<String> buyingSaleBoxes;
  final ValueChanged<ThreadSaleBox>? onBuySaleBox;
  final Future<void> Function(String url, String label)? onOpenLink;
  final bool privateMedia;

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
        child: ThreadRichContent.renderModel(
          renderModel: renderModel,
          buyingSaleBoxes: buyingSaleBoxes,
          onBuySaleBox: onBuySaleBox,
          onOpenLink: onOpenLink,
          privateMedia: privateMedia,
        ),
      ),
    );
  }
}

class ThreadInlineImage extends StatelessWidget {
  const ThreadInlineImage({
    super.key,
    required this.image,
    this.privateMedia = false,
    this.onOpenLink,
    this.href,
  });

  final ThreadImage image;

  /// Memory-only display; saving would route bytes through the disk cache.
  final bool privateMedia;

  /// Link policy for the failure placeholder's and [href]'s open actions.
  final Future<void> Function(String url, String label)? onOpenLink;

  /// Link wrapping the image; tap still opens the viewer.
  final String? href;

  void _openImageViewer(BuildContext context) {
    final gallery = ThreadImageGallery.maybeOf(context)?.images ?? const [];
    // This occurrence: the same URL may repeat with another link around it.
    final index = gallery.indexWhere((item) => identical(item.image, image));
    showThreadImageViewer(
      context,
      images: index < 0 ? [ThreadImageRenderBlock(image, href: href)] : gallery,
      initialIndex: index < 0 ? 0 : index,
      privateMedia: privateMedia,
      onOpen: _openFrom(context),
      onCopy: _copyDownloadLink,
    );
  }

  // A closed viewer's context falls back to the post's for link feedback.
  ForumImageLinkAction _openFrom(BuildContext postContext) =>
      (context, url) => _openContentLink(
            context.mounted ? context : postContext,
            url,
            '',
            onOpenLink,
          );

  @override
  Widget build(BuildContext context) {
    return PerfTrace.span(
      'ThreadInlineImage.build',
      () {
        return SelectionContainer.disabled(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openImageViewer(context),
            onLongPress: switch (href) {
              // A linked image's long press shows its destination first.
              final href? => () => _showLinkSheet(
                    context,
                    href,
                    () => _openContentLink(context, href, '', onOpenLink),
                  ),
              null => () => showForumImageMenu(
                    context,
                    url: image.url,
                    privateMedia: privateMedia,
                    onOpen: _openFrom(context),
                    onCopy: _copyDownloadLink,
                  ),
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                key: const ValueKey('thread-inline-image-container'),
                constraints: const BoxConstraints(maxHeight: 360),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final logicalWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    final spec = ForumImageDecodeSpec.forDisplay(
                      logicalSize: Size(logicalWidth, 360),
                      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                      maxLongEdge: 1600,
                    );

                    return CachedForumImage(
                      url: image.url,
                      fit: BoxFit.scaleDown,
                      // Width- or height-bound alike, decode what is shown.
                      decodeToFit: true,
                      memCacheWidth: spec.memCacheWidth,
                      memCacheHeight: spec.memCacheHeight,
                      maxWidthDiskCache: spec.maxWidthDiskCache,
                      maxHeightDiskCache: spec.maxHeightDiskCache,
                      privateMemoryOnly: privateMedia,
                      placeholder: (context) {
                        return const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorWidget: (context) => ThreadImageFailurePlaceholder(
                        url: image.url,
                        onOpen: () => _openContentLink(
                          context,
                          image.url,
                          '',
                          onOpenLink,
                        ),
                        onCopy: () => _copyDownloadLink(context, image.url),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      // Private image URLs stay out of timeline traces.
      arguments: privateMedia ? null : {'url': image.url},
    );
  }
}

class ThreadImageFailurePlaceholder extends StatelessWidget {
  const ThreadImageFailurePlaceholder({
    super.key,
    required this.url,
    required this.onOpen,
    required this.onCopy,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = foregroundColor ?? AppColors.textMuted;
    final bgColor = backgroundColor ?? AppColors.surfaceTint;

    return Semantics(
      button: true,
      label: '图片加载失败',
      hint: '点按浏览器打开，长按复制链接',
      child: Material(
        color: bgColor,
        child: InkWell(
          onTap: onOpen,
          onLongPress: onCopy,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, color: textColor),
                    const SizedBox(height: 8),
                    Text(
                      '图片加载失败',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点按浏览器打开\n长按复制链接',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.88),
                        height: 1.3,
                      ),
                    ),
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
