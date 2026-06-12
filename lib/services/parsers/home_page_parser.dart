import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class HomePageParser {
  HomePageParser({ForumUrlResolver? urls}) : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  List<ForumThread> parseLatestThreads(dom.Document document) {
    final container =
        document.querySelector('.carousel-item.active') ?? document.body;
    if (container == null) return const [];
    return _threadsFromLinks(container.querySelectorAll('a[href]'));
  }

  String? latestThreadsScriptUrl(dom.Document document) {
    final container =
        document.querySelector('.carousel-item.active') ?? document.body;
    final scriptSrc =
        container?.querySelector('script[src]')?.attributes['src'];
    if (scriptSrc == null || scriptSrc.isEmpty) return null;
    return urls.absoluteUrl(scriptSrc);
  }

  List<ForumThread> parseLatestThreadsFromScript(String script) {
    final fragment = html_parser.parseFragment(_htmlFromDocumentWrites(script));
    return _threadsFromLinks(fragment.querySelectorAll('a[href]'));
  }

  List<ForumCategory> parseHotCategories(dom.Document document) {
    final hotList = _accordionListAfterToggle(document, '热门版块');
    if (hotList == null) return const [];

    return _parseSubtoggleLinks(hotList)
        .map(
          (link) => ForumCategory(
            name: link.title,
            slug: urls.slugFromHref(link.href),
            url: urls.absoluteUrl(link.href),
          ),
        )
        .toList();
  }

  List<ForumSection> parseForumSections(dom.Document document) {
    final simpleSections = _parseSimpleForumSections(document);
    if (simpleSections.isNotEmpty) return simpleSections;
    return parseDesktopForumSections(document);
  }

  List<ForumSection> parseDesktopForumSections(dom.Document document) {
    final sections = <ForumSection>[];
    for (final heading in document.querySelectorAll('h2 a')) {
      final title = _cleanText(heading.text);
      if (title.isEmpty) continue;

      final table = _closest(heading, 'table');
      if (table == null) continue;

      final boards = <ForumBoard>[];
      for (final row in table.querySelectorAll('tr')) {
        final board = _desktopBoardFromRow(row, title);
        if (board != null) boards.add(board);
      }
      if (boards.isEmpty) continue;

      sections.add(ForumSection(title: title, items: boards));
    }
    return sections;
  }

  List<ForumSection> _parseSimpleForumSections(dom.Document document) {
    final accordion = document.querySelector('ul.accordion');
    if (accordion == null) return const [];

    final sections = <ForumSection>[];
    for (var i = 0; i < accordion.children.length; i++) {
      final child = accordion.children[i];
      final toggle = _directToggle(child);
      if (toggle == null) continue;

      final title = _cleanText(toggle.text);
      if (title.isEmpty || title == '热门版块') continue;

      final list = _nextElement(accordion.children, i, 'ul');
      if (list == null) continue;

      final links = _parseSubtoggleLinks(list).take(12).toList();
      if (links.isEmpty) continue;

      sections.add(
        ForumSection(
          title: title,
          items: links
              .map(
                (link) => ForumBoard(
                  name: link.title,
                  url: urls.absoluteUrl(link.href),
                  section: title,
                ),
              )
              .toList(),
        ),
      );
      if (sections.length == 8) break;
    }
    return sections;
  }

  List<ForumThread> _threadsFromLinks(List<dom.Element> links) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (title.isEmpty || !urls.isThreadHref(href) || !seen.add(href)) {
        continue;
      }
      threads.add(
        ForumThread(
          title: title,
          url: urls.absoluteUrl(href),
          replies: 0,
          section: '最新讨论',
          author: '匿名',
        ),
      );
      if (threads.length == 3) break;
    }
    return threads;
  }

  String _htmlFromDocumentWrites(String script) {
    final buffer = StringBuffer();
    for (final line in script.split('\n')) {
      final start = line.indexOf('document.write("');
      if (start == -1) continue;
      final contentStart = start + 'document.write("'.length;
      final contentEnd = line.lastIndexOf('");');
      if (contentEnd <= contentStart) continue;
      buffer.write(line.substring(contentStart, contentEnd));
    }
    return buffer.toString();
  }

  dom.Element? _accordionListAfterToggle(dom.Document document, String title) {
    final accordion = document.querySelector('ul.accordion');
    if (accordion == null) return null;

    for (var i = 0; i < accordion.children.length; i++) {
      final toggle = _directToggle(accordion.children[i]);
      if (toggle == null || _cleanText(toggle.text) != title) continue;
      return _nextElement(accordion.children, i, 'ul');
    }
    return null;
  }

  dom.Element? _directToggle(dom.Element element) {
    if (element.localName != 'li') return null;
    return element.children
        .where((child) =>
            child.localName == 'a' && child.classes.contains('toggle'))
        .firstOrNull;
  }

  dom.Element? _nextElement(List<dom.Element> elements, int index, String tag) {
    for (var i = index + 1; i < elements.length; i++) {
      if (elements[i].localName == tag) return elements[i];
      if (_directToggle(elements[i]) != null) return null;
    }
    return null;
  }

  List<_ForumLinkData> _parseSubtoggleLinks(dom.Element element) {
    final seen = <String>{};
    final links = <_ForumLinkData>[];
    for (final link in element.querySelectorAll('a.subtoggle[href]')) {
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (href.isEmpty || title.isEmpty || !seen.add('$href$title')) continue;
      links.add(_ForumLinkData(title: title, href: href));
    }
    return links;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  ForumBoard? _desktopBoardFromRow(dom.Element row, String sectionTitle) {
    final titleCell = _desktopBoardTitleCell(row);
    if (titleCell == null) return null;

    final links = titleCell
        .querySelectorAll(
            'a[href*="thread.php?fid-"], a[href*="thread_new.php?fid"]')
        .where((link) => _cleanText(link.text).isNotEmpty)
        .toList();
    if (links.isEmpty) return null;

    final main = links.first;
    final mainHref = main.attributes['href'] ?? '';
    final mainName = _cleanText(main.text);
    if (mainHref.isEmpty || mainName.isEmpty) return null;

    final counts = _countsFromRow(row);
    final children = <ForumBoard>[];
    final seenChildren = <String>{};
    for (final link in links.skip(1)) {
      final href = link.attributes['href'] ?? '';
      final name = _cleanText(link.text);
      if (href.isEmpty || name.isEmpty || !seenChildren.add('$href$name')) {
        continue;
      }
      children.add(
        ForumBoard(
          name: name,
          url: urls.absoluteUrl(href),
          section: '$sectionTitle / $mainName',
        ),
      );
    }

    return ForumBoard(
      name: mainName,
      url: urls.absoluteUrl(mainHref),
      section: sectionTitle,
      subtitle: _desktopBoardSubtitle(titleCell, mainName),
      topicCount: counts?.$1,
      postCount: counts?.$2,
      children: children,
    );
  }

  dom.Element? _desktopBoardTitleCell(dom.Element row) {
    for (final cell in row.children) {
      if (cell.querySelector(
              'h3 a[href*="thread.php?fid-"], h3 a[href*="thread_new.php?fid"]') !=
          null) {
        return cell;
      }
    }
    return null;
  }

  (int, int)? _countsFromRow(dom.Element row) {
    for (final cell in row.children) {
      final match =
          RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(_cleanText(cell.text));
      if (match == null) continue;
      final topics = int.tryParse(match.group(1)!);
      final posts = int.tryParse(match.group(2)!);
      if (topics != null && posts != null) return (topics, posts);
    }
    return null;
  }

  String? _desktopBoardSubtitle(dom.Element titleCell, String boardName) {
    var text = _cleanText(titleCell.text);
    text = text.replaceFirst(boardName, '').trim();
    text = text.replaceFirst(RegExp(r'^\(\d+\)\s*'), '').trim();
    text = text.replaceAll(RegExp(r'子版[:：].*$'), '').trim();
    return text.isEmpty ? null : text;
  }

  dom.Element? _closest(dom.Element element, String tagName) {
    dom.Element? current = element;
    while (current != null) {
      if (current.localName == tagName) return current;
      current = current.parent;
    }
    return null;
  }
}

class _ForumLinkData {
  const _ForumLinkData({required this.title, required this.href});

  final String title;
  final String href;
}
