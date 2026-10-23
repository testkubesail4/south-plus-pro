import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

const _archive = [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 1, 2, 3];

class _RealHttpOverrides extends HttpOverrides {}

class _Clock {
  DateTime now = DateTime.utc(2020);
  final delays = <Duration>[];

  DateTime call() => now;

  Future<void> delay(Duration duration) async {
    delays.add(duration);
    now = now.add(duration);
  }
}

class _HoldClock {
  DateTime now = DateTime.utc(2020);
  final requested = <Duration>[];
  Completer<void>? pending;

  DateTime call() => now;

  Future<void> delay(Duration duration) {
    requested.add(duration);
    final done = Completer<void>();
    pending = done;
    return done.future.then((_) {
      now = now.add(duration);
    });
  }

  void elapse() {
    final gate = pending;
    pending = null;
    gate?.complete();
  }
}

class _LocalForumClient extends ForumClient {
  _LocalForumClient(
    this.origin,
    HttpClient transport, {
    required DateTime Function() now,
    required Future<void> Function(Duration duration) delay,
  }) : super(httpClient: transport, clock: now, delay: delay);

  final Uri origin;
  bool authenticated = false;

  @override
  bool get isLoggedIn => authenticated;

  @override
  Uri get baseUri => origin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late Directory directory;
  late HttpClient transport;
  late _Clock clock;
  late ForumClient client;
  late List<String> hits;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('forum_pace_');
    transport = HttpOverrides.runWithHttpOverrides(
      HttpClient.new,
      _RealHttpOverrides(),
    );
    clock = _Clock();
    client = _LocalForumClient(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      transport,
      now: clock.call,
      delay: clock.delay,
    );
    hits = [];
    server.listen((request) {
      hits.add('${request.method} ${request.uri.path}');
      final scripted = _scripted.removeAt(0);
      scripted(request);
    });
  });

  tearDown(() async {
    transport.close(force: true);
    client.close(force: true);
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  final scripts = <void Function(HttpRequest)>[];

  setUp(() {
    scripts.clear();
    _scripted = scripts;
  });

  test('forum HTTP starts, including redirects, stay at least 1s apart',
      () async {
    _scripted.addAll([
      _text('alpha'),
      _text('beta'),
      _bytes([1, 2, 3]),
      (request) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/attachment-file');
        request.response.close();
      },
      (request) {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(_archive);
        request.response.close();
      },
    ]);

    expect(await client.get('/read.php'), 'alpha');
    expect(await client.post('/post.php', const {'step': '2'}), 'beta');
    expect(await client.getBytes('/ck.php'), Uint8List.fromList([1, 2, 3]));
    final attachment = await client.downloadAttachment(
      'job.php?action-download-pid-tpc-tid-1-aid-2.html',
      directory: directory,
    );

    expect(await attachment.file.readAsBytes(), _archive);
    expect(hits, [
      'GET /read.php',
      'POST /post.php',
      'GET /ck.php',
      'GET /job.php',
      'GET /attachment-file',
    ]);
    expect(clock.delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 1),
      const Duration(seconds: 1),
      const Duration(seconds: 1),
    ]);
  });

  test('overlapping forum requests still start 1s apart', () async {
    _scripted.addAll([_text('one'), _text('two')]);
    await Future.wait([client.get('/one'), client.get('/two')]);
    expect(clock.delays, [const Duration(seconds: 1)]);
  });

  test('GET and POST redirects are followed once and stay paced', () async {
    _scripted.addAll([
      (request) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/landed');
        request.response.close();
      },
      _text('landed-get'),
      (request) {
        request.response.statusCode = HttpStatus.seeOther;
        request.response.headers.set(HttpHeaders.locationHeader, '/posted');
        request.response.close();
      },
      _text('landed-post'),
    ]);

    expect(await client.get('/start'), 'landed-get');
    expect(await client.post('/send', const {'step': '2'}), 'landed-post');
    expect(hits, [
      'GET /start',
      'GET /landed',
      'POST /send',
      'GET /posted',
    ]);
    expect(clock.delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 1),
      const Duration(seconds: 1),
    ]);
  });

  test('307 and 308 do not resend a POST', () async {
    for (final status in [
      HttpStatus.temporaryRedirect,
      HttpStatus.permanentRedirect,
    ]) {
      _scripted.add((request) {
        request.response.statusCode = status;
        request.response.headers.set(HttpHeaders.locationHeader, '/again');
        request.response.write('nope');
        request.response.close();
      });
      await expectLater(
        client.post('/send', const {'step': '2'}),
        throwsA(
          isA<ForumRequestException>().having(
            (error) => error.kind,
            'kind',
            ForumRequestKind.server,
          ),
        ),
      );
    }
    _scripted.addAll([
      (request) {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(HttpHeaders.locationHeader, '/landed-get');
        request.response.close();
      },
      _text('followed'),
    ]);
    expect(await client.get('/start-get'), 'followed');
    expect(hits.where((hit) => hit.contains('/again')), isEmpty);
    expect(hits, contains('GET /landed-get'));
  });

  test('a sleeping search rereads the deadline when cooldown is raised',
      () async {
    final held = _HoldClock();
    final paced = _LocalForumClient(
      client.baseUri,
      transport,
      now: held.call,
      delay: held.delay,
    );
    final releaseBody = Completer<void>();
    final arrivals = <DateTime>[];
    void record(HttpRequest request, String body) {
      arrivals.add(held.now);
      request.response.headers.contentType = ContentType.html;
      request.response.write(body);
      request.response.close();
    }

    _scripted.add((request) {
      arrivals.add(held.now);
      releaseBody.future.then((_) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<html><title>提示</title><body>刷新不要快于 9 秒</body></html>',
        );
        request.response.close();
      });
    });
    _scripted.add((request) {
      record(request, '<html></html>');
    });

    final first = paced.post('search.php', const {'keyword': '示例'});
    final second = paced.post('search.php', const {'keyword': '示例'});
    final firstResult = expectLater(
      first,
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.rateLimited,
        ),
      ),
    );
    await _until(
      () =>
          arrivals.length == 1 &&
          held.requested.contains(const Duration(milliseconds: 3334)),
    );
    releaseBody.complete();
    await _until(() => held.requested.contains(const Duration(seconds: 10)));
    expect(arrivals, hasLength(1));
    held.elapse();
    await _until(() => arrivals.length == 2);
    expect(
      arrivals[1].difference(arrivals[0]),
      greaterThanOrEqualTo(const Duration(seconds: 10)),
    );
    await firstResult;
    expect(await second, '<html></html>');
    paced.close();
  });

  test('slow connects still send at least 1s apart, including attachments',
      () async {
    final held = _HoldClock();
    final connects = <Completer<void>>[];
    transport.connectionFactory = (uri, proxyHost, proxyPort) async {
      final gate = Completer<void>();
      connects.add(gate);
      await gate.future;
      return Socket.startConnect(uri.host, uri.port);
    };
    final paced = _LocalForumClient(
      client.baseUri,
      transport,
      now: held.call,
      delay: held.delay,
    );
    final arrivals = <DateTime>[];
    for (var i = 0; i < 2; i++) {
      _scripted.add((request) {
        arrivals.add(held.now);
        if (request.uri.path == '/job.php') {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(_archive);
        } else {
          request.response.write('ok');
        }
        request.response.close();
      });
    }

    final page = paced.get('/a');
    final saved = paced.downloadAttachment(
      'job.php?action-download-pid-tpc-tid-1-aid-2.html',
      directory: directory,
    );
    await _until(() => connects.length == 2);
    expect(held.requested, isEmpty);
    for (final gate in connects) {
      gate.complete();
    }
    await _until(() => arrivals.length == 1 && held.requested.isNotEmpty);
    expect(held.requested.single, const Duration(seconds: 1));
    held.elapse();
    await _until(() => arrivals.length == 2);
    expect(
      arrivals[1].difference(arrivals[0]),
      greaterThanOrEqualTo(const Duration(seconds: 1)),
    );
    expect(await page, 'ok');
    expect(await (await saved).file.readAsBytes(), _archive);
    paced.close();
  });

  test('search.php starts stay at least 3334ms apart', () async {
    _scripted.addAll([
      _text('<html></html>'),
      _text('<html></html>'),
      _text('home'),
      _text('<html></html>'),
    ]);

    await client.get('search.php');
    await client.post('search.php?', const {'keyword': '示例'});
    await client.get('index.php');
    await client.get('search.php?step=2');

    expect(clock.delays, [
      const Duration(milliseconds: 3334),
      const Duration(seconds: 1),
      const Duration(milliseconds: 2334),
    ]);
  });

  test('a search cooldown is rateLimited and later searches wait 10s',
      () async {
    final elapsed = Stopwatch()..start();
    _scripted.addAll([
      _text(_searchForm),
      _text('<html><head><title>提示</title><body>刷新不要快于 9 秒</body></html>'),
      _text(_searchForm),
      _text(_oneResult),
    ]);
    final repository = ForumRepository(client: client);

    await expectLater(
      repository.searchThreads('示例主题'),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.rateLimited,
        ),
      ),
    );
    expect(hits.where((hit) => hit.startsWith('POST')), ['POST /search.php']);

    expect(await repository.searchThreads('示例主题'), hasLength(1));
    expect(
      elapsed.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: 'cooldown wait must use the injected delay',
    );
    expect(clock.delays, [
      const Duration(milliseconds: 3334),
      const Duration(seconds: 10),
      const Duration(seconds: 10),
    ]);
  });

  test('GET retries a cooldown once and POST never resubmits', () async {
    _scripted.addAll([
      _text('<html><body>刷新不要快于 3 秒</body></html>'),
      _text('page-ok'),
      _status(HttpStatus.internalServerError, 'down'),
      _text('<html><body>搜索间隔过短</body></html>'),
    ]);

    expect(await client.get('/index.php'), 'page-ok');
    expect(hits, ['GET /index.php', 'GET /index.php']);
    expect(clock.delays, [const Duration(seconds: 1)]);

    await expectLater(
      client.post('/post.php', const {'step': '2'}),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.server,
        ),
      ),
    );
    expect(hits.where((hit) => hit.contains('/post.php')), ['POST /post.php']);

    await expectLater(
      client.post('search.php', const {'keyword': '示例'}),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.rateLimited,
        ),
      ),
    );
    expect(
        hits.where((hit) => hit.contains('search.php')), ['POST /search.php']);
  });

  test('PM requests are paced but never retry, redirect, or accept non-200',
      () async {
    final failure = throwsA(isA<ForumRequestException>());
    _scripted.addAll([
      _status(HttpStatus.tooManyRequests, '刷新不要快于 3 秒'),
      _text('unexpected retry'),
    ]);
    await expectLater(
        client.getOnce('message.php?action-unread-mid-701-verify-fixture.html'),
        failure);
    expect(hits, ['GET /message.php']);
    _scripted.clear();
    _scripted.addAll([
      (request) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader,
            '/message.php?action-clear-verify-fixture.html');
        request.response.close();
      },
      _text('unexpected redirect'),
    ]);
    await expectLater(
      client.post('message.php', {
        'action': 'write',
        'touidmsg': '901',
        'msg_title': 'fixture-pm-title-canary',
        'atc_content': 'fixture-pm-body-canary',
        'verify': 'fixture-pm-token-canary',
      }),
      failure,
    );
    expect(hits, ['GET /message.php', 'POST /message.php']);
    _scripted.clear();
    _scripted.add(_status(HttpStatus.created, '操作完成'));
    await expectLater(client.getOnce('message.php?action=scout'), failure);
    expect(hits, ['GET /message.php', 'POST /message.php', 'GET /message.php']);
    expect(
        clock.delays, [const Duration(seconds: 1), const Duration(seconds: 1)]);
  });

  test('search GET cooldown retries once, then stays rateLimited', () async {
    _scripted.addAll([
      _text('<html><title>刷新不要快於 9 秒</title><body></body></html>'),
      _text('<html><body>请 8 秒后再搜索</body></html>'),
    ]);

    await expectLater(
      client.get('search.php'),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.rateLimited,
        ),
      ),
    );
    expect(hits, ['GET /search.php', 'GET /search.php']);
    expect(clock.delays, [const Duration(seconds: 10)]);
  });

  test(
      'searchThreads returns rows or an empty normal page, and classifies failures',
      () async {
    final repository = ForumRepository(client: client);

    _scripted.addAll([_text(_searchForm), _text(_oneResult)]);
    final found = await repository.searchThreads('示例主题');
    expect(found.single.title, '示例主题甲');

    _scripted.addAll([_text(_searchForm), _text(_zeroTotal)]);
    expect(await repository.searchThreads('示例主题'), isEmpty);

    _scripted.addAll([_text(_searchForm), _text(_resultWithoutRows)]);
    expect(await repository.searchThreads('示例主题'), isEmpty);

    _scripted.addAll([
      _text('<html><title>提示信息</title><body>请先登录后再继续</body></html>'),
    ]);
    await expectLater(
      repository.searchThreads('示例主题'),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.loginRequired,
        ),
      ),
    );

    _scripted.addAll([
      _text(_searchForm),
      _text(
        '<html><title>提示信息</title><body>您没有权限执行此操作'
        '<a href="read.php?tid-9.html">热门主题</a></body></html>',
      ),
    ]);
    await expectLater(
      repository.searchThreads('示例主题'),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.forbidden,
        ),
      ),
    );

    _scripted.addAll([
      _text(_searchForm),
      _status(HttpStatus.internalServerError, '<html><title>错误</title></html>'),
    ]);
    await expectLater(
      repository.searchThreads('示例主题'),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.server,
        ),
      ),
    );

    _scripted.add((request) {
      request.response.detachSocket().then((socket) => socket.destroy());
    });
    await expectLater(
      repository.searchThreads('示例主题'),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.network,
        ),
      ),
    );
  });

  for (final change in ['session', 'credentials']) {
    for (final phase in ['form read', 'paced send', 'response']) {
      test('reply rejects $change change during $phase', () async {
        const thread = ForumThread(
          title: 'Synthetic thread',
          url: 'https://south-plus.net/read.php?tid-100.html',
          replies: 0,
          section: 'Synthetic board',
        );
        final held = _HoldClock();
        client = _LocalForumClient(
          client.baseUri,
          transport,
          now: phase == 'paced send' ? held.call : clock.call,
          delay: phase == 'paced send' ? held.delay : clock.delay,
        )..authenticated = true;
        final repository = ForumRepository(client: client);
        final epoch = repository.sessionEpoch.value;
        final generation = client.credentialGeneration;
        final entered = Completer<void>();
        final release = Completer<void>();
        final bodies = <String>[];
        void respond(HttpRequest request, String body, bool hold) {
          if (hold) {
            entered.complete();
            release.future.then((_) => _text(body)(request));
          } else {
            _text(body)(request);
          }
        }

        _scripted.addAll([
          (request) => respond(request, _postForm, phase == 'form read'),
          (request) async {
            bodies.add(await utf8.decoder.bind(request).join());
            respond(
                request, '<html><body>发表成功</body></html>', phase == 'response');
          },
        ]);
        final reply = repository.submitReply(
            thread: thread,
            title: 'Synthetic subject',
            content: 'Private draft');
        final rejected = expectLater(
          reply,
          throwsA(isA<ForumRequestException>().having(
              (error) => error.kind, 'kind', ForumRequestKind.loginRequired)),
        );
        if (phase == 'paced send') {
          await _until(() => held.pending != null);
        } else {
          await entered.future;
        }
        if (change == 'session') {
          await repository.clearSession();
          expect(repository.sessionEpoch.value, epoch + 1);
        } else {
          await client.clearSession();
          expect(repository.sessionEpoch.value, epoch,
              reason:
                  'credential invalidation must not rely on an epoch change');
        }
        expect(client.isCredentialCurrent(generation), isFalse);
        if (phase == 'paced send') {
          held.elapse();
        } else {
          release.complete();
        }
        await rejected;
        expect(
            hits,
            phase == 'response'
                ? ['GET /read.php', 'POST /post.php']
                : ['GET /read.php']);
        expect(bodies, phase == 'response' ? hasLength(1) : isEmpty);
      });
    }
  }

  test(
      'compose uncertainty never retries while replies retain transport errors',
      () async {
    const category = ForumCategory(name: '版块甲', slug: 'f7');
    const thread = ForumThread(
      title: '示例主题甲',
      url: 'https://south-plus.net/read.php?tid-100.html',
      replies: 1,
      section: '版块甲',
    );
    (client as _LocalForumClient).authenticated = true;
    final repository = ForumRepository(client: client);

    final blank = await repository.submitThread(
      category: category,
      title: ' ',
      content: '正文',
    );
    expect(blank.success, isFalse);
    expect(hits, isEmpty);

    final blankReply = await repository.submitReply(
      thread: thread,
      title: '',
      content: ' ',
    );
    expect(blankReply.success, isFalse);
    expect(hits, isEmpty);

    _scripted.addAll([
      _text(_postForm),
      _text('<html><head><title>发帖完毕</title></head><body>发帖完毕</body></html>'),
    ]);
    final posted = await repository.submitThread(
      category: category,
      title: '示例标题',
      content: '示例正文',
    );
    expect(posted.success, isFalse);
    expect(posted.unconfirmed, isTrue);

    _scripted.addAll([
      _text(_postForm),
      _text('<html><head><title>认证码不正确</title></head></html>'),
    ]);
    final rejected = await repository.submitReply(
      thread: thread,
      title: '',
      content: '示例回复',
    );
    expect(rejected.success, isFalse);
    expect(rejected, isA<ReplyResult>());

    _scripted.add(
      _text('<html><title>提示信息</title><body>请先登录后再继续</body></html>'),
    );
    await expectLater(
      repository.submitThread(
        category: category,
        title: '示例标题',
        content: '示例正文',
      ),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.loginRequired,
        ),
      ),
    );
    expect(hits.where((hit) => hit.startsWith('POST')), hasLength(2));

    final postsBefore = hits.where((hit) => hit.startsWith('POST')).length;
    _scripted.addAll([
      _text(_postForm),
      _text('<html><body>您没有权限执行此操作</body></html>'),
    ]);
    await expectLater(
      repository.submitReply(
        thread: thread,
        title: '',
        content: '示例回复',
      ),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.forbidden,
        ),
      ),
    );

    _scripted.addAll([
      _text(_postForm),
      _text('<html><body>刷新不要快于 9 秒</body></html>'),
    ]);
    final uncertain = await repository.submitThread(
      category: category,
      title: '示例标题',
      content: '示例正文',
    );
    expect(uncertain.unconfirmed, isTrue);
    expect(
      hits.where((hit) => hit.startsWith('POST')).length,
      postsBefore + 2,
    );

    _scripted.add(_status(HttpStatus.internalServerError, 'down'));
    await expectLater(
      repository.submitReply(
        thread: thread,
        title: '',
        content: '示例回复',
      ),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.server,
        ),
      ),
    );

    _scripted.add((request) {
      request.response.detachSocket().then((socket) => socket.destroy());
    });
    await expectLater(
      repository.submitThread(
        category: category,
        title: '示例标题',
        content: '示例正文',
      ),
      throwsA(
        isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.network,
        ),
      ),
    );
  });
}

