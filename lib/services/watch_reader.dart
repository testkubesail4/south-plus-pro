import 'package:html/dom.dart' as dom;

import '../models/forum_models.dart';
import '../models/watch_models.dart';
import 'forum_url_resolver.dart';
import 'keyword_match.dart';
import 'parsers/board_thread_page_parser.dart';
import 'parsers/thread_detail_parser.dart';
import 'parsers/user_profile_parser.dart';

class WatchIncomplete implements Exception {
  const WatchIncomplete(this.reason);
  final String reason;
}

class WatchStep {
  const WatchStep({this.event, this.done = false, this.baseline = false});
  final WatchEvent? event;
  final bool done;
  final bool baseline;
}

/// One resumable source step. State is committed only after a successful step.
class WatchReader {
  WatchReader({
    required this.urls,
    required this.getDocument,
    required this.now,
  });
  final ForumUrlResolver urls;
  final Future<dom.Document> Function(String path) getDocument;
  final DateTime Function() now;

  ThreadDetailParser get _threads => ThreadDetailParser(urls: urls);

  Future<({List<ThreadReply> posts, int pages, String? title})> _thread(
    String tid,
    int page,
  ) async {
    final doc = await getDocument('read.php?tid-$tid-page-$page.html');
    if (urls.tidFromUrl(_threads.threadUrl(doc) ?? '') != tid) {
      throw const WatchIncomplete('帖子身份无法确认，保留进度稍后重试');
    }
    final posts = _threads.desktopThreadCards(doc);
    final pagination = _threads.desktopPagination(
      doc,
      requestedPage: page,
      threadUrl: 'read.php?tid-$tid.html',
    );
    if (posts.isEmpty || pagination.currentPage != page) {
      throw const WatchIncomplete('帖子或指定页不可见，保留进度稍后重试');
    }
    return (
      posts: posts,
      pages: pagination.totalPages,
      title: _threads.threadTitle(doc),
    );
  }

  Map<String, dynamic> _postRow(
    String tid,
    int page,
    ThreadReply p,
    String title,
  ) =>
      {
        'id': p.postId, 'tid': tid, 'pid': p.postId, 'page': page,
        'title': title, 'truncated': false,
        'authorUid': urls.uidFromUrl(p.authorUrl ?? ''),
        // replyTitle is the outgoing action label, never a parent relationship.
        'url':
            urls.absoluteUrl('read.php?tid-$tid-page-$page.html#${p.postId}'),
      };

  Future<WatchStep> step(
    WatchRule rule,
    WatchContentKind kind,
    Map<String, dynamic> state,
  ) async {
    if (rule.scope == WatchScope.thread) return _threadStep(rule, state);
    return _listStep(rule, kind, state);
  }

  Future<WatchStep> _threadStep(
    WatchRule rule,
    Map<String, dynamic> state,
  ) async {
    final tid = rule.subjectId;
    final baseline = state['initialized'] != true;
    final high = state['high'] as int? ?? 0;
    if (state['queue'] case final List queue when queue.isNotEmpty) {
      final row = Map<String, dynamic>.from(queue.first as Map);
      queue[0] = row;
      final event =
          baseline ? null : await _match(rule, WatchContentKind.replies, row);
      queue.removeAt(0);
      final id = int.parse(row['id'] as String);
      if (id > (state['nextHigh'] as int? ?? high)) state['nextHigh'] = id;
      return WatchStep(event: event, baseline: baseline);
    }
    // Baseline every visible page once. Later walk backwards to an observed old
    // PID boundary, keeping the old watermark until all new candidates resolve.
    final first = await _thread(tid, 1);
    final tail =
        baseline || first.pages == 1 ? first : await _thread(tid, first.pages);
    if (state.remove('end') == true) {
      state['high'] = state.remove('nextHigh') ?? high;
      state['initialized'] = true;
      state.remove('page');
      state.remove('head');
      return WatchStep(done: true, baseline: baseline);
    }
    final requested = state['page'] as int? ?? (baseline ? 1 : first.pages);
    final page =
        requested > first.pages ? (baseline ? 1 : first.pages) : requested;
    final result = page == 1
        ? first
        : page == first.pages && !baseline
            ? tail
            : await _thread(tid, page);
    final rows = result.posts
        .where((p) => (int.tryParse(p.postId ?? '') ?? 0) > high)
        .map(
          (p) =>
              _postRow(tid, page, p, result.title ?? first.title ?? rule.label),
        )
        .toList();
    rows.sort(
      (a, b) =>
          int.parse(a['id'] as String).compareTo(int.parse(b['id'] as String)),
    );
    if (baseline) {
      final next = rows
          .map((r) => int.parse(r['id'] as String))
          .fold<int>(high, (a, b) => a > b ? a : b);
      state['nextHigh'] =
          next > (state['nextHigh'] as int? ?? high) ? next : state['nextHigh'];
      state['queue'] = <Map<String, dynamic>>[];
    } else {
      state['queue'] = rows;
    }
    final boundary = result.posts.any(
      (p) =>
          (int.tryParse(p.postId ?? '') ?? 0) > 0 &&
          int.parse(p.postId!) <= high,
    );
    if (baseline ? page < result.pages : page > 1 && !boundary) {
      state['page'] = baseline ? page + 1 : page - 1;
    } else {
      state['end'] = true;
    }
    return WatchStep(baseline: baseline);
  }

