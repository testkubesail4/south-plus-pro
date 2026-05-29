import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class SearchResultParser {
  SearchResultParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  List<ForumThread> parse(dom.Document document) {
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
    return threads;
  }

  int? _firstInt(String input) {
    final match = RegExp(r'\d+').firstMatch(input);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
