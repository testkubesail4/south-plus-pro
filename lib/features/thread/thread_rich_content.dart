import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';
import '../common/cached_forum_image.dart';

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
          inlineSpans.add(_textSpan(context, segment, baseStyle));
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
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: href));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('链接已复制')),
          );
        },
        child: Text(segment.text ?? href, style: style),
      ),
    );
  }

  InlineSpan _emojiSpan(ThreadContentSegment segment) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: CachedForumImage(
          url: segment.url!,
          width: 26,
          height: 26,
          fit: BoxFit.contain,
          errorWidget: (context) => const SizedBox(width: 0, height: 0),
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

class _RichQuoteBlock extends StatelessWidget {
  const _RichQuoteBlock({required this.segments});

  final List<ThreadContentSegment> segments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
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

class ThreadInlineImage extends StatelessWidget {
  const ThreadInlineImage({super.key, required this.image});

  final ThreadImage image;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            child: CachedForumImage(url: image.url, fit: BoxFit.contain),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 360),
          color: AppColors.surfaceTint,
          child: CachedForumImage(
            url: image.url,
            fit: BoxFit.contain,
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
