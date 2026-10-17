import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late HttpClient transport;
  late ForumClient client;
  late _RecordingStore store;
  late Future<void> Function(Duration) delay;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
    delay = (_) async {};
    store = _RecordingStore();
    client = _LocalClient(Uri.http('127.0.0.1:${server.port}', '/'), transport,
        store, (duration) => delay(duration));
  });
  tearDown(() async {
    transport.close(force: true);
    await server.close(force: true);
  });

  test('account URL encoding preserves repeated groups and Unicode text',
      () async {
    String? body;
    ContentType? contentType;
    int? contentLength;
    String? transferEncoding;
    server.listen((request) async {
      contentType = request.headers.contentType;
      contentLength = request.headers.contentLength;
      transferEncoding =
          request.headers.value(HttpHeaders.transferEncodingHeader);
      body = await utf8.decoder.bind(request).join();
      request.response.write('ok');
      await request.response.close();
    });
    await client.postForm('profile.php?action=bbsset', const [
      MapEntry('msggroups[]', '3'),
      MapEntry('msggroups[]', '7'),
      MapEntry('prohonor', '昵称 &+=\n次行'),
    ]);
    expect(contentType?.mimeType, 'application/x-www-form-urlencoded');
    expect(contentType?.charset, 'utf-8');
    expect(contentLength, utf8.encode(body!).length);
    expect(transferEncoding, isNull);
    expect(body,
        'msggroups%5B%5D=3&msggroups%5B%5D=7&prohonor=%E6%98%B5%E7%A7%B0+%26%2B%3D%0D%0A%E6%AC%A1%E8%A1%8C');
  });

  test(
      'multipart preserves binary and quotes disposition without header injection',
      () async {
    var hits = 0;
    ContentType? contentType;
    String? injectedHeader;
    int? contentLength;
    String? transferEncoding;
    List<int>? received;
    server.listen((request) async {
      hits++;
      contentType = request.headers.contentType;
      contentLength = request.headers.contentLength;
      transferEncoding =
          request.headers.value(HttpHeaders.transferEncodingHeader);
      injectedHeader = request.headers.value('x-injected');
      received = await request
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      request.response.write('private-response-canary');
      await request.response.close();
    });
    final output = _CapturedStdout();
    final binary =
        Uint8List.fromList([0, 255, 13, 10, ...utf8.encode('binary-canary')]);
    await IOOverrides.runZoned(
      () => client.postForm('profile.php?action=ajaxface&verify=query-canary',
          const [MapEntry('proemail', 'private-field-canary\n第二行')],
          multipart: true,
          files: [
            ForumFormFile(
                name: 'upload',
                fileName: 'avatar"\r\nX-Injected: yes.png',
                mimeType: 'image/png',
                bytes: binary),
          ]),
      stdout: () => output,
    );
    expect(contentType?.mimeType, 'multipart/form-data');
    final boundary = contentType!.parameters['boundary']!;
    expect(boundary, isNotEmpty);
    expect(injectedHeader, isNull);
    expect(contentLength, received!.length);
    expect(transferEncoding, isNull);
    expect(received, [
      ...utf8.encode('--$boundary\r\nContent-Disposition: form-data; '
          'name="proemail"\r\n\r\nprivate-field-canary\r\n第二行\r\n'
          '--$boundary\r\nContent-Disposition: form-data; name="upload"; '
          'filename="avatar%22%0D%0AX-Injected: yes.png"\r\n'
          'Content-Type: image/png\r\n\r\n'),
      ...binary,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ]);
    if (ForumTraceLogger.enabled) {
      expect(output.buffer.toString(), contains('POST profile.php (account)'));
      expect(output.buffer.toString(), isNot(contains('canary')));
      expect(output.buffer.toString(), isNot(contains('X-Injected')));
    }
    await expectLater(
      client.postForm('profile.php?action=ajaxface', const [],
          multipart: true,
          files: [
            ForumFormFile(
                name: 'upload',
                fileName: 'safe.png',
                mimeType: 'image/png\r\nX-Injected: yes',
                bytes: binary),
          ]),
      throwsA(isA<ForumRequestException>().having(
          (error) => error.kind, 'kind', ForumRequestKind.invalidInput)),
    );
    expect(hits, 1, reason: 'invalid MIME must be rejected before dispatch');
  });

  for (final status in [301, 302, 303, 307, 308, 400, 429, 503, 200]) {
    test('account POST never replays after HTTP $status', () async {
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        request.response.statusCode = status;
        request.response.headers.set(HttpHeaders.locationHeader, '/replay');
        request.response.write(status == 200 ? '请求过于频繁' : '操作完成');
        await request.response.close();
      });
      await expectLater(
          client.postForm(
              'profile.php?action=modify', const [MapEntry('step', '2')]),
          throwsA(isA<ForumRequestException>()));
      expect(paths, ['/profile.php']);
    });
  }

  test('mutating GET refuses a same-action redirect without a second request',
      () async {
    const action = 'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14';
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.toString());
      await request.drain<void>();
      if (requests.length == 1) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/$action');
      } else {
        request.response.write('ok');
      }
      await request.response.close();
    });
    await expectLater(
        client.getForm(action, followRedirects: false),
        throwsA(isA<ForumRequestException>()
            .having((error) => error.kind, 'kind', ForumRequestKind.server)));
    expect(requests, ['/$action']);
  });

  test('account POST connection failure cannot replay a dispatched write',
      () async {
    var hits = 0;
    server.listen((request) async {
      hits++;
      await request.drain<void>();
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
    });
    await expectLater(
        client.postForm(
            'profile.php?action=modify', const [MapEntry('step', '2')]),
        throwsA(isA<ForumRequestException>()));
    expect(hits, 1);
  });

  test('queued account write checks ownership again at pacer dispatch',
      () async {
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      await request.drain<void>();
      request.response.write('ok');
      await request.response.close();
    });
    await client.getOnce('prime');
    final waiting = Completer<void>();
    final release = Completer<void>();
    delay = (_) {
      waiting.complete();
      return release.future;
    };
    var epoch = 1;
    void requireOwner() {
      if (epoch != 1) {
        throw const ForumRequestException(
            ForumRequestKind.loginRequired, 'stale');
      }
    }

    final rejected = expectLater(
        client.postForm(
            'profile.php?action=modify', const [MapEntry('step', '2')],
            requireCurrentSession: requireOwner),
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    await waiting.future;
    epoch++;
    release.complete();
    await rejected;
    delay = (_) async {};
    await client.getOnce('after');
    expect(paths, ['/prime', '/after']);
  });

  for (final method in ['GET', 'POST']) {
    test(
        'stale account $method response cannot replace or persist account B cookies',
        () async {
      final received = Completer<void>();
      final release = Completer<void>();
      String? observedCookie;
      String? sentCookie;
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/profile.php') {
          sentCookie = request.headers.value(HttpHeaders.cookieHeader);
          received.complete();
          await release.future;
          request.response.headers
              .add(HttpHeaders.setCookieHeader, 'winduser=stale-A; Path=/');
        } else if (request.uri.path == '/seed') {
          request.response.headers.add(HttpHeaders.setCookieHeader,
              'winduser=${request.uri.queryParameters['owner']}; Path=/');
        } else {
          observedCookie = request.headers.value(HttpHeaders.cookieHeader);
        }
        request.response.write('ok');
        await request.response.close();
      });
      await client.getOnce('seed?owner=A');
      var epoch = 1;
      void requireOwner() {
        if (epoch != 1) {
          throw const ForumRequestException(
              ForumRequestKind.loginRequired, 'stale');
        }
      }

      final pending = method == 'GET'
          ? client.getForm('profile.php?action=modify',
              requireCurrentSession: requireOwner)
          : client.postForm(
              'profile.php?action=modify', const [MapEntry('step', '2')],
              requireCurrentSession: requireOwner);
      final rejected = expectLater(
          pending,
          throwsA(isA<ForumRequestException>().having(
              (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
      await received.future;
      epoch++;
      await client.clearSession();
      await client.getOnce('seed?owner=B');
      final savesBeforeStaleResponse = store.saves;
      release.complete();
      await rejected;
      expect(sentCookie, 'winduser=A');
      expect(store.saves, savesBeforeStaleResponse,
          reason: 'reject stale Set-Cookie before any persistence');
      final persisted = await ForumSessionStore().loadCookies();
      expect(persisted.values.map((cookie) => cookie.value), ['B']);
      await client.getOnce('echo');
      expect(observedCookie, 'winduser=B');
    });
  }

  test(
      'a replaced client cannot persist old cookies after the new client clears',
      () async {
    String? observedCookie;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/echo') {
        observedCookie = request.headers.value(HttpHeaders.cookieHeader);
      } else {
        request.response.headers.add(HttpHeaders.setCookieHeader,
            'winduser=${request.uri.queryParameters['owner']}; Path=/');
      }
      request.response.write('ok');
      await request.response.close();
    });
    await client.getOnce('seed?owner=A');
    final order = <String>[];
    store.events = order;
    store.saveStarted = Completer<void>();
    final release = Completer<void>();
    store.releaseSave = release;
    var epoch = 1;
    final rejected = expectLater(
        client.postForm(
            'profile.php?owner=stale-A', const [MapEntry('step', '2')],
            requireCurrentSession: () {
          if (epoch != 1) {
            throw const ForumRequestException(
                ForumRequestKind.loginRequired, 'stale');
          }
        }),
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    await store.saveStarted!.future;
    epoch++;
    final replacementStore = _RecordingStore()..events = order;
    final replacement =
        _LocalClient(client.baseUri, transport, replacementStore, (_) async {});
    final switched = replacement.clearSession().then((_) async {
      await replacement.getOnce('seed?owner=B');
    });
    release.complete();
    await Future.wait([rejected, switched]);
    expect(order, ['save:stale-A', 'clear', 'save:B']);
    final persisted = await ForumSessionStore().loadCookies();
    expect(persisted.values.map((cookie) => cookie.value), ['B']);
    await replacement.getOnce('echo');
    expect(observedCookie, 'winduser=B');
  });

  test('another client clearing during restore cannot resurrect persisted auth',
      () async {
    await ForumSessionStore().saveCookies({
      'fixture': ForumStoredCookie.session(
          name: 'winduser', value: 'A', origin: client.baseUri),
    });
    final order = <String>[];
    store.events = order;
    store.loadStarted = Completer<void>();
    final release = Completer<void>();
    store.releaseLoad = release;
    final restoring = client.restoreCookies();
    await store.loadStarted!.future;
    final replacement = _LocalClient(client.baseUri, transport,
        _RecordingStore()..events = order, (_) async {});
    final clearing = replacement.clearSession();
    release.complete();
    await Future.wait([restoring, clearing]);
    expect(order, ['clear'],
        reason: 'restoring cookies must not save old auth');
    expect(await ForumSessionStore().loadCookies(), isEmpty);
  });

  for (final (entry, foreignHop) in [
    ('profile.php?action=modify', false),
    ('profile.php?action=modify', true),
    ('pw_ajax.php?action=showface', false),
    ('pw_ajax.php?action=showface', true),
  ]) {
    test(
        'account $entry redirect stays private (foreign second hop: $foreignHop)',
        () async {
      final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => foreign.close(force: true));
      var foreignHits = 0;
      foreign.listen((request) async {
        foreignHits++;
        request.response.write('foreign-response-canary');
        await request.response.close();
      });
      final paths = <String>[];
      final initialPath = '/${Uri.parse(entry).path}';
      server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        if (request.uri.path == initialPath || foreignHop) {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
              HttpHeaders.locationHeader,
              request.uri.path == initialPath
                  ? '/hop?action=tasks&verify=query-canary'
                  : 'http://127.0.0.1:${foreign.port}/foreign');
        }
        request.response.write('private-response-canary');
        await request.response.close();
      });
      final output = _CapturedStdout();
      await IOOverrides.runZoned(
        () async {
          final response = client.getForm(entry);
          if (foreignHop) {
            await expectLater(response, throwsA(isA<ForumRequestException>()));
          } else {
            expect(await response, 'private-response-canary');
          }
        },
        stdout: () => output,
      );
      expect(paths, [initialPath, '/hop']);
      expect(foreignHits, 0);
      if (ForumTraceLogger.enabled) {
        expect(output.buffer.toString(), contains('GET '));
        expect(output.buffer.toString(), isNot(contains('canary')));
      }
    });
  }
}