Future<void> _until(bool Function() done) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (done()) return;
    await pumpEventQueue();
  }
  fail('timed out');
}

List<void Function(HttpRequest)> _scripted = [];

void Function(HttpRequest) _text(String body) {
  return (request) {
    request.response.headers.contentType = ContentType.html;
    request.response.write(body);
    request.response.close();
  };
}

void Function(HttpRequest) _bytes(List<int> bytes) {
  return (request) {
    request.response.headers.contentType = ContentType.binary;
    request.response.add(bytes);
    request.response.close();
  };
}

void Function(HttpRequest) _status(int status, String body) {
  return (request) {
    request.response.statusCode = status;
    request.response.write(body);
    request.response.close();
  };
}

const _searchForm = '''
<html><body>
  <form action="search.php?" method="post">
    <input name="keyword" value="">
  </form>
</body></html>
''';

const _oneResult = '''
<html><head><title>搜索结果</title></head><body>
  <p>共找到 1 条</p>
  <table><tr>
    <td><a href="read.php?tid-100.html">示例主题甲</a></td>
    <td></td>
    <td><a href="thread.php?fid-1">版块甲</a></td>
    <td><a href="u.php?uid-1">作者甲</a> 2020-01-02</td>
    <td>3</td>
  </tr></table>
</body></html>
''';

const _zeroTotal = '''
<html><head><title>搜索结果</title></head><body>
  共找到 0 条
  <table><tr><th>标题</th></tr></table>
</body></html>
''';

const _resultWithoutRows = '''
<html><head><title>搜索结果</title></head><body>
  <table><tr><th>标题</th><th>版块</th></tr></table>
</body></html>
''';

const _postForm = '''
<html><body>
  <form name="FORM" method="post" action="post.php?">
    <input name="fid" value="7">
    <input name="atc_title" value="">
    <textarea name="atc_content"></textarea>
  </form>
</body></html>
''';