  Future<({List<Map<String, dynamic>> rows, int pages})> _listPage(
    WatchRule rule,
    WatchContentKind kind,
    int page,
  ) async {
    if (rule.scope == WatchScope.board) {
      final category = ForumCategory(
        name: rule.label,
        slug: 'fid-${rule.subjectId}',
      );
      final path = urls.boardDesktopPath(
        category,
        page: page,
        order: ForumThreadOrder.postedAt,
      )!;
      final doc = await getDocument(path);
      if (doc.querySelector('ul.stream') == null) {
        throw const WatchIncomplete('版块列表不可识别，保留进度稍后重试');
      }
      final parser = BoardThreadPageParser(urls: urls);
      final rows = parser
          .parseWallThreads(doc, category)
          .where((t) => !t.isSticky)
          .map(
            (t) => <String, dynamic>{
              'id': urls.tidFromUrl(t.url),
              'tid': urls.tidFromUrl(t.url),
              'title': t.title,
              'url': t.url,
              'authorUid': urls.uidFromUrl(t.authorUrl ?? ''),
              'truncated': t.title.endsWith('..'),
            },
          )
          .toList();
      final pagination = parser.wallPages(doc);
      if (pagination == null || pagination.current != page || rows.isEmpty) {
        throw const WatchIncomplete('版块分页或非置顶主题不可确认，保留进度');
      }
      return (rows: rows, pages: pagination.total);
    }
    final action = switch (kind) {
      WatchContentKind.topics => 'topic',
      WatchContentKind.replies => 'post',
      WatchContentKind.favorites => 'favor',
    };
    final doc = await getDocument(
      'u.php?action-$action-uid-${rule.subjectId}-page-$page.html',
    );
    final tab = switch (kind) {
      WatchContentKind.topics => UserProfileTab.topics,
      WatchContentKind.replies => UserProfileTab.posts,
      WatchContentKind.favorites => UserProfileTab.favorites,
    };
    final parsed = UserProfileParser(
      urls: urls,
    ).parseContentPage(doc, uid: rule.subjectId, tab: tab, page: page);
    if (!parsed.paginationKnown || parsed.items.isEmpty) {
      throw WatchIncomplete(
        kind == WatchContentKind.favorites
            ? '收藏列表为空或不可见，不能确认是否有新可见收藏'
            : '文章列表为空或分页无法确认，保留进度稍后重试',
      );
    }
    final rows = parsed.items
        .map(
          (item) => <String, dynamic>{
            'id':
                kind == WatchContentKind.replies ? item.postId : item.threadId,
            'tid': item.threadId,
            'pid': item.postId,
            'title': item.title,
            'url': item.url,
            'truncated': item.titleTruncated,
            'authorUid': rule.subjectId,
          },
        )
        .toList();
    if (rows.any(
      (r) =>
          !RegExp(r'^[1-9]\d*$').hasMatch(r['id'] as String? ?? '') ||
          r['tid'] == null,
    )) {
      throw const WatchIncomplete('列表缺少原生帖子身份，保留进度稍后重试');
    }
    return (rows: rows, pages: parsed.totalPages);
  }

