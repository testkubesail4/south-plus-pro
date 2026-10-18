import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';

const _simple = '''<div class="carousel-item active"><div>最新讨论</div>
<a href="read.php?tid-900.html">Native preview</a>
<script src="new.php?action=article&amp;order=2&amp;simple=1"></script></div>
<div class="carousel-item"><div>最新回复</div><script src="native-replies.js"></script></div>
<div class="carousel-item"><div>提问求物</div><script src="native-requests.js"></script></div>''';
const _directory = '''<table><tr><th><h2>Root</h2></th></tr>
<tr><th><h3><a href="thread.php?fid-6.html">Games</a></h3></th></tr>
<tr><th><h3><a href="thread.php?fid-36.html">Books</a></h3></th></tr></table>''';

String _feed(String title, {int count = 10}) => List.generate(
        count,
        (index) =>
            '''document.write("<a href='read.php?tid-${9000 + index}.html'>$title $index</a> <a href='u.php?uid-${index + 1}.html'>(Author $index)</a> <font>(回复：$index)</font> <a href='thread.php?fid-6.html'>(Feed board)</a><br>");''')
    .join('\n');

String _board(String fid, {List<String> titles = const []}) => '''
<div id="breadcrumbs"><a href="thread.php?fid-13.html">Parent</a>
<a href="thread.php?fid-$fid.html">Board $fid</a>
<a href="thread.php?fid-$fid-page-1.html">[点击进入列表模式]</a></div>
<table id="ajaxtable"><tr class="tr3"><td><h3>
<a href="read.php?tid-1.html">Sticky, never an ordinary quick item</a></h3>
<img src="images/headtopic_1.gif"></td><td>0 / 0</td></tr></table>
<ul class="stream">${[
      for (var index = 0; index < titles.length; index++)
        '''
<li class="dcsns-li"><span class="section-title"><a href="read.php?tid-${700 + index}.html">${titles[index]}</a></span>
<span class="section-text">回复/人气：$index/20</span>
<span class="section-intro"><a class="bl" href="u.php?uid-${index + 1}.html">Author $index</a>2026-01-01</span></li>'''
    ].join()}</ul>''';

Future<void> _sources(
        {String fid = '6',
        String? path = 'Root / Games',
        QuickOrder order = QuickOrder.posted,
        String? account}) =>
    HomeReadingPreferences.saveQuickSources([
      HomeQuickSource(
          kind: HomeQuickSourceKind.board,
          fid: fid,
          boardPath: path,
          order: order),
      const HomeQuickSource(),
      const HomeQuickSource(kind: HomeQuickSourceKind.hidden),
    ], account: account);

class _Client extends ForumClient {
  final paths = <String>[];
  Future<String> Function(String)? response;

