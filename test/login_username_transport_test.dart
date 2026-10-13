import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _LocalClient extends ForumClient {
  _LocalClient(this.origin, HttpClient transport)
      : super(httpClient: transport);
  final Uri origin;
  @override
  Uri get baseUri => origin;
}

class _TraceOutput implements Stdout {
  final text = StringBuffer();
  @override
  void writeln([Object? object = '']) => text.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late HttpClient transport;
  late ForumClient client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = HttpOverrides.runWithHttpOverrides(
        HttpClient.new, _RealHttpOverrides());
    client =
        _LocalClient(Uri.parse('http://127.0.0.1:${server.port}/'), transport);
  });
  tearDown(() async {
    transport.close(force: true);
    await server.close(force: true);
  });

  for (final redirect in ['foreign', 'userinfo', 'chained-foreign']) {
    test('identity GET refuses $redirect redirects before following', () async {
      final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => foreign.close(force: true));
      var foreignHits = 0;
      var unsafeLocalHits = 0;
      foreign.listen((request) async {
        foreignHits++;
        request.response
            .write('<input name="sendtoname" value="fixture-foreign">');
        await request.response.close();
      });
      server.listen((request) async {
        if (request.uri.path == '/unsafe') {
          unsafeLocalHits++;
          request.response
              .write('<input name="sendtoname" value="fixture-unsafe">');
        } else {
          final next = redirect == 'chained-foreign' &&
                  request.uri.path == '/sendemail.php'
              ? '/u.php'
              : redirect == 'userinfo'
                  ? 'http://fixture-user@127.0.0.1:${server.port}/unsafe'
                  : 'http://127.0.0.1:${foreign.port}/sendemail.php?uid-901.html';
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, next);
        }
        await request.response.close();
      });
      await expectLater(client.getOnce('sendemail.php?uid-901.html'),
          throwsA(isA<ForumRequestException>()));
      expect(foreignHits, 0);
      expect(unsafeLocalHits, 0);
    });
  }

  for (final (status, kind) in [
    (401, ForumRequestKind.loginRequired),
    (403, ForumRequestKind.forbidden),
    (429, ForumRequestKind.rateLimited),
    (500, ForumRequestKind.server),
    (404, ForumRequestKind.server),
  ]) {
    test('identity GET retains the failure for HTTP $status', () async {
      server.listen((request) async {
        request.response.statusCode = status;
        request.response
            .write('<input name="sendtoname" value="fixture-invalid-status">');
        await request.response.close();
      });
      await expectLater(
          client.getOnce('sendemail.php?uid-901.html'),
          throwsA(isA<ForumRequestException>()
              .having((error) => error.kind, 'kind', kind)));
    });
  }

  test('identity trace stays private after a same-origin redirect', () async {
    server.listen((request) async {
      if (request.uri.path == '/sendemail.php') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader,
            '/u.php?action=tasks&fixture=fixture-query-canary');
      } else {
        request.response
            .write('<input name="sendtoname" value="fixture-name-canary">');
      }
      await request.response.close();
    });
    final output = _TraceOutput();
    await IOOverrides.runZoned(
      () => client.getOnce('sendemail.php?uid-909090901.html'),
      stdout: () => output,
    );
    final trace = output.text.toString();
    expect(trace, contains('GET sendemail.php'));
    expect(trace, isNot(contains('909090901')));
    expect(trace, isNot(contains('canary')));
  }, skip: !ForumTraceLogger.enabled);
}
