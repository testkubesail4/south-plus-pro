import 'dart:math';

import '../models/forum_models.dart';
import 'forum_blocking_settings.dart';
import 'forum_url_resolver.dart';
import 'keyword_match.dart';

class ThreadSearchHit {
  const ThreadSearchHit({
    required this.page,
    this.anchor,
    required this.floorLabel,
    required this.author,
    required this.snippet,
  });

  final int page;
  final String? anchor;
  final String floorLabel;
  final String author;
  final String snippet;
}

typedef _SearchPost = ({
  String text,
  String author,
  String? uid,
  String? anchor,
  String floorLabel,
  String? contentKey,
  bool opening,
});

final _plainPages = Expando<List<_SearchPost>>();

List<ThreadSearchHit> searchLoadedThread(
    List<ThreadDetail> pages, String keyword, BlockingRules rules) {
  final hits = <ThreadSearchHit>[];
  for (final page in pages) {
    final uri = Uri.tryParse(page.thread.url);
    final urls = ForumUrlResolver(
        baseUri:
            uri?.hasAuthority == true && {'http', 'https'}.contains(uri!.scheme)
                ? Uri.parse('${uri.origin}/')
                : null);
    final authorUid = urls.uidFromUrl(page.thread.url);
    final posts = _plainPages[page] ??= _plainPosts(page);
    for (final post in posts) {
      if (authorUid != null && post.uid != authorUid) continue;
      if (rules.floorBlock(
              uid: post.uid,
              contentKey: post.contentKey,
              isOpeningPost: post.opening) !=
          FloorBlock.none) continue;
      if (post.text.isEmpty || matchKeyword(keyword, [post.text]) != true)
        continue;
      hits.add(ThreadSearchHit(
        page: page.pagination.currentPage,
        anchor: post.anchor,
        floorLabel: post.floorLabel,
        author: post.author,
        snippet: _snippet(post.text, keyword),
      ));
    }
  }
  return List.unmodifiable(hits);
}

List<_SearchPost> _plainPosts(ThreadDetail detail) => [
      if (detail.body.isNotEmpty || detail.bodySegments.isNotEmpty)
        (
          text: _plainText(detail.bodySegments, detail.body),
          author: detail.thread.author ?? '匿名',
          uid: detail.thread.authorUid,
          anchor: _anchor(detail.bodyAnchors),
          floorLabel: '主楼',
          contentKey: detail.bodyContentKey,
          opening: true,
        ),
      for (final reply in detail.replies)
        (
          text: _plainText(reply.segments, reply.content),
          author: reply.author,
          uid: reply.authorUid,
          anchor: _anchor(reply.anchors),
          floorLabel: _floorLabel(reply.floor),
          contentKey: reply.blockContentKey,
          opening: false,
        ),
    ];

String? _anchor(List<String> anchors) =>
    anchors.where(RegExp(r'^[1-9]\d*$').hasMatch).firstOrNull ??
    (anchors.contains('tpc') ? 'tpc' : null) ??
    anchors.where({'read_tpc', 'td_tpc'}.contains).firstOrNull ??
    anchors.firstOrNull;

String _floorLabel(String? floor) {
  if (floor == '楼主') return '主楼';
  final number = RegExp(r'\d+').firstMatch(floor ?? '')?.group(0);
  return number == null ? '楼层' : '$number 楼';
}

String _plainText(List<ThreadContentSegment> segments, String fallback) {
  if (segments.isEmpty) return _normalize(fallback);
  final text = StringBuffer();
  void walk(Iterable<ThreadContentSegment> nodes) {
    for (final node in nodes) {
      switch (node.type) {
        case ThreadContentSegmentType.text:
          final link = Uri.tryParse(node.href ?? '');
          final attachment = link?.path.endsWith('job.php') == true &&
              RegExp(r'action(?:=|-)download').hasMatch(link!.query);
          text.write(attachment ? ' ' : node.text ?? '');
        case ThreadContentSegmentType.code:
          text.write(node.text ?? '');
        case ThreadContentSegmentType.quote:
        case ThreadContentSegmentType.block:
        case ThreadContentSegmentType.list:
          text.writeln();
          walk(node.children);
          text.writeln();
        case ThreadContentSegmentType.table:
          text.writeln();
          for (final row in node.tableRows) {
            for (final cell in row) {
              walk(cell.segments);
              text.write(' ');
            }
            text.writeln();
          }
        case ThreadContentSegmentType.image:
        case ThreadContentSegmentType.saleBox:
        case ThreadContentSegmentType.media:
          text.write(' ');
      }
    }
  }

  walk(segments);
  return _normalize(text.toString());
}

String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

String _snippet(String text, String keyword) {
  final lower = text.toLowerCase();
  final words = keyword.trim().toLowerCase().split(RegExp(r'\s+'));
  var offset = text.length;
  for (final word in words) {
    final found = lower.indexOf(word);
    if (found >= 0) offset = min(offset, found);
  }
  final runes = text.runes.toList();
  if (runes.length <= 120) return text;
  final center = text.substring(0, min(offset, text.length)).runes.length;
  final start = max(0, center - 40);
  final end = min(runes.length, start + 118);
  return '${start > 0 ? '…' : ''}'
      '${String.fromCharCodes(runes.sublist(start, end))}'
      '${end < runes.length ? '…' : ''}';
}
