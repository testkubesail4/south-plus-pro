import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/forum_models.dart';
import 'forum_client.dart';
import 'forum_request_exception.dart';
import 'forum_url_resolver.dart';
import 'full_scan.dart';
import 'keyword_match.dart';
import 'parsers/forum_favorites_parser.dart';
import 'parsers/thread_detail_parser.dart';

class FavoriteSearchHit {
  const FavoriteSearchHit({required this.thread, required this.page});
  final UserListItem thread;
  final int page;
}

FullScan<FavoriteSearchHit> createFavoriteScan({
  required ForumClient client,
  required bool Function() isCurrentSession,
  required String keyword,
  required FavoriteCollections? loaded,
  String? categoryId,
}) {
  if (categoryId != null && !RegExp(r'^(?:0|[1-9]\d*)$').hasMatch(categoryId)) {
    throw const ForumRequestException(ForumRequestKind.invalidInput, '收藏分类无效');
  }
  final urls = ForumUrlResolver(baseUri: client.baseUri);
  final seedPage = loaded?.categoryId == categoryId ? loaded : null;
  String key(UserListItem item) => urls.tidFromUrl(item.url) ?? item.url;

  Iterable<FavoriteSearchHit> seed() sync* {
    if (seedPage == null) return;
    final seen = <String>{};
    for (final entry in seedPage.items) {
      final item = entry.thread;
      if (item.titleTruncated || matchKeyword(keyword, [item.title]) != true)
        continue;
      if (!seen.add(key(item))) continue;
      yield FavoriteSearchHit(thread: item, page: seedPage.page);
      if (seen.length > maxScanResults) return;
    }
  }

  var categoryName = seedPage?.categories
      .where((category) => category.id == categoryId)
      .firstOrNull
      ?.label;
  int? previousPage;
  String? previousFingerprint;
  late final PageFullScan<FavoriteSearchHit> scan;
  scan = PageFullScan<FavoriteSearchHit>(
    client: client,
    isCurrentSession: isCurrentSession,
    initialHits: seed(),
    initialPending:
        seedPage?.items.where((entry) => entry.thread.titleTruncated).length ??
            0,
    totalPages: seedPage?.pageCount,
    readPage: (page, request) async {
      FavoriteCollections view;
      if (seedPage != null && page == seedPage.page) {
        view = seedPage;
      } else {
        final path = Uri(path: 'u.php', queryParameters: {
          'action': 'favor',
          if (categoryId != null) 'type': categoryId,
          'page': '$page',
        }).toString();
        final html = await request.getOnce(path);
        final document = html_parser.parse(html);
        if (document.querySelector('#u-contentmain .u-table') == null) {
          _rejectPage(document, '未读到收藏列表');
        }
        try {
          view = const ForumFavoritesParser()
              .parse(html, client.baseUri, categoryId: categoryId)
              .collections;
        } on ForumRequestException catch (error) {
          if (error.kind != ForumRequestKind.server) rethrow;
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '收藏页面格式无效');
        }
      }
      if (view.page != page || view.pageCount == null) {
        throw const ForumRequestException(
            ForumRequestKind.invalidInput, '无法确认收藏分页');
      }
      if (categoryId != null && categoryId != '0') {
        final current = view.categories
            .singleWhere((category) => category.id == categoryId)
            .label;
        if (categoryName != null && categoryName != current) {
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '收藏分类已变更，请重新搜索');
        }
        categoryName = current;
      }
      final identities =
          view.items.map((entry) => key(entry.thread)).toSet().toList()..sort();
      final fingerprint = identities.join(',');
      if (previousPage != null &&
          previousPage != page &&
          previousFingerprint == fingerprint) {
        throw const ForumRequestException(
            ForumRequestKind.invalidInput, '收藏分页重复，请刷新后重试');
      }
      previousPage = page;
      previousFingerprint = fingerprint;
      final seen = {
        ...scan.hits.map((hit) => key(hit.thread)),
        ...scan.unresolved.map((hit) => key(hit.thread)),
      };
      final rows =
          view.items.where((entry) => !seen.contains(key(entry.thread)));
      var pending = rows.where((entry) => entry.thread.titleTruncated).length;
      request.setPending(pending);
      final hits = <FavoriteSearchHit>[];
      final unresolved = <FavoriteSearchHit>[];
      for (final entry in rows) {
        var item = entry.thread;
        if (!item.titleTruncated && matchKeyword(keyword, [item.title]) != true)
          continue;
        if (item.titleTruncated) {
          try {
            final tid = urls.tidFromUrl(item.url);
            if (tid == null) {
              throw const ForumRequestException(
                  ForumRequestKind.invalidInput, '收藏链接无效');
            }
            final html = await request.getOnce('read.php?tid-$tid.html');
            final document = html_parser.parse(html);
            final title = document.querySelector('#subject_tpc');
            if (title == null || title.text.trim().isEmpty) {
              _rejectPage(document, '无法确认收藏标题');
            }
            final linked = ThreadDetailParser(urls: urls).threadUrl(document);
            if (linked != null && urls.tidFromUrl(linked) != tid) {
              throw const ForumRequestException(
                  ForumRequestKind.invalidInput, '响应不是所选主题');
            }
            item = item.copyWith(
                title: title.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
                titleTruncated: false);
          } on ForumRequestException catch (error) {
            if (error.kind != ForumRequestKind.forbidden &&
                error.kind != ForumRequestKind.invalidInput) rethrow;
            unresolved.add(FavoriteSearchHit(thread: item, page: page));
            seen.add(key(item));
          }
          request.setPending(--pending);
          if (item.titleTruncated) {
            if (seen.length > maxScanResults) break;
            continue;
          }
        }
        if (matchKeyword(keyword, [item.title]) == true &&
            seen.add(key(item))) {
          hits.add(FavoriteSearchHit(thread: item, page: page));
        }
        if (seen.length > maxScanResults) break;
      }
      return ScanPage(
          page: page,
          totalPages: view.pageCount,
          hasMore: page < view.pageCount!,
          hits: hits,
          unresolved: unresolved);
    },
  );
  return scan;
}

Never _rejectPage(dom.Document document, String message) {
  final text = '${document.querySelector('title')?.text ?? ''}\n'
      '${document.body?.text ?? ''}';
  final kind = forumTextNeedsLogin(text) ||
          document.querySelector('input[name="pwpwd"]') != null
      ? ForumRequestKind.loginRequired
      : forumTextIsForbidden(text)
          ? ForumRequestKind.forbidden
          : forumTextIsRateLimited(text)
              ? ForumRequestKind.rateLimited
              : ForumRequestKind.invalidInput;
  throw ForumRequestException(kind, message);
}
