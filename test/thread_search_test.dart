import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/services/thread_search.dart';

const _thread = ForumThread(
    title: 'Fixture',
    url: 'https://south-plus.net/read.php?tid-701.html',
    replies: 20,
    section: 'Fixture board',
    author: 'OP',
    authorUrl: 'https://south-plus.net/u.php?uid-901.html');

class _History extends BrowsingHistoryStore {
  int writes = 0;
  @override
  Future<void> recordThread(ForumThread thread, {DateTime? viewedAt}) async {
    writes++;
  }
}

class _Client extends ForumClient {
  final paths = <String>[];
  final normalPaths = <String>[];
  String Function(int) response = (page) => _html(page, 3, 'needle page $page');
  Completer<String>? gate;
  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession}) async {
    requireCurrentSession();
    paths.add(path);
    final page = int.tryParse(
            RegExp(r'(?:^|[?&-])page[-=](\d+)').firstMatch(path)?.group(1) ??
                '') ??
        1;
    final html = gate == null ? response(page) : await gate!.future;
    requireCurrentSession();
    return html;
  }

  @override
  Future<String> get(String path) async {
    normalPaths.add(path);
    return path.startsWith('read.php')
        ? response(1)
        : '<form action="u.php?action=favor"></form>';
  }

  @override
  Future<void> clearSession() async {}
}

String _post(String uid, String pid, String floor, String text) => '''
<table class="js-post"><tr><th class="r_two"><a href="u.php?uid-$uid.html"><strong>Author $uid</strong></a></th>
<th class="r_one"><div class="tiptop"><span class="fl"><a class="s3">$floor</a></span></div>
<div class="tpc_content"><div id="read_$pid">$text</div></div></th></tr></table>''';

