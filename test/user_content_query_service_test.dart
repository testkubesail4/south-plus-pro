import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/user_content_query.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/services/user_content_query_service.dart';
import 'package:south_plus_rewrite/services/user_content_sort.dart';

String _row(int tid, {int? pid, String board = '48', String? title}) =>
    '<tr><td><a href="${pid == null ? 'read.php?tid-$tid.html' : 'job.php?action-topost-tid-$tid-pid-$pid.html'}">'
    '${title ?? 'title $tid'}</a><a href="thread.php?fid-$board.html">board $board</a></td></tr>';

String _page(String rows,
        {int pages = 1,
        int page = 1,
        String action = 'post',
        String uid = '7',
        String type = ''}) =>
    '<div id="u-contentmain"><table class="u-table">$rows</table>'
    '${pages == 1 ? '' : '<div class="pages">Pages: $page/$pages<a href="u.php?action-$action-uid-$uid${type.isEmpty ? '' : '-type-$type'}-page-$pages.html">»</a></div>'}'
    '</div>';

int _number(String path) =>
    int.tryParse(
        RegExp(r'(?:^|[?&-])page[-=](\d+)').firstMatch(path)?.group(1) ?? '') ??
    1;
const _board = '<div class="hthread"><div class="threadlist">'
    '<a href="thread.php?fid-48-type-1.html">分类</a></div></div>';
String _thread(
        {bool classified = true,
        int tid = 12,
        String? authorUid,
        String board = '48',
        String? title}) =>
    '<div id="breadcrumbs"><a href="thread.php?fid-$board.html">board $board</a></div>'
    '<h1 id="subject_tpc">${classified ? '[分类]' : ''}${title ?? 'title $tid'}</h1>'
    '<a href="read.php?tid-$tid.html">topic</a>'
    '${authorUid == null ? '' : '<table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-$authorUid.html"><strong>author</strong></a></th><th class="r_one"><div id="read_tpc">body</div></th></tr></table>'}';

class _DocumentClient extends ForumClient {
  _DocumentClient(this.read);
  final Future<dom.Document> Function(String) read;
  int active = 0;
  int peak = 0;
  @override
  Future<String> get(String path) async => (await read(path)).outerHtml;
  @override
  Future<String> getOnce(String path) => get(path);
  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy =
          ForumReadRedirectPolicy.none}) async {
    requireCurrentSession();
    active++;
    if (active > peak) peak = active;
    try {
      final result = await read(path);
      requireCurrentSession();
      return result.outerHtml;
    } finally {
      active--;
    }
  }
}

class _RealHttp extends HttpOverrides {}

class _LocalClient extends ForumClient {
  _LocalClient(this.baseUri, HttpClient transport)
      : super(httpClient: transport, delay: (_) async {});
  @override
  final Uri baseUri;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> paths;
  late int epoch;
  late Future<dom.Document> Function(String) respond;
  late UserContentQueryService service;
  late _DocumentClient client;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    paths = [];
    epoch = 0;
    respond = (path) async => html.parse(_page(''));
    Future<dom.Document> read(String path) {
      paths.add(path);
      return respond(path);
    }

