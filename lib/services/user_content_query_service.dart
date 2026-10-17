import 'package:html/dom.dart' as dom;

import '../models/forum_models.dart';
import '../models/user_content_query.dart';
import 'forum_request_exception.dart';
import 'forum_url_resolver.dart';
import 'parsers/user_profile_parser.dart';

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

  Future<UserContentResult> fetch(UserContentQuery query,
      {bool refresh = false}) {
    _validateId(query.uid);
    if (query.boardId != null) _validateId(query.boardId!);
    if (query.classificationId != null) {
      _validateId(query.classificationId!);
      if (query.boardId == null) {
        throw ArgumentError('A classification requires a board');
      }
    }
    if (query.tab != UserProfileTab.topics &&
        query.tab != UserProfileTab.posts) {
      throw ArgumentError('Only topics and replies support content queries');
    }
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
    final budget = _ReadBudget(8);
    if (query.classificationId != null) {
      if (!_boards.containsKey(query.boardId!)) budget.remaining--;
      final filters = await _boardFilters(query.boardId!, generation);
      _assertScope(generation);
      if (!filters.any((item) => item.id == query.classificationId)) {
        throw ArgumentError('Classification is not offered by this board');
      }
    }
    if (state.cursor >= state.rows.length && state.page < state.totalPages) {
      final page = state.page + 1;
      final nativeType = query.tab == UserProfileTab.topics
          ? query.articleType
          : UserContentArticleType.all;
      final key = '${query.uid}/${query.tab.name}/${nativeType.name}/$page';
      final parsed = await _page(query, nativeType, page, key, generation);
      _assertScope(generation);
      state.page = page;
      state.totalPages = parsed.totalPages;
      for (final item in parsed.items) {
        final identity = _rowIdentity(item, query.tab);
        if (state.seen.add(identity)) state.rows.add(item);
        if (item.boardId != null) {
          state.boards[item.boardId!] = ForumCategory(
            name: item.section ?? '版块 ${item.boardId}',
            slug: 'f${item.boardId}',
            url: item.boardUrl,
          );
        }
      }
    }
    final retries = List<UserListItem>.of(state.pendingLookupRows.keys);
    final work = [...retries, ...state.rows.skip(state.cursor)];
    for (var index = 0; index < work.length; index++) {
      final item = work[index];
      final isNew = index >= retries.length;
      if (query.boardId != null &&
          item.boardId != null &&
          item.boardId != query.boardId) {
        state.unresolved.remove(item);
        state.pendingLookupRows.remove(item);
        if (isNew) state.cursor++;
        continue;
      }
      final requiresMetadata = query.classificationId != null ||
          (query.boardId != null && item.boardId == null) ||
          (query.tab == UserProfileTab.posts &&
              query.articleType != UserContentArticleType.all);
      if (!requiresMetadata) {
        state.matches.add(item);
        if (isNew) state.cursor++;
        continue;
      }
      final tid = item.threadId ?? urls.tidFromUrl(item.url);
      if (tid == null) {
        state.unresolved.add(item);
        if (isNew) state.cursor++;
        continue;
      }
      if (!_metadata.containsKey(tid) && budget.remaining <= 0) break;
      UserContentThreadMetadata metadata;
      (bool?, String?) typeResolution;
      try {
        metadata = await _threadMetadata(item, tid, generation, budget);
        _assertScope(generation);
        typeResolution = query.tab == UserProfileTab.topics
            ? (true, null)
            : await _resolveType(
                query, tid, metadata, state, budget, generation);
        _assertScope(generation);
      } on _BudgetExhausted {
        break;
      } on ForumRequestException catch (error) {
        _assertScope(generation);
        if (error.kind == ForumRequestKind.loginRequired ||
            error.kind == ForumRequestKind.rateLimited) rethrow;
        state.unresolved.add(item);
        if (isNew) state.cursor++;
        continue;
      }
      state.checkedTids.add(tid);
      state.pendingLookupRows.remove(item);
      if (typeResolution.$2 != null) {
        state.pendingLookupRows[item] = typeResolution.$2!;
      }
      final boardId = metadata.boardId ?? item.boardId;
      final boardMatch = query.boardId == null
          ? true
          : boardId == null
              ? null
              : query.boardId == boardId;
      final classificationMatch = query.classificationId == null
          ? true
          : metadata.classificationKnown
              ? metadata.classificationId == query.classificationId
              : null;
      final typeMatch = typeResolution.$1;
      if (boardMatch == false ||
          classificationMatch == false ||
          typeMatch == false) {
        state.unresolved.remove(item);
        state.pendingLookupRows.remove(item);
        if (isNew) state.cursor++;
        continue;
      }
      if (boardMatch == null ||
          classificationMatch == null ||
          typeMatch == null) {
        state.unresolved.add(item);
      } else {
        state.unresolved.remove(item);
        state.matches.add(item);
      }
      if (isNew) state.cursor++;
    }
    _assertScope(generation);
    final pendingLookups = state.pendingLookupRows.values.toSet();
    final hasLookupPages = pendingLookups.any((key) =>
        _lookups[key] == null ||
        (!_lookups[key]!.unavailable && _lookups[key]!.hasMore));
    return UserContentResult(
      items: List.unmodifiable(state.rows.where(state.matches.contains)),
      unresolvedItems:
          List.unmodifiable(state.rows.where(state.unresolved.contains)),
      boards: List.unmodifiable(state.boards.values),
      scannedPages: state.page,
      totalPages: state.totalPages,
      checkedThreads: state.checkedTids.length,
      pendingMetadataCount:
          state.rows.length - state.cursor + state.pendingLookupRows.length,
      lookupPagesScanned: state.lookupKeys
          .fold(0, (sum, key) => sum + (_lookups[key]?.page ?? 0)),
      lookupPagesTotal: state.lookupKeys
          .fold(0, (sum, key) => sum + (_lookups[key]?.totalPages ?? 1)),
      hasMore: state.cursor < state.rows.length ||
          state.page < state.totalPages ||
          hasLookupPages,
    );
  }

  Future<(bool?, String?)> _resolveType(
    UserContentQuery query,
    String tid,
    UserContentThreadMetadata metadata,
    _QueryState state,
    _ReadBudget budget,
    int generation,
  ) async {
    final known = metadata.articleType(query.articleType);
    if (known != null || metadata.authorUid == null) return (known, null);
    final key = '${metadata.authorUid}/${query.articleType.name}';
    final lookup = _lookups.putIfAbsent(key, _TypeLookup.new);
    if (_lookups.length > 256) _lookups.remove(_lookups.keys.first);
    state.lookupKeys.add(key);
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
          lookup.page = page;
          lookup.totalPages = parsed.totalPages;
          lookup.tids.addAll(
              parsed.items.map((item) => item.threadId).whereType<String>());
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
            error.kind != ForumRequestKind.server) rethrow;
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
    final action = query.tab == UserProfileTab.topics ? 'topic' : 'post';
    final typePart =
        type == UserContentArticleType.all ? '' : '-type-${type.name}';
    late Future<UserContentPage> pending;
    pending = (() async {
      final document = await getDocument(
          'u.php?action-$action-uid-${query.uid}$typePart-page-$page.html');
      _assertScope(generation);
      _requireShape(document, '#u-contentmain .u-table', '无法识别用户文章列表');
      return _parser.parseContentPage(document,
          uid: query.uid, tab: query.tab, page: page, articleType: type);
    })()
        .catchError((Object error, StackTrace stack) {
      if (identical(_pages[key], pending)) _pages.remove(key);
      Error.throwWithStackTrace(error, stack);
    });
    _putBounded(_pages, key, pending, 24);
    return pending;
  }

  Future<UserContentThreadMetadata> _threadMetadata(
      UserListItem item, String tid, int generation, _ReadBudget budget) {
    final existing = _metadata[tid];
    if (existing != null) return existing;
    final needsBoard =
        item.boardId != null && !_boards.containsKey(item.boardId!);
    // Leave one read available if the thread has moved to another board.
    if (budget.remaining < (needsBoard ? 3 : 2)) {
      throw const _BudgetExhausted();
    }
    budget.take();
    if (needsBoard) budget.take();
    late Future<UserContentThreadMetadata> pending;
    pending = (() async {
      final classifications = item.boardId == null
          ? <UserContentClassification>[]
          : await _boardFilters(item.boardId!, generation);
      _assertScope(generation);
      final document = await getDocument('read.php?tid-$tid.html');
      _assertScope(generation);
      _requireShape(document, '#subject_tpc', '无法识别主题资料');
      var metadata = _parser.parseContentThreadMetadata(document,
          classifications: classifications,
          profileTitle: item.title,
          threadId: tid);
      // A moved thread must use its current board's taxonomy, not the profile row.
      if (metadata.boardId != null && metadata.boardId != item.boardId) {
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
    throw ForumRequestException(ForumRequestKind.server, message);
  }

  String _rowIdentity(UserListItem item, UserProfileTab tab) {
    if (tab == UserProfileTab.posts && item.postId != null) {
      return 'pid:${item.postId}';
    }
    if (tab == UserProfileTab.topics && item.threadId != null) {
      return 'tid:${item.threadId}';
    }
    return item.url;
  }

  void _putBounded<T>(Map<String, T> cache, String key, T value, int limit) {
    cache[key] = value;
    if (cache.length > limit) cache.remove(cache.keys.first);
  }
}

class _QueryState {
  final rows = <UserListItem>[];
  final matches = <UserListItem>{};
  final unresolved = <UserListItem>{};
  final pendingLookupRows = <UserListItem, String>{};
  final lookupKeys = <String>{};
  final seen = <String>{};
  final checkedTids = <String>{};
  final boards = <String, ForumCategory>{};
  int page = 0;
  int totalPages = 1;
  int cursor = 0;
  Future<UserContentResult>? pending;
}

class _TypeLookup {
  final tids = <String>{};
  int page = 0;
  int totalPages = 1;
  Future<void>? pending;
  bool unavailable = false;
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