String _html(int page, int total, String text, {String uid = '902'}) => '''
<html><head><title>Fixture</title></head><body>
<script>var verifyhash = 'fixture-only';</script><a id="favor">收藏</a>
<span id="subject_tpc">Fixture</span><a href="read.php?tid-701.html">Fixture</a>
<div class="pages"><span class="pagesone">Pages: $page/$total</span></div>
${_post(uid, '${500 + page}', 'B${page * 10}F', text)}
</body></html>''';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'loaded search uses visible text, rule snapshots, exact anchors and rune-safe snippets',
      () {
    final page = ThreadDetail(
      thread: _thread,
      body: 'raw needle locked image',
      bodyAnchors: const ['read_tpc', 'tpc'],
      bodySegments: const [
        ThreadContentSegment.text('needle main'),
        ThreadContentSegment.image(
            url: 'https://example.invalid/image', alt: 'needle image'),
        ThreadContentSegment.saleBox(
            ThreadSaleBox(summary: 'needle locked', buyPath: 'job.php')),
        ThreadContentSegment.media(
            url: 'https://example.invalid/media', text: 'needle media'),
        ThreadContentSegment.text('needle attachment',
            href: 'https://south-plus.net/job.php?action=download&aid=1'),
      ],
      replies: [
        const ThreadReply(
            author: 'blocked user',
            authorUrl: 'https://south-plus.net/u.php?uid-903.html',
            content: 'needle private',
            anchors: ['503']),
        const ThreadReply(
            author: 'blocked content',
            content: 'needle blocked',
            blockContentKey: 'same'),
        ThreadReply(
            author: 'visible',
            authorUrl: 'https://south-plus.net/u.php?uid-902.html',
            content: '${'😀' * 140}Needle${'文' * 140}',
            floor: 'B12F',
            anchors: const ['read_502', '502', 'fl-12']),
        const ThreadReply(
          author: 'nested',
          content: 'not the rendered text',
          floor: 'B13F',
          segments: [
            ThreadContentSegment.text('in'),
            ThreadContentSegment.text('line '),
            ThreadContentSegment.quote([ThreadContentSegment.text('quote')]),
            ThreadContentSegment.list([
              ThreadContentSegment.block([ThreadContentSegment.text('list')]),
            ]),
            ThreadContentSegment.table([
              [
                ThreadContentTableCell([ThreadContentSegment.text('table')])
              ],
            ]),
            ThreadContentSegment.code('code'),
          ],
        ),
      ],
    );
    final rules = BlockingRules(users: const [
      BlockedUser(
          uid: '903',
          name: 'blocked user',
          userBlocked: true,
          avatarBlocked: false),
    ], contentKeys: const {
      'same'
    });
    expect(searchLoadedThread([page], 'needle', const BlockingRules()),
        hasLength(4));
    final hits = searchLoadedThread([page], 'needle', rules);
    expect(hits.map((hit) => hit.floorLabel), ['主楼', '12 楼']);
    expect(hits.map((hit) => hit.anchor), ['tpc', '502']);
    expect(hits.last.snippet, contains('Needle'));
    expect(hits.last.snippet.runes.length, lessThanOrEqualTo(120));
    expect(
        searchLoadedThread([page], 'inline quote list table code', rules)
            .single
            .floorLabel,
        '13 楼');
    for (final hidden in [
      'image',
      'locked',
      'media',
      'attachment',
      'private',
      'blocked'
    ]) {
      expect(searchLoadedThread([page], 'needle $hidden', rules), isEmpty,
          reason: hidden);
    }
    final opBlocked = BlockingRules(users: const [
      BlockedUser(
          uid: '901', name: 'OP', userBlocked: true, avatarBlocked: false),
    ]);
    expect(searchLoadedThread([page], 'main', opBlocked), isEmpty);
    final filtered = ThreadDetail(
        thread: _thread.copyWith(
            url: 'https://south-plus.net/read.php?tid-701-uid-902.html'),
        body: '',
        replies: page.replies);
    expect(
        searchLoadedThread([filtered], 'needle', const BlockingRules())
            .single
            .author,
        'visible');
  });

  testWidgets(
      'scan includes loaded middle page, reads only missing pages without favorite or history I/O',
      (tester) async {
    final client = _Client();
    final history = _History();
    final repo = ForumRepository(client: client, historyStore: history);
    addTearDown(() => client.close(force: true));
    final job = repo.scanThread(
        _thread.copyWith(
            url: 'https://south-plus.net/read.php?tid-701-page-e.html#501'),
        'needle',
        loaded: const [
          ThreadDetail(
              thread: _thread,
              body: '',
              replies: [
                ThreadReply(
                    author: 'loaded',
                    content: 'needle loaded',
                    floor: 'B20F',
                    anchors: ['502'])
              ],
              pagination: ThreadPagination(currentPage: 2, totalPages: 3))
        ],
        rules: const BlockingRules());
    addTearDown(job.dispose);
    expect(client.paths, isEmpty);
    expect(job.hits.single.page, 2);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((hit) => hit.page), [2, 1, 3]);
    expect(client.paths, [
      'read.php?tid-701.html',
      'read.php?tid-701-fpage-0-toread--page-3.html'
    ]);
    expect(client.normalPaths, isEmpty,
        reason: 'no favorite lookup, history loader or image request');
    expect(history.writes, 0);

    await repo.fetchThreadDetail(_thread);
    expect(history.writes, 1,
        reason: 'the interactive loader still records views');
    expect(client.normalPaths, contains('u.php?action-favor.html'),
        reason:
            'the fixture really exposes the favorite lookup that scans must avoid');
  });

  testWidgets('mixed-age loaded pages keep the largest observed total',
      (tester) async {
    final client = _Client();
    final repo = ForumRepository(client: client, historyStore: _History());
    addTearDown(() => client.close(force: true));
    final job = repo.scanThread(_thread, 'needle',
        loaded: const [
          ThreadDetail(
              thread: _thread,
              body: 'needle refreshed',
              replies: [],
              pagination: ThreadPagination(currentPage: 1, totalPages: 3)),
          ThreadDetail(
              thread: _thread,
              body: '',
              replies: [
                ThreadReply(author: 'old append', content: 'needle old')
              ],
              pagination: ThreadPagination(currentPage: 2, totalPages: 2)),
        ],
        rules: const BlockingRules());
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(client.paths, ['read.php?tid-701-fpage-0-toread--page-3.html']);
    expect(job.progress.totalPages, 3);
    expect(job.progress.scannedPages, 3);
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((hit) => hit.page), [1, 2, 3]);
  });

  testWidgets('another thread in either supported URL form is not admitted',
      (tester) async {
    for (final link in ['read.php?tid-999.html', 'read.php?tid=999']) {
      final client = _Client()
        ..response = (_) => _html(1, 1, 'needle wrong')
            .replaceFirst('read.php?tid-701.html', link);
      final job = ForumRepository(client: client, historyStore: _History())
          .scanThread(_thread, 'needle',
              loaded: const [], rules: const BlockingRules());
      addTearDown(() => client.close(force: true));
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.failed, reason: link);
      expect(job.progress.failure, ForumRequestKind.invalidInput);
      expect(job.hits, isEmpty);
      await tester.pump(const Duration(minutes: 1));
      expect(client.paths, hasLength(1));
    }
  });

  testWidgets(
      'author scope survives normalization and does not trust unrelated loaded pages or server rows',
      (tester) async {
    final client = _Client()
      ..response = (page) => _html(page, 2, 'needle owned', uid: '902')
          .replaceFirst('</body>',
              '${_post('903', '999', 'B99F', 'needle foreign')}</body>');
    final repo = ForumRepository(client: client, historyStore: _History());
    addTearDown(() => client.close(force: true));
    final job = repo.scanThread(
        _thread.copyWith(
            url: 'https://south-plus.net/read.php?tid-701-uid-902-page-e.html'),
        'needle',
        loaded: const [
          ThreadDetail(thread: _thread, body: 'needle wrong scope', replies: [])
        ],
        rules: const BlockingRules());
    addTearDown(job.dispose);
    expect(job.hits, isEmpty);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits, hasLength(2));
    expect(job.hits.every((hit) => hit.author == 'Author 902'), isTrue);
    expect(client.paths.every((path) => path.contains('-uid-902')), isTrue);
  });

  testWidgets(
      '200 error pages classify at admission while identical words in posts remain searchable',
      (tester) async {
    for (final (body, kind) in [
      ('请先登录', ForumRequestKind.loginRequired),
      ('没有权限', ForumRequestKind.forbidden),
      ('刷新不要快于 9 秒', ForumRequestKind.rateLimited),
    ]) {
      final client = _Client()
        ..response = (_) => '<html><title>提示</title><body>$body</body></html>';
      final repo = ForumRepository(client: client, historyStore: _History());
      final job = repo.scanThread(_thread, 'needle',
          loaded: const [], rules: const BlockingRules());
      addTearDown(() => client.close(force: true));
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      expect(job.progress.failure, kind);
      expect(
          job.progress.state,
          kind == ForumRequestKind.rateLimited
              ? ScanState.waiting
              : ScanState.failed);
      job.stop();
    }
    final client = _Client()
      ..response = (_) => _html(1, 1, '请先登录 没有权限 请求过于频繁 needle');
    final job = ForumRepository(client: client, historyStore: _History())
        .scanThread(_thread, 'needle',
            loaded: const [], rules: const BlockingRules());
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.single.snippet, contains('请求过于频繁'));
  });

  testWidgets(
      'unreadable pagination fails without retry and a session change drops a pending page',
      (tester) async {
    final client = _Client()
      ..response = (_) =>
          _html(1, 3, 'needle').replaceFirst('Pages: 1/3', 'unknown pager');
    final repo = ForumRepository(client: client, historyStore: _History());
    addTearDown(() => client.close(force: true));
    final invalid = repo.scanThread(_thread, 'needle',
        loaded: const [], rules: const BlockingRules());
    addTearDown(invalid.dispose);
    invalid.start();
    await tester.pump();
    expect(invalid.progress.failure, ForumRequestKind.invalidInput);
    await tester.pump(const Duration(minutes: 1));
    expect(client.paths, hasLength(1));

    final gate = client.gate = Completer<String>();
    final stale = repo.scanThread(_thread, 'needle',
        loaded: const [], rules: const BlockingRules());
    addTearDown(stale.dispose);
    stale.start();
    await tester.pump();
    await repo.clearSession();
    gate.complete(_html(1, 3, 'needle stale'));
    await tester.pump();
    expect(stale.progress.failure, ForumRequestKind.loginRequired);
    expect(stale.hits, isEmpty);
    expect(client.paths, hasLength(2));
  });
}
