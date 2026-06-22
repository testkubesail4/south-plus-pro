import 'package:flutter/widgets.dart';

import '../../models/forum_models.dart';

enum ThreadRenderBlockType {
  text,
  link,
  downloadLink,
  image,
  emoji,
  quote,
  saleBox,
}

class ThreadTextStyleData {
  const ThreadTextStyleData({
    this.colorValue,
    this.backgroundColorValue,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.fontScale = 1,
  });

  factory ThreadTextStyleData.fromSegment(ThreadContentSegment segment) {
    return ThreadTextStyleData(
      colorValue: segment.colorValue,
      backgroundColorValue: segment.backgroundColorValue,
      isBold: segment.isBold,
      isItalic: segment.isItalic,
      isUnderline: segment.isUnderline,
      isStrike: segment.isStrike,
      fontScale: segment.fontScale,
    );
  }

  final int? colorValue;
  final int? backgroundColorValue;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final double fontScale;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThreadTextStyleData &&
        other.colorValue == colorValue &&
        other.backgroundColorValue == backgroundColorValue &&
        other.isBold == isBold &&
        other.isItalic == isItalic &&
        other.isUnderline == isUnderline &&
        other.isStrike == isStrike &&
        other.fontScale == fontScale;
  }

  @override
  int get hashCode => Object.hash(
        colorValue,
        backgroundColorValue,
        isBold,
        isItalic,
        isUnderline,
        isStrike,
        fontScale,
      );
}

sealed class ThreadRenderBlock {
  const ThreadRenderBlock(this.type);

  final ThreadRenderBlockType type;
}

class ThreadTextRenderBlock extends ThreadRenderBlock {
  const ThreadTextRenderBlock({
    required this.text,
    required this.style,
  }) : super(ThreadRenderBlockType.text);

  final String text;
  final ThreadTextStyleData style;
}

class ThreadLinkRenderBlock extends ThreadRenderBlock {
  const ThreadLinkRenderBlock({
    required this.text,
    required this.url,
    required this.style,
  }) : super(ThreadRenderBlockType.link);

  final String text;
  final String url;
  final ThreadTextStyleData style;
}

class ThreadDownloadLinkRenderBlock extends ThreadRenderBlock {
  const ThreadDownloadLinkRenderBlock({
    required this.label,
    required this.url,
  }) : super(ThreadRenderBlockType.downloadLink);

  final String label;
  final String url;
}

class ThreadImageRenderBlock extends ThreadRenderBlock {
  const ThreadImageRenderBlock(this.image) : super(ThreadRenderBlockType.image);

  final ThreadImage image;
}

class ThreadEmojiRenderBlock extends ThreadRenderBlock {
  const ThreadEmojiRenderBlock({
    required this.url,
    this.alt,
  }) : super(ThreadRenderBlockType.emoji);

  final String url;
  final String? alt;
}

class ThreadQuoteRenderBlock extends ThreadRenderBlock {
  const ThreadQuoteRenderBlock(this.renderModel)
      : super(ThreadRenderBlockType.quote);

  final ThreadPostRenderModel renderModel;
}

class ThreadSaleBoxRenderBlock extends ThreadRenderBlock {
  const ThreadSaleBoxRenderBlock(this.saleBox)
      : super(ThreadRenderBlockType.saleBox);

  final ThreadSaleBox saleBox;
}

class ThreadPostRenderModel {
  const ThreadPostRenderModel({
    required this.blocks,
    required this.hasImages,
    required this.hasEmoji,
    required this.hasDownloadLinks,
    required this.hasQuotes,
    required this.hasSaleBoxes,
  });

  static const empty = ThreadPostRenderModel(
    blocks: <ThreadRenderBlock>[],
    hasImages: false,
    hasEmoji: false,
    hasDownloadLinks: false,
    hasQuotes: false,
    hasSaleBoxes: false,
  );

