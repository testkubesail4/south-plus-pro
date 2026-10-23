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

/// Index paths ("2", "3/0") of the blocks in [after] that a purchase of the
/// sale box [buyPath] unlocked in [before]: the paid content, which is the
/// second quote after the header that took the box's place.
///
/// Strict on purpose: the box must be the only one with that buy path, gone
/// from [after], and every other block of the post (and every container on the
/// way to the box) must be semantically unchanged. Anything else (the author
/// edited the post meanwhile, a different shape, a box inside a table cell)
/// returns empty and the content simply appears without the reveal.
Set<String> purchaseRevealPaths(
  ThreadPostRenderModel before,
  ThreadPostRenderModel after, {
  required String buyPath,
}) {
  if (_countSaleBoxes(before.blocks, buyPath) != 1 ||
      _countSaleBoxes(after.blocks, buyPath) != 0) {
    return const <String>{};
  }
  return _revealIn(before.blocks, after.blocks, '', buyPath);
}

Set<String> _revealIn(
  List<ThreadRenderBlock> before,
  List<ThreadRenderBlock> after,
  String prefix,
  String buyPath,
) {
  const none = <String>{};
  final boxAt = before.indexWhere(
    (b) => b is ThreadSaleBoxRenderBlock && b.saleBox.buyPath == buyPath,
  );
  if (boxAt >= 0) {
    final tail = before.length - boxAt - 1;
    final spanEnd = after.length - tail;
    if (spanEnd < boxAt) return none;
    for (var k = 0; k < boxAt; k++) {
      if (!_sameBlock(before[k], after[k])) return none;
    }
    for (var k = 0; k < tail; k++) {
      if (!_sameBlock(before[boxAt + 1 + k], after[spanEnd + k])) return none;
    }
    final span = after.sublist(boxAt, spanEnd);
    // The native header (it states the box's own price) and then the paid
    // box, both quotes. Two ordinary quotes are not proof: skip the fade.
    // Only the paid box is revealed.
    final price = (before[boxAt] as ThreadSaleBoxRenderBlock).saleBox.price;
    if (price != null &&
        span.length == 2 &&
        span[0] is ThreadQuoteRenderBlock &&
        span[1] is ThreadQuoteRenderBlock &&
        _plainText((span[0] as ThreadQuoteRenderBlock).renderModel)
            .contains('售价${price}SP币')) {
      return {'$prefix${boxAt + 1}'};
    }
    return none;
  }
  if (before.length != after.length) return none;
  Set<String>? found;
  for (var k = 0; k < before.length; k++) {
    if (_countSaleBoxes([before[k]], buyPath) == 0) {
      if (!_sameBlock(before[k], after[k])) return none;
      continue;
    }
    if (found != null) return none;
    found = _revealInContainer(before[k], after[k], '$prefix$k/', buyPath);
  }
  return found ?? none;
}

Set<String> _revealInContainer(
  ThreadRenderBlock before,
  ThreadRenderBlock after,
  String prefix,
  String buyPath,
) {
  const none = <String>{};
  switch ((before, after)) {
    case (final ThreadBlockRenderBlock b, final ThreadBlockRenderBlock a):
      if (b.alignment != a.alignment) return none;
      return _revealIn(
          b.renderModel.blocks, a.renderModel.blocks, prefix, buyPath);
    case (final ThreadQuoteRenderBlock b, final ThreadQuoteRenderBlock a):
      return _revealIn(
          b.renderModel.blocks, a.renderModel.blocks, prefix, buyPath);
    case (final ThreadListRenderBlock b, final ThreadListRenderBlock a):
      if (b.isOrdered != a.isOrdered ||
          b.listStyle != a.listStyle ||
          b.items.length != a.items.length) {
        return none;
      }
      Set<String>? found;
      for (var k = 0; k < b.items.length; k++) {
        if (_countSaleBoxes(b.items[k].blocks, buyPath) == 0) {
          if (!_sameModel(b.items[k], a.items[k])) return none;
          continue;
        }
        if (found != null) return none;
        found = _revealIn(
          b.items[k].blocks,
          a.items[k].blocks,
          '$prefix$k/',
          buyPath,
        );
      }
      return found ?? none;
    default:
      // shortcut: a box inside a table cell appears without the reveal.
      return none;
  }
}

/// The visible words of [model] without whitespace.
String _plainText(ThreadPostRenderModel model) {
  final out = StringBuffer();
  void walk(List<ThreadRenderBlock> blocks) {
    for (final block in blocks) {
      switch (block) {
        case ThreadTextRenderBlock(:final text):
          out.write(text);
        case ThreadLinkRenderBlock(:final text):
          out.write(text);
        case ThreadQuoteRenderBlock(:final renderModel):
          walk(renderModel.blocks);
        case ThreadBlockRenderBlock(:final renderModel):
          walk(renderModel.blocks);
        default:
          break;
      }
    }
  }

  walk(model.blocks);
  return out.toString().replaceAll(RegExp(r'\s+'), '');
}

