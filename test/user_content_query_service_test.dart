import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/user_content_query.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/user_content_query_service.dart';

String _row(int tid, {int? pid, String board = '48', String? title}) =>
    '<tr><td>'
    '<a href="${pid == null ? 'read.php?tid-$tid.html' : 'job.php?action-topost-tid-$tid-pid-$pid.html'}">${title ?? 'title $tid'}</a>'
    '<a href="thread.php?fid-$board.html">board $board</a></td></tr>';

String _page(String rows,
        {int pages = 1, String action = 'post', String uid = '7'}) =>
    '<div id="u-contentmain"><table class="u-table">$rows</table><div class="pages">'
    '<a href="u.php?action-$action-uid-$uid-page-$pages.html">last</a></div></div>';

const _board = '<div class="hthread"><div class="threadlist">'
    '<a href="thread.php?fid-48-type-1.html">分类</a></div></div>';

String _thread({bool classified = true, int tid = 12, String? authorUid}) =>
    '<div id="breadcrumbs"><a href="thread.php?fid-48.html">board</a></div>'
    '<h1 id="subject_tpc">${classified ? '[分类]' : ''}title $tid</h1>'
    '${authorUid == null ? '' : '<table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-$authorUid.html"><strong>author</strong></a></th><th class="r_one"><div id="read_tpc">body</div></th></tr></table>'}';

