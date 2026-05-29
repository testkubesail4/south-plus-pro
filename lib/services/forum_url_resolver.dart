import '../models/forum_models.dart';

class ForumUrlResolver {
  const ForumUrlResolver();

  String absoluteUrl(String href) {
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) return href;
    if (href.startsWith('//')) return 'https:$href';
    if (href.startsWith('/')) return 'https://south-plus.net$href';
    return 'https://south-plus.net/$href';
  }

  String relativePath(String url) {
    if (!url.startsWith('https://south-plus.net/')) return url;
    return url.substring('https://south-plus.net/'.length);
  }

  String captchaPath(String src) {
    final path = relativePath(absoluteUrl(src));
    final separator = path.endsWith('?')
        ? ''
        : path.contains('?')
            ? '&'
            : '?';
    return '${path}${separator}nowtime=${DateTime.now().millisecondsSinceEpoch}';
  }

  String? tidFromUrl(String url) {
    for (final pattern in [
      RegExp(r'tid-(\d+)'),
      RegExp(r'[?&]t(\d+)'),
      RegExp(r'[?&]tid=(\d+)'),
    ]) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? uidFromUrl(String url) {
    for (final pattern in [
      RegExp(r'uid-(\d+)'),
      RegExp(r'[?&]uid=(\d+)'),
    ]) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? fidFromCategory(ForumCategory category) {
    for (final value in [category.slug, category.url ?? '']) {
      final match = RegExp(r'(?:^f|fid-|[?&]f)(\d+)').firstMatch(value);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? boardDesktopPath(ForumCategory category, {int page = 1}) {
    final fid = fidFromCategory(category);
    if (fid != null) {
      final pagePart = page <= 1 ? '' : '-page-$page';
      return 'thread.php?fid-$fid$pagePart.html';
    }
    final slug = category.slug;
    if (slug.startsWith('fid-')) return 'thread.php?$slug.html';
    final href = category.url;
    if (href == null) return null;
    final hrefFid = RegExp(r'fid-\d+').firstMatch(href)?.group(0);
    return hrefFid == null ? null : 'thread.php?$hrefFid.html';
  }

  String boardSimplePath(ForumCategory category, {int page = 1}) {
    final href = category.url;
    if (href != null && href.contains('/simple/')) {
      if (page <= 1) return href;
      final fidMatch = RegExp(r'\?f(\d+)(?:_\d+)?\.html').firstMatch(href);
      if (fidMatch != null) {
        return 'https://south-plus.net/simple/index.php?f${fidMatch.group(1)}_$page.html';
      }
    }
    final fid = fidFromCategory(category);
    if (fid != null) {
      final pagePart = page <= 1 ? '' : '_$page';
      return 'https://south-plus.net/simple/index.php?f$fid$pagePart.html';
    }
    return 'https://south-plus.net/simple/index.php?${category.slug}.html';
  }

  String threadDetailPath(String url) {
    final uri = Uri.tryParse(url);
    final isSouthPlus =
        uri == null || uri.host.isEmpty || uri.host.endsWith('south-plus.net');
    final tid = tidFromUrl(url);
    if (isSouthPlus &&
        tid != null &&
        !url.contains('/simple/') &&
        (url.contains('read.php') || url.contains('job.php?action-topost'))) {
      return 'simple/index.php?t$tid.html';
    }
    return relativePath(url);
  }

  String userTabUrl(String uid, UserProfileTab tab) {
    return switch (tab) {
      UserProfileTab.home => 'https://south-plus.net/u.php?uid-$uid.html',
      UserProfileTab.profile =>
        'https://south-plus.net/u.php?action-show-uid-$uid.html',
      UserProfileTab.topics =>
        'https://south-plus.net/u.php?action-topic-uid-$uid.html',
      UserProfileTab.posts =>
        'https://south-plus.net/u.php?action-post-uid-$uid.html',
      UserProfileTab.favorites =>
        'https://south-plus.net/u.php?action-favor-uid-$uid.html',
    };
  }

  bool isThreadHref(String href) {
    final query = Uri.tryParse(href)?.query ?? '';
    return query.startsWith('t') && query.endsWith('.html');
  }

  String slugFromHref(String href) {
    final query = Uri.tryParse(href)?.query ?? href;
    return query.endsWith('.html')
        ? query.substring(0, query.length - '.html'.length)
        : query;
  }
}
