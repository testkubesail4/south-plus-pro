import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';
import 'thread_content_parser.dart';

class ThreadDetailParser {
  ThreadDetailParser({
    ForumUrlResolver? urls,
    ThreadContentParser? contentParser,
  })  : urls = urls ?? ForumUrlResolver(),
        contentParser = contentParser ?? ThreadContentParser(urls: urls);

  final ForumUrlResolver urls;
  final ThreadContentParser contentParser;

  List<ThreadReply> desktopThreadCards(dom.Document document) {
    final replies = <ThreadReply>[];
    for (final post in document.querySelectorAll('table.js-post')) {
      final authorCell = post.querySelector('th.r_two');
      final contentCell = post.querySelector('th.r_one');
      final content = _desktopContentElement(contentCell);
      if (authorCell == null || contentCell == null || content == null) {
        continue;
      }

      final renderContentClone = content.clone(true);
      _removeIgnoredContent(renderContentClone);
      _moveAttachmentBlocksBelowReadContent(renderContentClone);
      final saleBoxesFirst = _startsWithSaleBox(renderContentClone);
      final segments = contentParser.extractInlineSegments(renderContentClone);

      final contentClone = content.clone(true);
      _removeIgnoredContent(contentClone);
      _moveAttachmentBlocksBelowReadContent(contentClone);
      final saleBoxes = _extractSaleBoxes(contentClone);
      final quote = contentParser.extractQuote(contentClone);
      final links = _extractLinks(contentClone);
      final images = const <ThreadImage>[];
      final text = _cleanText(contentClone.text);
      if (text.isEmpty &&
          segments.isEmpty &&
          saleBoxes.isEmpty &&
          images.isEmpty &&
          links.isEmpty) {
        continue;
      }

      final strong = authorCell.querySelector('a[href*="uid"] strong');
      final authorLink = strong?.parent ??
          authorCell.querySelector('a[href*="action-show-uid"]') ??
          authorCell.querySelector('a[href*="uid"]');
      final authorHref = authorLink?.attributes['href'] ?? '';
      final author = _cleanText(
        strong?.text ?? authorLink?.text ?? '匿名',
      );
      final avatarSrc =
          authorCell.querySelector('.user-pic img')?.attributes['src'] ??
              authorCell.querySelector('a[href*="uid"] img')?.attributes['src'];
      final authorPostsHref = _authorPostsHref(contentCell);
      final quoteHref = _quoteHref(contentCell);
      final floor = _floor(contentCell);
      final postedAt = _postedAt(contentCell);
      replies.add(
        ThreadReply(
          author: author,
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
          authorAvatarUrl: avatarSrc == null || avatarSrc.isEmpty
              ? null
              : urls.absoluteUrl(avatarSrc),
          authorPostsUrl: authorPostsHref == null
              ? null
              : urls.absoluteUrl(authorPostsHref),
          content: text,
          postedAt: postedAt.isEmpty ? null : postedAt,
          floor: floor.isEmpty ? null : floor,
          quote: quote,
          quoteUrl: quoteHref == null ? null : urls.absoluteUrl(quoteHref),
          segments: segments,
          images: images,
          links: links,
          saleBoxes: saleBoxes,
          saleBoxesFirst: saleBoxesFirst,
        ),
      );
    }
    return replies;
  }

  ThreadPagination desktopPagination(
    dom.Document document, {
    int requestedPage = 1,
  }) {
    final text = _cleanText(document.body?.text ?? '');
    final pagesMatch = RegExp(r'Pages:\s*(\d+)\s*/\s*(\d+)').firstMatch(text);
    final currentFromText =
        pagesMatch == null ? null : int.tryParse(pagesMatch.group(1)!);
    final totalFromText =
        pagesMatch == null ? null : int.tryParse(pagesMatch.group(2)!);

    var totalFromLinks = 1;
    for (final link in document.querySelectorAll('a[href*="read.php?tid-"]')) {
      final page = _pageFromHref(link.attributes['href'] ?? '');
      if (page != null && page > totalFromLinks) totalFromLinks = page;
    }

    final total = totalFromText ?? totalFromLinks;
    final current = (currentFromText ?? requestedPage).clamp(1, total).toInt();
    return ThreadPagination(currentPage: current, totalPages: total);
  }

  String? threadTitle(dom.Document document) {
    final candidates = [
      document.querySelector('#subject_tpc'),
      document.querySelector('strong a[href*="read.php?tid"]'),
    ];
    for (final candidate in candidates) {
      final title = _cleanText(candidate?.text ?? '');
      if (title.isNotEmpty) return title;
    }
    return null;
  }

  String? threadUrl(dom.Document document) {
    for (final link in document.querySelectorAll('a[href*="read.php?tid-"]')) {
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (title.isEmpty ||
          href.contains('page-') ||
          href.contains('-uid-') ||
          href.contains('skinco-') ||
          !_isThreadReadHref(href)) {
        continue;
      }
      return urls.absoluteUrl(href);
    }
    return null;
  }