class _RealHttp extends HttpOverrides {}

class _LocalClient extends ForumClient {
  _LocalClient(this.baseUri, HttpClient transport, ForumSessionStore store,
      Future<void> Function(Duration) delay)
      : super(httpClient: transport, sessionStore: store, delay: delay);
  @override
  final Uri baseUri;
}

class _RecordingStore extends ForumSessionStore {
  var saves = 0;
  List<String>? events;
  Completer<void>? saveStarted;
  Completer<void>? releaseSave;
  Completer<void>? loadStarted;
  Completer<void>? releaseLoad;
  @override
  Future<Map<String, ForumStoredCookie>> loadCookies() async {
    final cookies = await super.loadCookies();
    if (releaseLoad != null) {
      loadStarted!.complete();
      await releaseLoad!.future;
    }
    return cookies;
  }

  @override
  Future<void> saveCookies(Map<String, ForumStoredCookie> cookies) async {
    saves++;
    final release = releaseSave;
    releaseSave = null;
    if (release != null) {
      saveStarted!.complete();
      await release.future;
    }
    await super.saveCookies(cookies);
    events
        ?.add('save:${cookies.values.map((cookie) => cookie.value).join(',')}');
  }

  @override
  Future<void> clear() {
    events?.add('clear');
    return super.clear();
  }
}

class _CapturedStdout implements Stdout {
  final buffer = StringBuffer();
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