    service = UserContentQueryService(
      urls: ForumUrlResolver(baseUri: Uri.parse('https://south-plus.net/')),
      sessionEpoch: () => epoch,
      getDocument: read,
    );
    client = _DocumentClient(read);
    addTearDown(() => client.close(force: true));
  });
  FullScan<UserListItem> scan(UserContentQuery query,
      {List<UserListItem>? loaded, int? loadedPages, int? totalPages}) {
    final owner = epoch;
    final job = service.scan(query,
        client: client,
        isCurrentSession: () => owner == epoch,
        loaded: loaded,
        loadedPages: loadedPages,
        totalPages: totalPages);
    addTearDown(job.dispose);
    return job;
  }

  test(
      'loaded requests advance one page and dedup overlapping PIDs without metadata',
      () async {
    respond = (path) async {
      final n = _number(path);
      return html.parse(_page(
          n == 1
              ? _row(12, pid: 101) + _row(12, pid: 102)
              : _row(12, pid: 102) + _row(13, pid: 103),
          pages: 60,
          page: n));
    };
    const query = UserContentQuery(uid: '7', tab: UserProfileTab.posts);
    final first = await service.fetch(query);
    expect(first.items.map((item) => item.postId), ['101', '102']);
    expect(first.items.every((item) => item.sourcePage == 1), isTrue);
    expect(first.totalPages, 60);
    final second = await service.fetch(query);
    expect(second.items.map((item) => item.postId), ['101', '102', '103']);
    expect(second.items.last.sourcePage, 2);
    expect(paths, hasLength(2));
    expect(paths.every((path) => path.startsWith('u.php')), isTrue);
  });

  test(
      'loaded board filters stay local and unknown classification is not a negative',
      () async {
    respond = (_) async =>
        html.parse(_page(_row(12) + _row(13, board: '9'), action: 'topic'));
    final plain = await service.fetch(const UserContentQuery(
        uid: '7', tab: UserProfileTab.topics, boardId: '48'));
    expect(plain.items.map((item) => item.threadId), ['12']);
    expect(plain.boards.map((board) => board.name), ['board 48', 'board 9']);
    final filtered = await service.fetch(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.topics,
        boardId: '48',
        classificationId: '1'));
    expect(filtered.items, isEmpty);
    expect(filtered.unresolvedItems.single.threadId, '12');
    expect(filtered.checkedThreads, 0);
    expect(filtered.pendingMetadataCount, 0);
    expect(filtered.hasMore, isFalse);
    expect(filtered.isComplete, isFalse);
    expect(paths, hasLength(1),
        reason: 'no implicit board/thread metadata reads');
  });

  test(
      'native article type is sent only for topics; loaded replies remain unresolved',
      () async {
    respond = (path) async => html.parse(_page(_row(12, pid: 101),
        action: path.contains('action-topic') ? 'topic' : 'post'));
    await service.fetch(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.topics,
        articleType: UserContentArticleType.sale));
    expect(paths.single, contains('type-sale'));
    final result = await service.fetch(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale));
    expect(paths.last, isNot(contains('type-')));
    expect(result.items, isEmpty);
    expect(result.unresolvedItems, hasLength(1));
    expect(paths, hasLength(2));
  });

  test('loaded in-flight content is rejected after session changes', () async {
    final gate = Completer<dom.Document>();
    respond = (_) => gate.future;
    const query = UserContentQuery(uid: '7', tab: UserProfileTab.posts);
    final pending = service.fetch(query);
    final rejected = expectLater(
        pending,
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    epoch++;
    gate.complete(html.parse(_page(_row(12, pid: 101))));
    await rejected;
    respond = (_) async => html.parse(_page(_row(13, pid: 102)));
    expect((await service.fetch(query)).items.single.threadId, '13');
    expect(paths, hasLength(2));
  });

  testWidgets(
      'full title search seeds loaded rows, finds page two and never searches reply body',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('read.php'))
        return html.parse(
            _thread(tid: 13, title: 'needle completed', authorUid: '88')
                .replaceFirst('>body</div>', '>reply-only-body-canary</div>'));
      final n = _number(path);
      return html.parse(_page(
          n == 1
              ? _row(12, pid: 101, title: 'needle loaded') +
                  _row(13, pid: 102, title: 'cut..')
              : _row(12, pid: 101, title: 'needle loaded') +
                  _row(14, pid: 103, title: 'needle second'),
          pages: 2,
          page: n));
    };
    const base = UserContentQuery(uid: '7', tab: UserProfileTab.posts);
    await service.fetch(base);
    const query = UserContentQuery(
        uid: '7', tab: UserProfileTab.posts, keyword: 'needle');
    expect(query.cacheKey, isNot(base.cacheKey));
    final job = scan(query);
    expect(job.hits.single.postId, '101');
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((item) => item.postId), ['101', '102', '103']);
    expect(job.hits.map((item) => item.sourcePage), [1, 1, 2]);
    expect(job.hits[1].titleTruncated, isFalse);
    expect(paths, [
      'u.php?action-post-uid-7-page-1.html',
      'read.php?tid-13.html',
      'u.php?action-post-uid-7-page-2.html'
    ]);
    final bodyQuery = scan(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        keyword: 'reply-only-body-canary'));
    bodyQuery.start();
    await tester.pump();
    expect(bodyQuery.progress.state, ScanState.done);
    expect(bodyQuery.hits, isEmpty,
        reason: 'only the participating thread title is searchable');
    expect(bodyQuery.unresolved, isEmpty);
    expect(client.peak, 1);
  });

  for (final tab in [UserProfileTab.topics, UserProfileTab.posts]) {
    testWidgets('empty-keyword $tab sort scans list pages only and stays partial until done',
        (tester) async {
      final gate = Completer<dom.Document>();
      final action = tab == UserProfileTab.topics ? 'topic' : 'post';
      String row(int id, String title, String date, int? views) =>
          _row(12, pid: tab == UserProfileTab.posts ? id : null, title: title)
              .replaceFirst('</td>', ' [$date] ${views == null ? '' : '浏览:$views 回复:$views'}</td>')
              .replaceFirst('tid-12.html', 'tid-$id.html');
      respond = (path) async {
        if (!path.startsWith('u.php')) fail('sorting must not enrich from $path');
        if (_number(path) == 2) return gate.future;
        return html.parse(_page(
            row(101, 'unknown..', '2024-02-29', null) +
            row(102, 'zero', '2024-01-01', 0), pages: 2, action: action));
      };
      final repository = ForumRepository(client: client);
      final query = UserContentQuery(uid: '7', tab: tab);
      final loaded = await repository.fetchUserContent(query);
      expect(loaded.hasMore, isTrue);
      expect(loaded.isComplete, isFalse);
      final sort = UserContentSort(tab == UserProfileTab.topics
          ? UserContentSortKey.views : UserContentSortKey.time);
      final local = sortUserContent(loaded.items, sort);
      expect(local.map((row) => tab == UserProfileTab.posts ? row.postId : row.threadId),
          tab == UserProfileTab.topics ? ['102', '101'] : ['101', '102']);
      expect(paths, hasLength(1), reason: 'loaded sorting adds no requests');
      final job = repository.scanUserContent(query, loaded: loaded.items,
          loadedPages: loaded.scannedPages, totalPages: loaded.totalPages);
      addTearDown(job.dispose);
      expect(job.hits, hasLength(2), reason: 'truncated title is valid without a keyword');
      expect(job.progress.pending, 0);
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.running);
      expect(job.progress.scannedPages, 1);
      expect(job.hits, hasLength(2), reason: 'in-flight order is only partial');
      gate.complete(html.parse(_page(row(103, 'maximum..', '2025-01-01', 90),
          pages: 2, page: 2, action: action)));
      await tester.pump();
      expect(job.progress.state, ScanState.done);
      expect(job.progress.scannedPages, 2);
      expect(job.unresolved, isEmpty);
      final all = sortUserContent(job.hits, sort);
      expect(tab == UserProfileTab.posts ? all.first.postId : all.first.threadId, '103');
      expect(paths, ['u.php?action-$action-uid-7-page-1.html',
        'u.php?action-$action-uid-7-page-2.html']);
    });
  }

  testWidgets(
      'classification metadata is explicit and shared by TID while preserving distinct replies',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php')) {
        final tid = int.parse(RegExp(r'tid-(\d+)').firstMatch(path)!.group(1)!);
        return html.parse(_thread(tid: tid));
      }
      return html.parse(_page(_row(1, pid: 100) +
          _row(1, pid: 101) +
          [for (var tid = 2; tid <= 12; tid++) _row(tid, pid: 100 + tid)]
              .join()));
    };
    const query = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        boardId: '48',
        classificationId: '1');
    final loaded = await service.fetch(query);
    expect(paths, hasLength(1));
    expect(loaded.unresolvedItems, hasLength(13));
    final job = scan(query,
        loaded: [...loaded.items, ...loaded.unresolvedItems],
        loadedPages: loaded.scannedPages,
        totalPages: loaded.totalPages);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits, hasLength(13));
    expect(job.hits.take(2).map((item) => item.postId), ['100', '101']);
    expect(paths.where((path) => path == 'read.php?tid-1.html'), hasLength(1));
    expect(paths.where((path) => path.startsWith('thread.php')), hasLength(1));
    expect(paths.where((path) => path.startsWith('u.php')), hasLength(1));
  });

  testWidgets(
      'server failures in type lookup use shared retry without losing metadata',
      (tester) async {
    var attempts = 0;
    respond = (path) async {
      if (path.startsWith('read.php'))
        return html.parse(_thread(authorUid: '88'));
      if (path.contains('uid-88')) {
        if (++attempts == 1) {
          throw const ForumRequestException(
              ForumRequestKind.server, 'HTTP 500');
        }
        return html
            .parse(_page(_row(12), action: 'topic', uid: '88', type: 'sale'));
      }
      return html.parse(_page(_row(12, pid: 101)));
    };
    final job = scan(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale));
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.waiting);
    expect(job.progress.failure, ForumRequestKind.server);
    expect(attempts, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(job.progress.state, ScanState.done);
    expect(job.hits.single.postId, '101');
    expect(job.unresolved, isEmpty);
    expect(attempts, 2);
    expect(paths.where((path) => path.startsWith('read.php')), hasLength(1));
  });

  testWidgets(
      'reply type proof advances the native author list and keeps repeated replies',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('read.php'))
        return html.parse(_thread(authorUid: '88'));
      if (path.contains('uid-88')) {
        final n = _number(path);
        return html.parse(_page(n == 1 ? _row(999) : _row(12),
            pages: 2, page: n, action: 'topic', uid: '88', type: 'sale'));
      }
      return html.parse(_page(_row(12, pid: 101) + _row(12, pid: 102)));
    };
    final job = scan(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale));
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((item) => item.postId), ['101', '102']);
    expect(paths.where((path) => path.contains('uid-88')), hasLength(2));
    expect(paths.where((path) => path.startsWith('read.php')), hasLength(1));
    expect(paths.where((path) => path.startsWith('thread.php')), isEmpty);
  });

  testWidgets(
      'only valid native type exhaustion is negative; malformed or repeated pages remain unresolved',
      (tester) async {
    for (final mode in [
      'negative',
      'missing-root',
      'repeat',
      'wrong-type-hit',
      'wrong-type-empty',
      'wrong-uid',
      'wrong-tab'
    ]) {
      paths.clear();
      respond = (path) async {
        if (path.startsWith('read.php'))
          return html.parse(_thread(authorUid: '88'));
        if (path.contains('uid-88')) {
          if (mode == 'missing-root')
            return html.parse('<table class="u-table"></table>');
          if (mode.startsWith('wrong-')) {
            final href = switch (mode) {
              'wrong-type-hit' =>
                'u.php?action-topic-uid-88-type-poll-page-1.html',
              'wrong-type-empty' =>
                'u.php?action=topic&amp;uid=88&amp;type=poll&amp;page=1',
              'wrong-uid' => 'u.php?action-topic-uid-99-type-sale-page-1.html',
              _ => 'u.php?action-post-uid-88-type-sale-page-1.html',
            };
            final rows = mode == 'wrong-type-empty' ? '' : _row(12);
            return html.parse(
                '<div id="u-contentmain"><table class="u-table">$rows</table>'
                '<div class="pages">Pages: 1/1<a href="$href">last</a></div></div>');
          }
          final n = _number(path);
          return html.parse(_page(mode == 'repeat' ? _row(999) : '',
              pages: mode == 'repeat' ? 2 : 1,
              page: n,
              action: 'topic',
              uid: '88',
              type: 'sale'));
        }
        return html.parse(_page(_row(12, pid: 101)));
      };
      final job = scan(const UserContentQuery(
          uid: '7',
          tab: UserProfileTab.posts,
          articleType: UserContentArticleType.sale));
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.done, reason: mode);
      expect(job.hits, isEmpty);
      expect(job.unresolved.length, mode == 'negative' ? 0 : 1);
    }
  });

  testWidgets(
      'native board category evidence overrides a spoofable header prefix',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('thread.php'))
        return html.parse('$_board'
            '<table id="ajaxtable"><tr class="tr3"><td><h3>'
            '<a href="read.php?tid-12.html">[分类]title 12</a></h3></td></tr></table>');
      if (path.startsWith('read.php')) return html.parse(_thread());
      return html.parse(_page(_row(12, pid: 101)));
    };
    final job = scan(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        boardId: '48',
        classificationId: '1'));
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits, isEmpty);
    expect(job.unresolved, isEmpty);
  });

  testWidgets('permanent unknowns do not starve later list pages',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php')) {
        final tid = int.parse(RegExp(r'tid-(\d+)').firstMatch(path)!.group(1)!);
        return html.parse(_thread(tid: tid));
      }
      final n = _number(path);
      return html.parse(_page(
          n == 4
              ? _row(99)
              : [
                  for (var offset = 1; offset <= 5; offset++)
                    _row((n - 1) * 5 + offset,
                        title: '[分类]title ${(n - 1) * 5 + offset}')
                ].join(),
          pages: 4,
          page: n,
          action: 'topic'));
    };
    final job = scan(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.topics,
        boardId: '48',
        classificationId: '1'));
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.progress.scannedPages, 4);
    expect(job.unresolved, hasLength(15));
    expect(job.hits.single.threadId, '99');
    expect(paths.where((path) => path.startsWith('read.php')), hasLength(16));
  });

  testWidgets(
      'complete nonmatching titles perform no metadata reads, including favorites',
      (tester) async {
    respond = (path) async =>
        html.parse(_page(_row(12, title: 'unrelated'), action: 'favor'));
    const query = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.favorites,
        boardId: '48',
        classificationId: '1',
        keyword: 'needle');
    final loaded = await service.fetch(query);
    expect(loaded.unresolvedItems, hasLength(1));
    final job = scan(query,
        loaded: loaded.unresolvedItems, loadedPages: 1, totalPages: 1);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits, isEmpty);
    expect(job.unresolved, isEmpty);
    expect(paths, hasLength(1));
    expect(paths.single, contains('action-favor'));
  });

  testWidgets(
      'empty, unconfirmed and repeated range pages never claim complete',
      (tester) async {
    for (final mode in ['empty', 'no-pager', 'repeat']) {
      paths.clear();
      respond = (path) async {
        final n = _number(path);
        return html.parse(_page(
            n == 1 || mode == 'repeat' ? _row(12, pid: 101) : '',
            pages: mode == 'no-pager' && n > 1 ? 1 : 3,
            page: n));
      };
      final job =
          scan(const UserContentQuery(uid: '7', tab: UserProfileTab.posts));
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.failed, reason: mode);
      expect(job.progress.failure, ForumRequestKind.invalidInput);
      expect(job.hits.single.postId, '101');
      await tester.pump(const Duration(minutes: 1));
      expect(paths, hasLength(2));
    }
  });

  testWidgets(
      'changing scan queries cannot share a cancelled metadata response',
      (tester) async {
    final old = Completer<dom.Document>();
    final fresh = Completer<dom.Document>();
    var reads = 0;
    respond = (_) => ++reads == 1 ? old.future : fresh.future;
    const row = UserListItem(
        title: 'cut..',
        titleTruncated: true,
        url: 'https://south-plus.net/read.php?tid-12.html',
        threadId: '12',
        sourcePage: 1);
    final first = scan(
        const UserContentQuery(
            uid: '7', tab: UserProfileTab.topics, keyword: 'old'),
        loaded: const [row],
        loadedPages: 1,
        totalPages: 1);
    var notified = 0;
    first.addListener(() => notified++);
    first.start();
    await tester.pump();
    first.dispose();
    final before = notified;
    final second = scan(
        const UserContentQuery(
            uid: '7', tab: UserProfileTab.topics, keyword: 'new'),
        loaded: const [row],
        loadedPages: 1,
        totalPages: 1);
    second.start();
    await tester.pump();
    fresh.complete(html.parse(_thread(title: 'new title')));
    await tester.pump();
    old.complete(html.parse(_thread(title: 'old title')));
    await tester.pump();
    expect(second.progress.state, ScanState.done);
    expect(second.hits.single.title, contains('new title'));
    expect(first.hits, isEmpty);
    expect(notified, before);
    expect(reads, 2);
  });

  testWidgets(
      'the bounded metadata cache retains successful thread facts amid negative history',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('read.php')) {
        final tid = int.parse(RegExp(r'tid-(\d+)').firstMatch(path)!.group(1)!);
        return html.parse(_thread(tid: tid, board: tid == 12 ? '48' : '9'));
      }
      final n = _number(path);
      final rows = n == 7
          ? _row(12, pid: 102, board: '')
          : '${n == 1 ? _row(12, pid: 101, board: '') : ''}'
              '${[
              for (var i = 0; i < (n == 1 ? 49 : 50); i++)
                _row(100 + (n == 1 ? i : 49 + (n - 2) * 50 + i),
                    pid: 1000 + n * 50 + i, board: '')
            ].join()}';
      return html.parse(_page(rows, pages: 7, page: n));
    };
    final job = scan(const UserContentQuery(
        uid: '7', tab: UserProfileTab.posts, boardId: '48'));
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((item) => item.postId), ['101', '102']);
    expect(paths.where((path) => path == 'read.php?tid-12.html'), hasLength(1));
    expect(client.peak, 1);
  });

  testWidgets('unknown rows share the result cap and stop before another page',
      (tester) async {
    respond = (path) async {
      if (path.startsWith('read.php')) {
        final tid = int.parse(RegExp(r'tid-(\d+)').firstMatch(path)!.group(1)!);
        return html.parse(_thread(tid: tid));
      }
      final n = _number(path);
      return html.parse(_page(
          [for (var i = 0; i < 50; i++) _row(n * 100 + i, pid: n * 1000 + i)]
              .join(),
          pages: 8,
          page: n));
    };
    final job = scan(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale));
    job.start();
    await tester.pump();
    expect(job.progress.capped, isTrue);
    expect(job.progress.state, ScanState.stopped);
    expect(job.progress.canResume, isFalse);
    expect(job.unresolved, hasLength(maxScanResults));
    expect(paths.where((path) => path.startsWith('u.php')), hasLength(5));
    expect(paths.where((path) => path.startsWith('read.php')), hasLength(201));
  });

  testWidgets(
      'profile details publish tab pagination and their loaded first page is not fetched again',
      (tester) async {
    respond = (path) async {
      if (path.contains('action-topic'))
        return html.parse(_page(_row(10), pages: 3, action: 'topic'));
      if (path.contains('action-post')) {
        final n = _number(path);
        return html.parse(_page(_row(n == 1 ? 12 : 14, pid: n == 1 ? 101 : 102),
            pages: 2, page: n));
      }
      if (path.contains('action-favor'))
        return html.parse(_page(_row(13, title: 'cut..'), action: 'favor'));
      return html.parse('<div class="u-box-wrap"></div>');
    };
    final repo = ForumRepository(client: client);
    addTearDown(repo.clearSession);
    final profile = await repo.fetchUserProfileDetails(
        const UserProfile(uid: '7', name: 'user', url: 'u.php?uid-7.html'));
    expect(profile.contentPagination[UserProfileTab.topics]?.totalPages, 3);
    expect(profile.contentPagination[UserProfileTab.posts]?.totalPages, 2);
    expect(profile.contentPagination[UserProfileTab.favorites]?.totalPages, 1);
    expect(profile.favorites.single.titleTruncated, isTrue);
    final job = repo.scanUserContent(
        const UserContentQuery(
            uid: '7', tab: UserProfileTab.posts, keyword: 'title'),
        loaded: profile.posts,
        loadedPages: 1,
        totalPages:
            profile.contentPagination[UserProfileTab.posts]?.totalPages);
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((item) => item.sourcePage), [1, 2]);
    expect(paths.skip(4), ['u.php?action-post-uid-7-page-2.html']);
    await repo.clearSession();
  });

  test(
      'classification metadata follows only the explicit read-only board redirect policy',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = Uri.http('127.0.0.1:${server.port}', '/');
    final transport =
        HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
    final network = _LocalClient(origin, transport);
    final requests = <String>[];
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      if (request.uri.path == '/thread.php') {
        request.response.statusCode = 302;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/thread_new.php?fid=48');
      } else if (request.uri.path == '/thread_new.php') {
        request.response.write(_board);
      } else if (request.uri.path == '/read.php') {
        request.response.write(_thread());
      }
      await request.response.close();
    });
    final scoped = UserContentQueryService(
        urls: ForumUrlResolver(baseUri: origin),
        sessionEpoch: () => 0,
        getDocument: (_) => throw StateError('scan must use guarded client'));
    final job = scoped.scan(
        const UserContentQuery(
            uid: '7',
            tab: UserProfileTab.posts,
            boardId: '48',
            classificationId: '1'),
        client: network,
        isCurrentSession: () => true,
        loaded: [
          UserListItem(
              title: 'title 12',
              url: origin.resolve('read.php?tid-12.html').toString(),
              threadId: '12',
              postId: '101',
              boardId: '48',
              sourcePage: 1)
        ],
        loadedPages: 1,
        totalPages: 1);
    addTearDown(() async {
      job.dispose();
      transport.close(force: true);
      await server.close(force: true);
    });
    final finished = Completer<void>();
    job.addListener(() {
      if ({ScanState.done, ScanState.failed, ScanState.stopped}
              .contains(job.progress.state) &&
          !finished.isCompleted) finished.complete();
    });
    job.start();
    await finished.future.timeout(const Duration(seconds: 3));
    expect(job.progress.state, ScanState.done);
    expect(job.hits.single.postId, '101');
    expect(requests, [
      'GET /thread.php?fid-48.html',
      'GET /thread_new.php?fid=48',
      'GET /read.php?tid-12.html'
    ]);
  });
}
