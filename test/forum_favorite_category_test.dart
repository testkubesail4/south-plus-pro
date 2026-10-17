import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

import 'support/native_favorite_fixture.dart';

// Captured native response; request credentials are deliberately not part of this fixture.
const _menu = '''<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[
<div class="bor">
<table cellspacing="0" cellpadding="5" width="120">
<tr><th class="h" style="cursor:move" onmousedown="read.move(event);"><span class="fr" style="margin-top:2px;cursor:pointer" onclick="closep();"><img src="images/close.gif" /></span>选择分类</th></tr>
<tr><td><a onclick="favor('0');" href="javascript:">默认分类</a></td></tr>
<tr><td><a onclick="favor('1');return false;" href="javascript:">SPP-repro-10</a></td></tr>
</table>
</div>
]]></ajax>''';
const _ack =
    '<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[帖子收藏成功!]]></ajax>';
const _favorite = ThreadFavorite(
    tid: '543736',
    verify: 'test-only-token',
    state: ThreadFavoriteState.notFavorite);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('native favorite menu is intermediate even when a category contains 收藏',
      () async {
    for (final label in ['SPP-repro-10', '我的收藏']) {
      final client = _Client()
        ..categories = [label]
        ..responses.addAll([_menu.replaceFirst('SPP-repro-10', label), _ack]);
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      final result = await repository.addFavorite(_favorite);
      expect(result.success, isFalse);
      expect(result.state, ThreadFavoriteState.notFavorite);
      expect(result.message, '选择收藏分类');
      final selection = result.categorySelection!;
      expect(selection.categories.map((c) => c.id), ['0', '1']);
      expect(selection.categories.map((c) => c.label), ['默认分类', label]);
      expect(client.requests, hasLength(1),
          reason: 'discarding the menu sends no write');
      expect(
          client.requests.single.queryParameters.containsKey('type'), isFalse);
      final completed = await repository.selectFavoriteCategory(selection, '1');
      expect(completed.success, isTrue);
      expect(completed.state, ThreadFavoriteState.favorite);
      expect(completed.categorySelection, isNull);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.queryParameters, {
        'action': 'favor',
        'tid': _favorite.tid,
        'type': '1',
        'nowtime': client.requests.last.queryParameters['nowtime'],
        'verify': 'token-2',
      });
      expect(client.redirects, [false, false]);
    }
  });

  test('only an offered category and an unconsumed owning menu can write',
      () async {
    final client = _Client()..responses.addAll([_menu, _ack]);
    final repository = ForumRepository(client: client);
    final other = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    addTearDown(other.clearSession);
    final selection =
        (await repository.addFavorite(_favorite)).categorySelection!;
    for (final id in ['2', '-1', '01', '1&tid=999', '1\n']) {
      await expectLater(
          repository.selectFavoriteCategory(selection, id), _invalid);
    }
    await expectLater(other.selectFavoriteCategory(selection, '1'), _invalid);
    await expectLater(
        repository.selectFavoriteCategory(
            FavoriteCategorySelection(categories: selection.categories), '1'),
        _invalid);
    expect(client.requests, hasLength(1));
    expect((await repository.selectFavoriteCategory(selection, '0')).success,
        isTrue);
    expect(client.requests.last.queryParameters['type'], '0');
    await expectLater(
        repository.selectFavoriteCategory(selection, '0'), _invalid);
    expect(client.requests, hasLength(2));
  });

  test('unsupported menus never become success or expose raw HTML', () async {
    for (final response in [
      _menu.replaceFirst("favor('1');return false;", "favor('1');alert(1);"),
      _menu.replaceFirst(
          "favor('1');return false;", "favor('0');return false;"),
      _menu.replaceFirst(
          "favor('1');return false;", "favor('-1');return false;"),
      _menu.replaceFirst('href="javascript:"', 'href="https://evil.invalid/"'),
      _menu.replaceFirst('href="javascript:"', 'href="javascript:alert(1)"'),
      _menu.replaceFirst('SPP-repro-10', '收藏\u0001分类'),
      _menu.replaceFirst(
          "favor('1');return false;", "favor('1');\nreturn false;"),
      _menu.replaceFirst('选择分类', '收藏分类格式已更改'),
      _menu.replaceFirst('</div>', '<script>收藏成功</script></div>'),
    ]) {
      final client = _Client()..responses.add(response);
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      final result = await repository.addFavorite(_favorite);
      expect(result.success, isFalse);
      expect(result.categorySelection, isNull);
      expect(result.state, _favorite.state);
      expect(result.message, isNot(contains('<')));
      expect(result.message, isNot(contains('favor(')));
      expect(client.requests, hasLength(1));
    }
  });

  test('only literal terminal ACKs mark a favorite, including already-favorite',
      () async {
    for (final response in [
      _ack,
      '收藏成功',
      '<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[您已经收藏了该主题]]></ajax>',
      '<ajax><![CDATA[收藏失败]]></ajax>',
      '<ajax><![CDATA[收藏权限不足]]></ajax>',
      '<ajax><![CDATA[收藏分类不存在]]></ajax>',
      '<ajax><![CDATA[未知收藏状态]]></ajax>',
      '<ajax><![CDATA[<script>收藏成功</script>]]></ajax>',
      '<html><body><div hidden>收藏成功</div></body></html>',
    ]) {
      final client = _Client()..responses.add(response);
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      final result = await repository.addFavorite(_favorite);
      final expected = response == _ack ||
          response == '收藏成功' ||
          response.contains('您已经收藏了该主题');
      expect(result.success, expected, reason: response);
      expect(result.state,
          expected ? ThreadFavoriteState.favorite : _favorite.state);
      expect(result.categorySelection, isNull);
      expect(client.requests, hasLength(1));
    }
  });

  test(
      'unconfirmed completion consumes the menu without committing favorite state',
      () async {
    for (final response in [
      '<ajax><![CDATA[收藏分类不存在]]></ajax>',
      _menu,
      'unknown'
    ]) {
      final client = _Client()
        ..applyWrite = false
        ..responses.addAll([_menu, response]);
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      final selection =
          (await repository.addFavorite(_favorite)).categorySelection!;
      final completed = await repository.selectFavoriteCategory(selection, '1');
      expect(completed.success, isFalse);
      expect(completed.state, _favorite.state);
      expect(completed.categorySelection, isNull);
      await expectLater(
          repository.selectFavoriteCategory(selection, '1'), _invalid);
      expect(client.requests, hasLength(2));
    }
  });

  test('session change invalidates offered and in-flight favorite operations',
      () async {
    for (final stage in ['offered', 'first', 'second']) {
      final client = _Client()..responses.addAll([_menu, _ack]);
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      FavoriteCategorySelection? selection;
      if (stage != 'first') {
        selection =
            (await repository.addFavorite(_favorite)).categorySelection!;
      }
      if (stage == 'offered') {
        await repository.clearSession();
        await expectLater(
            repository.selectFavoriteCategory(selection!, '1'), _stale);
        expect(client.requests, hasLength(1));
      } else {
        client.gate = Completer<String>();
        final pending = stage == 'first'
            ? repository.addFavorite(_favorite)
            : repository.selectFavoriteCategory(selection!, '1');
        final rejected = expectLater(pending, _stale);
        await repository.clearSession();
        client.gate!.complete(_ack);
        await rejected;
        expect(client.requests, hasLength(1),
            reason:
                'logout also retires the fresh read before a selected write');
      }
    }
  });

  test('favorite request identity is validated and query values are encoded',
      () async {
    final client = _Client()..responses.add(_ack);
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    for (final favorite in [
      const ThreadFavorite(tid: '1&tid=2', verify: 'token'),
      const ThreadFavorite(tid: '1', verify: 'token\n'),
      const ThreadFavorite(tid: '1', verify: ''),
    ]) {
      await expectLater(repository.addFavorite(favorite), _invalid);
    }
    expect(client.requests, isEmpty);
    await repository
        .addFavorite(const ThreadFavorite(tid: '1', verify: 'a&tid=2'));
    expect(client.requests.single.queryParameters['tid'], '1');
    expect(client.requests.single.queryParameters['verify'], 'a&tid=2');
  });

  for (final status in [302, 307]) {
    for (final secondStage in [false, true]) {
      test('favorite stage ${secondStage ? 2 : 1} refuses HTTP $status replay',
          () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final transport =
            HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
        final client =
            _LocalClient(Uri.http('127.0.0.1:${server.port}', '/'), transport);
        final repository = ForumRepository(client: client);
        addTearDown(() async {
          await repository.clearSession();
          transport.close(force: true);
          await server.close(force: true);
        });
        final requests = <Uri>[];
        server.listen((request) async {
          requests.add(request.uri);
          await request.drain<void>();
          if (request.uri.path == '/u.php') {
            request.response.headers.contentType =
                ContentType('text', 'html', charset: 'utf-8');
            request.response.write(
                nativeFavoriteHtml(categories: ['SPP-repro-10'], rows: []));
          } else if (secondStage && requests.length == 1) {
            request.response.headers.contentType =
                ContentType('text', 'xml', charset: 'utf-8');
            request.response.write(_menu);
          } else {
            request.response.statusCode = status;
            request.response.headers
                .set(HttpHeaders.locationHeader, request.uri.toString());
            request.response.write(_ack);
          }
          await request.response.close();
        });
        if (secondStage) {
          final selection =
              (await repository.addFavorite(_favorite)).categorySelection!;
          final result =
              await repository.selectFavoriteCategory(selection, '1');
          expect(result.success, isFalse,
              reason:
                  'redirected write remains unconfirmed after fresh empty readback');
        } else {
          await expectLater(repository.addFavorite(_favorite),
              throwsA(isA<ForumRequestException>()));
        }
        expect(requests.where((request) => request.path == '/pw_ajax.php'),
            hasLength(secondStage ? 2 : 1));
      });
    }
  }
}