  ThreadActionLink? previousThread(dom.Document document) {
    return _actionLink(
      document,
      'a[href*="action-previous"][href*="goto-previous"]',
      fallbackLabel: '上一主题',
    );
  }

  ThreadActionLink? nextThread(dom.Document document) {
    return _actionLink(
      document,
      'a[href*="action-previous"][href*="goto-next"]',
      fallbackLabel: '下一主题',
    );
  }

  ThreadActionLink? rssFeed(dom.Document document) {
    return _actionLink(
      document,
      'a[href^="rss.php?tid="], a[href*="/rss.php?tid="]',
      fallbackLabel: 'RSS',
    );
  }

  String? sectionTitle(dom.Document document) {
    final sectionFromTitle = _sectionTitleFromDocumentTitle(
      document.querySelector('title')?.text ?? '',
    );
    if (sectionFromTitle != null) return sectionFromTitle;

    final breadcrumbLinks = [
      ...document.querySelectorAll('.breadcrumb a[href]'),
      ...document.querySelectorAll('#breadCrumb a[href]'),
      ...document.querySelectorAll('.guide a[href]'),
      ...document.querySelectorAll('.crumb a[href]'),
      ...document.querySelectorAll('a[href*="thread.php?fid-"]'),
      ...document.querySelectorAll('a[href*="thread.php?fid="]'),
      ...document.querySelectorAll('a[href*="simple/index.php?f"]'),
      ...document.querySelectorAll('a[href*="simple/index.php?p"]'),
      ...document.querySelectorAll('a[href*="?f"]'),
      ...document.querySelectorAll('a[href*="?p"]'),
    ];

    for (final link in breadcrumbLinks.reversed) {
      final href = link.attributes['href'] ?? '';
      if (!urls.isBoardHref(href)) continue;
      final title = _cleanText(link.text);
      if (title.isEmpty || _isGenericCrumbTitle(title)) continue;
      return title;
    }
    return null;
  }

  String? _sectionTitleFromDocumentTitle(String title) {
    final match = RegExp(r'\|\s*([^-|]+?)\s*-\s*南\+').firstMatch(title);
    final section = _cleanText(match?.group(1) ?? '');
    return section.isEmpty || _isGenericCrumbTitle(section) ? null : section;
  }

  bool _isThreadReadHref(String href) {
    return RegExp(r'read\.php\?tid-\d+\.html$').hasMatch(href) ||
        RegExp(r'read\.php\?tid-\d+(?:-|&)').hasMatch(href);
  }

  ThreadActionLink? _actionLink(
    dom.Document document,
    String selector, {
    required String fallbackLabel,
  }) {
    final link = document.querySelector(selector);
    final href = link?.attributes['href'] ?? '';
    if (href.isEmpty || href.startsWith('javascript:')) return null;
    final label = _cleanText(link?.text ?? '');
    return ThreadActionLink(
      label: label.isEmpty ? fallbackLabel : label,
      url: urls.absoluteUrl(href),
    );
  }

  bool _isGenericCrumbTitle(String title) {
    const genericTitles = {
      '南+ South Plus',
      'South Plus',
      '首页',
      '論壇',
      '论坛',
      '返回',
    };
    return genericTitles.contains(title);
  }

