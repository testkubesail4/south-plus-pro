import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class BoardThreadPageParser {
  BoardThreadPageParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  List<ForumThread> parseDesktopThreads(
    dom.Document document,
    ForumCategory category,
  ) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('tr.tr3')) {
      final threadLink = _desktopThreadLink(row);
      if (threadLink == null) continue;
      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;

      final authorLink = row.querySelector('a.bl[href*="uid"]') ??
          row.querySelector('a[href*="action-show-uid"]');
      final authorHref = authorLink?.attributes['href'] ?? '';
      final text = _cleanText(row.text);
      final metrics = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(text);
      if (metrics == null) continue;
      final date =
          RegExp(r'\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?').firstMatch(text);
      threads.add(
        ForumThread(
          title: title,
          url: urls.absoluteUrl(href),
          replies: int.tryParse(metrics.group(1)!) ?? 0,
          section: category.name,
          author: _cleanText(authorLink?.text ?? '').isEmpty
              ? null
              : _cleanText(authorLink?.text ?? ''),
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
          lastPost: date?.group(0),
          isSticky: _isDesktopStickyThread(row, threadLink),
        ),
      );
      if (threads.length >= 60) break;
    }
    return threads;
  }

  List<ForumThread> parseSimpleThreads(
    dom.Document document,
    ForumCategory category,
  ) {
    final threads = <ForumThread>[];
    final seen = <String>{};

    for (final link in document.querySelectorAll('li a[href*="?t"]')) {
      final parent = link.parent;
      if ((parent?.attributes['style'] ?? '').contains('display:none')) {
        continue;
      }
      final href = link.attributes['href'] ?? '';
      if (!urls.isThreadHref(href) || !seen.add(href)) continue;

      final meta = _cleanText(link.querySelector('.by')?.text ?? '');
      final title = _threadTitleFromBoardLink(link, meta);
      if (title.isEmpty) continue;

      final repliesText = _cleanText(parent?.querySelector('.num')?.text ?? '');
      threads.add(
        ForumThread(
          title: title,
          url: urls.absoluteUrl(href),
          replies: _firstInt(repliesText) ?? 0,
          section: category.name,
          author: _authorFromBoardMeta(meta),
          lastPost: _dateFromBoardMeta(meta),
          isSticky: _isSimpleStickyThread(link),
        ),
      );
      if (threads.length >= 80) break;
    }
    return threads;
  }

  List<ForumBoard> parseDesktopSubBoards(
    dom.Document document,
    ForumCategory category,
  ) {
    final subBoardTable = _subBoardTable(document);
    if (subBoardTable == null) return const [];

    final boards = <ForumBoard>[];
    final seen = <String>{};
    for (final row in subBoardTable.querySelectorAll('tr')) {
      final board = _subBoardFromRow(row, category);
      if (board == null || !seen.add(board.url)) continue;
      boards.add(board);
    }
    return boards;
  }

  List<ForumBoardAd> parseSimpleAds(dom.Document document) {
    final ads = <ForumBoardAd>[];
    final seen = <String>{};
    final bannerImages = document.querySelectorAll(
      '.col > .text-center img[src], img[src*="mobileads"]',
    );
    for (final image in bannerImages) {
      final imageSrc = image.attributes['src'] ?? '';
      if (imageSrc.isEmpty) continue;
      final link = _closestLink(image);
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('javascript:')) continue;
      final title = _cleanText(
        image.attributes['alt'] ?? link.text,
      );
      final absolute = urls.absoluteUrl(href);
      if (!seen.add(absolute)) continue;
      ads.add(
        ForumBoardAd(
          title: title.isEmpty ? '赞助内容' : title,
          url: absolute,
          imageUrl: urls.absoluteUrl(imageSrc),
          subtitle: '广告',
        ),
      );
      break;
    }

    for (final item in document.querySelectorAll('.threadlist li')) {
      if ((item.attributes['style'] ?? '').contains('display:none')) continue;
      if (item.querySelector('a[href*="?t"]') != null) continue;
      final link = item.querySelector('a[href]');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('javascript:')) continue;
      final absolute = urls.absoluteUrl(href);
      if (!seen.add(absolute)) continue;
      final title = _cleanText(link.text);
      if (title.isEmpty) continue;
      ads.add(
        ForumBoardAd(
          title: title,
          url: absolute,
          subtitle: _cleanText(item.querySelector('.by')?.text ?? ''),
        ),
      );
      if (ads.length >= 3) break;
    }
    return ads;
  }

  int? desktopCurrentPage(dom.Document document) {
    final pages = _desktopPages(document);
    return pages?.$1;
  }

  int? desktopTotalPages(dom.Document document) {
    final pages = _desktopPages(document);
    return pages?.$2;
  }

  ({int current, int total})? simplePages(dom.Document document) {
    final currentText = _cleanText(
      document.querySelector('.pagination .active b')?.text ??
          document.querySelector('.pagination .active')?.text ??
          '',
    );
    final current = int.tryParse(currentText);
    var total = current ?? 1;
    for (final link in document.querySelectorAll('.pagination a[href]')) {
      final href = link.attributes['href'] ?? '';
      final match = RegExp(r'\?f\d+_(\d+)\.html').firstMatch(href);
      final page = match == null ? null : int.tryParse(match.group(1)!);
      if (page != null && page > total) total = page;
    }
    if (current == null) return null;
    return (current: current, total: total);
  }

  (int, int)? _desktopPages(dom.Document document) {
    final text = _cleanText(document.body?.text ?? '');
    final match = RegExp(r'Pages:\s*(\d+)\s*/\s*(\d+)').firstMatch(text);
    if (match == null) return null;
    final current = int.tryParse(match.group(1)!);
    final total = int.tryParse(match.group(2)!);
    if (current == null || total == null || total < 1) return null;
    return (current, total);
  }

  dom.Element? _closestLink(dom.Element element) {
    dom.Element? current = element.parent;
    while (current != null) {
      if (current.localName == 'a') return current;
      current = current.parent;
    }
    return null;
  }

  dom.Element? _desktopThreadLink(dom.Element row) {
    for (final link in row.querySelectorAll('a[href*="read.php?tid-"]')) {
      final title = _cleanText(link.text);
      if (title.isEmpty || RegExp(r'^\d+$').hasMatch(title)) continue;
      return link;
    }
    return null;
  }

  dom.Element? _subBoardTable(dom.Document document) {
    for (final table in document.querySelectorAll('table')) {
      final text = _cleanText(table.text);
      if (!text.startsWith('子版块')) continue;
      if (!text.contains('论坛') || !text.contains('文章')) continue;
      return table;
    }
    return null;
  }

  ForumBoard? _subBoardFromRow(dom.Element row, ForumCategory category) {
    final titleLink = _subBoardTitleLink(row);
    if (titleLink == null) return null;

    final href = titleLink.attributes['href'] ?? '';
    final name = _cleanText(titleLink.text);
    if (href.isEmpty || name.isEmpty || name == category.name) return null;

    final cells = row.children.map((cell) => _cleanText(cell.text)).toList();
    final postCount =
        cells.map((value) => int.tryParse(value)).whereType<int>().firstOrNull;
    final latest = cells
        .where((value) => value.isNotEmpty)
        .where((value) => value != name)
        .where((value) => int.tryParse(value) == null)
        .lastOrNull;

    return ForumBoard(
      name: name,
      url: urls.absoluteUrl(href),
      section: category.name,
      postCount: postCount,
      subtitle: latest,
    );
  }

  dom.Element? _subBoardTitleLink(dom.Element row) {
    for (final selector in [
      'h2 a[href*="thread.php?fid-"]',
      'h3 a[href*="thread.php?fid-"]',
      'a.fnamecolor[href*="thread.php?fid-"]',
      'a[href*="thread.php?fid-"]',
    ]) {
      for (final link in row.querySelectorAll(selector)) {
        if (_cleanText(link.text).isNotEmpty) return link;
      }
    }
    return null;
  }

  bool _isSimpleStickyThread(dom.Element link) {
    if (link.querySelector('b, font') != null) return true;
    final meta = _cleanText(link.querySelector('.by')?.text ?? '');
    if (meta == '论坛公告' || meta.contains('版主')) return true;
    final text = _cleanText(link.text);
    return text.contains('公告') || text.contains('置顶');
  }

  bool _isDesktopStickyThread(dom.Element row, dom.Element threadLink) {
    if (row.querySelector('a[href*="notice.php"]') != null) return false;
    if (threadLink.querySelector('b, font') != null) return true;
    final text = _cleanText(row.text);
    if (text.contains('置顶') || text.contains('总置顶') || text.contains('区置顶')) {
      return true;
    }
    final titleCell = threadLink.parent;
    if (titleCell?.querySelector('img[src*="topic"][src*="top"]') != null) {
      return true;
    }
    final iconAlt = row
        .querySelectorAll('img[alt], img[title]')
        .map((image) =>
            '${image.attributes['alt'] ?? ''} ${image.attributes['title'] ?? ''}')
        .join(' ');
    return iconAlt.contains('置顶') || iconAlt.toLowerCase().contains('top');
  }

  String _threadTitleFromBoardLink(dom.Element link, String meta) {
    final text = _cleanText(link.text);
    if (meta.isEmpty) return text;
    return _cleanText(text.replaceFirst(meta, ''));
  }

  String? _authorFromBoardMeta(String meta) {
    if (meta.isEmpty) return null;
    final parts = meta.split(' - 发布于 ');
    return parts.first.trim().isEmpty ? null : parts.first.trim();
  }

  String? _dateFromBoardMeta(String meta) {
    final parts = meta.split(' - 发布于 ');
    return parts.length > 1 && parts.last.trim().isNotEmpty
        ? parts.last.trim()
        : null;
  }

  int? _firstInt(String input) {
    final match = RegExp(r'\d+').firstMatch(input);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
