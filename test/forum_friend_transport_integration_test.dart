import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';
import 'package:south_plus_rewrite/services/forum_trace_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final status in [200, 302, 307]) {
    test('repository add GET HTTP $status cannot replay or expose private data',
        () async {
      final fixture = await _Fixture.start();
      await fixture.signIn('A');
      final mutations = <Uri>[];
      fixture.onFriend = (request) async {
        mutations.add(request.uri);
        request.response.statusCode = status;
        request.response.headers.set(HttpHeaders.locationHeader,
            '/pw_ajax.php?action=addfriend&touid=902&verify=redirectCanary');
        request.response.write(status == 200
            ? _xml('请求过于频繁 privateResponseCanary')
            : _xml('privateResponseCanary'));
        await request.response.close();
      };
      final output = _CapturedStdout();
      await IOOverrides.runZoned(() async {
        final result = await fixture.repository.addFriend('902');
        expect(result.status,
            anyOf(ForumFriendAddStatus.unknown, ForumFriendAddStatus.rejected));
      }, stdout: () => output);
      expect(mutations, hasLength(1),
          reason: 'the initial GET may already have added the friend');
      expect(mutations.single.queryParameters['verify'], 'fxToken1');
      final trace = output.buffer.toString();
      if (ForumTraceLogger.enabled) expect(trace, contains('GET '));
      for (final secret in [
        'fxToken1',
        'redirectCanary',
        'privateResponseCanary',
      ]) {
        expect(trace, isNot(contains(secret)));
      }
    });
  }

  test(
      'logout rejects an in-flight friend result before persisting old cookies',
      () async {
    final fixture = await _Fixture.start();
    await fixture.signIn('A');
    final received = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    String? sentCookie;
    fixture.onFriend = (request) async {
      sentCookie = request.headers.value(HttpHeaders.cookieHeader);
      received.complete();
      await release.future;
      request.response.headers.add(
          HttpHeaders.setCookieHeader, 'winduser=synthetic-stale-A; Path=/');
      request.response.write(_xml('成功将对方加为好友'));
      await request.response.close();
    };
    final rejected = expectLater(fixture.repository.addFriend('902'), _expired);
    await received.future;
    await fixture.repository.clearSession();
    await fixture.signIn('B');
    release.complete();
    await rejected;
    expect(sentCookie, 'winduser=synthetic-A');
    final persisted = await ForumSessionStore(origin: fixture.client.baseUri).loadCookies();
    expect(persisted.values.map((cookie) => cookie.value), ['synthetic-B']);
    await fixture.client.getOnce('fixture-echo');
    expect(fixture.echoCookie, 'winduser=synthetic-B');
    expect(fixture.repository.currentUsername, 'Synthetic B');
  });

  test(
      'verification draft from a cleared session cannot post as the next owner',
      () async {
    final fixture = await _Fixture.start();
    await fixture.signIn('A');
    fixture.onFriend = (request) async {
      request.response.write(_verificationForm());
      await request.response.close();
    };
    final result = await fixture.repository.addFriend('902');
    expect(result.status, ForumFriendAddStatus.verificationRequired);
    expect(result.request, isNotNull);
    final before = fixture.friendRequests.length;
    await fixture.repository.clearSession();
    await fixture.signIn('B');
    await expectLater(
        fixture.repository.confirmFriendRequest(result.request!,
            message: 'synthetic verification message'),
        _expired);
    expect(fixture.friendRequests.length, before,
        reason:
            'a stale draft cannot dispatch a friend request with owner B auth');
  });

  test('foreign verification form never receives a request or session cookie',
      () async {
    final fixture = await _Fixture.start();
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => foreign.close(force: true));
    var foreignHits = 0;
    foreign.listen((request) async {
      foreignHits++;
      request.response.write(_xml('请求添加为好友，正在等待好友验证。'));
      await request.response.close();
    });
    await fixture.signIn('A');
    fixture.onFriend = (request) async {
      request.response.write(_verificationForm(
          action:
              'http://127.0.0.1:${foreign.port}/pw_ajax.php?action=addfriend'));
      await request.response.close();
    };
    try {
      final result = await fixture.repository.addFriend('902');
      if (result.request != null) {
        await expectLater(
            fixture.repository.confirmFriendRequest(result.request!,
                message: 'synthetic private message'),
            throwsA(isA<ForumRequestException>()));
      } else {
        expect(result.status, isNot(ForumFriendAddStatus.added));
        expect(result.status, isNot(ForumFriendAddStatus.pending));
      }
    } on ForumRequestException {
      // Rejecting the untrusted form while reading it is equally safe.
    }
    expect(fixture.friendRequests, hasLength(1),
        reason: 'the untrusted popup must actually reach the admission check');
    expect(foreignHits, 0);
    expect(fixture.friendRequests.where((request) => request.method == 'POST'),
        isEmpty);
  });
}

