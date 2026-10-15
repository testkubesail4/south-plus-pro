import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';

void main() {
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