  factory ThreadPostRenderModel.fromSegments(
      List<ThreadContentSegment> segments) {
    if (segments.isEmpty) return empty;

    final blocks = <ThreadRenderBlock>[];
    var hasImages = false;
    var hasEmoji = false;
    var hasDownloadLinks = false;
    var hasQuotes = false;
    var hasSaleBoxes = false;

    void addBlock(ThreadRenderBlock block) {
      if (block case ThreadTextRenderBlock()) {
        if (block.text.isEmpty) return;
        final previous = blocks.isEmpty ? null : blocks.last;
        if (previous is ThreadTextRenderBlock &&
            previous.style == block.style) {
          blocks[blocks.length - 1] = ThreadTextRenderBlock(
            text: previous.text + block.text,
            style: previous.style,
          );
          return;
        }
      }
      blocks.add(block);
    }

    for (final segment in segments) {
      switch (segment.type) {
        case ThreadContentSegmentType.text:
          final style = ThreadTextStyleData.fromSegment(segment);
          final href = segment.href;
          if (href != null && isForumPreviewableDownloadLink(href)) {
            addBlock(
              ThreadDownloadLinkRenderBlock(
                label: forumDownloadLinkLabel(segment.text, href),
                url: href,
              ),
            );
            hasDownloadLinks = true;
            continue;
          }
          if (href != null) {
            addBlock(
              ThreadLinkRenderBlock(
                text: segment.text ?? href,
                url: href,
                style: style,
              ),
            );
            continue;
          }
          final plainText = segment.text ?? '';
          if (_appendDownloadAwareTextBlocks(
            plainText: plainText,
            style: style,
            addBlock: addBlock,
          )) {
            hasDownloadLinks = true;
            continue;
          }
          addBlock(ThreadTextRenderBlock(text: plainText, style: style));
        case ThreadContentSegmentType.image:
          if (segment.isEmoji) {
            final url = segment.url;
            if (url == null || url.isEmpty) continue;
            addBlock(ThreadEmojiRenderBlock(url: url, alt: segment.alt));
            hasEmoji = true;
            continue;
          }
          final url = segment.url;
          if (url == null || url.isEmpty) continue;
          addBlock(
              ThreadImageRenderBlock(ThreadImage(url: url, alt: segment.alt)));
          hasImages = true;
        case ThreadContentSegmentType.quote:
          final quoteModel =
              ThreadPostRenderModel.fromSegments(segment.children);
          if (quoteModel.blocks.isEmpty) continue;
          addBlock(ThreadQuoteRenderBlock(quoteModel));
          hasQuotes = true;
          hasImages = hasImages || quoteModel.hasImages;
          hasEmoji = hasEmoji || quoteModel.hasEmoji;
          hasDownloadLinks = hasDownloadLinks || quoteModel.hasDownloadLinks;
        case ThreadContentSegmentType.saleBox:
          final saleBox = segment.saleBox;
          if (saleBox == null) continue;
          addBlock(ThreadSaleBoxRenderBlock(saleBox));
          hasSaleBoxes = true;
      }
    }

    return ThreadPostRenderModel(
      blocks: List<ThreadRenderBlock>.unmodifiable(blocks),
      hasImages: hasImages,
      hasEmoji: hasEmoji,
      hasDownloadLinks: hasDownloadLinks,
      hasQuotes: hasQuotes,
      hasSaleBoxes: hasSaleBoxes,
    );
  }

  final List<ThreadRenderBlock> blocks;
  final bool hasImages;
  final bool hasEmoji;
  final bool hasDownloadLinks;
  final bool hasQuotes;
  final bool hasSaleBoxes;

  bool get isEmpty => blocks.isEmpty;
}

bool _appendDownloadAwareTextBlocks({
  required String plainText,
  required ThreadTextStyleData style,
  required void Function(ThreadRenderBlock block) addBlock,
}) {
  final matches = forumDownloadLinkPattern.allMatches(plainText).toList();
  if (matches.isEmpty) return false;

  var cursor = 0;
  var foundPreviewable = false;
  for (final match in matches) {
    final rawUrl = match.group(0);
    if (rawUrl == null) continue;
    final url = forumTrimDownloadUrl(rawUrl);
    if (!isForumPreviewableDownloadLink(url)) continue;
    foundPreviewable = true;

    final before = plainText.substring(cursor, match.start);
    if (before.isNotEmpty) {
      addBlock(ThreadTextRenderBlock(text: before, style: style));
    }
    addBlock(
      ThreadDownloadLinkRenderBlock(
        label: forumDownloadLinkLabel(null, url),
        url: url,
      ),
    );
    cursor = match.start + url.length;
  }

  if (!foundPreviewable) return false;

  final after = plainText.substring(cursor);
  if (after.isNotEmpty) {
    addBlock(ThreadTextRenderBlock(text: after, style: style));
  }
  return true;
}