final _expired = throwsA(isA<ForumRequestException>()
    .having((error) => error.kind, 'kind', ForumRequestKind.loginRequired));

String _xml(String payload) => '<?xml version="1.0" encoding="utf-8"?>'
    '<ajax><![CDATA[$payload]]></ajax>';

String _verificationForm({String action = 'pw_ajax.php?action=addfriend'}) =>
    _xml('''<form method="post" action="$action">
<input type="hidden" name="verify" value="formCanary">
<input type="hidden" name="job" value="add">
<input type="hidden" name="step" value="2">
<input type="hidden" name="touid" value="902">
<textarea name="checkmsg"></textarea><input type="submit" value="提交">
</form>''');

class _Fixture {
  _Fixture(this.server, this.transport, this.client)
      : repository = ForumRepository(client: client);

  final HttpServer server;
  final HttpClient transport;
  final ForumClient client;
  final ForumRepository repository;
  final requests = <({String method, Uri uri})>[];
  Iterable<({String method, Uri uri})> get friendRequests =>
      requests.where((request) =>
          request.uri.path == '/pw_ajax.php' &&
          request.uri.queryParameters['action'] == 'addfriend');
  Future<void> Function(HttpRequest)? onFriend;
  String owner = 'A';
  String? echoCookie;

  static Future<_Fixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport =
        HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
    final config = _LocalConfig(Uri.http('127.0.0.1:${server.port}', '/'));
    final client =
        ForumClient(httpClient: transport, config: config, delay: (_) async {});
    final fixture = _Fixture(server, transport, client);
    addTearDown(() async {
      await fixture.repository.clearSession();
      transport.close(force: true);
      await server.close(force: true);
    });
    server.listen(fixture.handle);
    return fixture;
  }

  Future<void> signIn(String account) async {
    owner = account;
    await client.getOnce('fixture-session');
    expect(await repository.restoreSession(), isTrue);
  }

  Future<void> handle(HttpRequest request) async {
    requests.add((method: request.method, uri: request.uri));
    await request.drain<void>();
    request.response.headers.contentType = ContentType.html;
    if (request.uri.path == '/fixture-session') {
      request.response.headers.add(
          HttpHeaders.setCookieHeader, 'winduser=synthetic-$owner; Path=/');
    } else if (request.uri.path == '/index.php') {
      request.response.write('''<html><head>
<script>var verifyhash = 'fxToken1';</script></head><body>
<div id="user-login"><a href="u.php">Synthetic $owner</a></div>
<div id="menu_profile"><div class="ul2">
<a href="u.php?action-show-uid-${owner == 'A' ? '901' : '903'}.html">个人资料</a>
</div></div></body></html>''');
    } else if (request.uri.path == '/u.php' &&
        request.uri.query == 'action-show-uid-902.html') {
      request.response.write('''<html><head>
<script>var verifyhash = 'fxToken1';</script></head><body>
<div id="u-sidebar"><a onclick="ajax.send('pw_ajax.php?action=addfriend&touid=902','','')">加为好友</a></div>
</body></html>''');
    } else if (request.uri.path == '/fixture-echo') {
      echoCookie = request.headers.value(HttpHeaders.cookieHeader);
    } else if (request.uri.path == '/pw_ajax.php' &&
        request.uri.queryParameters['action'] == 'addfriend' &&
        onFriend != null) {
      await onFriend!(request);
      return;
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

class _LocalConfig extends ForumNetworkConfig {
  const _LocalConfig(this.baseUri)
      : super(
            site: const ForumSite('fixture.invalid'),
            mode: ForumNetworkMode.native,
            dohProvider: ForumNetworkConfig.defaultProvider);
  @override
  final Uri baseUri;
}

class _RealHttp extends HttpOverrides {}

class _CapturedStdout implements Stdout {
  final buffer = StringBuffer();
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
