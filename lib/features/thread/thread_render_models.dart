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
  block,
  code,
  list,
  table,
  media,
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
    this.fontFamily,
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
      fontFamily: segment.fontFamily,
    );
  }

  final int? colorValue;
  final int? backgroundColorValue;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final double fontScale;
  final String? fontFamily;

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
        other.fontScale == fontScale &&
        other.fontFamily == fontFamily;
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
        fontFamily,
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
  const ThreadImageRenderBlock(this.image, {this.href})
      : super(ThreadRenderBlockType.image);

  final ThreadImage image;

  /// Link wrapping the image ([url][img]...[/url] or a > img).
  final String? href;
}

class ThreadEmojiRenderBlock extends ThreadRenderBlock {
  const ThreadEmojiRenderBlock({
    required this.url,
    this.alt,
    this.href,
  }) : super(ThreadRenderBlockType.emoji);

  final String url;
  final String? alt;
  final String? href;
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

/// A paragraph-level container (p/div/align) that starts on its own line.
class ThreadBlockRenderBlock extends ThreadRenderBlock {
  const ThreadBlockRenderBlock(this.renderModel, this.alignment)
      : super(ThreadRenderBlockType.block);

  final ThreadPostRenderModel renderModel;
  final ThreadContentAlignment alignment;
}

class ThreadCodeRenderBlock extends ThreadRenderBlock {
  const ThreadCodeRenderBlock(this.text) : super(ThreadRenderBlockType.code);

  final String text;
}

class ThreadListRenderBlock extends ThreadRenderBlock {
  const ThreadListRenderBlock({
    required this.items,
    required this.isOrdered,
    required this.listStyle,
  }) : super(ThreadRenderBlockType.list);

  final List<ThreadPostRenderModel> items;
  final bool isOrdered;
  final String listStyle;

  String markerAt(int index) {
    if (!isOrdered) return '•';
    final letter = switch (listStyle) {
      'a' => 'a',
      'A' => 'A',
      _ => null,
    };
    if (letter == null) return '${index + 1}.';
    // Spreadsheet-style letters keep going past z (aa, ab, ...).
    var n = index;
    var marker = '';
    do {
      marker = String.fromCharCode(letter.codeUnitAt(0) + n % 26) + marker;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return '$marker.';
  }
}

class ThreadTableRenderCell {
  const ThreadTableRenderCell(this.renderModel, {required this.isHeader});

  final ThreadPostRenderModel renderModel;
  final bool isHeader;
}

class ThreadTableRenderBlock extends ThreadRenderBlock {
  const ThreadTableRenderBlock(this.rows) : super(ThreadRenderBlockType.table);

  final List<List<ThreadTableRenderCell>> rows;
}

/// Audio/video/flash: never played in-app; shown as a card with its link.
class ThreadMediaRenderBlock extends ThreadRenderBlock {
  const ThreadMediaRenderBlock({required this.url, required this.label})
      : super(ThreadRenderBlockType.media);

  final String? url;
  final String label;
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

    void absorb(ThreadPostRenderModel model) {
      hasImages = hasImages || model.hasImages;
      hasEmoji = hasEmoji || model.hasEmoji;
      hasDownloadLinks = hasDownloadLinks || model.hasDownloadLinks;
      hasQuotes = hasQuotes || model.hasQuotes;
      hasSaleBoxes = hasSaleBoxes || model.hasSaleBoxes;
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
            addBlock(ThreadEmojiRenderBlock(
              url: url,
              alt: segment.alt,
              href: segment.href,
            ));
            hasEmoji = true;
            continue;
          }
          final url = segment.url;
          if (url == null || url.isEmpty) continue;
          addBlock(ThreadImageRenderBlock(
            ThreadImage(url: url, alt: segment.alt),
            href: segment.href,
          ));
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
        case ThreadContentSegmentType.block:
          final model = ThreadPostRenderModel.fromSegments(segment.children);
          if (model.blocks.isEmpty) continue;
          addBlock(ThreadBlockRenderBlock(model, segment.alignment));
          absorb(model);
        case ThreadContentSegmentType.code:
          final text = segment.text ?? '';
          if (text.isEmpty) continue;
          addBlock(ThreadCodeRenderBlock(text));
        case ThreadContentSegmentType.list:
          final items = [
            for (final child in segment.children)
              ThreadPostRenderModel.fromSegments([child]),
          ].where((item) => item.blocks.isNotEmpty).toList();
          if (items.isEmpty) continue;
          addBlock(ThreadListRenderBlock(
            items: List.unmodifiable(items),
            isOrdered: segment.isOrdered,
            listStyle: segment.listStyle,
          ));
          items.forEach(absorb);
        case ThreadContentSegmentType.table:
          final rows = [
            for (final row in segment.tableRows)
              if (row.isNotEmpty)
                List<ThreadTableRenderCell>.unmodifiable([
                  for (final cell in row)
                    ThreadTableRenderCell(
                      ThreadPostRenderModel.fromSegments(cell.segments),
                      isHeader: cell.isHeader,
                    ),
                ]),
          ];
          if (rows.isEmpty) continue;
          addBlock(ThreadTableRenderBlock(List.unmodifiable(rows)));
          for (final row in rows) {
            for (final cell in row) {
              absorb(cell.renderModel);
            }
          }
        case ThreadContentSegmentType.media:
          final url = segment.url;
          addBlock(ThreadMediaRenderBlock(
            url: url == null || url.isEmpty ? null : url,
            label: segment.text?.trim() ?? '',
          ));
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
  pageDivider,
  loadMore,
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
  const ThreadDetailPaginationEntry({this.pagination, Key? key})
      : super(ThreadDetailListEntryType.pagination, key: key);

  /// The page it pages from; null for the first loaded page.
  final ThreadPagination? pagination;
}

/// Marks where an automatically appended page starts.
class ThreadDetailPageDividerEntry extends ThreadDetailListEntry {
  const ThreadDetailPageDividerEntry(this.page, {Key? key})
      : super(ThreadDetailListEntryType.pageDivider, key: key);

  final int page;
}

/// The state of loading the next page at the end of the list.
class ThreadDetailLoadMoreEntry extends ThreadDetailListEntry {
  const ThreadDetailLoadMoreEntry({
    required this.hasMore,
    required this.loading,
    required this.failed,
    Key? key,
  }) : super(ThreadDetailListEntryType.loadMore, key: key);

  final bool hasMore;
  final bool loading;
  final bool failed;
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
