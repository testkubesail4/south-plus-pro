import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';

class _RealHttp extends HttpOverrides {}

class _Client extends ForumClient {
  _Client(
      this.baseUri, HttpClient transport, Future<void> Function(Duration) delay)
      : super(httpClient: transport, delay: delay);
  @override
  final Uri baseUri;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guarded reads revoke a queued dispatch and never retry invalid pages',
      () async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport =
        HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
    final hits = <String>[];
    var foreignHits = 0;
    final redirectTargets = [
      '/job.php?action=buytopic&tid=701&pid=tpc&verify=fixture',
      '/u.php?action-favor-job-deltype-type-1-uid-901-verify-fixture.html',
      '/profile.php?action=modify',
      '/thread_new.php?fid=221&job=clear',
      '/thread_new.php?fid=221&fid=222',
      '/thread_new.php?fid=221#fragment',
      '/thread_new.php?fid=invalid',
      '/thread_new.php',
      'http://fixture@127.0.0.1:${server.port}/thread_new.php?fid=221',
      'http://127.0.0.1:${foreign.port}/thread_new.php?fid=221',
      'http://127.0.0.1:${foreign.port}/login.php',
    ];
    foreign.listen((request) async {
      foreignHits++;
      request.response.write('must not read');
      await request.response.close();
    });
    server.listen((request) async {
      hits.add(request.uri.path);
      if (request.uri.path == '/missing') {
        request.response.statusCode = 404;
      } else if (request.uri.path == '/limited') {
        request.response.statusCode = 429;
      } else if (request.uri.path == '/no-location') {
        request.response.statusCode = 302;
      } else if (request.uri.path == '/loop') {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader, '/loop');
      } else if (request.uri.path == '/need-login') {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader, '/login.php');
      } else if (request.uri.path == '/safety') {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader,
            redirectTargets[int.parse(request.uri.queryParameters['index']!)]);
      } else if (request.uri.path == '/thread.php') {
        request.response.statusCode = 302;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/thread_new.php?fid=221');
      } else if (request.uri.path == '/redirect') {
        request.response.statusCode = 302;
        request.response.headers.set(HttpHeaders.locationHeader,
            'http://127.0.0.1:${foreign.port}/private');
      }
      request.response.write('fixture');
      await request.response.close();
    });
    Completer<void>? gate;
    final waiting = Completer<void>();
    final client =
        _Client(Uri.http('127.0.0.1:${server.port}', '/'), transport, (_) {
      final pending = gate;
      if (pending == null) return Future.value();
      if (!waiting.isCompleted) waiting.complete();
      return pending.future;
    });
    addTearDown(() async {
      transport.close(force: true);
      await server.close(force: true);
      await foreign.close(force: true);
    });
    var current = true;
    void check() {
      if (!current) {
        throw const ForumRequestException(
            ForumRequestKind.loginRequired, 'stale');
      }
    }

    await client.getOnceGuarded('prime', requireCurrentSession: check);
    gate = Completer<void>();
    final rejected = expectLater(
        client.getOnceGuarded('queued', requireCurrentSession: check),
        throwsA(isA<ForumRequestException>()
            .having((e) => e.kind, 'kind', ForumRequestKind.loginRequired)));
    await waiting.future;
    current = false;
    gate.complete();
    await rejected;
    expect(hits, ['/prime']);

    gate = null;
    current = true;
    for (final (path, kind) in [
      ('missing', ForumRequestKind.invalidInput),
      ('limited', ForumRequestKind.rateLimited),
      ('redirect', ForumRequestKind.invalidInput),
    ]) {
      await expectLater(
          client.getOnceGuarded(path, requireCurrentSession: check),
          throwsA(isA<ForumRequestException>()
              .having((e) => e.kind, 'kind', kind)));
    }
    expect(hits, ['/prime', '/missing', '/limited', '/redirect']);
    expect(foreignHits, 0);

    for (var index = 0; index < redirectTargets.length; index++) {
      for (final policy in ForumReadRedirectPolicy.values) {
        Object? failure;
        try {
          await client.getOnceGuarded('safety?index=$index',
              requireCurrentSession: check, redirectPolicy: policy);
        } catch (error) {
          failure = error;
        }
        expect(
            hits.where({
              '/job.php',
              '/u.php',
              '/profile.php',
              '/thread_new.php',
              '/login.php'
            }.contains),
            isEmpty,
            reason:
                '${policy.name}: ${redirectTargets[index]} must receive zero requests');
        expect(
            failure,
            isA<ForumRequestException>().having(
                (error) => error.kind, 'kind', ForumRequestKind.invalidInput));
      }
    }
    expect(foreignHits, 0);

    for (final (path, failure) in [
      ('no-location', ForumRequestKind.invalidInput),
      ('loop', ForumRequestKind.invalidInput),
      ('need-login', ForumRequestKind.loginRequired),
    ]) {
      final finished = Completer<void>();
      final job = PageFullScan<int>(
        client: client,
        isCurrentSession: () => true,
        readPage: (page, request) async {
          await request.getOnce(path);
          return ScanPage(page: page, hasMore: false);
        },
      );
      job.addListener(() {
        if (job.progress.state == ScanState.failed && !finished.isCompleted) {
          finished.complete();
        }
      });
      addTearDown(job.dispose);
      job.start();
      await finished.future.timeout(const Duration(seconds: 2));
      expect(job.progress.failure, failure);
      expect(job.progress.canResume, isFalse);
      expect(hits.where((hit) => hit == '/$path'), hasLength(1),
          reason: 'redirects stop at the first response, without retry');
    }

    expect(await client.getOnce('thread.php?fid-222'), 'fixture',
        reason: 'ordinary GET keeps following read redirects');
    await expectLater(
        client.getOnceGuarded('thread.php?fid-222',
            requireCurrentSession: check),
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.invalidInput)));
    expect(
        await client.getOnceGuarded('thread.php?fid-222',
            requireCurrentSession: check,
            redirectPolicy: ForumReadRedirectPolicy.board),
        'fixture');
    expect(hits.where((hit) => hit == '/thread_new.php'), hasLength(2),
        reason: 'only the ordinary GET and explicit board policy follow');
  });
}
