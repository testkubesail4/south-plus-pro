import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';
import 'board_view_parser.dart';
import 'thread_title_style_parser.dart';

class BoardThreadPageParser {
  BoardThreadPageParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  String? parseBoardName(dom.Document document, ForumCategory category) {
    final fid = urls.fidFromCategory(category);
    if (fid == null) return null;
    for (final link in document.querySelectorAll('#breadcrumbs a[href]')) {
      if (urls.fidFromUrl(link.attributes['href'] ?? '') != fid) continue;
      final name = _cleanText(link.text);
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  List<ForumBoardFilter> parseFilters(
    dom.Document document,
    ForumCategory category,
  ) {
    final filters = <ForumBoardFilter>[];
    final seen = <String>{};
    for (final link in [
      ...document.querySelectorAll('.hthread .threadlist a[href]'),
      ...document.querySelectorAll('#menu_special a[href]'),
    ]) {
      final href = link.attributes['href'] ?? '';
      final parsed = urls.boardFilterFromUrl(
        category,
        label: _cleanText(link.text),
        url: href,
      );
      if (parsed == null || parsed.label.isEmpty) continue;
      final key = urls.boardDesktopPath(category, filter: parsed)!;
      if (!seen.add(key)) continue;
      filters.add(
        ForumBoardFilter(
          label: parsed.kind == ForumBoardFilterKind.special ||
                  parsed.kind == ForumBoardFilterKind.all
              ? parsed.label.replaceAll(' ', '')
              : parsed.label,
          url: parsed.url,
          kind: parsed.kind,
        ),
      );
    }
    return filters;
  }

  ForumBoardFilter? parseActiveFilter(
    dom.Document document,
    ForumCategory category,
    List<ForumBoardFilter> filters, {
    ForumBoardFilter? requested,
  }) {
    final script =
        document.querySelectorAll('script').map((s) => s.text).join();
    final selectedId = RegExp(
      r'''setCurrent\(['"](thread_type_(?:all|digest|\d+))['"],\s*['"]thread_type_all['"]''',
    ).firstMatch(script)?.group(1);
    final link = (selectedId == null
            ? null
            : document.querySelector('#$selectedId a[href]')) ??
        document.querySelector('.hthread .current a[href]');
    final selected = requested ??
        urls.boardFilterFromUrl(
          category,
          label: '',
          url: link?.attributes['href'] ?? '',
        );
    if (selected != null) {
      final key = urls.boardDesktopPath(category, filter: selected);
      for (final filter in filters) {
        if (urls.boardDesktopPath(category, filter: filter) == key) return filter;
      }
      return selected;
    }
    return filters.where((f) => f.kind == ForumBoardFilterKind.all).firstOrNull;
  }

  List<ForumCategory> parseParents(
    dom.Document document,
    ForumCategory category,
  ) {
    final parents = <ForumCategory>[];
    final seen = <String>{urls.fidFromCategory(category) ?? ''};
    for (final link in document.querySelectorAll('#breadcrumbs a[href]')) {
      final href = link.attributes['href'] ?? '';
      final fid = urls.fidFromUrl(href);
      final name = _cleanText(link.text);
      if (fid == null || name.isEmpty || !seen.add(fid)) continue;
      parents.add(
        ForumCategory(
          name: name,
          slug: 'fid-$fid',
          url: urls.absoluteUrl(href),
        ),
      );
    }
    return parents;
  }

  bool hasPictureWall(dom.Document document, ForumCategory category) {
    if (document.querySelector('ul.stream') != null) return true;
    final fid = urls.fidFromCategory(category);
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (urls.fidFromUrl(href) == null) continue;
      final name = pictureWallBoardName(_cleanText(link.text));
      if (name == '' || name == category.name) return true;
      if (Uri.tryParse(urls.absoluteUrl(href))?.path == '/thread_new.php' &&
          urls.fidFromUrl(href) == fid) return true;
    }
    return false;
  }

  String validationText(dom.Document document, ForumCategory category) {
    final validation = document.clone(true);
    final titles = <dom.Element>[];
    for (final item in validation.querySelectorAll('ul.stream > li.dcsns-li')) {
      final link =
          item.querySelector('.section-title a[href*="read.php?tid-"]');
      if (link != null) titles.add(link);
    }
    for (final row in validation.querySelectorAll('#ajaxtable tr.tr3')) {
      final link = _desktopThreadLink(row);
      if (link != null) titles.add(link);
    }
    for (final row in _subBoardTable(validation)?.querySelectorAll('tr') ??
        <dom.Element>[]) {
      final board = _subBoardFromRow(row, category);
      if (board == null || urls.fidFromUrl(board.url) == null) continue;
      titles.addAll(row.children.last.querySelectorAll('a[href]'));
    }
    for (final link in titles) {
      if (urls.forumLinkTarget(link.attributes['href'] ?? '')
          is ForumThreadLinkTarget) link.nodes.clear();
    }
    return '${validation.querySelector('title')?.text ?? ''}\n'
        '${validation.body?.text ?? ''}';
  }

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
          titleStyle: parseThreadTitleStyle(threadLink),
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

  List<ForumBoard> parseDesktopSubBoards(
    dom.Document document,
    ForumCategory category,
  ) {
    final subBoardTable = _subBoardTable(document);
    if (subBoardTable == null) return const [];

    final rows = subBoardTable.querySelectorAll('tr');
    final wallNames = rows
        .map(_subBoardTitleLink)
        .whereType<dom.Element>()
        .map((link) => pictureWallBoardName(_cleanText(link.text)))
        .whereType<String>()
        .toSet();
    final boards = <ForumBoard>[];
    final seen = <String>{};
    for (final row in rows) {
      final name = _cleanText(_subBoardTitleLink(row)?.text ?? '');
      final board = _subBoardFromRow(
        row,
        category,
        hasPictureWall: wallNames.contains(name),
      );
      if (board == null || !seen.add(board.url)) continue;
      boards.add(board);
    }
    return boards;
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

    if (current != null && current > total) total = current;
    return current == null ? null : (current: current, total: total);
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
      titleStyle: parseThreadTitleStyle(threadLink),
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
    if (urls.fidFromUrl(href) == null) return null;
    final uri = Uri.tryParse(href);
    if (uri == null) return null;
    if (uri.query.contains('='))
      return int.tryParse(uri.queryParameters['page'] ?? '');
    return int.tryParse(
      RegExp(r'(?:^|-)page-(\d+)(?:-|\.html$|$)')
              .firstMatch(uri.query)
              ?.group(1) ??
          '',
    );
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

  ForumBoard? _subBoardFromRow(
    dom.Element row,
    ForumCategory category, {
    bool hasPictureWall = false,
  }) {
    final titleLink = _subBoardTitleLink(row);
    if (titleLink == null) return null;

    final href = titleLink.attributes['href'] ?? '';
    final name = _cleanText(titleLink.text);
    if (href.isEmpty ||
        name.isEmpty ||
        name == category.name ||
        urls.fidFromUrl(href) == null ||
        pictureWallBoardName(name) != null) return null;

    final cells = row.children.map((cell) => _cleanText(cell.text)).toList();
    final postCount =
        cells.map((value) => int.tryParse(value)).whereType<int>().firstOrNull;
    final description = _cleanText(row.querySelector('.smalltxt')?.text ?? '');
    final lastPost = row.children.last;
    final lastTitle = _cleanText(
      lastPost.querySelector('h3 a[href], a[href*="read.php?tid-"]')?.text ??
          '',
    );
    final lastTime = lastPost.attributes['title']?.trim();

    return ForumBoard(
      name: name,
      url: urls.absoluteUrl(href),
      section: category.name,
      postCount: postCount,
      subtitle: description.isEmpty ? null : description,
      lastPostTitle: lastTitle.isEmpty ? null : lastTitle,
      lastPostTime: lastTime == null || lastTime.isEmpty ? null : lastTime,
      hasPictureWall: hasPictureWall,
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

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
