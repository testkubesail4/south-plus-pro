import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class BoardThreadPageParser {
  BoardThreadPageParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  List<ForumThread> parseWallThreads(
    dom.Document document,
    ForumCategory category,
  ) {
    final threads = <ForumThread>[];
    final seen = <String>{};

    for (final item in document.querySelectorAll('ul.stream > li.dcsns-li')) {
      final threadLink =
          item.querySelector('.section-title a[href*="read.php?tid-"]');
      if (threadLink == null) continue;
      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;

      final authorLink = item.querySelector(
        '.section-intro a.bl[href*="uid"], .section-intro a[href*="action-show-uid"]',
      );
      final authorHref = authorLink?.attributes['href'] ?? '';
      final metrics = RegExp(r'回复\s*/\s*人气\s*[:：]\s*(\d+)\s*/\s*(\d+)')
          .firstMatch(_cleanText(item.text));
      final date = RegExp(r'\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?').firstMatch(
        _cleanText(item.querySelector('.section-intro')?.text ?? item.text),
      );

      threads.add(
        ForumThread(
          title: title,
          url: urls.absoluteUrl(href),
          replies: int.tryParse(metrics?.group(1) ?? '') ?? 0,
          section: category.name,
          author: _cleanText(authorLink?.text ?? '').isEmpty
              ? null
              : _cleanText(authorLink?.text ?? ''),
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
          lastPost: date?.group(0),
          previewImageUrl: _wallPreviewImageUrl(item),
        ),
      );
      if (threads.length >= 80) break;
    }
    return threads;
  }

  // Full desktop table parsing is still kept for older call sites and tests,
  // but board pages now prefer parseWallThreads() plus board-level sticky rows.
  List<ForumThread> parseDesktopThreads(
    dom.Document document,
    ForumCategory category,
  ) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('#ajaxtable tr.tr3')) {
      final threadLink = _desktopThreadLink(row);
      if (threadLink == null) continue;
      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;

      final thread = _desktopThreadFromRow(row, threadLink, category);
      if (thread == null) continue;
      threads.add(thread.copyWith(
        isSticky: _isDesktopStickyThread(row, threadLink),
      ));
      if (threads.length >= 60) break;
    }
    return threads;
  }

  List<ForumThread> parseDesktopStickyThreads(
    dom.Document document,
    ForumCategory category,
  ) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('#ajaxtable tr.tr3')) {
      final threadLink = _desktopThreadLink(row);
      if (threadLink == null || !_isDesktopStickyThread(row, threadLink)) {
        continue;
      }
      final thread = _desktopThreadFromRow(row, threadLink, category);
      if (thread == null || !seen.add(thread.url)) continue;
      threads.add(thread);
      if (threads.length >= 20) break;
    }
    return threads;
  }

  List<ForumBoardAd> parseDesktopAds(dom.Document document) {
    final ads = <ForumBoardAd>[];
    final seen = <String>{};
    // thread_new.php renders the simple-page top external ad inside the same
    // #ajaxtable block as pinned topics. External h3 links are ads, not
    // ForumThread rows, or they pollute the list before real board stickies.
    for (final row in document.querySelectorAll('#ajaxtable tr.tr3')) {
      final link = row.querySelector('h3 a[href^="http"]');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (href.isEmpty || title.isEmpty) continue;
      final absolute = urls.absoluteUrl(href);
      if (!seen.add(absolute)) continue;
      ads.add(
        ForumBoardAd(
          title: title,
          url: absolute,
          subtitle: _cleanText(row.querySelector('a.bl')?.text ?? '').isEmpty
              ? '广告'
              : _cleanText(row.querySelector('a.bl')?.text ?? ''),
        ),
      );
      if (ads.length >= 2) break;
    }
    return ads;
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

  ({int current, int total})? wallPages(dom.Document document) {
    final containers = document.querySelectorAll('.pages');
    final root = containers.isEmpty ? document : containers.first;
    final pageText = _cleanText(root.text ?? '');
    final desktopMatch =
        RegExp(r'Pages:\s*(\d+)\s*/\s*(\d+)').firstMatch(pageText);
    var current = int.tryParse(desktopMatch?.group(1) ?? '');
    var total = int.tryParse(desktopMatch?.group(2) ?? '') ?? current ?? 1;

    final selectedText = _cleanText(
      root.querySelector('b, .current')?.text ?? '',
    );
    current ??= int.tryParse(selectedText);

    for (final link in root.querySelectorAll('a[href*="thread_new.php"]')) {
      final href = link.attributes['href'] ?? '';
      final page = _threadNewPageFromHref(href);
      if (page != null && page > total) total = page;
      final textPage = int.tryParse(_cleanText(link.text));
      if (textPage != null && textPage > 0) {
        current ??= 1;
      }
    }

    return current == null ? null : (current: current, total: total);
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

  ForumThread? _desktopThreadFromRow(
    dom.Element row,
    dom.Element threadLink,
    ForumCategory category,
  ) {
    final href = threadLink.attributes['href'] ?? '';
    final title = _cleanText(threadLink.text);
    if (href.isEmpty || title.isEmpty) return null;

    final authorLink = row.querySelector('a.bl[href*="uid"]') ??
        row.querySelector('a[href*="action-show-uid"]');
    final authorHref = authorLink?.attributes['href'] ?? '';
    final text = _cleanText(row.text);
    final metrics = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(text);
    if (metrics == null) return null;
    final date =
        RegExp(r'\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?').firstMatch(text);

    return ForumThread(
      title: title,
      url: urls.absoluteUrl(href),
      replies: int.tryParse(metrics.group(1)!) ?? 0,
      section: category.name,
      author: _cleanText(authorLink?.text ?? '').isEmpty
          ? null
          : _cleanText(authorLink?.text ?? ''),
      authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
      lastPost: date?.group(0),
      isSticky: true,
    );
  }

  dom.Element? _closestLink(dom.Element element) {
    dom.Element? current = element.parent;
    while (current != null) {
      if (current.localName == 'a') return current;
      current = current.parent;
    }
    return null;
  }

  String? _wallPreviewImageUrl(dom.Element item) {
    final image =
        item.querySelector('.section-text a[href*="read.php?tid-"] img[src]') ??
            item.querySelector('.section-text img[src]');
    final src = image?.attributes['src'] ?? '';
    if (src.isEmpty) return null;
    if (src.contains('/images/noimageavailble_icon.png')) return null;
    return urls.absoluteUrl(src);
  }

  int? _threadNewPageFromHref(String href) {
    for (final pattern in [
      RegExp(r'thread_new\.php\?fid-\d+-page-(\d+)\.html'),
      RegExp(r'thread_new\.php\?fid=\d+&page=(\d+)'),
    ]) {
      final match = pattern.firstMatch(href);
      if (match != null) return int.tryParse(match.group(1)!);
    }
    return null;
  }

  dom.Element? _desktopThreadLink(dom.Element row) {
    for (final link in row.querySelectorAll(
      'a[id^="a_ajax_"][href*="read.php?tid-"], h3 a[href*="read.php?tid-"]',
    )) {
      final title = _cleanText(link.text);
      if (title.isNotEmpty && !RegExp(r'^\d+$').hasMatch(title)) return link;
    }
    for (final link in row.querySelectorAll('a[href*="read.php?tid-"]')) {
      final title = _cleanText(link.text);
      if (title.isEmpty ||
          title == '打开新窗口' ||
          RegExp(r'^\d+$').hasMatch(title)) {
        continue;
      }
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
    if (row.querySelector('h3 a[href^="http"]') != null) return false;

    // south-plus has three desktop sticky levels in thread_new.php:
    // headtopic_3 = global/top-site rows, headtopic_2 = section-level rows,
    // headtopic_1 = current-board sticky rows. The simple page only exposes the
    // board-level sticky for this board list, so only headtopic_1 is merged into
    // the wall stream. Broad sticky rows would otherwise make desktop show many
    // extra pinned topics that simple mode hides.
    if (row.querySelector('img[src*="headtopic_1"]') != null) return true;
    final iconAlt = row
        .querySelectorAll('img[alt], img[title], img[src]')
        .map((image) =>
            '${image.attributes['alt'] ?? ''} ${image.attributes['title'] ?? ''} ${image.attributes['src'] ?? ''}')
        .join(' ');
    return iconAlt.contains('置顶') && iconAlt.contains('headtopic_1');
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
