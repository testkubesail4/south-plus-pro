import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  for (final viaSameOrigin in [false, true]) {
    test(
        'blocking refuses a foreign origin before contacting it (via same origin: $viaSameOrigin)',
        () async {
      final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => foreign.close(force: true));
      addTearDown(() => origin.close(force: true));
      var foreignHits = 0;
      foreign.listen((request) async {
        foreignHits++;
        await request.drain<void>();
        request.response
            .write('<ajax><![CDATA[{"version":"3.1","blist":{}}]]></ajax>');
        await request.response.close();
      });
      final originPaths = <String>[];
      origin.listen((request) async {
        await request.drain<void>();
        originPaths.add(request.uri.path);
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
            HttpHeaders.locationHeader,
            viaSameOrigin && request.uri.path == '/pw_ajax.php'
                ? '/followup'
                : 'http://127.0.0.1:${foreign.port}/foreign-config');
        await request.response.close();
      });
      final client = _LocalClient(Uri.http('127.0.0.1:${origin.port}', '/'));
      addTearDown(() => client.close(force: true));
      await expectLater(
          client.post(
              'pw_ajax.php?action=getblocklist&verify=TEST1234', const {}),
          throwsA(isA<ForumRequestException>()
              .having((error) => error.kind, 'kind', ForumRequestKind.server)));
      expect(foreignHits, 0);
      expect(originPaths, ['/pw_ajax.php', if (viaSameOrigin) '/followup']);
    });
  }

  test('blocking HTTP traces hide tokens and rule payloads across redirects',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/pw_ajax.php') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader,
            '/followup?h_name-tasks&verify=fixture-token-canary');
      } else {
        request.response
            .write('<ajax><![CDATA[fixture-response-canary]]></ajax>');
      }
      await request.response.close();
    });
    final client = _LocalClient(Uri.http('127.0.0.1:${server.port}', '/'));
    addTearDown(() => client.close(force: true));
    final output = _CapturedStdout();
    await IOOverrides.runZoned(() async {
      await client.post(
          'pw_ajax.php?action=updateblocklist&verify=fixture-token-canary', {
        'blocklistconfig':
            '{"name":"fixture-name-canary","uid":"fixture-uid-canary"}'
      });
    }, stdout: () => output);
    final trace = output.buffer.toString();
    expect(trace, contains('POST pw_ajax.php (blocking)'));
    expect(trace, contains('GET pw_ajax.php (blocking)'));
    expect(trace, isNot(contains('canary')));
  },
      skip: !ForumTraceLogger.enabled
          ? 'Run with --dart-define=FORUM_TRACE=true'
          : false);
}

class _LocalClient extends ForumClient {
  _LocalClient(this.baseUri)
      : super(httpClient: HttpClient(), delay: (_) async {});

  @override
  final Uri baseUri;
  @override
  Future<void> restoreCookies() async {}
}

class _CapturedStdout implements Stdout {
  final buffer = StringBuffer();
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
