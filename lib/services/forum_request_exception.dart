import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

enum ForumRequestKind {
  rateLimited,
  loginRequired,
  forbidden,
  invalidInput,
  network,
  server,
}

class ForumRequestException implements Exception {
  const ForumRequestException(this.kind, this.message);

  final ForumRequestKind kind;
  final String message;

  @override
  String toString() => message;
}

final RegExp _rateLimitedText = RegExp(
  r'^(?:(?:论坛设置|論壇設置)[:：]\s*)?(?:'
  r'刷新不要快[于於]\s*\d+\s*秒|'
  r'(?:搜索|搜尋|刷新)(?:间隔|間隔)\s*(?:过短|過短|\d+\s*秒[后後]再(?:试|試))|'
  r'(?:请求|請求|操作|搜索|搜尋)?(?:过于频繁|過於頻繁|太频繁|太頻繁)|'
  r'请?\s*\d+\s*秒[后後]再(?:搜索|搜尋|刷新|试|試))\s*[。.!！]?$',
);

const _loginPhrases = <String>[
  '请先登录',
  '請先登錄',
  '請先登入',
  '尚未登录',
  '尚未登錄',
  '请登录后',
  '請登錄後',
  '登录后方可',
  '您还未登录',
  '您還沒有登錄',
];

const _forbiddenPhrases = <String>[
  '没有权限',
  '沒有權限',
  '无权',
  '無權',
  '权限不足',
  '權限不足',
  '禁止访问',
  '禁止訪問',
  '禁止浏览',
  '禁止瀏覽',
];

bool forumTextIsRateLimited(String text) =>
    _rateLimitedText.hasMatch(text.replaceAll(RegExp(r'\s+'), ' ').trim());

bool forumResponseIsRateLimited(String html) =>
    forumDocumentIsRateLimited(html_parser.parse(html));

bool forumDocumentIsRateLimited(dom.Document document) {
  for (final heading in document
      .querySelectorAll('#main > .t > table td.h, #main > .t > table th.h')) {
    if (_insideUserContent(heading) ||
        !RegExp(r'^(?:南\+ South Plus\s+)?提示信息$').hasMatch(heading.text.trim()))
      continue;
    dom.Element? table = heading.parent;
    while (table != null && table.localName != 'table') {
      table = table.parent;
    }
    for (final message
        in table?.querySelectorAll('tr.f_one td center') ?? <dom.Element>[]) {
      if (!_insideUserContent(message) && forumTextIsRateLimited(message.text))
        return true;
    }
  }
  if (document.querySelector(
          '.tpc_content, [id^="read_"], #cate_thread, #ajaxtable, '
          'ul.stream, #u-top, .u-table, .u-box-wrap, .set-table2, .bianji, .signature, '
          'a[href*="read.php"], blockquote, textarea') !=
      null) return false;
  final title = (document.querySelector('title')?.text ?? '')
      .replaceFirst(RegExp(r'\s+-\s+南\+ South Plus - powered by Pu!mdHd$'), '');
  final body = (document.body?.text ?? '').trim();
  return (body.isEmpty && forumTextIsRateLimited(title)) ||
      forumTextIsRateLimited(body);
}

bool _insideUserContent(dom.Element node) {
  for (dom.Element? parent = node; parent != null; parent = parent.parent) {
    if (parent.id.startsWith('read_') ||
        {'cate_thread', 'ajaxtable', 'u-top'}.contains(parent.id) ||
        parent.classes.any({
          'tpc_content',
          'stream',
          'u-table',
          'u-box-wrap',
          'set-table2',
          'bianji',
          'signature'
        }.contains) ||
        {'blockquote', 'textarea', 'script', 'style'}
            .contains(parent.localName)) {
      return true;
    }
  }
  return false;
}

bool forumTextNeedsLogin(String text) => _loginPhrases.any(text.contains);

bool forumTextIsForbidden(String text) => _forbiddenPhrases.any(text.contains);
