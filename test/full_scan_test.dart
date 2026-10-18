import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/services/keyword_match.dart';

class _Client extends ForumClient {
  final calls = <String>[];
  Future<String> Function()? answer;
  var active = 0;
  var peak = 0;

  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy =
          ForumReadRedirectPolicy.none}) async {
    requireCurrentSession();
    calls.add(path);
    active++;
    if (active > peak) peak = active;
    try {
      final body = await (answer?.call() ?? Future.value('ok'));
      requireCurrentSession();
      return body;
    } finally {
      active--;
    }
  }
}

void main() {
  test('keyword matching is AND across fields and preserves uncertainty', () {
    expect(
        matchKeyword('  ALPHA\t beta ', ['Alpha title', null, 'Beta author']),
        isTrue);
    expect(matchKeyword('alpha gamma', ['alpha beta']), isFalse);
    expect(matchKeyword('alpha gamma', ['alpha..'], truncated: true), isNull);
    expect(matchKeyword('alpha', ['ALPHA..'], truncated: true), isTrue);
    expect(matchKeyword(' \n ', const [], truncated: true), isTrue);
  });

  PageFullScan<int> scan(_Client client,
          {bool Function()? current,
          Iterable<ScanPage<int>> loaded = const [],
          int total = 3,
          int cap = 200}) =>
      PageFullScan<int>(
        client: client,
        isCurrentSession: current ?? () => true,
        totalPages: total,
        loaded: loaded,
        maxResults: cap,
        readPage: (page, request) async {
          await request.getOnce('$page');
          return ScanPage(
              page: page,
              totalPages: total,
              hasMore: page < total,
              hits: [page]);
        },
      );

  testWidgets('loaded pages seed results without rereads, then finish in order',
      (tester) async {
    final client = _Client();
    final job = scan(client, loaded: const [
      ScanPage(page: 3, totalPages: 3, hasMore: false, hits: [3]),
      ScanPage(page: 1, totalPages: 3, hasMore: true, hits: [1]),
    ]);
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    expect(job.progress.scannedPages, 2);
    expect(client.calls, isEmpty);
    job.start();
    await tester.pump();
    expect(client.calls, ['2']);
    expect(job.progress.state, ScanState.done);
    expect(job.progress.scannedPages, 3);
    expect(job.hits, [3, 1, 2]);
    expect(() => job.hits.add(9), throwsUnsupportedError);
  });

  for (final kind in [ForumRequestKind.network, ForumRequestKind.rateLimited]) {
    testWidgets('$kind uses bounded backoff and stops after three attempts',
        (tester) async {
      final client = _Client()
        ..answer = () => Future.error(ForumRequestException(kind, 'fixture'));
      final job = scan(client);
      addTearDown(() => client.close(force: true));
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      expect(job.progress.state, ScanState.waiting);
      expect(job.progress.retryAt, isNotNull);
      expect(job.progress.attempt, 1);
      final firstDeadline = job.progress.retryAt!;
      expect(client.calls, ['1']);
      await tester.pump(Duration(
          milliseconds: kind == ForumRequestKind.rateLimited ? 9900 : 900));
      expect(client.calls, ['1'], reason: 'never retry before the base delay');
      await tester.pump(Duration(
          milliseconds: kind == ForumRequestKind.rateLimited ? 3000 : 400));
      expect(client.calls, ['1', '1'],
          reason: 'jitter stays within 25 percent of the first delay');
      expect(
          job.progress.retryAt!.difference(firstDeadline),
          greaterThanOrEqualTo(Duration(
              milliseconds: kind == ForumRequestKind.rateLimited ? 7000 : 700)),
          reason: 'the second backoff grows exponentially, not a constant gap');
      await tester.pump(const Duration(minutes: 1));
      expect(client.calls, ['1', '1', '1']);
      expect(job.progress.state, ScanState.failed);
      expect(job.progress.failure, kind);
      expect(job.progress.canResume, isTrue);
      await tester.pump(const Duration(minutes: 2));
      expect(client.calls, hasLength(3));
    });
  }

  testWidgets('login, forbidden and invalid pages never automatically retry',
      (tester) async {
    for (final kind in [
      ForumRequestKind.loginRequired,
      ForumRequestKind.forbidden,
      ForumRequestKind.invalidInput,
    ]) {
      final client = _Client()
        ..answer = () => Future.error(ForumRequestException(kind, 'fixture'));
      final job = scan(client);
      addTearDown(() => client.close(force: true));
      addTearDown(job.dispose);
      job.start();
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      expect(client.calls, ['1'], reason: '$kind');
      expect(job.progress.state, ScanState.failed);
      expect(job.progress.canResume, isFalse);
      job.resume();
      await tester.pump();
      expect(client.calls, ['1']);
    }
  });

  testWidgets('stop and immediate resume wait for the old response to drain',
      (tester) async {
    final gate = Completer<String>();
    final client = _Client()..answer = () => gate.future;
    final job = scan(client, total: 2);
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    job.stop();
    expect(job.progress.state, ScanState.stopped);
    job.resume();
    await tester.pump();
    expect(client.calls, ['1']);
    client.answer = null;
    gate.complete('stale');
    await tester.pump();
    expect(client.calls, ['1', '1', '2']);
    expect(client.peak, 1);
    expect(job.hits, [1, 2], reason: 'the old response is never committed');
    expect(job.progress.state, ScanState.done);
  });

  testWidgets('stopping a retry cancels its timer and explicit resume can run',
      (tester) async {
    final client = _Client()
      ..answer = () => Future.error(
          const ForumRequestException(ForumRequestKind.rateLimited, 'fixture'));
    final job = scan(client, total: 1);
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(job.progress.state, ScanState.waiting);
    job.stop();
    await tester.pump(const Duration(minutes: 1));
    expect(client.calls, ['1']);
    client.answer = null;
    job.resume();
    await tester.pump();
    expect(client.calls, ['1', '1']);
    expect(job.progress.state, ScanState.done);
  });

  testWidgets('session changes reject both unsent work and late results',
      (tester) async {
    var current = false;
    final client = _Client();
    final job = scan(client, current: () => current);
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(client.calls, isEmpty);
    expect(job.progress.failure, ForumRequestKind.loginRequired);

    current = true;
    final gate = Completer<String>();
    client.answer = () => gate.future;
    final pending = scan(client, current: () => current);
    addTearDown(pending.dispose);
    pending.start();
    await tester.pump();
    current = false;
    gate.complete('private stale response');
    await tester.pump();
    expect(pending.hits, isEmpty);
    expect(pending.progress.failure, ForumRequestKind.loginRequired);
    expect(client.calls, ['1']);
  });

  testWidgets('hits and unresolved share one cap, including loaded seeds',
      (tester) async {
    final client = _Client();
    final job = PageFullScan<int>(
      client: client,
      isCurrentSession: () => true,
      maxResults: 3,
      loaded: const [
        ScanPage(page: 1, totalPages: 3, hasMore: true, hits: [1, 2]),
      ],
      readPage: (page, request) async {
        await request.getOnce('$page');
        return ScanPage(
            page: page, totalPages: 3, hasMore: true, unresolved: [3, 4, 5]);
      },
    );
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    job.start();
    await tester.pump();
    expect(job.hits, [1, 2]);
    expect(job.unresolved, [3]);
    expect(job.progress.capped, isTrue);
    expect(job.progress.state, ScanState.stopped);
    expect(job.progress.canResume, isFalse);
    job.resume();
    await tester.pump();
    expect(client.calls, ['2']);
  });

  testWidgets(
      'partial seeds retain known hits while pending metadata shares the cap',
      (tester) async {
    final client = _Client();
    final gate = Completer<void>();
    final job = PageFullScan<int>(
      client: client,
      isCurrentSession: () => true,
      initialHits: const [1, 2],
      initialPending: 2,
      maxResults: 3,
      readPage: (page, request) async {
        request.setPending(1);
        await gate.future;
        return ScanPage(page: page, hasMore: false, hits: [3, 4]);
      },
    );
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    var notifications = 0;
    job.addListener(() => notifications++);
    expect(job.hits, [1, 2]);
    expect(job.progress.pending, 2);
    job.start();
    await tester.pump();
    expect(job.progress.pending, 1);
    expect(notifications, 2,
        reason: 'one metadata-stage notification, not one for every row');
    gate.complete();
    await tester.pump();
    expect(job.hits, [1, 2, 3]);
    expect(job.progress.pending, 0);
    expect(job.progress.capped, isTrue);
    expect(job.progress.canResume, isFalse);
    expect(notifications, 3);
  });

  testWidgets(
      'metadata discovered after a list response is pushed to observers',
      (tester) async {
    final list = Completer<String>();
    final metadata = Completer<String>();
    final client = _Client();
    client.answer =
        () => client.calls.last == 'list' ? list.future : metadata.future;
    late final PageFullScan<int> job;
    job = PageFullScan<int>(
      client: client,
      isCurrentSession: () => true,
      readPage: (page, request) async {
        await request.getOnce('list');
        request.setPending(2);
        await request.getOnce('metadata');
        request.setPending(1);
        job.retain(request, hits: [1]);
        return ScanPage(page: page, hasMore: false);
      },
    );
    addTearDown(() => client.close(force: true));
    addTearDown(() {
      if (!list.isCompleted) list.complete('disposed list');
      if (!metadata.isCompleted) metadata.complete('disposed metadata');
    });
    addTearDown(job.dispose);
    final observed = <ScanProgress>[];
    job.addListener(() => observed.add(job.progress));
    job.start();
    await tester.pump();
    expect(observed.every((progress) => progress.pending == 0), isTrue);
    list.complete('list');
    await tester.pump();
    expect(observed.last.pending, 2,
        reason: 'the listener, not a pull of the getter, sees the new work');
    expect(client.calls, ['list', 'metadata']);
    metadata.complete('title');
    await tester.pump();
    expect(observed.where((progress) => progress.pending > 0), hasLength(1));
    expect(observed.length, lessThanOrEqualTo(4));
    expect(job.hits, [1]);
    expect(job.progress.state, ScanState.done);
    expect(client.peak, 1);
  });

  testWidgets('retaining results cannot cross active scan owners',
      (tester) async {
    final client = _Client();
    final held = Completer<void>();
    final first = PageFullScan<int>(
      client: client,
      isCurrentSession: () => true,
      readPage: (page, request) async {
        await held.future;
        return ScanPage(page: page, hasMore: false);
      },
    );
    var calls = 0;
    final second = PageFullScan<int>(
      client: client,
      isCurrentSession: () => true,
      readPage: (page, request) async {
        if (++calls > 1)
          throw StateError('must not restart a failed owner check');
        first.retain(request, hits: [9]);
        return ScanPage(page: page, hasMore: false);
      },
    );
    addTearDown(() => client.close(force: true));
    addTearDown(() {
      if (!held.isCompleted) held.complete();
    });
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.start();
    await tester.pump();
    second.start();
    await tester.pump();
    expect(second.progress.state, ScanState.failed);
    expect(second.progress.failure, ForumRequestKind.invalidInput);
    expect(first.hits, isEmpty);
    expect(calls, 1);
    held.complete();
    await tester.pump();
    expect(first.progress.state, ScanState.done);
    expect(first.hits, isEmpty);
  });

  testWidgets(
      'dispose never notifies or starts another page after a late reply',
      (tester) async {
    final gate = Completer<String>();
    final client = _Client()..answer = () => gate.future;
    final job = scan(client);
    addTearDown(() => client.close(force: true));
    var notifications = 0;
    job.addListener(() => notifications++);
    job.start();
    await tester.pump();
    job.dispose();
    final before = notifications;
    gate.complete('late');
    await tester.pump();
    expect(notifications, before);
    expect(client.calls, ['1']);
    expect(job.hits, isEmpty);
  });

  testWidgets('a listener can stop before the first dispatch', (tester) async {
    final client = _Client();
    final job = scan(client);
    addTearDown(() => client.close(force: true));
    addTearDown(job.dispose);
    job.addListener(() {
      if (job.progress.state == ScanState.running) job.stop();
    });
    job.start();
    await tester.pump();
    expect(client.calls, isEmpty);
    expect(job.progress.state, ScanState.stopped);
  });
}
