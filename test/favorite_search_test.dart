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
        if (gate != null) {
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
    final client = _Client();
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
      expect(job.hits.map((hit) => hit.thread.threadId), ['701']);
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
          ['tid-702.html', 'tid-703.html', 'tid-702.html', 'tid-703.html']);
      expect(client.peak, 1);
    }
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
    final client = _Client()
      ..pageRows[1] = [_row(701, category: 'A')]
      ..pageRows[2] = [_row(703, category: 'B')];
    final repo = ForumRepository(client: client);
    addTearDown(() => client.close(force: true));
    final loaded = await repo.fetchFavoriteCollections(categoryId: '1');
    client.categories = ['B', 'A'];
    final job =
        repo.scanFavorites(categoryId: '1', keyword: 'needle', loaded: loaded);
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.failed);
    expect(job.progress.failure, ForumRequestKind.invalidInput);
    expect(job.hits.single.thread.threadId, '701');
    expect(client.scanPaths, hasLength(1));
    expect(client.writes, isEmpty);
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
