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
  r'刷新不要快[于於]|不要快[于於]|刷新間隔|刷新间隔|搜索間隔|搜索间隔|搜尋間隔|过于频繁|過於頻繁|太频繁|太頻繁|\d+\s*秒[后後]再',
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

bool forumTextIsRateLimited(String text) => _rateLimitedText.hasMatch(text);

bool forumTextNeedsLogin(String text) => _loginPhrases.any(text.contains);

bool forumTextIsForbidden(String text) => _forbiddenPhrases.any(text.contains);