  Future<WatchStep> _listStep(
    WatchRule rule,
    WatchContentKind kind,
    Map<String, dynamic> state,
  ) async {
    final favorites = kind == WatchContentKind.favorites;
    final baseline = state['initialized'] != true;
    if (state['queue'] case final List queue when queue.isNotEmpty) {
      final row = Map<String, dynamic>.from(queue.first as Map);
      queue[0] = row;
      WatchEvent? event;
      if (favorites) {
        final inventory =
            (state['inventory'] as List? ?? const []).cast<String>();
        if (!baseline && !inventory.contains(row['id']))
          event = await _match(rule, kind, row);
      } else if (rule.scope == WatchScope.user) {
        final known = (state['inventory'] ??= <String>[]) as List;
        if (!baseline && !known.contains(row['id']))
          event = await _match(rule, kind, row);
        if (!known.contains(row['id'])) known.add(row['id']);
      } else if (!baseline &&
          int.parse(row['id'] as String) > (state['high'] as int? ?? 0)) {
        event = await _match(rule, kind, row);
      }
      queue.removeAt(0);
      return WatchStep(event: event, baseline: baseline);
    }
    final first = await _listPage(rule, kind, 1);
    if (state['end'] == true) {
      if (favorites) {
        state['inventory'] = state.remove('observed');
      } else {
        state['high'] = state.remove('nextHigh');
      }
      state['initialized'] = true;
      state.remove('end');
      state.remove('page');
      state.remove('head');
      return WatchStep(done: true, baseline: baseline);
    }
    final requested = state['page'] as int? ?? 1;
    final page = requested > first.pages ? 1 : requested;
    final result = page == 1 ? first : await _listPage(rule, kind, page);
    final high = result.rows
        .map((r) => int.parse(r['id'] as String))
        .fold<int>(0, (a, b) => a > b ? a : b);
    if (baseline && rule.scope == WatchScope.board) {
      state.addAll({'high': high, 'initialized': true});
      return const WatchStep(done: true, baseline: true);
    }
    final nextHigh = state['nextHigh'] as int? ?? state['high'] as int? ?? 0;
    state['nextHigh'] = high > nextHigh ? high : nextHigh;
    if (page == 1 && favorites) state['observed'] = <String>[];
    if (favorites)
      (state['observed'] as List).addAll(
        result.rows.map<String>((r) => r['id'] as String),
      );
    final known =
        ((state['inventory'] ??= <String>[]) as List).cast<String>().toSet();
    if (baseline) {
      if (!favorites)
        (state['inventory'] as List).addAll(
          result.rows
              .map<String>((r) => r['id'] as String)
              .where((id) => known.add(id)),
        );
      state['queue'] = <Map<String, dynamic>>[];
    } else {
      state['queue'] = result.rows
          .where(
            (r) => rule.scope == WatchScope.user
                ? !known.contains(r['id'])
                : int.parse(r['id'] as String) > (state['high'] as int),
          )
          .toList();
    }
    // Only the explicitly POSTDATE-ordered board source has a safe older boundary.
    final reachedOld = rule.scope == WatchScope.board &&
        result.rows.any(
          (r) => int.parse(r['id'] as String) <= (state['high'] as int),
        );
    if (page < result.pages && !reachedOld) {
      state['page'] = page + 1;
    } else {
      state['end'] = true;
    }
    return WatchStep(baseline: baseline);
  }

