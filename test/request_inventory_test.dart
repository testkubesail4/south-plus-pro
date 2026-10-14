import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';

const _directory = '''<table>
<tr><th><h2>Fixture section</h2></th></tr>
<tr><th><h3><a href="thread.php?fid-901.html">Fixture board</a></h3></th>
<td>1 / 2</td></tr></table>''';
const _simple = '''<a href="read.php?tid-900001.html">Fixture discussion</a>
$_directory''';
const _desktop = '<a href="u.php">Fixture account</a>$_directory';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
        ForumNetworkSetupStore.completedKey: true,
      }));

  for (final signedIn in [false, true]) {
    testWidgets('${signedIn ? 'signed-in' : 'guest'} startup request inventory',
        (tester) async {
      if (signedIn) {
        await ForumSessionStore().saveCookies({
          'fixture': const ForumStoredCookie(
            name: 'fixture_winduser',
            value: 'synthetic-session',
            domain: 'south-plus.net',
            path: '/',
          ),
        });
      }
      final transport = _InventoryTransport({
        '/simple/index.php': _simple,
        '/index.php': _desktop,
      });
      final repository = _repository(transport);
      await tester
          .pumpWidget(MaterialApp(home: SessionGate(repository: repository)));
      await tester.pumpAndSettle();
      expect(find.text('Fixture discussion'), findsOneWidget);
      expect(transport.hits, [
        if (signedIn) 'GET /index.php',
        'GET /simple/index.php',
        'GET /index.php',
      ]);
      // Rebuilding the shell must not start another fetch.
      await tester.pump();
      expect(transport.hits.length, signedIn ? 3 : 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('home script fallback and explicit revisits request inventory',
      () async {
    final transport = _InventoryTransport({
      '/simple/index.php':
          '<div class="carousel-item active"><script src="/fixture-latest.js"></script></div>$_directory',
      '/fixture-latest.js':
          '''document.write("<a href='read.php?tid-900001.html'>Fixture discussion</a>");''',
      '/index.php': _desktop,
    });
    final repository = _repository(transport);
    for (var visit = 0; visit < 2; visit++) {
      expect((await repository.fetchHome()).latest.single.title,
          'Fixture discussion');
    }
    expect(transport.hits, [
      'GET /simple/index.php',
      'GET /fixture-latest.js',
      'GET /index.php',
      'GET /simple/index.php',
      'GET /fixture-latest.js',
      'GET /index.php',
    ]);
  });

  test('board page visit requests only its own page', () async {
    final transport = _InventoryTransport({
      '/thread_new.php?fid-901-orderway-lastpost-asc-DESC-page-1.html': '''
<div id="breadcrumbs"><a href="thread.php?fid-901.html">Fixture board</a></div>
<ul class="stream"><li class="dcsns-li"><span class="section-title">
<a href="read.php?tid-900001.html">Fixture discussion</a></span></li></ul>''',
    });
    final page = await _repository(transport).fetchBoardThreadPage(
      const ForumCategory(name: 'Fixture board', slug: 'f901'),
    );
    expect(page.threads.single.title, 'Fixture discussion');
    expect(transport.hits, [
      'GET /thread_new.php?fid-901-orderway-lastpost-asc-DESC-page-1.html',
    ]);
  });
}

ForumRepository _repository(_InventoryTransport transport) => ForumRepository(
      client: ForumClient(
        httpClient: transport,
        delay: (_) async {},
      ),
    );

// An injected SDK transport exercises repository + client without DNS or sockets.
class _InventoryTransport implements HttpClient {
  _InventoryTransport(this.responses);
  final Map<String, String> responses;
  final hits = <String>[];

  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final body = responses[path];
    if (body == null) throw StateError('Unscripted request: $path');
    hits.add('GET $path');
    return _Request(uri, body);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.body);
  @override
  final Uri uri;
  final String body;
  @override
  final HttpHeaders headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => _Response(body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  List<String>? operator [](String name) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body);
  final String body;
  @override
  int get statusCode => HttpStatus.ok;
  @override
  final HttpHeaders headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(utf8.encode(body)).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