  @override
  Future<void> clearSession() async {}

  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy =
          ForumReadRedirectPolicy.none}) async {
    requireCurrentSession();
    paths.add(path);
    final String body;
    if (path == 'simple/index.php') {
      body = _simple;
    } else if (path == 'index.php') {
      body = _directory;
    } else {
      body = await response!(path);
    }
    requireCurrentSession();
    return body;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'configured sources own their snapshot and request bounded feed metadata',
      () async {
    await HomeReadingPreferences.saveQuickSources(const [
      HomeQuickSource(
          kind: HomeQuickSourceKind.board,
          fid: '6',
          boardPath: 'Saved / Old name'),
      HomeQuickSource(
          kind: HomeQuickSourceKind.board,
          fid: '36',
          order: QuickOrder.replied),
      HomeQuickSource(kind: HomeQuickSourceKind.hidden),
    ]);
    final client = _Client()
      ..response = (path) async =>
          _feed('Feed ${Uri.parse(path).queryParameters['fidin']}');
    final repo = ForumRepository(client: client);
    final home = await repo.fetchHome();
    expect(home.quickLists.map((list) => list.title), ['Games 新帖', 'Books 回复']);
    expect(client.paths, ['simple/index.php', 'index.php'],
        reason: 'custom slots do not eagerly fetch the native feed');
    final first = home.quickLists.first;
    final result = await Future.wait(
        [repo.fetchQuickList(first), repo.fetchQuickList(first)]);
    expect(result.first, hasLength(8));
    expect(result.first[3].author, 'Author 3');
    expect(result.first[3].section, 'Feed board');
    await repo.fetchQuickList(first);
    await repo.fetchQuickList(home.quickLists.last);
    final queries = client.paths
        .skip(2)
        .map((path) => Uri.parse(path).queryParameters)
        .toList();
    expect(queries.map((query) => (query['fidin'], query['order'])),
        [('6', '2'), ('36', '1')]);
    for (final query in queries) {
      expect(query['num'], '8');
      expect(query['length'], '120');
      for (final flag in ['author', 'postdate', 'replies', 'fname', 'simple']) {
        expect(query[flag], '1');
      }
    }
    await expectLater(
        repo.fetchQuickList(ForumQuickList(
            title: first.title,
            source: first.source,
            scriptUrl: first.scriptUrl)),
        throwsA(isA<ForumRepositoryException>()));
    expect(client.paths, hasLength(4), reason: 'no forged list dispatch');
  });

  test(
      'empty feeds fall back to ordinary streams in both orders without recent-board writes',
      () async {
    await HomeReadingPreferences.saveQuickSources(const [
      HomeQuickSource(kind: HomeQuickSourceKind.board, fid: '6'),
      HomeQuickSource(
          kind: HomeQuickSourceKind.board,
          fid: '36',
          order: QuickOrder.replied),
      HomeQuickSource(kind: HomeQuickSourceKind.hidden),
    ]);
    final client = _Client()
      ..response = (path) async {
        if (path.startsWith('new.php')) return '';
        final fid = path.contains('fid-36-') ? '36' : '6';
        return _board(fid, titles: [
          '没有权限 请求过于频繁',
          for (var i = 1; i < 10; i++) 'ordinary $i'
        ]);
      };
    final repo = ForumRepository(client: client);
    final home = await repo.fetchHome();
    for (final list in home.quickLists) {
      final threads = await repo.fetchQuickList(list);
      expect(threads, hasLength(8));
      expect(threads.first.title, '没有权限 请求过于频繁');
      expect(threads.map((thread) => thread.title),
          isNot(contains('Sticky, never an ordinary quick item')));
    }
    expect(client.paths.where((path) => path.startsWith('thread_new.php')), [
      'thread_new.php?fid-6-orderway-postdate-asc-DESC-page-1.html',
      'thread_new.php?fid-36-orderway-lastpost-asc-DESC-page-1.html',
    ]);
    expect((await HomeReadingPreferences.load()).recentBoards, isEmpty);
  });

  test('wall aliases use canonical breadcrumbs and reapply the requested order',
      () async {
    await _sources(fid: '222');
    final loop = await _loopback((request) {
      if (request.uri.path == '/new.php') return;
      if (request.uri.query.contains('fid-222-')) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/thread_new.php?fid=221');
      } else {
        request.response.write(_board('221', titles: [
          request.uri.query == 'fid=221'
              ? 'wrong default order'
              : 'canonical posted order'
        ]));
      }
    });
    final home = await loop.repo.fetchHome();
    expect((await loop.repo.fetchQuickList(home.quickLists.first)).single.title,
        'canonical posted order');
    expect(loop.hits.where((path) => path.startsWith('/thread_new.php')), [
      '/thread_new.php?fid-222-orderway-postdate-asc-DESC-page-1.html',
      '/thread_new.php?fid=221',
      '/thread_new.php?fid-221-orderway-postdate-asc-DESC-page-1.html',
    ]);
  });

  for (final (location, kind) in [
    (
      '/job.php?action=buytopic&tid=1&pid=tpc&verify=fixture',
      ForumRequestKind.invalidInput
    ),
    ('/u.php?action=favor&job=deltype&type=1', ForumRequestKind.invalidInput),
    ('/thread_new.php?fid=221&action=delete', ForumRequestKind.invalidInput),
    ('/login.php', ForumRequestKind.loginRequired),
  ]) {
    test('board source redirect rejects $location before following', () async {
      await _sources(fid: '222');
      final loop = await _loopback((request) {
        if (request.uri.path == '/new.php') return;
        if (request.uri.query.contains('fid-222-')) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, location);
        } else {
          request.response.write('<body>must not be requested</body>');
        }
      });
      final home = await loop.repo.fetchHome();
      await expectLater(
          loop.repo.fetchQuickList(home.quickLists.first),
          throwsA(isA<ForumRequestException>()
              .having((error) => error.kind, 'kind', kind)));
      expect(loop.hits, isNot(contains(location)),
          reason: 'zero follow-up requests');
      expect(loop.hits, hasLength(4));
    });
  }

  for (final (label, body, failure) in [
    ('normal empty parent', _board('13'), null),
    (
      'invalid fid',
      '<title>您要访问的链接无效</title><div id="breadcrumbs"><a href="index.php">Home</a></div>',
      ForumRequestKind.invalidInput
    ),
    (
      'category redirect',
      '<title>综合交流</title><table><tr><th><h2>Category, not a board</h2></th></tr></table>',
      ForumRequestKind.invalidInput
    ),
    (
      'unrecognized template with retained navigation',
      _board('13').replaceFirst('<ul class="stream"></ul>', ''),
      ForumRequestKind.server
    ),
  ]) {
    test('board fallback distinguishes $label', () async {
      await _sources(fid: '13');
      final client = _Client()
        ..response = (path) async => path.startsWith('new.php') ? '' : body;
      final repo = ForumRepository(client: client);
      final home = await repo.fetchHome();
      final request = repo.fetchQuickList(home.quickLists.first);
      if (failure == null) {
        expect(await request, isEmpty);
      } else {
        await expectLater(
            request,
            throwsA(isA<ForumRequestException>()
                .having((e) => e.kind, 'kind', failure)));
      }
    });
  }

  for (final (body, kind) in [
    ('请先登录', ForumRequestKind.loginRequired),
    ('没有权限', ForumRequestKind.forbidden),
    ('论坛设置:刷新不要快于 1 秒', ForumRequestKind.rateLimited),
  ]) {
    for (final atFeed in [false, true]) {
      test(
          'quick source preserves ${kind.name} at ${atFeed ? 'feed' : 'board'} without retrying',
          () async {
        await _sources();
        final client = _Client()
          ..response = (path) async {
            if (path.startsWith('new.php'))
              return atFeed ? '<title>$body</title>' : '';
            return atFeed
                ? _board('6', titles: ['must not be fetched'])
                : '<title>$body</title>';
          };
        final repo = ForumRepository(client: client);
        final home = await repo.fetchHome();
        await expectLater(
            repo.fetchQuickList(home.quickLists.first),
            throwsA(isA<ForumRequestException>()
                .having((e) => e.kind, 'kind', kind)));
        expect(client.paths, hasLength(atFeed ? 3 : 4));
      });
    }
  }

  for (final change in ['source', 'session', 'layout/label/other-account']) {
    test('pending quick source checks $change before publishing or fallback',
        () async {
      await _sources();
      final requested = Completer<void>();
      final pending = Completer<String>();
      final client = _Client()
        ..response = (path) {
          if (path.startsWith('new.php')) {
            if (!requested.isCompleted) requested.complete();
            return pending.future;
          }
          return Future.value(_board('6', titles: ['obsolete fallback']));
        };
      final repo = ForumRepository(client: client);
      final home = await repo.fetchHome();
      final result = repo.fetchQuickList(home.quickLists.first);
      final rejected = change == 'layout/label/other-account'
          ? null
          : expectLater(result, throwsA(isA<ForumRepositoryException>()));
      await requested.future;
      if (change == 'source') {
        await _sources(fid: '36');
      } else if (change == 'session') {
        await repo.clearSession();
      } else {
        await HomeReadingPreferences.saveQuickRowCount(5);
        await HomeReadingPreferences.setCollapsed('board:42', true);
        await _sources(path: 'Renamed / Games');
        await _sources(fid: '36', account: 'another account');
      }
      pending.complete(
          change == 'layout/label/other-account' ? _feed('retained') : '');
      if (rejected != null) {
        await rejected;
      } else {
        expect(await result, hasLength(8));
        expect(await repo.fetchQuickList(home.quickLists.first), hasLength(8));
      }
      expect(client.paths, hasLength(3),
          reason: 'no obsolete fallback or unrelated reload');
    });
  }

  test('a source changed while paced never dispatches the old feed', () async {
    await _sources();
    final loop = await _loopback(
        (request) => request.response.write(_feed('must not leave')));
    final home = await loop.repo.fetchHome();
    loop.clock.hold = Completer<void>();
    final result = loop.repo.fetchQuickList(home.quickLists.first);
    final rejected =
        expectLater(result, throwsA(isA<ForumRepositoryException>()));
    await loop.clock.waiting.future;
    await _sources(fid: '36');
    loop.clock.hold!.complete();
    await rejected;
    expect(loop.hits, ['/simple/index.php', '/index.php']);
  });
}