final _invalid = throwsA(isA<ForumRequestException>()
    .having((error) => error.kind, 'kind', ForumRequestKind.invalidInput));
final _stale = throwsA(isA<ForumRequestException>()
    .having((error) => error.kind, 'kind', ForumRequestKind.loginRequired));

class _Client extends NativeFavoriteClient {
  _Client() {
    categories = ['SPP-repro-10'];
    rows = [];
  }
  final responses = <String>[];
  final requests = <Uri>[];
  final redirects = <bool>[];
  Completer<String>? gate;

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    final uri = Uri.parse(path);
    if (uri.path != 'pw_ajax.php')
      return super.getForm(path,
          requireCurrentSession: requireCurrentSession,
          followRedirects: followRedirects);
    requireCurrentSession?.call();
    requests.add(uri);
    redirects.add(followRedirects);
    final response = gate != null ? await gate!.future : responses.removeAt(0);
    if (uri.queryParameters.containsKey('type')) {
      await super.getForm(path,
          requireCurrentSession: requireCurrentSession,
          followRedirects: followRedirects);
    }
    requireCurrentSession?.call();
    return response;
  }
}

class _RealHttp extends HttpOverrides {}

class _LocalClient extends ForumClient {
  _LocalClient(this.baseUri, HttpClient transport)
      : super(httpClient: transport, delay: (_) async {});
  @override
  final Uri baseUri;
  @override
  bool get isLoggedIn => true;
}