  Future<WatchEvent?> _match(
    WatchRule rule,
    WatchContentKind kind,
    Map<String, dynamic> row,
  ) async {
    final tid = row['tid'] as String;
    String? author = row['authorUid'] as String?;
    String title = row['title'] as String;
    String? body = row['body'] as String?;
    String? quote = row['quote'] as String?;
    String url = row['url'] as String;
    final needsPost = kind == WatchContentKind.replies && body == null;
    final needsOpening = rule.keyword.trim().isNotEmpty &&
        (rule.keywordField == WatchKeywordField.body ||
            row['truncated'] == true);
    if (needsPost || (needsOpening && body == null)) {
      if (needsPost) {
        // The redirect identifies the page; only the exact native PID is evidence.
        var doc = await getDocument(urls.relativePath(url));
        var post = _threads
            .desktopThreadCards(doc)
            .where((p) => p.postId == row['pid'])
            .firstOrNull;
        if (post == null && rule.scope == WatchScope.thread) {
          doc = await getDocument(
            'job.php?action-topost-tid-$tid-pid-${row['pid']}.html',
          );
          post = _threads
              .desktopThreadCards(doc)
              .where((p) => p.postId == row['pid'])
              .firstOrNull;
        }
        if (urls.tidFromUrl(_threads.threadUrl(doc) ?? '') != tid ||
            post == null ||
            (rule.scope == WatchScope.user &&
                urls.uidFromUrl(post.authorUrl ?? '') != rule.subjectId)) {
          throw const WatchIncomplete('指定回复或作者无法确认，保留此回复稍后重试');
        }
        body = post.content;
        quote = post.quote;
        author = urls.uidFromUrl(post.authorUrl ?? '');
        final page = _threads
            .desktopPagination(doc, threadUrl: 'read.php?tid-$tid.html')
            .currentPage;
        url = urls.absoluteUrl(
          'read.php?tid-$tid-page-$page.html#${post.postId}',
        );
        if (row['truncated'] == true &&
            rule.keywordField == WatchKeywordField.title) {
          title = _threads.threadTitle(doc) ??
              (throw const WatchIncomplete('主题标题无法确认'));
        }
      } else {
        final doc = await getDocument('read.php?tid-$tid.html');
        if (urls.tidFromUrl(_threads.threadUrl(doc) ?? '') != tid)
          throw const WatchIncomplete('主题身份无法确认');
        final opening = _threads
            .desktopThreadCards(doc)
            .where((p) => p.postId == 'tpc')
            .firstOrNull;
        if (opening == null) throw const WatchIncomplete('主题正文不可见，保留进度');
        body = opening.content;
        title = _threads.threadTitle(doc) ??
            (throw const WatchIncomplete('主题标题无法确认'));
        if (kind != WatchContentKind.favorites)
          author = urls.uidFromUrl(opening.authorUrl ?? '');
      }
    }
    if (rule.keyword.trim().isNotEmpty) {
      final field = rule.keywordField == WatchKeywordField.title ? title : body;
      if (field == null) throw const WatchIncomplete('匹配字段不可见，保留进度');
      if (matchKeyword(rule.keyword, [field]) != true) return null;
    }
    var confidence = WatchConfidence.certain;
    var reason = kind == WatchContentKind.favorites
        ? '与完整可见快照相比新增；不代表收藏操作时间，移除后再加入可能无法识别'
        : '按原生帖子身份确认';
    if (rule.involvingUid != null) {
      final floors = RegExp(r'(?:引用第|回\s*)(\d+)\s*楼')
          .allMatches(body ?? quote ?? '')
          .map((m) => int.parse(m.group(1)!))
          .toSet()
          .toList();
      if (floors.isEmpty) return null;
      final signature = floors.join(',');
      if (row['lookupFloors'] != signature) {
        row['lookupFloors'] = signature;
        row['lookupIndex'] = 0;
        row['lookupPage'] = 1;
        row['lookupUnknown'] = false;
      }
      int? matchedFloor;
      for (var index = row['lookupIndex'] as int? ?? 0;
          index < floors.length;
          index++) {
        final floor = floors[index];
        row['lookupIndex'] = index;
        ThreadReply? target;
        var page = row['lookupPage'] as int? ?? 1;
        while (target == null) {
          final result = await _thread(tid, page);
          target = result.posts
              .where(
                (p) => floor == 0
                    ? p.postId == 'tpc'
                    : int.tryParse(
                          RegExp(
                                r'\d+',
                              ).firstMatch(p.floor ?? '')?.group(0) ??
                              '',
                        ) ==
                        floor,
              )
              .firstOrNull;
          if (target != null || page >= result.pages) break;
          row['lookupPage'] = ++page;
        }
        final targetUid =
            target == null ? null : urls.uidFromUrl(target.authorUrl ?? '');
        if (targetUid == rule.involvingUid) {
          matchedFloor = floor;
          break;
        }
        if (targetUid == null) row['lookupUnknown'] = true;
        row['lookupPage'] = 1;
        row['lookupIndex'] = index + 1;
      }
      if (matchedFloor == null) {
        if (row['lookupUnknown'] == true) {
          row['lookupIndex'] = 0;
          row['lookupPage'] = 1;
          row['lookupUnknown'] = false;
          throw const WatchIncomplete('引用目标楼层或作者不可见，保留此回复');
        }
        return null;
      }
      confidence = WatchConfidence.probable;
      reason =
          '引用文字指向 $matchedFloor 楼，作者 UID ${rule.involvingUid} 已核实；文字可被伪造，仅供参考';
    }
    final id = '${rule.id}/${kind.name}/${row['id']}';
    return WatchEvent(
      id: id,
      ruleId: rule.id,
      title: title,
      url: url,
      kind: kind,
      confidence: confidence,
      reason: reason,
      detectedAt: now(),
      authorUid: author,
    );
  }
}
