import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/forum_models.dart';
import '../models/user_content_query.dart';
import 'forum_client.dart';
import 'full_scan.dart';
import 'keyword_match.dart';
import 'forum_request_exception.dart';
import 'parsers/thread_detail_parser.dart';
import 'forum_url_resolver.dart';
import 'parsers/user_profile_parser.dart';

typedef _ScanMetadata = ({UserContentThreadMetadata metadata, bool? type});

class UserContentQueryService {
  UserContentQueryService({
    required this.getDocument,
    required this.urls,
    required this.sessionEpoch,
  }) : _parser = UserProfileParser(urls: urls);

  final Future<dom.Document> Function(String path) getDocument;
  final ForumUrlResolver urls;
  final int Function() sessionEpoch;
  final UserProfileParser _parser;
  final _states = <String, _QueryState>{};
  final _pages = <String, Future<UserContentPage>>{};
  final _boards = <String, Future<List<UserContentClassification>>>{};
  final _metadata = <String, Future<UserContentThreadMetadata>>{};
  final _boardMetadata = <String, UserContentThreadMetadata>{};
  final _lookups = <String, _TypeLookup>{};
  int? _epoch;
  int _generation = 0;

  void _checkScope() {
    final epoch = sessionEpoch();
    if (_epoch == epoch) return;
    _epoch = epoch;
    _generation++;
    _states.clear();
    _pages.clear();
    _boards.clear();
    _metadata.clear();
    _boardMetadata.clear();
    _lookups.clear();
  }

