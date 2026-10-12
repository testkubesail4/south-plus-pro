import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_request_exception.dart';
import '../forum_url_resolver.dart';

class SearchResultParser {
  SearchResultParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

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
    return text.contains('搜索结果') ||
        text.contains('搜索結果') ||
        RegExp(r'共\s*(?:搜索|搜尋)?到\s*\d+').hasMatch(text) ||
        RegExp(r'(?:找到|搜索到|搜尋到)\s*\d+\s*[条條篇]')
            .hasMatch(text) ||
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
