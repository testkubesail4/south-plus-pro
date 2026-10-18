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

    for (final (path, expectedRequests) in [('no-location', 1), ('loop', 6)]) {
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
      expect(job.progress.failure, ForumRequestKind.invalidInput);
      expect(job.progress.canResume, isFalse);
      expect(hits.where((hit) => hit == '/$path'), hasLength(expectedRequests),
          reason: 'invalid redirects must not restart a scan retry round');
    }
  });
}