  List<ThreadLink> _extractLinks(dom.Element content) {
    final links = <ThreadLink>[];
    final seen = <String>{};
    for (final link in content.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty ||
          href == '#' ||
          href.startsWith('javascript:') ||
          href.startsWith('mailto:')) {
        continue;
      }
      final url = urls.absoluteUrl(href);
      if (!seen.add(url)) continue;
      final label = _cleanText(link.text);
      links.add(ThreadLink(label: label.isEmpty ? url : label, url: url));
      if (links.length >= 20) break;
    }
    return links;
  }

  dom.Element? _desktopContentElement(dom.Element? contentCell) {
    if (contentCell == null) return null;
    return contentCell.querySelector('.tpc_content') ??
        contentCell.querySelector('[id^="read_"]') ??
        contentCell.querySelector('.tpc_content .f14');
  }

  void _moveAttachmentBlocksBelowReadContent(dom.Element content) {
    final readContent = content.querySelector('[id^="read_"]');
    final parent = readContent?.parent;
    if (readContent == null || parent == null) return;

    final attachments = <dom.Element>[];
    for (final node in List<dom.Node>.from(parent.nodes)) {
      if (identical(node, readContent)) break;
      if (node is dom.Element && _isTopAttachmentBlock(node)) {
        attachments.add(node);
      }
    }
    if (attachments.isEmpty) return;

    for (final attachment in attachments) {
      attachment.remove();
    }

    if (_cleanText(readContent.text).isNotEmpty &&
        !_endsWithLineBreak(readContent)) {
      readContent.append(dom.Element.tag('br'));
    }
    for (final attachment in attachments) {
      readContent.append(attachment);
    }
  }

  bool _isTopAttachmentBlock(dom.Element element) {
    return element.id.startsWith('att_') &&
        element.querySelector('img[src]') != null;
  }

  bool _endsWithLineBreak(dom.Element element) {
    for (final node in element.nodes.reversed) {
      if (node is dom.Text && _cleanText(node.text).isEmpty) continue;
      return node is dom.Element && node.localName == 'br';
    }
    return false;
  }

  void _removeIgnoredContent(dom.Element content) {
    for (final element in content.querySelectorAll(
      'script, style, noscript, div[id^="alert_"], div[id^="p_"], div[id^="w_"]',
    )) {
      element.remove();
    }
  }

  String _floor(dom.Element contentCell) {
    final floor = _cleanText(
      contentCell.querySelector('.tiptop .fl .s3')?.text ??
          contentCell.querySelector('.tiptop .fl')?.text ??
          '',
    );
    return floor;
  }

  String _postedAt(dom.Element contentCell) {
    final time = contentCell.querySelector('.tiptop .gray');
    final title = _cleanText(time?.attributes['title'] ?? '');
    final text = _cleanText(time?.text ?? '');
    final source = title.isNotEmpty ? title : text;
    return RegExp(r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}')
            .firstMatch(source)
            ?.group(0) ??
        '';
  }

  String? _authorPostsHref(dom.Element contentCell) {
    for (final link in contentCell.querySelectorAll(
      'a[href*="read.php?tid-"][href*="-uid-"]',
    )) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty ||
          href.contains('skinco-') ||
          href.contains('page-') ||
          !RegExp(r'read\.php\?tid-\d+-uid-\d+\.html').hasMatch(href)) {
        continue;
      }
      final label = _cleanText(link.text);
      if (label.isEmpty || label.contains('只看')) return href;
    }
    return null;
  }

  String? _quoteHref(dom.Element contentCell) {
    for (final link
        in contentCell.querySelectorAll('a[href*="post.php?action-quote"]')) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('javascript:')) continue;
      return href;
    }
    return null;
  }

  int? _pageFromHref(String href) {
    final match = RegExp(r'page-(\d+)').firstMatch(href);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  bool _startsWithSaleBox(dom.Element content) {
    for (final node in content.nodes) {
      if (node is dom.Text && _cleanText(node.text).isEmpty) continue;
      if (node is dom.Element) {
        if (node.localName == 'h6' &&
            node.classes.contains('quote') &&
            node.classes.contains('jumbotron')) {
          return true;
        }
        if (_cleanText(node.text).isEmpty) continue;
      }
      return false;
    }
    return false;
  }

  List<ThreadSaleBox> _extractSaleBoxes(dom.Element content) {
    final saleBoxes = <ThreadSaleBox>[];
    for (final saleElement in content.querySelectorAll('h6.quote.jumbotron')) {
      final input = saleElement.querySelector('input[type="button"]');
      final onclick = input?.attributes['onclick'] ?? '';
      final buyPath = _buyPathFromOnclick(onclick);
      if (buyPath == null) continue;

      final summary = _cleanText(
        saleElement.querySelector('.s3')?.text ?? saleElement.text,
      );
      final warningElement = _saleWarningElement(saleElement);
      final warning = _cleanText(warningElement?.text ?? '');
      final priceMatch = RegExp(r'售价\s*(\d+)\s*SP币').firstMatch(summary);
      final buyersMatch = RegExp(r'已有\s*(\d+)\s*人购买').firstMatch(summary);

      saleBoxes.add(
        ThreadSaleBox(
          summary: summary.isEmpty ? '此帖需要购买后查看' : summary,
          buyPath: buyPath,
          warning: warning.isEmpty ? null : warning,
          price: priceMatch == null ? null : int.tryParse(priceMatch.group(1)!),
          buyers:
              buyersMatch == null ? null : int.tryParse(buyersMatch.group(1)!),
        ),
      );

      saleElement.remove();
      warningElement?.remove();
    }
    return saleBoxes;
  }

  String? _buyPathFromOnclick(String onclick) {
    final match = RegExp("location\\.href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
        .firstMatch(onclick);
    return match?.group(1);
  }

  dom.Element? _saleWarningElement(dom.Element saleElement) {
    final parent = saleElement.parent;
    if (parent == null) return null;
    final siblings = parent.children;
    final index = siblings.indexOf(saleElement);
    if (index == -1 || index + 1 >= siblings.length) return null;
    final sibling = siblings[index + 1];
    if (sibling.localName != 'blockquote') return null;
    return sibling.classes.contains('blockquote') ? sibling : null;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