void main() {
  late List<String> paths;
  late int epoch;
  late Future<dom.Document> Function(String) respond;
  late UserContentQueryService service;
  setUp(() {
    paths = [];
    epoch = 0;
    respond = (path) async => html.parse(_page(''));
    service = UserContentQueryService(
      urls: ForumUrlResolver(baseUri: Uri.parse('https://south-plus.net/')),
      sessionEpoch: () => epoch,
      getDocument: (path) {
        paths.add(path);
        return respond(path);
      },
    );
  });

  test('advances one native page and dedups overlap without losing replies',
      () async {
    respond = (path) async => html.parse(path.contains('page-1.html')
        ? _page(_row(12, pid: 101) + _row(12, pid: 102), pages: 60)
        : _page(_row(12, pid: 102) + _row(13, pid: 103), pages: 60));
    const query = UserContentQuery(uid: '7', tab: UserProfileTab.posts);
    final first = await service.fetch(query);
    expect(paths, hasLength(1));
    expect(first.items.map((item) => item.postId), ['101', '102']);
    expect(first.scannedPages, 1);
    expect(first.totalPages, 60);
    expect(first.hasMore, isTrue);
    final second = await service.fetch(query);
    expect(paths, hasLength(2));
    expect(second.items.map((item) => item.postId), ['101', '102', '103']);
    expect(second.scannedPages, 2);
  });

  test('board filtering is local, not an ignored native fid parameter',
      () async {
    respond = (path) async => html.parse(
        _page(_row(12, board: '48') + _row(13, board: '9'), action: 'topic'));
    final result = await service.fetch(const UserContentQuery(
        uid: '7', tab: UserProfileTab.topics, boardId: '48'));
    expect(paths.single, isNot(contains('fid-')));
    expect(result.items.map((item) => item.threadId), ['12']);
    expect(result.boards.map((item) => item.name), ['board 48', 'board 9']);
    expect(result.isComplete, isTrue);
  });

  test('native article type is sent for topics but never for replies',
      () async {
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php')) return html.parse(_thread());
      return html.parse(_page(_row(12, pid: 101)));
    };
    await service.fetch(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.topics,
        articleType: UserContentArticleType.sale));
    expect(paths.first, contains('type-sale'));
    paths.clear();
    final result = await service.fetch(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale));
    expect(paths.first, isNot(contains('type-')));
    expect(result.items, isEmpty);
    expect(result.unresolvedItems, hasLength(1));
    expect(result.hasMore, isFalse);
    expect(result.isComplete, isFalse);
  });

  test('classification probes are bounded and metadata dedups by TID',
      () async {
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php'))
        return html.parse(_thread(
            tid: int.parse(RegExp(r'tid-(\d+)').firstMatch(path)!.group(1)!)));
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
    final first = await service.fetch(query);
    expect(paths.where((path) => !path.startsWith('u.php')).length,
        lessThanOrEqualTo(8));
    expect(paths.where((path) => path == 'read.php?tid-1.html'), hasLength(1));
    expect(first.items.map((item) => item.postId).take(2), ['100', '101']);
    expect(first.pendingMetadataCount, greaterThan(0));
    expect(first.hasMore, isTrue);
    final second = await service.fetch(query);
    expect(second.items, hasLength(13));
    expect(second.checkedThreads, 12);
    expect(second.isComplete, isTrue);
    expect(paths.where((path) => path.startsWith('u.php')), hasLength(1));
  });

  test('concurrent selectors share in-flight thread metadata', () async {
    final gate = Completer<dom.Document>();
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php')) return gate.future;
      return html.parse(_page(_row(12, pid: 101)));
    };
    const one = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        boardId: '48',
        classificationId: '1');
    const two = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        boardId: '48',
        classificationId: '1',
        articleType: UserContentArticleType.sale);
    final first = service.fetch(one);
    final second = service.fetch(two);
    await Future<void>.delayed(Duration.zero);
    expect(paths.where((path) => path.startsWith('read.php')), hasLength(1));
    gate.complete(html.parse(_thread()));
    expect((await first).items, hasLength(1));
    expect((await second).unresolvedItems, hasLength(1));
  });

  test(
      'older reply type lookup progresses by author and preserves repeated replies',
      () async {
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php'))
        return html.parse(_thread(authorUid: '88'));
      if (path.contains('uid-88')) {
        return html.parse(_page(
            path.contains('page-1.html') ? _row(999) : _row(12),
            pages: 2,
            action: 'topic',
            uid: '88'));
      }
      return html.parse(_page(_row(12, pid: 101) + _row(12, pid: 102)));
    };
    const query = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale);
    final first = await service.fetch(query);
    expect(first.items, isEmpty);
    expect(first.unresolvedItems, hasLength(2));
    expect(first.lookupPagesScanned, 1);
    expect(first.lookupPagesTotal, 2);
    expect(first.hasMore, isTrue);
    expect(paths.where((path) => path.contains('uid-88')), hasLength(1));
    final second = await service.fetch(query);
    expect(second.items.map((item) => item.postId), ['101', '102']);
    expect(second.unresolvedItems, isEmpty);
    expect(second.lookupPagesScanned, 2);
    expect(second.isComplete, isTrue);
    expect(paths.where((path) => path.startsWith('read.php')), hasLength(1));
    expect(paths.where((path) => path.contains('uid-88')), hasLength(2));
  });

  test('only valid native lookup exhaustion proves a negative article type',
      () async {
    var missingRoot = false;
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php'))
        return html.parse(_thread(authorUid: '88'));
      if (path.contains('uid-88')) {
        return html.parse(missingRoot
            ? '<table class="u-table"></table>'
            : _page('', action: 'topic', uid: '88'));
      }
      return html.parse(_page(_row(12, pid: 101)));
    };
    const query = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        articleType: UserContentArticleType.sale);
    final negative = await service.fetch(query);
    expect(negative.items, isEmpty);
    expect(negative.unresolvedItems, isEmpty);
    expect(negative.isComplete, isTrue);
    missingRoot = true;
    final unknown = await service.fetch(query, refresh: true);
    expect(unknown.items, isEmpty);
    expect(unknown.unresolvedItems, hasLength(1));
    expect(unknown.isComplete, isFalse);
    expect(unknown.hasMore, isFalse);
  });

  test('native board category evidence overrides a spoofable header prefix',
      () async {
    respond = (path) async {
      if (path.startsWith('thread.php'))
        return html.parse('$_board'
            '<table id="ajaxtable"><tr class="tr3"><td><h3>'
            '<a href="read.php?tid-12.html">[分类]title 12</a></h3></td></tr></table>');
      if (path.startsWith('read.php')) return html.parse(_thread());
      return html.parse(_page(_row(12, pid: 101)));
    };
    final result = await service.fetch(const UserContentQuery(
        uid: '7',
        tab: UserProfileTab.posts,
        boardId: '48',
        classificationId: '1'));
    expect(result.items, isEmpty);
    expect(result.unresolvedItems, isEmpty);
    expect(result.isComplete, isTrue);
  });

  test('permanent unknown metadata never starves later profile history',
      () async {
    respond = (path) async {
      if (path.startsWith('thread.php')) return html.parse(_board);
      if (path.startsWith('read.php')) {
        final tid = int.parse(RegExp(r'tid-(\d+)').firstMatch(path)!.group(1)!);
        return html.parse(_thread(tid: tid));
      }
      final page = int.parse(RegExp(r'page-(\d+)').firstMatch(path)!.group(1)!);
      return html.parse(_page(
          [
            for (var offset = 1; offset <= 50; offset++)
              _row((page - 1) * 50 + offset,
                  title: '[分类]title ${(page - 1) * 50 + offset}'),
          ].join(),
          pages: 7,
          action: 'topic'));
    };
    const query = UserContentQuery(
        uid: '7',
        tab: UserProfileTab.topics,
        boardId: '48',
        classificationId: '1');
    UserContentResult? result;
    for (var advance = 0; advance < 80; advance++) {
      final before = paths.length;
      result = await service.fetch(query);
      expect(
          paths.skip(before).where((path) => !path.startsWith('u.php')).length,
          lessThanOrEqualTo(8));
      if (!result.hasMore) break;
    }
    expect(result!.hasMore, isFalse);
    expect(result.scannedPages, 7);
    expect(result.unresolvedItems, hasLength(350));
    expect(result.items, isEmpty);
    expect(result.isComplete, isFalse);
    final headers = paths.where((path) => path.startsWith('read.php')).toList();
    expect(headers, hasLength(350));
    expect(headers.toSet(), hasLength(350));
  });

  test('stale in-flight content is rejected after session changes', () async {
    final gate = Completer<dom.Document>();
    respond = (path) => gate.future;
    const query = UserContentQuery(uid: '7', tab: UserProfileTab.posts);
    final pending = service.fetch(query);
    final expectation = expectLater(
        pending,
        throwsA(isA<ForumRequestException>()
            .having((e) => e.kind, 'kind', ForumRequestKind.loginRequired)));
    epoch++;
    gate.complete(html.parse(_page(_row(12, pid: 101))));
    await expectation;
    respond = (path) async => html.parse(_page(_row(13, pid: 102)));
    final current = await service.fetch(query);
    expect(current.items.single.threadId, '13');
    expect(paths, hasLength(2));
  });
}