  void _assertScope(int generation) {
    if (_generation != generation || _epoch != sessionEpoch()) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已变更，请重新加载');
    }
  }

  void _validateId(String value) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) {
      throw ArgumentError.value(value, 'id', 'Expected a positive numeric ID');
    }
  }

  Future<List<UserContentClassification>> fetchBoardFilters(String boardId) {
    _validateId(boardId);
    _checkScope();
    return _boardFilters(boardId, _generation);
  }

  Future<List<UserContentClassification>> _boardFilters(
      String boardId, int generation) {
    final existing = _boards[boardId];
    if (existing != null) return existing;
    late Future<List<UserContentClassification>> pending;
    pending = (() async {
      final document = await getDocument('thread.php?fid-$boardId.html');
      _assertScope(generation);
      _requireShape(document, '.hthread, #ajaxtable', '无法识别版块分类');
      final classifications =
          _parser.parseContentClassifications(document, boardId);
      final rows = _parser.parseContentBoardMetadata(document,
          boardId: boardId, classifications: classifications);
      for (final entry in rows.entries) {
        _putBounded(_boardMetadata, entry.key, entry.value, 256);
      }
      return List<UserContentClassification>.unmodifiable(classifications);
    })()
        .catchError((Object error, StackTrace stack) {
      if (identical(_boards[boardId], pending)) _boards.remove(boardId);
      Error.throwWithStackTrace(error, stack);
    });
    _putBounded(_boards, boardId, pending, 32);
    return pending;
  }

  void _validateQuery(UserContentQuery query) {
    _validateId(query.uid);
    if (query.boardId != null) _validateId(query.boardId!);
    if (query.classificationId != null) {
      _validateId(query.classificationId!);
      if (query.boardId == null) {
        throw ArgumentError('A classification requires a board');
      }
    }
    if (!{UserProfileTab.topics, UserProfileTab.posts, UserProfileTab.favorites}
            .contains(query.tab) ||
        (query.tab == UserProfileTab.favorites &&
            query.articleType != UserContentArticleType.all)) {
      throw ArgumentError('Unsupported content query');
    }
  }

  Future<UserContentResult> fetch(UserContentQuery query,
      {bool refresh = false}) {
    _validateQuery(query);
    _checkScope();
    if (refresh) {
      _generation++;
      _states.clear();
      _pages.clear();
      _boards.clear();
      _metadata.clear();
      _boardMetadata.clear();
      _lookups.clear();
    }
    final key = query.cacheKey;
    final state = _states.putIfAbsent(key, _QueryState.new);
    if (_states.length > 8) _states.remove(_states.keys.first);
    final existing = state.pending;
    if (existing != null) return existing;
    final generation = _generation;
    late Future<UserContentResult> pending;
    pending = _advance(query, state, generation).whenComplete(() {
      if (identical(state.pending, pending)) state.pending = null;
    });
    state.pending = pending;
    return pending;
  }

  Future<UserContentResult> _advance(
      UserContentQuery query, _QueryState state, int generation) async {
    if (state.page < state.totalPages) {
      final page = state.page + 1;
      final type = query.tab == UserProfileTab.topics
          ? query.articleType
          : UserContentArticleType.all;
      final key = '${query.uid}/${query.tab.name}/${type.name}/$page';
      final parsed = await _page(query, type, page, key, generation);
      _assertScope(generation);
      state.page = page;
      if (parsed.totalPages > state.totalPages)
        state.totalPages = parsed.totalPages;
      for (final item in parsed.items) {
        if (state.seen.add(_rowIdentity(item, query.tab))) state.rows.add(item);
        if (item.boardId != null) {
          state.boards[item.boardId!] = ForumCategory(
              name: item.section ?? '版块 ${item.boardId}',
              slug: 'f${item.boardId}',
              url: item.boardUrl);
        }
      }
    }
    final matches = <UserListItem>[];
    final unresolved = <UserListItem>[];
    for (final item in state.rows) {
      final match = _localMatch(item, query);
      if (match == true) matches.add(item);
      if (match == null) unresolved.add(item);
    }
    _assertScope(generation);
    return UserContentResult(
      items: List.unmodifiable(matches),
      unresolvedItems: List.unmodifiable(unresolved),
      boards: List.unmodifiable(state.boards.values),
      scannedPages: state.page,
      totalPages: state.totalPages,
      checkedThreads: 0,
      pendingMetadataCount: 0,
      hasMore: state.page < state.totalPages,
    );
  }

  bool? _localMatch(UserListItem item, UserContentQuery query) {
    final tid = item.threadId ?? urls.tidFromUrl(item.url);
    var metadata = _boardMetadata[tid];
    if (item.boardId != null &&
        metadata?.boardId != null &&
        item.boardId != metadata!.boardId) metadata = null;
    final type = query.tab == UserProfileTab.topics ||
            query.articleType == UserContentArticleType.all
        ? true
        : metadata?.articleType(query.articleType);
    return _matches(item, query, metadata, type);
  }

  bool? _matches(UserListItem item, UserContentQuery query,
      UserContentThreadMetadata? metadata, bool? type) {
    final boardId = metadata?.boardId ?? item.boardId;
    final board = query.boardId == null
        ? true
        : boardId == null
            ? null
            : boardId == query.boardId;
    final classification = query.classificationId == null
        ? true
        : metadata?.classificationKnown == true
            ? metadata!.classificationId == query.classificationId
            : null;
    if (board == false || classification == false || type == false)
      return false;
    return board == null || classification == null || type == null
        ? null
        : true;
  }

  FullScan<UserListItem> scan(
    UserContentQuery query, {
    required ForumClient client,
    required bool Function() isCurrentSession,
    List<UserListItem>? loaded,
    int? loadedPages,
    int? totalPages,
  }) {
    _validateQuery(query);
    _checkScope();
    final base = UserContentQuery(
        uid: query.uid,
        tab: query.tab,
        boardId: query.boardId,
        articleType: query.articleType,
        classificationId: query.classificationId);
    final state = _states[base.cacheKey];
    final source = List<UserListItem>.of(loaded ?? state?.rows ?? const []);
    var sourceMax = 0;
    final cached = <int, List<UserListItem>>{};
    for (final item in source) {
      final page = item.sourcePage ?? 1;
      if (page < 1) throw ArgumentError('Invalid loaded page');
      if (page > sourceMax) sourceMax = page;
      cached.putIfAbsent(page, () => []).add(item);
    }
    final count = loadedPages ??
        (loaded != null ? (sourceMax == 0 ? 1 : sourceMax) : state?.page ?? 0);
    if (count < 0) throw ArgumentError('Invalid loaded page count');
    if (sourceMax <= count) {
      for (var page = 1; page <= count; page++) {
        cached.putIfAbsent(page, () => []);
      }
    }
    var total = loaded != null ? totalPages : totalPages ?? state?.totalPages;
    if (total != null && (total < 1 || total < sourceMax || total < count))
      total = null;
    String identity(UserListItem item) => _rowIdentity(item, query.tab);
    String? tid(UserListItem item) => urls.tidFromUrl(item.url);
    bool? titleMatch(UserListItem item) => matchKeyword(
        query.keyword, [item.title], truncated: item.titleTruncated);
    bool needsMetadata(UserListItem item) =>
        titleMatch(item) != false &&
        _localMatch(item, query) != false &&
        (titleMatch(item) == null || _localMatch(item, query) == null);
    Iterable<UserListItem> seed() sync* {
      final seen = <String>{};
      for (final item in source) {
        if (_localMatch(item, query) != true || titleMatch(item) != true)
          continue;
        if (!seen.add(identity(item))) continue;
        yield item;
        if (seen.length > maxScanResults) return;
      }
    }

    late ScanRequest active;
    final worker = UserContentQueryService(
      urls: urls,
      sessionEpoch: sessionEpoch,
      getDocument: (path) async {
        final board = path.startsWith('thread.php?fid-');
        final html = board
            ? await client.getOnceGuarded(path,
                requireCurrentSession: active.checkCurrent,
                redirectPolicy: ForumReadRedirectPolicy.board)
            : await active.getOnce(path);
        active.checkCurrent();
        return html_parser.parse(html);
      },
    );
    worker._checkScope();
    final generation = worker._generation;
    final decisions = <String, _ScanMetadata?>{};
    late final PageFullScan<UserListItem> scan;
    void remember(String id, _ScanMetadata? value) {
      decisions[id] = value;
      if (decisions.length <= 256) return;
      final protected = {...scan.hits.map(tid), ...scan.unresolved.map(tid)};
      final obsolete = decisions.keys.firstWhere(
          (key) => !protected.contains(key),
          orElse: () => decisions.keys.first);
      decisions.remove(obsolete);
    }

    Future<_ScanMetadata?> metadata(UserListItem item) async {
      final id = tid(item);
      if (id == null) return null;
      if (decisions.containsKey(id)) return decisions[id];
      _ScanMetadata? decision;
      try {
        final taxonomy = query.classificationId != null ||
            (query.tab == UserProfileTab.posts &&
                query.articleType == UserContentArticleType.digest);
        final info = await worker._threadMetadata(
            item, id, generation, _ReadBudget(8),
            taxonomy: taxonomy);
        active.checkCurrent();
        bool? type = true;
        if (query.tab == UserProfileTab.posts &&
            query.articleType != UserContentArticleType.all) {
          type = null;
          if (matchKeyword(query.keyword, [info.title ?? item.title]) == true &&
              _matches(item, query, info, true) != false) {
            while (true) {
              final resolved = await worker._resolveType(
                  query, id, info, _ReadBudget(8), generation);
              active.checkCurrent();
              type = resolved.$1;
              if (resolved.$2 == null) break;
            }
          }
        }
        decision = (metadata: info, type: type);
      } on ForumRequestException catch (error) {
        if (error.kind != ForumRequestKind.forbidden &&
            error.kind != ForumRequestKind.invalidInput) rethrow;
      }
      active.checkCurrent();
      remember(id, decision);
      return decision;
    }

    int? workingPage;
    List<UserListItem>? workingRows;
    var cursor = 0;
    var classificationChecked = false;
    final processed = <String>{};
    int? previousPage;
    String? previousFingerprint;
    scan = PageFullScan<UserListItem>(
      client: client,
      isCurrentSession: isCurrentSession,
      initialHits: seed(),
      initialPending: source
          .where(needsMetadata)
          .map((item) => tid(item) ?? identity(item))
          .toSet()
          .length,
      totalPages: total,
      readPage: (page, request) async {
        active = request;
        if (workingPage != page || workingRows == null) {
          workingRows = null;
          cursor = 0;
          processed.clear();
          if (cached.containsKey(page)) {
            workingRows = cached[page]!;
          } else {
            final type = query.tab == UserProfileTab.topics
                ? query.articleType
                : UserContentArticleType.all;
            final parsed = await worker._page(
                query,
                type,
                page,
                '${query.uid}/${query.tab.name}/${type.name}/$page',
                generation);
            request.checkCurrent();
            if (total == null || parsed.totalPages > total!)
              total = parsed.totalPages;
            workingRows = parsed.items;
          }
          final fingerprint = workingRows!.map(identity).toSet().toList()
            ..sort();
          final value = fingerprint.join(',');
          if (!cached.containsKey(page) &&
              previousPage != null &&
              previousPage != page &&
              value == previousFingerprint) {
            throw const ForumRequestException(
                ForumRequestKind.invalidInput, '用户列表分页重复，请刷新后重试');
          }
          previousPage = page;
          previousFingerprint = value;
          workingPage = page;
        }
        final rows = workingRows!;
        final seen = {
          ...scan.hits.map(identity),
          ...scan.unresolved.map(identity)
        };
        final pending = rows
            .skip(cursor)
            .where((item) =>
                !seen.contains(identity(item)) &&
                !processed.contains(identity(item)) &&
                needsMetadata(item) &&
                !decisions.containsKey(tid(item)))
            .map((item) => tid(item) ?? identity(item))
            .toSet();
        request.setPending(pending.length);
        if (query.classificationId != null &&
            pending.isNotEmpty &&
            !classificationChecked) {
          final filters =
              await worker._boardFilters(query.boardId!, generation);
          request.checkCurrent();
          if (!filters.any((filter) => filter.id == query.classificationId)) {
            throw const ForumRequestException(
                ForumRequestKind.invalidInput, '版块分类已变更，请重新选择');
          }
          classificationChecked = true;
        }
        while (cursor < rows.length) {
          request.checkCurrent();
          var item = rows[cursor];
          final id = identity(item);
          final local = _localMatch(item, query);
          if (seen.contains(id) ||
              processed.contains(id) ||
              local == false ||
              titleMatch(item) == false) {
            processed.add(id);
            cursor++;
            continue;
          }
          final needs = titleMatch(item) == null || local == null;
          bool? match = local;
          if (needs) {
            final decision = await metadata(item);
            request.checkCurrent();
            if (decision == null) {
              match = null;
            } else {
              final data = decision.metadata;
              final changedBoard =
                  data.boardId != null && data.boardId != item.boardId;
              item = item.copyWith(
                  title: data.title,
                  titleTruncated: false,
                  boardId: data.boardId,
                  boardUrl: data.boardId == null
                      ? null
                      : urls.absoluteUrl('thread.php?fid-${data.boardId}.html'),
                  section: data.boardName ??
                      (changedBoard ? '版块 ${data.boardId}' : null));
              match = _matches(item, query, data, decision.type);
            }
          }
          final title = titleMatch(item);
          if (title != false && match != false) {
            if (title == null || match == null) {
              scan.retain(request, unresolved: [item]);
            } else {
              scan.retain(request, hits: [item]);
            }
          }
          if (needs && pending.remove(tid(item) ?? id))
            request.setPending(pending.length);
          processed.add(id);
          seen.add(id);
          cursor++;
        }
        return ScanPage(
            page: page,
            totalPages: total,
            hasMore: total == null || page < total!);
      },
    );
    return scan;
  }

  Future<(bool?, String?)> _resolveType(
    UserContentQuery query,
    String tid,
    UserContentThreadMetadata metadata,
    _ReadBudget budget,
    int generation,
  ) async {
    final known = metadata.articleType(query.articleType);
    if (known != null || metadata.authorUid == null) return (known, null);
    final key = '${metadata.authorUid}/${query.articleType.name}/$tid';
    final lookup = _lookups.putIfAbsent(key, _TypeLookup.new);
    if (_lookups.length > 256) _lookups.remove(_lookups.keys.first);
    if (lookup.tids.contains(tid)) return (true, null);
    if (lookup.unavailable) return (null, null);
    if (!lookup.hasMore) return (false, null);
    if (budget.lookupKeys.add(key)) {
      budget.take();
      var pending = lookup.pending;
      if (pending == null) {
        final page = lookup.page + 1;
        final lookupQuery = UserContentQuery(
            uid: metadata.authorUid!,
            tab: UserProfileTab.topics,
            articleType: query.articleType);
        late Future<void> next;
        next = _page(
                lookupQuery,
                query.articleType,
                page,
                '${lookupQuery.uid}/topics/${query.articleType.name}/$page',
                generation)
            .then((parsed) {
          _assertScope(generation);
          final ids = parsed.items
              .map((item) => item.threadId)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
          final fingerprint = ids.join(',');
          if (lookup.page > 0 && fingerprint == lookup.fingerprint) {
            lookup.unavailable = true;
            return;
          }
          lookup.fingerprint = fingerprint;
          lookup.page = page;
          lookup.totalPages = parsed.totalPages;
          lookup.tids.addAll(parsed.items
              .map((item) => item.threadId)
              .where((candidate) => candidate == tid)
              .whereType<String>());
        }).whenComplete(() {
          if (identical(lookup.pending, next)) lookup.pending = null;
        });
        lookup.pending = pending = next;
      }
      try {
        await pending;
      } on ForumRequestException catch (error) {
        _assertScope(generation);
        if (error.kind != ForumRequestKind.forbidden &&
            error.kind != ForumRequestKind.invalidInput) rethrow;
        lookup.unavailable = true;
        return (null, null);
      }
      _assertScope(generation);
    }
    if (lookup.tids.contains(tid)) return (true, null);
    return lookup.hasMore ? (null, key) : (false, null);
  }

  Future<UserContentPage> _page(UserContentQuery query,
      UserContentArticleType type, int page, String key, int generation) {
    final existing = _pages[key];
    if (existing != null) return existing;
    final action = switch (query.tab) {
      UserProfileTab.topics => 'topic',
      UserProfileTab.posts => 'post',
      UserProfileTab.favorites => 'favor',
      _ => throw ArgumentError('Unsupported content tab'),
    };
    final typePart =
        type == UserContentArticleType.all ? '' : '-type-${type.name}';
    late Future<UserContentPage> pending;
    pending = (() async {
      final document = await getDocument(
          'u.php?action-$action-uid-${query.uid}$typePart-page-$page.html');
      _assertScope(generation);
      _requireShape(document, '#u-contentmain .u-table', '无法识别用户文章列表');
      final result = _parser.parseContentPage(document,
          uid: query.uid, tab: query.tab, page: page, articleType: type);
      if (!result.paginationKnown) {
        throw const ForumRequestException(
            ForumRequestKind.invalidInput, '无法确认用户列表分页');
      }
      return result;
    })()
        .catchError((Object error, StackTrace stack) {
      if (identical(_pages[key], pending)) _pages.remove(key);
      Error.throwWithStackTrace(error, stack);
    });
    _putBounded(_pages, key, pending, 24);
    return pending;
  }

  Future<UserContentThreadMetadata> _threadMetadata(
      UserListItem item, String tid, int generation, _ReadBudget budget,
      {required bool taxonomy}) {
    final existing = _metadata[tid];
    if (existing != null) return existing;
    final needsBoard =
        taxonomy && item.boardId != null && !_boards.containsKey(item.boardId!);
    // Leave one read available if the thread has moved to another board.
    if (budget.remaining < (needsBoard ? 3 : 2)) {
      throw const _BudgetExhausted();
    }
    budget.take();
    if (needsBoard) budget.take();
    late Future<UserContentThreadMetadata> pending;
    pending = (() async {
      final classifications = !taxonomy || item.boardId == null
          ? <UserContentClassification>[]
          : await _boardFilters(item.boardId!, generation);
      _assertScope(generation);
      final document = await getDocument('read.php?tid-$tid.html');
      _assertScope(generation);
      _requireShape(document, '#subject_tpc', '无法识别主题资料');
      final linked = ThreadDetailParser(urls: urls).threadUrl(document);
      if ((linked != null && urls.tidFromUrl(linked) != tid) ||
          document.querySelector('#subject_tpc')!.text.trim().isEmpty) {
        throw const ForumRequestException(
            ForumRequestKind.invalidInput, '主题资料与请求不符');
      }
      var metadata = _parser.parseContentThreadMetadata(document,
          classifications: classifications,
          profileTitle: item.title,
          threadId: tid);
      // A moved thread must use its current board's taxonomy, not the profile row.
      if (taxonomy &&
          metadata.boardId != null &&
          metadata.boardId != item.boardId) {
        if (!_boards.containsKey(metadata.boardId!)) budget.take();
        final actual = await _boardFilters(metadata.boardId!, generation);
        _assertScope(generation);
        metadata = _parser.parseContentThreadMetadata(document,
            classifications: actual, profileTitle: item.title, threadId: tid);
      }
      final candidate = _boardMetadata[tid];
      final listed =
          metadata.boardId == null || candidate?.boardId == metadata.boardId
              ? candidate
              : null;
      return UserContentThreadMetadata(
        title: metadata.title,
        boardName: metadata.boardName,
        authorUid: metadata.authorUid,
        boardId: metadata.boardId ?? listed?.boardId,
        classificationId: listed?.classificationKnown == true
            ? listed?.classificationId
            : metadata.classificationId,
        classificationKnown: metadata.classificationKnown ||
            (listed?.classificationKnown ?? false),
        digest: listed?.digest,
        poll: metadata.poll ?? listed?.poll,
        sale: metadata.sale ?? listed?.sale,
      );
    })()
        .catchError((Object error, StackTrace stack) {
      if (identical(_metadata[tid], pending)) _metadata.remove(tid);
      Error.throwWithStackTrace(error, stack);
    });
    _putBounded(_metadata, tid, pending, 256);
    return pending;
  }

  void _requireShape(dom.Document document, String selector, String message) {
    if (document.querySelector(selector) != null) return;
    final text = '${document.querySelector('title')?.text ?? ''}\n'
        '${document.body?.text ?? ''}';
    if (forumTextIsRateLimited(text)) {
      throw const ForumRequestException(ForumRequestKind.rateLimited, '请求过于频繁');
    }
    if (forumTextNeedsLogin(text) ||
        document.querySelector('form[action*="login.php"]') != null) {
      throw const ForumRequestException(ForumRequestKind.loginRequired, '需要登录');
    }
    if (forumTextIsForbidden(text)) {
      throw const ForumRequestException(ForumRequestKind.forbidden, '没有权限');
    }
    throw ForumRequestException(ForumRequestKind.invalidInput, message);
  }

  String _rowIdentity(UserListItem item, UserProfileTab tab) {
    if (tab == UserProfileTab.posts && item.postId != null) {
      return 'pid:${item.postId}';
    }
    final tid = item.threadId ?? urls.tidFromUrl(item.url);
    if (tab != UserProfileTab.posts && tid != null) return 'tid:$tid';
    return item.url;
  }

  void _putBounded<T>(Map<String, T> cache, String key, T value, int limit) {
    cache[key] = value;
    if (cache.length > limit) cache.remove(cache.keys.first);
  }
}

class _QueryState {
  final rows = <UserListItem>[];
  final seen = <String>{};
  final boards = <String, ForumCategory>{};
  int page = 0;
  int totalPages = 1;
  Future<UserContentResult>? pending;
}

class _TypeLookup {
  final tids = <String>{};
  int page = 0;
  int totalPages = 1;
  Future<void>? pending;
  bool unavailable = false;
  String? fingerprint;
  bool get hasMore => page < totalPages;
}

class _ReadBudget {
  _ReadBudget(this.remaining);
  int remaining;
  final lookupKeys = <String>{};
  void take() {
    if (remaining <= 0) throw const _BudgetExhausted();
    remaining--;
  }
}

class _BudgetExhausted implements Exception {
  const _BudgetExhausted();
}
