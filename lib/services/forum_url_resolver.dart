import '../models/forum_models.dart';
import 'forum_network_config.dart';

class ForumUrlResolver {
  ForumUrlResolver({
    Uri? baseUri,
  }) : baseUri = baseUri ?? ForumNetworkConfig.defaultSite.baseUri;

  final Uri baseUri;

  String get _origin => '${baseUri.scheme}://${baseUri.host}';

  String absoluteUrl(String href) {
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) {
      if (_isForumHost(uri.host)) {
        return uri
            .replace(scheme: baseUri.scheme, host: baseUri.host)
            .toString();
      }
      return href;
    }
    if (href.startsWith('//')) return absoluteUrl('https:$href');
    if (href.startsWith('./')) return '$_origin/${href.substring(2)}';
    if (href.startsWith('/')) return '$_origin$href';
    return '$_origin/$href';
  }

  String relativePath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    if (!_isForumHost(uri.host)) return url;
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    return '$path$query$fragment';
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
      final match =
          RegExp(r'(?:^f|fid-|[?&]fid=?|[?&]f)(\d+)').firstMatch(value);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? boardDesktopPath(ForumCategory category, {int page = 1}) {
    final fid = fidFromCategory(category);
    if (fid != null) {
      final normalizedPage = page < 1 ? 1 : page;
      return 'thread_new.php?fid-$fid-page-$normalizedPage.html';
    }
    final slug = category.slug;
    final slugFid = RegExp(r'^fid-(\d+)$').firstMatch(slug)?.group(1);
    if (slugFid != null) {
      final normalizedPage = page < 1 ? 1 : page;
      return 'thread_new.php?fid-$slugFid-page-$normalizedPage.html';
    }
    final href = category.url;
    if (href == null) return null;
    final hrefFid = RegExp(r'fid-(\d+)').firstMatch(href)?.group(1) ??
        RegExp(r'[?&]fid=(\d+)').firstMatch(href)?.group(1);
    if (hrefFid == null) return null;
    final normalizedPage = page < 1 ? 1 : page;
    return 'thread_new.php?fid-$hrefFid-page-$normalizedPage.html';
  }

  String boardSimplePath(ForumCategory category, {int page = 1}) {
    final href = category.url;
    if (href != null && href.contains('/simple/')) {
      if (page <= 1) return href;
      final fidMatch = RegExp(r'\?f(\d+)(?:_\d+)?\.html').firstMatch(href);
      if (fidMatch != null) {
        return '$_origin/simple/index.php?f${fidMatch.group(1)}_$page.html';
      }
    }
    final fid = fidFromCategory(category);
    if (fid != null) {
      final pagePart = page <= 1 ? '' : '_$page';
      return '$_origin/simple/index.php?f$fid$pagePart.html';
    }
    return '$_origin/simple/index.php?${category.slug}.html';
  }

  String threadDetailPath(String url, {int page = 1}) {
    final uri = Uri.tryParse(url);
    final isForum = uri == null || uri.host.isEmpty || _isForumHost(uri.host);
    final tid = tidFromUrl(url);
    if (isForum && tid != null) {
      final uid = uidFromUrl(url);
      final uidPart = uid == null ? '' : '-uid-$uid';
      if (page <= 1) return 'read.php?tid-$tid$uidPart.html';
      return 'read.php?tid-$tid$uidPart-fpage-0-toread--page-$page.html';
    }
    return relativePath(url);
  }

  String userTabUrl(String uid, UserProfileTab tab) {
    return switch (tab) {
      UserProfileTab.home => '$_origin/u.php?uid-$uid.html',
      UserProfileTab.profile => '$_origin/u.php?action-show-uid-$uid.html',
      UserProfileTab.topics => '$_origin/u.php?action-topic-uid-$uid.html',
      UserProfileTab.posts => '$_origin/u.php?action-post-uid-$uid.html',
      UserProfileTab.favorites => '$_origin/u.php?action-favor-uid-$uid.html',
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

  bool _isForumHost(String host) {
    final normalized = host.toLowerCase();
    return ForumNetworkConfig.sites.any(
      (site) => normalized == site.host || normalized.endsWith('.${site.host}'),
    );
  }
}
