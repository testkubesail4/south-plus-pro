import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';

import 'support/native_favorite_fixture.dart';

typedef _Row = ({String id, String tid, String category});
_Row _row(int tid, {String category = ''}) =>
    (id: '${tid + 1000}', tid: '$tid', category: category);

class _Client extends NativeFavoriteClient {
  _Client() {
    pageCount = 2;
  }
  final pageRows = <int, List<_Row>>{
    1: [_row(701), _row(702)],
    2: [_row(703), _row(704), _row(701)],
  };
  final titles = {
    '701': 'needle known',
    '702': 'cut..',
    '703': 'needle second page',
    '704': 'other title'
  };
  final fullTitles = {'702': '请求过于频繁 needle resolved'};
  final metadata = <String, List<Object>>{};
  final scanPaths = <Uri>[];
  Completer<String>? gate;
  String? gateTid;
  bool repeatContent = false;
  bool unreadablePager = false;
  int active = 0;
  int peak = 0;

  String listPage(int page, {String? category}) {
    final rows = pageRows[repeatContent ? 1 : page] ?? const <_Row>[];
    var html = nativeFavoriteHtml(
        categories: categories,
        rows: rows,
        pageCount: pageCount,
        filter: category);
    for (final row in rows) {
      html = html.replaceAll('Synthetic ${row.tid}',
          const HtmlEscape().convert(titles[row.tid] ?? 'needle ${row.tid}'));
    }
    html = html.replaceFirst(
        'Pages: 1&nbsp; / $pageCount',
        unreadablePager && page > 1
            ? 'unknown pager'
            : 'Pages: $page&nbsp; / $pageCount');
    return html;
  }

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    final uri = Uri.parse(path);
    if (uri.path != 'u.php')
      return super.getForm(path,
          requireCurrentSession: requireCurrentSession,
          followRedirects: followRedirects);
    reads.add(uri);
    return listPage(1, category: uri.queryParameters['type']);
  }

  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy =
          ForumReadRedirectPolicy.none}) async {
    requireCurrentSession();
    final uri = Uri.parse(path);
    scanPaths.add(uri);
    active++;
    if (active > peak) peak = active;
    try {
      String result;
      if (uri.path == 'u.php') {
        result = listPage(int.parse(uri.queryParameters['page']!),
            category: uri.queryParameters['type']);
      } else {
        final tid = RegExp(r'tid-([1-9]\d*)').firstMatch(uri.query)!.group(1)!;
        if (gate != null && (gateTid == null || gateTid == tid)) {
          result = await gate!.future;
        } else {
          final scripts = metadata[tid];
          final response =
              scripts?.isNotEmpty == true ? scripts!.removeAt(0) : null;
          if (response is ForumRequestException) throw response;
          result = response as String? ??
              '<span id="subject_tpc">${const HtmlEscape().convert(fullTitles[tid] ?? 'needle full $tid')}</span>'
                  '<a href="read.php?tid-$tid.html">topic</a>';
        }
      }
      requireCurrentSession();
      return result;
    } finally {
      active--;
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'known seeds are immediate; truncated titles and later-page hits use read-only sequential requests',
      (tester) async {
    final client = _Client()
      ..pageRows[1] = [
        _row(701),
        _row(702),
        (id: '2702', tid: '702', category: '')
      ];
    final repo = ForumRepository(client: client);
    addTearDown(() => client.close(force: true));
    final loaded = await repo.fetchFavoriteCollections();
    expect(loaded.items.last.thread.titleTruncated, isTrue);
    final job = repo.scanFavorites(keyword: 'needle', loaded: loaded);
    addTearDown(job.dispose);
    expect(job.hits.single.thread.title, 'needle known');
    expect(job.progress.pending, 1);
    expect(client.scanPaths, isEmpty);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.progress.scannedPages, 2);
    expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702', '703']);
    expect(job.hits.map((hit) => hit.page), [1, 1, 2]);
    expect(job.hits[1].thread.title, '请求过于频繁 needle resolved');
    expect(job.hits[1].thread.titleTruncated, isFalse);
    expect(job.hits[1].thread.author, 'Synthetic author');
    expect(job.progress.pending, 0);
    expect(client.scanPaths.map((uri) => uri.toString()),
        ['read.php?tid-702.html', 'u.php?action=favor&page=2']);
    expect(client.peak, 1);
    expect(client.reads, hasLength(1),
        reason: 'no history/detail/favorite lookup path');
    expect(client.writes, isEmpty);
  });

  testWidgets(
      'a denied title stays unresolved; login loss stops without reading the next page',
      (tester) async {
    for (final (response, expected) in [
      ('<body>没有权限</body>', ScanState.done),
      ('<body>请先登录</body>', ScanState.failed),
    ]) {
      final client = _Client()..metadata['702'] = [response];
      final repo = ForumRepository(client: client);
      addTearDown(() => client.close(force: true));
      final loaded = await repo.fetchFavoriteCollections();
      final job = repo.scanFavorites(keyword: 'needle', loaded: loaded);
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      expect(job.progress.state, expected);
      expect(job.hits.first.thread.threadId, '701');
      if (expected == ScanState.done) {
        expect(job.unresolved.single.thread.title, 'cut..');
        expect(job.progress.unresolved, 1);
        expect(job.hits.last.thread.threadId, '703');
      } else {
        expect(job.progress.failure, ForumRequestKind.loginRequired);
        expect(job.progress.canResume, isFalse);
        expect(client.scanPaths, hasLength(1));
      }
      expect(client.writes, isEmpty);
    }
  });

  testWidgets(
      'a transient metadata failure retries once through the shared backoff without losing earlier matches',
      (tester) async {
    for (final failure in <Object>[
      const ForumRequestException(ForumRequestKind.network, 'fixture'),
      '<body>刷新不要快于 9 秒</body>',
    ]) {
      final client = _Client()
        ..pageCount = 1
        ..pageRows[1] = [_row(701), _row(702), _row(703)]
        ..titles['703'] = 'another cut..'
        ..metadata['703'] = [failure];
      final repo = ForumRepository(client: client);
      addTearDown(() => client.close(force: true));
      final loaded = await repo.fetchFavoriteCollections();
      final job = repo.scanFavorites(keyword: 'needle', loaded: loaded);
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.waiting);
      expect(job.progress.pending, 1);
      expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702']);
      if (failure is String) {
        expect(job.progress.failure, ForumRequestKind.rateLimited);
        await tester.pump(const Duration(seconds: 9));
        expect(client.scanPaths, hasLength(2),
            reason: '200 cooldown is conservative');
        await tester.pump(const Duration(seconds: 4));
      } else {
        await tester.pump(const Duration(seconds: 2));
      }
      expect(job.progress.state, ScanState.done);
      expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702', '703']);
      expect(client.scanPaths.map((uri) => uri.query),
          ['tid-702.html', 'tid-703.html', 'tid-703.html']);
      expect(client.peak, 1);
    }
  });

  testWidgets(
      'partial title results survive stop, retry exhaustion and explicit resume',
      (tester) async {
    final client = _Client()
      ..pageCount = 1
      ..pageRows[1] = [_row(701), _row(702), _row(703)]
      ..titles['703'] = 'another cut..'
      ..gateTid = '703'
      ..gate = Completer<String>()
      ..metadata['703'] = [
        for (var attempt = 0; attempt < 3; attempt++)
          const ForumRequestException(ForumRequestKind.network, 'fixture'),
      ];
    final repo = ForumRepository(client: client);
    addTearDown(() => client.close(force: true));
    final held = client.gate!;
    addTearDown(() {
      if (!held.isCompleted) held.complete('disposed fixture');
    });
    final job = repo.scanFavorites(
        keyword: 'needle', loaded: await repo.fetchFavoriteCollections());
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(client.scanPaths.map((uri) => uri.query),
        ['tid-702.html', 'tid-703.html']);
    expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702']);
    job.stop();
    expect(job.progress.state, ScanState.stopped);
    expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702']);
    job.resume();
    client.gate = null;
    held.complete('<span id="subject_tpc">needle stale 703</span>');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(job.progress.state, ScanState.failed);
    expect(job.progress.canResume, isTrue);
    expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702']);
    job.resume();
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702', '703']);
    expect(client.scanPaths.where((uri) => uri.query == 'tid-702.html'),
        hasLength(1));
    expect(client.scanPaths.where((uri) => uri.query == 'tid-703.html'),
        hasLength(5));
    expect(client.reads, hasLength(1),
        reason: 'the admitted list page is not fetched again');
    expect(client.peak, 1);
  });

  testWidgets(
      'stop and resume during title work drains the stale response and does not suppress its replacement',
      (tester) async {
    final client = _Client()..gate = Completer<String>();
    final repo = ForumRepository(client: client);
    addTearDown(() => client.close(force: true));
    final loaded = await repo.fetchFavoriteCollections();
    final job = repo.scanFavorites(keyword: 'needle', loaded: loaded);
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    job.stop();
    job.resume();
    await tester.pump();
    expect(client.scanPaths, hasLength(1));
    final gate = client.gate!;
    client.gate = null;
    gate.complete('<span id="subject_tpc">needle stale</span>');
    await tester.pump();
    expect(job.progress.state, ScanState.done);
    expect(job.hits.map((hit) => hit.thread.threadId), ['701', '702', '703']);
    expect(job.hits.any((hit) => hit.thread.title.contains('stale')), isFalse);
    expect(client.peak, 1);
  });

  testWidgets(
      'stale account seeds are never inherited; category and unknown-pager boundaries stay explicit',
      (tester) async {
    final client = _Client();
    final repo = ForumRepository(client: client);
    addTearDown(() => client.close(force: true));
    final old = await repo.fetchFavoriteCollections();
    await repo.clearSession();
    client.loggedIn = true;
    final stale = repo.scanFavorites(keyword: 'needle', loaded: old);
    addTearDown(stale.dispose);
    expect(stale.hits, isEmpty);
    stale.start();
    await tester.pump();
    expect(stale.progress.failure, ForumRequestKind.loginRequired);
    expect(client.scanPaths, isEmpty);

    client.pageRows[1] = [_row(701, category: 'A')];
    client.pageRows[2] = [_row(703, category: 'A')];
    client.unreadablePager = true;
    final loaded = await repo.fetchFavoriteCollections(categoryId: '1');
    final job =
        repo.scanFavorites(categoryId: '1', keyword: 'needle', loaded: loaded);
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(client.scanPaths.single.queryParameters['type'], '1');
    expect(job.progress.failure, ForumRequestKind.invalidInput);
    expect(job.progress.state, ScanState.failed);
    expect(job.hits.single.thread.threadId, '701');
    await tester.pump(const Duration(minutes: 1));
    expect(client.scanPaths, hasLength(1));
  });

  testWidgets('a renumbered category cannot silently change the searched scope',
      (tester) async {
    for (final mode in ['fresh', 'retired-owner', 'consumed']) {
      final client = _Client()
        ..pageRows[1] = [_row(701, category: 'A')]
        ..pageRows[2] = [_row(703, category: 'B')];
      final repo = ForumRepository(client: client);
      addTearDown(() => client.close(force: true));
      final loaded = await repo.fetchFavoriteCollections(categoryId: '1');
      if (mode != 'fresh') {
        final writable =
            mode == 'consumed' ? loaded : await repo.fetchFavoriteCollections();
        final changed = await repo.createFavoriteCategory(writable, 'new');
        expect(changed.createdCategory?.label, 'new');
      }
      client.categories = ['B', 'A', ...client.categories.skip(2)];
      client.pageRows[1] = [_row(703, category: 'B')];
      client.pageRows[2] = [_row(705, category: 'B')];
      final writes = client.writes.length;
      final job = repo.scanFavorites(
          categoryId: '1', keyword: 'needle', loaded: loaded);
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.failed, reason: mode);
      expect(job.progress.failure, ForumRequestKind.invalidInput);
      expect(job.hits.map((hit) => hit.thread.threadId),
          mode == 'fresh' ? ['701'] : <String>[]);
      expect(client.scanPaths, hasLength(mode == 'consumed' ? 0 : 1));
      expect(client.writes, hasLength(writes));
    }
  });

  testWidgets(
      'repeated-page content fails closed and the shared hit cap stops later requests',
      (tester) async {
    final repeated = _Client()..repeatContent = true;
    final repo = ForumRepository(client: repeated);
    addTearDown(() => repeated.close(force: true));
    final job = repo.scanFavorites(
        keyword: 'needle', loaded: await repo.fetchFavoriteCollections());
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(job.progress.failure, ForumRequestKind.invalidInput);
    expect(job.progress.state, ScanState.failed);
    expect(job.hits, hasLength(2));
    expect(
        repeated.scanPaths.where((uri) => uri.path == 'u.php'), hasLength(1));

    final many = _Client()
      ..pageCount = 3
      ..pageRows[1] = [_row(701)]
      ..pageRows[2] = [for (var tid = 800; tid < 1020; tid++) _row(tid)];
    final largeRepo = ForumRepository(client: many);
    addTearDown(() => many.close(force: true));
    final capped = largeRepo.scanFavorites(
        keyword: 'needle', loaded: await largeRepo.fetchFavoriteCollections());
    addTearDown(capped.dispose);
    capped.start();
    await tester.pump();
    expect(capped.hits, hasLength(maxScanResults));
    expect(capped.progress.capped, isTrue);
    expect(capped.progress.canResume, isFalse);
    expect(many.scanPaths, hasLength(1));
    expect(many.scanPaths.single.queryParameters['page'], '2');
    expect(many.writes, isEmpty);
  });
}