Future<({ForumRepository repo, _Clock clock, List<String> hits})> _loopback(
    void Function(HttpRequest) serve) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final transport =
      HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
  final clock = _Clock();
  final client =
      _LocalClient(Uri.http('127.0.0.1:${server.port}', '/'), transport, clock);
  addTearDown(() async {
    transport.close(force: true);
    await server.close(force: true);
  });
  final hits = <String>[];
  server.listen((request) async {
    hits.add(request.uri.toString());
    request.response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    if (request.uri.path == '/simple/index.php') {
      request.response.write(_simple);
    } else if (request.uri.path == '/index.php') {
      request.response.write(_directory);
    } else {
      serve(request);
    }
    await request.response.close();
  });
  return (repo: ForumRepository(client: client), clock: clock, hits: hits);
}

class _RealHttp extends HttpOverrides {}

class _Clock {
  DateTime now = DateTime.utc(2020);
  Completer<void>? hold;
  final waiting = Completer<void>();
  Future<void> delay(Duration duration) async {
    if (hold != null) {
      waiting.complete();
      await hold!.future;
    }
    now = now.add(duration);
  }
}

class _LocalClient extends ForumClient {
  _LocalClient(this.baseUri, HttpClient transport, _Clock clock)
      : super(
            httpClient: transport, clock: () => clock.now, delay: clock.delay);
  @override
  final Uri baseUri;
}
