import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_request_exception.dart';
import '../forum_url_resolver.dart';
import 'thread_title_style_parser.dart';

class SearchResultParser {
  SearchResultParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  ForumSearchPage parsePage(dom.Document document) {
    final threads = parse(document);
    final totalMatch =
        RegExp(r'共\s*搜索到了\s*(\d+)\s*条信息').firstMatch(_pageText(document));
    final pages = document.querySelector('.pages');
    final currentMatch =
        RegExp(r'Pages:\s*(\d+)\s*/').firstMatch(_cleanText(pages?.text ?? ''));
    final current = int.tryParse(currentMatch?.group(1) ?? '') ??
        int.tryParse(
          _cleanText(pages?.querySelector('b, .current')?.text ?? ''),
        ) ??
        1;
    String? nextPagePath, previousPagePath;
    int? nextPage, previousPage;
    final pageLinks = <ForumSearchPageLink>[];
    final seenPages = <String>{};
    for (final link in pages?.querySelectorAll('a[href]') ?? <dom.Element>[]) {
      final path = urls.relativePath(
        urls.absoluteUrl(link.attributes['href'] ?? ''),
      );
      final uri = Uri.tryParse(path);
      if (uri == null ||
          uri.hasAuthority ||
          uri.hasScheme ||
          uri.path != 'search.php') {
        continue;
      }
      final pageMatch =
          RegExp(r'(?:[?&]page=|(?:^|-)page-)(\d+)').firstMatch(path);
      final page = int.tryParse(pageMatch?.group(1) ?? '');
      if (page != null && page >= 1 && seenPages.add(path)) {
        pageLinks.add(ForumSearchPageLink(
            label: _cleanText(link.text), path: path, page: page));
        if (page < current && (previousPage == null || page > previousPage)) {
          previousPage = page;
          previousPagePath = path;
        }
      }
      if (page != null &&
          page > current &&
          (nextPage == null || page < nextPage)) {
        nextPage = page;
        nextPagePath = path;
      }
    }
    return ForumSearchPage(
      threads: threads,
      total: int.tryParse(totalMatch?.group(1) ?? '') ??
          (_pageText(document).contains('没有查找匹配的内容') ? 0 : null),
      nextPagePath: nextPagePath,
      previousPagePath: previousPagePath,
      currentPage: current,
      pageLinks: List.unmodifiable(pageLinks),
    );
  }

  List<ForumThread> parse(dom.Document document) {
    final text = _pageText(document);
    if (forumTextIsRateLimited(text)) {
      throw const ForumRequestException(
        ForumRequestKind.rateLimited,
        '请求过于频繁',
      );
    }
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('tr')) {
      final threadLink = row.querySelector('a[href*="read.php?tid-"]');
      if (threadLink == null) continue;

      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;

      final cells = row.children
          .where((child) => child.localName == 'td' || child.localName == 'th')
          .toList();
      final sectionCell = cells.length > 2 ? cells[2] : row;
      final authorCell = cells.length > 3 ? cells[3] : row;
      final repliesCell = cells.length > 4 ? cells[4] : null;

      final section = _cleanText(
        sectionCell.querySelector('a[href*="thread.php"]')?.text ?? '',
      );
      final authorLink = authorCell.querySelector('a[href*="uid"]');
      final author = _cleanText(authorLink?.text ?? '');
      final authorHref = authorLink?.attributes['href'] ?? '';
      final date = RegExp(r'\d{4}-\d{2}-\d{2}')
          .firstMatch(_cleanText(authorCell.text))
          ?.group(0);

      threads.add(
        ForumThread(
          title: title,
          titleStyle: parseThreadTitleStyle(threadLink),
          url: urls.absoluteUrl(href),
          replies: _firstInt(_cleanText(repliesCell?.text ?? '')) ?? 0,
          section: section.isEmpty ? '搜索结果' : section,
          author: author.isEmpty ? null : author,
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
          lastPost: date,
        ),
      );
      if (threads.length >= 60) break;
    }
    final normal = _isNormalResult(text);
    if (!normal && forumTextNeedsLogin(text)) {
      throw const ForumRequestException(
        ForumRequestKind.loginRequired,
        '需要登录',
      );
    }
    if (!normal && forumTextIsForbidden(text)) {
      throw const ForumRequestException(
        ForumRequestKind.forbidden,
        '没有权限',
      );
    }
    if (threads.isEmpty &&
        document.querySelectorAll('tr.f_one center').any((element) =>
            RegExp(r'^用户\s*不存在$').hasMatch(_cleanText(element.text)))) {
      throw const ForumRequestException(
        ForumRequestKind.invalidInput,
        '用户不存在，请检查实际登录名称',
      );
    }
    if (threads.isEmpty && !normal) {
      throw const ForumRequestException(
        ForumRequestKind.server,
        '搜索结果无效',
      );
    }
    return threads;
  }

  String _pageText(dom.Document document) {
    return '${document.querySelector('title')?.text ?? ''}\n'
        '${document.body?.text ?? ''}';
  }

  bool _isNormalResult(String text) {
    return RegExp(r'共\s*搜索到了\s*\d+\s*条信息').hasMatch(text) ||
        text.contains('搜索结果') ||
        text.contains('搜索結果') ||
        RegExp(r'共\s*(?:搜索|搜尋)?到\s*\d+').hasMatch(text) ||
        RegExp(r'(?:找到|搜索到|搜尋到)\s*\d+\s*[条條篇]').hasMatch(text) ||
        text.contains('没有查找匹配的内容') ||
        text.contains('没有找到符合条件') ||
        text.contains('沒有找到符合條件');
  }

  int? _firstInt(String input) {
    final match = RegExp(r'\d+').firstMatch(input);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
