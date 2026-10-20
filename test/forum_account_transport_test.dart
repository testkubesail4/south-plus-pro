import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
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

  for (final status in [302, 307]) {
    test(
        'favorites POST HTTP $status is private and cannot follow a mutating redirect',
        () async {
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        request.response.statusCode = status;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/replay?verify=redirect-canary');
        request.response.write('private-response-canary');
        await request.response.close();
      });
      final output = _CapturedStdout();
      await IOOverrides.runZoned(() async {
        await expectLater(
            client.postForm('u.php?action=favor&verify=query-canary', const [
              MapEntry('verify', 'form-canary'),
              MapEntry('job', 'clear'),
              MapEntry('type', '0'),
              MapEntry('selid[]', '701'),
              MapEntry('selid[]', '702'),
            ]),
            throwsA(isA<ForumRequestException>()));
      }, stdout: () => output);
      expect(paths, ['/u.php']);
      if (ForumTraceLogger.enabled) {
        expect(output.buffer.toString(), contains('u.php (favorites)'));
        expect(output.buffer.toString(), isNot(contains('canary')));
      }
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

  test('queued private message and its form cannot cross a session change',
      () async {
    var owner = 'A';
    final sends = <String?>[];
    final composeCookies = <String?>[];
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/login.php') {
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=synthetic-$owner; Path=/');
        request.response.write('<a href="u.php">Synthetic $owner</a>');
      } else if (request.uri.path == '/message.php' &&
          request.method == 'GET') {
        composeCookies.add(request.headers.value(HttpHeaders.cookieHeader));
        request.response.write(_composeForm(owner));
      } else if (request.uri.path == '/message.php' &&
          request.method == 'POST') {
        sends.add(request.headers.value(HttpHeaders.cookieHeader));
        request.response.write('<body>操作完成</body>');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    expect(
        await repository.login(
            username: 'Synthetic A', password: 'fixture', captcha: 'fixture'),
        isTrue);
    final compose = await repository.fetchPmCompose();
    expect(composeCookies, ['winduser=synthetic-A']);
    final waiting = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    delay = (_) {
      waiting.complete();
      return release.future;
    };
    final outcome = repository
        .submitPm(
            compose: compose,
            recipientUid: '902',
            title: 'Synthetic private title',
            body: 'Synthetic private body')
        .then<Object?>((_) => null, onError: (Object error) => error);
    await waiting.future;
    await repository.clearSession();
    release.complete();
    final error = await outcome;
    expect(sends, isEmpty,
        reason: 'logout revokes A even after the message entered the pacer');
    expect(
        error,
        isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired));
    delay = (_) async {};
    owner = 'B';
    expect(
        await repository.login(
            username: 'Synthetic B', password: 'fixture', captcha: 'fixture'),
        isTrue);
    await repository.fetchPmCompose();
    expect(repository.currentUsername, 'Synthetic B');
    expect(composeCookies.last, 'winduser=synthetic-B');
    await expectLater(
        repository.submitPm(
            compose: compose,
            recipientUid: '902',
            title: 'Synthetic private title',
            body: 'Synthetic private body'),
        throwsA(isA<ForumRequestException>()));
    expect(sends, isEmpty,
        reason: 'A form must not send using the now-active B cookies');
  });

  for (final acceptedBeforeFailure in [true, false]) {
    test(
        acceptedBeforeFailure
            ? 'accepted login survives a newer failed login attempt'
            : 'unaccepted older login cannot replace a newer accepted login',
        () async {
      final olderReceived = Completer<void>();
      final releaseOlder = Completer<void>();
      final releaseSave = Completer<void>();
      addTearDown(() {
        if (!releaseOlder.isCompleted) releaseOlder.complete();
        if (!releaseSave.isCompleted) releaseSave.complete();
      });
      var logins = 0;
      String? observedCookie;
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.html;
        if (request.uri.path == '/login.php') {
          final owner = ['A', 'B', 'C'][logins++];
          if (owner == 'B') {
            olderReceived.complete();
            if (!acceptedBeforeFailure) await releaseOlder.future;
          }
          if (owner == 'C' && acceptedBeforeFailure) {
            request.response.write('<body>登录失败</body>');
          } else {
            request.response.headers.add(HttpHeaders.setCookieHeader,
                'winduser=synthetic-$owner; Path=/');
            request.response.write(_sessionHeader(owner));
          }
        } else if (request.uri.path == '/index.php' ||
            request.uri.path == '/simple/index.php') {
          request.response
              .write(_sessionHeader(acceptedBeforeFailure ? 'B' : 'C'));
        } else {
          observedCookie = request.headers.value(HttpHeaders.cookieHeader);
          request.response.write('ok');
        }
        await request.response.close();
      });
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      expect(
          await repository.login(
              username: 'Synthetic A', password: 'fixture', captcha: 'fixture'),
          isTrue);
      if (acceptedBeforeFailure) {
        store.saveStarted = Completer<void>();
        store.releaseSave = releaseSave;
      }
      final older = repository
          .login(
              username: 'Synthetic B', password: 'fixture', captcha: 'fixture')
          .then<Object?>((result) => result, onError: (Object error) => error);
      await olderReceived.future.timeout(const Duration(seconds: 5));
      if (acceptedBeforeFailure) {
        await store.saveStarted!.future.timeout(const Duration(seconds: 5));
        expect(repository.currentUsername, 'Synthetic A');
      }
      final newer = await repository
          .login(
              username: 'Synthetic C', password: 'fixture', captcha: 'fixture')
          .then<Object?>((result) => result, onError: (Object error) => error);
      releaseOlder.complete();
      releaseSave.complete();
      final olderResult = await older;
      final persisted = await store.loadCookies();
      final privateRead = await client
          .getForm('profile.php?action=bbsset', requireCurrentSession: () {})
          .then<Object?>((result) => result, onError: (Object error) => error);
      final winner = acceptedBeforeFailure ? 'B' : 'C';
      expect([
        repository.currentUsername,
        repository.accountIdentity.value?.uid,
        ...persisted.values.map((cookie) => cookie.value),
        observedCookie,
        privateRead,
        olderResult == true,
        newer == true,
      ], [
        'Synthetic $winner',
        acceptedBeforeFailure ? '903' : '905',
        'synthetic-$winner',
        'winduser=synthetic-$winner',
        'ok',
        acceptedBeforeFailure,
        !acceptedBeforeFailure,
      ]);
    });
  }

  test('guarded response can refresh its own auth cookie', () async {
    String? observedCookie;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/seed' || request.uri.path == '/profile.php') {
        final owner = request.uri.path == '/seed' ? 'A' : 'A-refreshed';
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=synthetic-$owner; Path=/');
      } else {
        observedCookie = request.headers.value(HttpHeaders.cookieHeader);
      }
      request.response.write('ok');
      await request.response.close();
    });
    await client.getOnce('seed');
    expect(
        await client.getForm('profile.php?action=bbsset',
            requireCurrentSession: () {}),
        'ok');
    expect((await store.loadCookies()).values.map((cookie) => cookie.value),
        ['synthetic-A-refreshed']);
    await client.getOnce('echo');
    expect(observedCookie, 'winduser=synthetic-A-refreshed');
  });

  test('superseded client cannot replace cookies or dispatch guarded requests',
      () async {
    final readReceived = Completer<void>();
    final releaseRead = Completer<void>();
    addTearDown(() {
      if (!releaseRead.isCompleted) releaseRead.complete();
    });
    var logins = 0;
    var guardedHits = 0;
    String? observedCookie;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/login.php') {
        final owner = ++logins == 1 ? 'A' : 'B';
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=synthetic-$owner; Path=/');
        request.response.write(_sessionHeader(owner));
      } else if (request.uri.path == '/index.php' ||
          request.uri.path == '/old-public') {
        if (request.uri.path == '/index.php') {
          readReceived.complete();
          await releaseRead.future;
        }
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'winduser=synthetic-stale-A; Path=/');
      } else if (request.uri.path == '/profile.php') {
        guardedHits++;
      } else {
        observedCookie = request.headers.value(HttpHeaders.cookieHeader);
      }
      await request.response.close();
    });
    final oldRepository = ForumRepository(client: client);
    addTearDown(oldRepository.clearSession);
    expect(
        await oldRepository.login(
            username: 'Synthetic A', password: 'fixture', captcha: 'fixture'),
        isTrue);
    final oldRead = client
        .getOnce('index.php')
        .then<Object?>((_) => null, onError: (Object error) => error);
    await readReceived.future.timeout(const Duration(seconds: 5));
    final replacement = _LocalClient(
        client.baseUri, transport, _RecordingStore(), (_) async {});
    final newRepository = ForumRepository(client: replacement);
    addTearDown(newRepository.clearSession);
    expect(
        await newRepository.login(
            username: 'Synthetic B', password: 'fixture', captcha: 'fixture'),
        isTrue);
    expect((await store.loadCookies()).values.map((cookie) => cookie.value),
        ['synthetic-B']);
    await client
        .getOnce('old-public')
        .then<Object?>((_) => null, onError: (Object error) => error);
    final afterFreshPublic = await store.loadCookies();
    final rejected = await client
        .getForm('profile.php?action=bbsset', requireCurrentSession: () {})
        .then<Object?>((_) => null, onError: (Object error) => error);
    releaseRead.complete();
    await oldRead;
    final persisted = await store.loadCookies();
    await replacement.getOnce('echo');
    expect([
      ...afterFreshPublic.values.map((cookie) => cookie.value),
      ...persisted.values.map((cookie) => cookie.value),
      observedCookie,
      guardedHits,
    ], [
      'synthetic-B',
      'synthetic-B',
      'winduser=synthetic-B',
      0
    ]);
    expect(
        rejected,
        isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired));
  });

  for (final (boundary, usernamePublished) in [
    ('identity', false),
    ('identity', true),
    ('friends', false),
    ('friends', true),
    ('pm', false),
    ('pm', true),
    ('public', true),
    ('redirect', true),
    ('attachment', true),
  ]) {
    test(
        'stale $boundary response cannot replace B cookies '
        '${usernamePublished ? 'after' : 'before'} username publication',
        () async {
      final loginReceived = Completer<void>();
      final releaseLogin = Completer<void>();
      final readReceived = Completer<void>();
      final releaseRead = Completer<void>();
      addTearDown(() {
        if (!releaseLogin.isCompleted) releaseLogin.complete();
        if (!releaseRead.isCompleted) releaseRead.complete();
      });
      var logins = 0;
      String? observedCookie;
      final heldPath = switch (boundary) {
        'friends' => '/u.php',
        'pm' => '/message.php',
        'attachment' => '/job.php',
        _ => '/index.php',
      };
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.html;
        if (request.uri.path == '/login.php') {
          final owner = ++logins == 1 ? 'A' : 'B';
          if (owner == 'B') {
            loginReceived.complete();
            await releaseLogin.future;
          }
          request.response.headers.add(
              HttpHeaders.setCookieHeader, 'winduser=synthetic-$owner; Path=/');
          request.response.write(_sessionHeader(owner));
        } else if (request.uri.path == '/index.php' ||
            request.uri.path == '/u.php' ||
            request.uri.path == '/message.php' ||
            request.uri.path == '/job.php') {
          final held = request.uri.path == heldPath;
          if (held) {
            readReceived.complete();
            await releaseRead.future;
            if (boundary == 'redirect') {
              request.response.statusCode = HttpStatus.found;
              request.response.headers.set(HttpHeaders.locationHeader, '/hop');
            } else {
              request.response.headers.add(HttpHeaders.setCookieHeader,
                  'winduser=synthetic-stale-A; Path=/');
            }
          }
          if (request.uri.path == '/job.php') {
            request.response.headers.contentType = ContentType.binary;
            request.response.add([1, 2, 3]);
          } else {
            request.response.write(request.uri.path == '/index.php'
                ? _sessionHeader('A')
                : request.uri.path == '/message.php'
                    ? _composeForm('A')
                    : '''<form method="post" action="u.php?action=friend">
<input type="hidden" name="uid" value="901">
<input type="hidden" name="verify" value="synthetic-A">
<input type="hidden" name="job" value="delete"></form>''');
          }
        } else if (request.uri.path == '/hop') {
          request.response.headers.add(HttpHeaders.setCookieHeader,
              'winduser=synthetic-stale-A; Path=/');
        } else if (request.uri.path == '/echo') {
          observedCookie = request.headers.value(HttpHeaders.cookieHeader);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      expect(
          await repository.login(
              username: 'Synthetic A', password: 'fixture', captcha: 'fixture'),
          isTrue);
      final switching = repository.login(
          username: 'Synthetic B', password: 'fixture', captcha: 'fixture');
      await loginReceived.future.timeout(const Duration(seconds: 5));
      // Both operations start after B's epoch bump, before its identity arrives.
      final attachmentDirectory = boundary == 'attachment'
          ? await Directory.systemTemp.createTemp('forum_cookie_canary_')
          : null;
      if (attachmentDirectory != null) {
        addTearDown(() => attachmentDirectory.delete(recursive: true));
      }
      final reading = switch (boundary) {
        'identity' => repository.ensureAccountIdentity(),
        'friends' => repository.fetchFriends(),
        'pm' => repository.fetchPmCompose(),
        'attachment' => client.downloadAttachment(
            'job.php?action=download&aid=701',
            directory: attachmentDirectory!),
        _ => client.getOnce('index.php'),
      };
      final outcome =
          reading.then<Object?>((_) => null, onError: (Object error) => error);
      await readReceived.future.timeout(const Duration(seconds: 5));
      final releaseBSave = Completer<void>();
      addTearDown(() {
        if (!releaseBSave.isCompleted) releaseBSave.complete();
      });
      if (!usernamePublished) {
        store.saveStarted = Completer<void>();
        store.releaseSave = releaseBSave;
      }
      releaseLogin.complete();
      if (usernamePublished) {
        expect(await switching, isTrue);
        expect(repository.currentUsername, 'Synthetic B');
        expect((await store.loadCookies()).values.map((cookie) => cookie.value),
            ['synthetic-B']);
      } else {
        await store.saveStarted!.future.timeout(const Duration(seconds: 5));
        expect(repository.currentUsername, 'Synthetic A');
      }
      final oldHeadersObserved = Completer<void>();
      (client as _LocalClient).onSessionCheck = (path) {
        if (client.baseUri.resolve(path).path == heldPath &&
            !oldHeadersObserved.isCompleted) {
          oldHeadersObserved.complete();
        }
      };
      releaseRead.complete();
      String? duringPublication;
      if (!usernamePublished) {
        // A rejected read may finish before invoking the repository's guard.
        await Future.any<void>([
          oldHeadersObserved.future,
          outcome.then<void>((_) {}),
        ]).timeout(const Duration(seconds: 5));
        await client.getOnce('echo');
        duringPublication = observedCookie;
        releaseBSave.complete();
        expect(await switching, isTrue);
        expect(repository.currentUsername, 'Synthetic B');
      }
      final error = await outcome;
      final persisted = await store.loadCookies();
      await client.getOnce('echo');
      expect([
        if (!usernamePublished) duringPublication,
        ...persisted.values.map((cookie) => cookie.value),
        observedCookie,
      ], [
        if (!usernamePublished) 'winduser=synthetic-B',
        'synthetic-B',
        'winduser=synthetic-B'
      ], reason: 'stale A cookies must never replace B in memory or storage');
      if (boundary != 'public' &&
          boundary != 'redirect' &&
          boundary != 'attachment') {
        expect(
            error,
            isA<ForumRequestException>().having(
                (error) => error.kind, 'kind', ForumRequestKind.loginRequired));
      }
    });
  }

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

String _sessionHeader(String owner) {
  final uid = switch (owner) {
    'A' => '901',
    'B' => '903',
    _ => '905',
  };
  return '''<html><head>
<script>var verifyhash = 'fxToken1';</script></head><body>
<div id="user-login"><a href="u.php">Synthetic $owner</a></div>
<div id="menu_profile"><div class="ul2">
<a href="u.php?action-show-uid-$uid.html">资料</a>
</div></div></body></html>''';
}

String _composeForm(String owner) =>
    '''<form method="post" action="message.php">
<input type="hidden" name="action" value="write">
<input type="hidden" name="step" value="2">
<input type="hidden" name="verify" value="synthetic-$owner">
<input name="touidmsg" value="902"><input name="msg_title">
<textarea name="atc_content"></textarea></form>''';

class _RealHttp extends HttpOverrides {}

class _LocalClient extends ForumClient {
  _LocalClient(this.baseUri, HttpClient transport, ForumSessionStore store,
      Future<void> Function(Duration) delay)
      : super(httpClient: transport, sessionStore: store, delay: delay);
  @override
  final Uri baseUri;
  void Function(String path)? onSessionCheck;
  @override
  Future<String> getForm(String path,
          {void Function()? requireCurrentSession,
          bool followRedirects = true}) =>
      super.getForm(path,
          requireCurrentSession: requireCurrentSession == null
              ? null
              : () {
                  onSessionCheck?.call(path);
                  requireCurrentSession();
                },
          followRedirects: followRedirects);
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