enum ThreadDetailListEntryType {
  topSpacing,
  pagination,
  openingPost,
  authorFilterChip,
  emptyState,
  reply,
  composer,
}

sealed class ThreadDetailListEntry {
  const ThreadDetailListEntry(this.type, {this.key});

  final ThreadDetailListEntryType type;
  final Key? key;
}

class ThreadDetailTopSpacingEntry extends ThreadDetailListEntry {
  const ThreadDetailTopSpacingEntry(this.height)
      : super(ThreadDetailListEntryType.topSpacing);

  final double height;
}

class ThreadDetailPaginationEntry extends ThreadDetailListEntry {
  const ThreadDetailPaginationEntry({Key? key})
      : super(ThreadDetailListEntryType.pagination, key: key);
}

class ThreadDetailOpeningPostEntry extends ThreadDetailListEntry {
  const ThreadDetailOpeningPostEntry({
    required this.hasBody,
    required this.renderModel,
    Key? key,
  }) : super(ThreadDetailListEntryType.openingPost, key: key);

  final bool hasBody;
  final ThreadPostRenderModel renderModel;
}

class ThreadDetailAuthorFilterChipEntry extends ThreadDetailListEntry {
  const ThreadDetailAuthorFilterChipEntry({
    required this.visibleFloorCount,
    Key? key,
  }) : super(ThreadDetailListEntryType.authorFilterChip, key: key);

  final int visibleFloorCount;
}

class ThreadDetailEmptyStateEntry extends ThreadDetailListEntry {
  const ThreadDetailEmptyStateEntry({
    required this.title,
    required this.message,
    Key? key,
  }) : super(ThreadDetailListEntryType.emptyState, key: key);

  final String title;
  final String message;
}

class ThreadDetailReplyEntry extends ThreadDetailListEntry {
  const ThreadDetailReplyEntry({
    required this.reply,
    required this.renderModel,
    Key? key,
  }) : super(ThreadDetailListEntryType.reply, key: key);

  final ThreadReply reply;
  final ThreadPostRenderModel renderModel;
}

class ThreadDetailComposerEntry extends ThreadDetailListEntry {
  const ThreadDetailComposerEntry({Key? key})
      : super(ThreadDetailListEntryType.composer, key: key);
}

String threadReplyStableId(
  ThreadReply reply, {
  required int index,
}) {
  final quoteUrl = reply.quoteUrl;
  if (quoteUrl != null && quoteUrl.isNotEmpty) return quoteUrl;
  final floor = reply.floor;
  if (floor != null && floor.isNotEmpty) return floor;
  final postedAt = reply.postedAt;
  if (postedAt != null && postedAt.isNotEmpty) {
    return '${reply.author}@$postedAt';
  }
  return '${reply.author}#$index';
}

String forumDownloadLinkLabel(String? label, String url) {
  final text = label?.trim();
  if (text != null && text.isNotEmpty && text != url) return text;
  if (url.startsWith('magnet:?')) return url;
  if (url.startsWith('ed2k://')) return 'Ed2k 链接';
  return url;
}

bool isForumPreviewableDownloadLink(String url) {
  final lower = url.toLowerCase();
  return lower.startsWith('magnet:?') ||
      lower.startsWith('ed2k://') ||
      forumDownloadFilePattern.hasMatch(lower);
}

String forumTrimDownloadUrl(String url) {
  return url.replaceFirst(RegExp(r'[\]\),.，。；;]+$'), '');
}

final forumDownloadFilePattern = RegExp(
  r'\.(torrent|zip|rar|7z|iso|mkv|mp4|avi|wmv|mov|apk|exe)(?:[?#]|$)',
  caseSensitive: false,
);

final forumDownloadLinkPattern = RegExp(
  "(magnet:\\?[^\\s<>\"']+|ed2k://[^\\s<>\"']+|https?://[^\\s<>\"']+\\.(?:torrent|zip|rar|7z|iso|mkv|mp4|avi|wmv|mov|apk|exe)(?:[?#][^\\s<>\"']*)?)",
  caseSensitive: false,
);