int _countSaleBoxes(List<ThreadRenderBlock> blocks, String buyPath) {
  var count = 0;
  for (final block in blocks) {
    switch (block) {
      case ThreadSaleBoxRenderBlock(:final saleBox):
        if (saleBox.buyPath == buyPath) count++;
      case ThreadQuoteRenderBlock(:final renderModel):
        count += _countSaleBoxes(renderModel.blocks, buyPath);
      case ThreadBlockRenderBlock(:final renderModel):
        count += _countSaleBoxes(renderModel.blocks, buyPath);
      case ThreadListRenderBlock(:final items):
        for (final item in items) {
          count += _countSaleBoxes(item.blocks, buyPath);
        }
      case ThreadTableRenderBlock(:final rows):
        for (final row in rows) {
          for (final cell in row) {
            count += _countSaleBoxes(cell.renderModel.blocks, buyPath);
          }
        }
      default:
        break;
    }
  }
  return count;
}

bool _sameModel(ThreadPostRenderModel a, ThreadPostRenderModel b) {
  if (a.blocks.length != b.blocks.length) return false;
  for (var i = 0; i < a.blocks.length; i++) {
    if (!_sameBlock(a.blocks[i], b.blocks[i])) return false;
  }
  return true;
}

/// Same content, not just the same kind. A sale box is the same box when its
/// buy path is (the buyer count moves between loads).
bool _sameBlock(ThreadRenderBlock a, ThreadRenderBlock b) {
  return switch (a) {
    final ThreadTextRenderBlock x =>
      b is ThreadTextRenderBlock && x.text == b.text && x.style == b.style,
    final ThreadLinkRenderBlock x => b is ThreadLinkRenderBlock &&
        x.text == b.text &&
        x.url == b.url &&
        x.style == b.style,
    final ThreadDownloadLinkRenderBlock x =>
      b is ThreadDownloadLinkRenderBlock &&
          x.label == b.label &&
          x.url == b.url,
    final ThreadImageRenderBlock x => b is ThreadImageRenderBlock &&
        x.image.url == b.image.url &&
        x.image.alt == b.image.alt &&
        x.href == b.href,
    final ThreadEmojiRenderBlock x => b is ThreadEmojiRenderBlock &&
        x.url == b.url &&
        x.alt == b.alt &&
        x.href == b.href,
    final ThreadQuoteRenderBlock x =>
      b is ThreadQuoteRenderBlock && _sameModel(x.renderModel, b.renderModel),
    final ThreadSaleBoxRenderBlock x =>
      b is ThreadSaleBoxRenderBlock && x.saleBox.buyPath == b.saleBox.buyPath,
    final ThreadBlockRenderBlock x => b is ThreadBlockRenderBlock &&
        x.alignment == b.alignment &&
        _sameModel(x.renderModel, b.renderModel),
    final ThreadCodeRenderBlock x =>
      b is ThreadCodeRenderBlock && x.text == b.text,
    final ThreadListRenderBlock x => b is ThreadListRenderBlock &&
        x.isOrdered == b.isOrdered &&
        x.listStyle == b.listStyle &&
        x.items.length == b.items.length &&
        [
          for (var i = 0; i < x.items.length; i++)
            _sameModel(x.items[i], b.items[i]),
        ].every((same) => same),
    final ThreadTableRenderBlock x => b is ThreadTableRenderBlock &&
        x.rows.length == b.rows.length &&
        [
          for (var r = 0; r < x.rows.length; r++)
            x.rows[r].length == b.rows[r].length &&
                [
                  for (var c = 0; c < x.rows[r].length; c++)
                    x.rows[r][c].isHeader == b.rows[r][c].isHeader &&
                        _sameModel(
                          x.rows[r][c].renderModel,
                          b.rows[r][c].renderModel,
                        ),
                ].every((same) => same),
        ].every((same) => same),
    final ThreadMediaRenderBlock x =>
      b is ThreadMediaRenderBlock && x.url == b.url && x.label == b.label,
  };
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
    required this.next,
    required this.loading,
    required this.failed,
    required this.paused,
    Key? key,
  }) : super(ThreadDetailListEntryType.loadMore, key: key);

  /// Two pages in a row added no new floor; the next waits for a tap.
  final bool paused;

  /// The page after the last one shown; null after the last page.
  final int? next;
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
    this.message,
    Key? key,
  }) : super(ThreadDetailListEntryType.emptyState, key: key);

  final String title;
  final String? message;
}

class ThreadDetailReplyEntry extends ThreadDetailListEntry {
  const ThreadDetailReplyEntry({
    required this.reply,
    required this.renderModel,
    this.stableId = '',
    Key? key,
  }) : super(ThreadDetailListEntryType.reply, key: key);

  final ThreadReply reply;

  /// The floor's id across refreshes (see [threadReplyStableId]).
  final String stableId;
  final ThreadPostRenderModel renderModel;
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
