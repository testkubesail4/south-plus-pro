import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

const _category = ForumCategory(name: 'f42', slug: 'f42');
const _failures = [
  ('没有权限', ForumRequestKind.forbidden),
  ('请先登录', ForumRequestKind.loginRequired),
  ('请求过于频繁', ForumRequestKind.rateLimited),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in ['wall', 'sticky', 'child-only']) {
    test('$mode neutral data control remains readable', () async {
      final page = await ForumRepository(
              client: _BodyClient(_page(mode, 'Fixture title')))
          .fetchBoardThreadPage(_category);
      expect(page.boardName, 'Fixture board');
      expect(mode == 'child-only' ? page.subBoards.length : page.threads.length,
          1);
    });
    for (final (phrase, kind) in _failures) {
      test('$mode trusted last-thread title $kind is user data', () async {
        final page =
            await ForumRepository(client: _BodyClient(_page(mode, phrase)))
                .fetchBoardThreadPage(_category);
        expect(page.boardName, 'Fixture board');
        if (mode == 'child-only') {
          expect(page.subBoards.single.lastPostTitle, phrase);
        } else {
          expect(page.threads.single.title, phrase);
        }
      });
      test('$mode warning outside the trusted anchor still rejects $kind',
          () async {
        await expectLater(
          ForumRepository(
                  client: _BodyClient(
                      _page(mode, 'Fixture title', warning: phrase)))
              .fetchBoardThreadPage(_category),
          _throwsKind(kind),
        );
      });
    }
  }
  for (final href in [
    'https://example.invalid/read.php?tid-701.html',
    'read.php?tid-fixture.html',
    'notice.php?fid-42.html',
  ]) {
    test('untrusted or non-thread title anchors remain error context: $href',
        () async {
      final response =
          _page('wall', '没有权限').replaceAll('read.php?tid-701.html', href);
      await expectLater(
          ForumRepository(client: _BodyClient(response))
              .fetchBoardThreadPage(_category),
          _throwsKind(ForumRequestKind.forbidden));
    });
  }
  for (final (phrase, kind) in _failures) {
    test('standalone error page still rejects $kind', () async {
      await expectLater(
        ForumRepository(
                client: _BodyClient('<html><body>$phrase</body></html>'))
            .fetchBoardThreadPage(_category),
        _throwsKind(kind),
      );
    });
  }

  for (final once in [false, true]) {
    test(
        'real ${once ? 'getOnce' : 'board loader'} makes one request for a valid rate-phrase title',
        () async {
      await _withServer((client, hits) async {
        if (once) {
          expect(await client.getOnce('thread_new.php?fid-42.html'),
              contains('请求过于频繁'));
        } else {
          final page = await ForumRepository(client: client)
              .fetchBoardThreadPage(_category);
          expect(page.threads.single.title, '请求过于频繁');
        }
        expect(hits(), 1);
      }, _page('wall', '请求过于频繁'));
    });
  }
  test('real get preserves one retry for a standalone rate-limited body',
      () async {
    await _withServer((client, hits) async {
      expect(await client.get('thread_new.php?fid-42.html'), '请求过于频繁');
      expect(hits(), 2);
    }, '请求过于频繁');
  });
  test('real getOnce retains HTTP 429 classification without an implicit retry',
      () async {
    await _withServer((client, hits) async {
      await expectLater(client.getOnce('thread_new.php?fid-42.html'),
          _throwsKind(ForumRequestKind.rateLimited));
      expect(hits(), 1);
    }, '请求过于频繁', status: 429);
  });
}

Matcher _throwsKind(ForumRequestKind kind) => throwsA(
    isA<ForumRequestException>().having((error) => error.kind, 'kind', kind));

String _page(String mode, String title, {String warning = ''}) {
  final body = switch (mode) {
    'wall' => '''<ul class="stream"><li class="dcsns-li">
      <span class="section-title"><a href="read.php?tid-701.html">$title</a></span>
      <span class="server-warning">$warning</span></li></ul>''',
    'sticky' => '''<table id="ajaxtable"><tr class="tr3">
      <td><h3><a href="read.php?tid-701.html">$title</a></h3>
        <img src="images/headtopic_1.gif">$warning</td><td>1 / 10</td></tr></table>''',
    _ =>
      '''<table><tr><td>子版块</td></tr><tr><td>论坛</td><td>文章</td><td>最后发表</td></tr>
      <tr><th><h3><a href="thread.php?fid-43.html">Fixture child</a></h3></th><td>12</td>
        <th><a href="read.php?tid-701.html">$title</a>$warning</th></tr></table>''',
  };
  return '''<html><body><div id="breadcrumbs">
    <a href="thread.php?fid-42.html">Fixture board</a></div>$body</body></html>''';
}

class _BodyClient extends ForumClient {
  _BodyClient(this.body);
  final String body;
  @override
  Future<String> get(String path) async => body;
  @override
  Future<String> getOnce(String path) async => body;
}

class _RealHttpOverrides extends HttpOverrides {}

class _LocalClient extends ForumClient {
  _LocalClient(this.origin, HttpClient transport, DateTime Function() clock,
      Future<void> Function(Duration) delay)
      : super(httpClient: transport, clock: clock, delay: delay);
  final Uri origin;
  @override
  Uri get baseUri => origin;
}

Future<void> _withServer(
    Future<void> Function(ForumClient client, int Function() hits) run,
    String body,
    {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final transport =
      HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttpOverrides());
  var count = 0;
  server.listen((request) async {
    count++;
    request.response.statusCode = status;
    request.response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    request.response.write(body);
    await request.response.close();
  });
  var now = DateTime.utc(2020);
  final client = _LocalClient(
      Uri.parse('http://127.0.0.1:${server.port}/'), transport, () => now,
      (duration) async {
    now = now.add(duration);
  });
  try {
    await run(client, () => count);
  } finally {
    transport.close(force: true);
    await server.close(force: true);
  }
}
