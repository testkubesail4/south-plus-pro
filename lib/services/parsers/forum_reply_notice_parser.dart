import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_request_exception.dart';
import '../forum_url_resolver.dart';

class ForumReplyNoticeParser {
  ForumReplyNoticeParser({required this.urls});

  final ForumUrlResolver urls;

  String? verifyToken(dom.Document document) {
    for (final script in document.querySelectorAll('head script')) {
      final match =
          RegExp(r'''\bvar\s+verifyhash\s*=\s*['"]([A-Za-z0-9]{8})['"]''')
              .firstMatch(script.text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  bool hasReplyNotice(dom.Document document) =>
      document.querySelector('a#newrp') != null;

  bool hasUnreadPm(dom.Document document) =>
      document.querySelectorAll('#td_msg img[src]').any((image) =>
          Uri.tryParse(image.attributes['src']!)?.path.split('/').last ==
          'shortmail.gif') ||
      document
          .querySelectorAll('a[href="message.php"]')
          .any((link) => link.text.trim() == '您有新的消息');

  List<ForumReplyNotice> parse(dom.Document document) {
    if (!document
        .querySelectorAll('th.h')
        .any((heading) => heading.text.trim() == '回复提醒')) {
      throw const ForumRequestException(ForumRequestKind.server, '没有解析到回复提醒');
    }
    final notices = <ForumReplyNotice>[];
    final seen = <int>{};
    for (final row in document.querySelectorAll('tr.tr3')) {
      final thread = row.querySelector('td.tal a[href*="read.php"]');
      final board = row.querySelector('td a[href*="thread.php"]');
      final threadUrl = urls.absoluteUrl(thread?.attributes['href'] ?? '');
      final boardUrl = urls.absoluteUrl(board?.attributes['href'] ?? '');
      final tid = int.tryParse(urls.tidFromUrl(threadUrl) ?? '');
      if (thread == null ||
          board == null ||
          tid == null ||
          tid <= 0 ||
          urls.forumLinkTarget(threadUrl) is! ForumThreadLinkTarget ||
          urls.forumLinkTarget(boardUrl) is! ForumBoardLinkTarget) {
        throw const ForumRequestException(ForumRequestKind.server, '回复提醒格式无效');
      }
      if (!seen.add(tid)) continue;
      final cells = row.querySelectorAll('td');
      notices.add(ForumReplyNotice(
        tid: tid,
        board: board.text.trim(),
        boardUrl: boardUrl,
        title: thread.text.trim(),
        threadUrl: threadUrl,
        date: cells.length > 2 ? cells[2].text.trim() : '',
      ));
    }
    return notices;
  }
}
