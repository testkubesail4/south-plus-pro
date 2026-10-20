import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('explicit UID lookup returns the actual login name using GET only',
      () async {
    final client = _UsernameClient();
    final repository = ForumRepository(client: client);
    final name = await repository.fetchLoginUsername('901');
    expect(name, 'fixture-login');
    expect(client.paths, ['sendemail.php?uid-901.html']);
  });

  test('email opt-out uses only the verified name in its bounded message',
      () async {
    final client = _UsernameClient()
      ..response = '''<div id="main"><div class="t"><div class="f_one">
        <center><b>fixture-opt-out</b> 不接受邮件</center></div></div></div>''';
    expect(await ForumRepository(client: client).fetchLoginUsername('901'),
        'fixture-opt-out');
  });

  test('invalid UID and logged-out lookup make no request', () async {
    final client = _UsernameClient();
    final repository = ForumRepository(client: client);
    for (final uid in [
      '',
      '0',
      '-1',
      '0901',
      ' 901',
      '901.html',
      '901&action=send'
    ]) {
      await expectLater(repository.fetchLoginUsername(uid),
          throwsA(isA<ForumRepositoryException>()));
    }
    client.loggedIn = false;
    await expectLater(repository.fetchLoginUsername('901'),
        _classified(ForumRequestKind.loginRequired));
    expect(client.paths, isEmpty);
  });

  test('missing or malformed login name never falls back to profile identity',
      () async {
    for (final body in [
      '<div id="u-top"><h1 class="u-h1">fixture-header-id</h1></div>',
      '<input name="sendtoname" value="  ">',
      '<input name="sendtoname" value="fixture&#10;name">',
      '<input name="sendtoname" value="${'x' * 129}">',
      '<div id="main"><div class="t"><div class="f_one"><center><b>fixture-unverified</b></center></div></div></div>',
      '<center><b>fixture-outside-main</b> 不接受邮件</center>',
    ]) {
      final client = _UsernameClient()..response = body;
      await expectLater(
          ForumRepository(client: client).fetchLoginUsername('901'),
          _classified(ForumRequestKind.server));
    }
  });

  test('blocking pages and transport errors retain their classified failure',
      () async {
    for (final (body, kind) in [
      ('请先登录', ForumRequestKind.loginRequired),
      ('没有权限', ForumRequestKind.forbidden),
      ('请求过于频繁', ForumRequestKind.rateLimited),
    ]) {
      final client = _UsernameClient()
        ..response = '$body <input name="sendtoname" value="fixture-forged">';
      await expectLater(
          ForumRepository(client: client).fetchLoginUsername('901'),
          _classified(kind));
    }
    final client = _UsernameClient()
      ..error = const ForumRequestException(ForumRequestKind.network, '网络失败');
    await expectLater(ForumRepository(client: client).fetchLoginUsername('901'),
        _classified(ForumRequestKind.network));
  });

  test('delayed identity is discarded across real session lifecycle changes',
      () async {
    for (final change in [
      'same-name-login',
      'logout-login',
      'expiry',
      'restore-owner',
      'site'
    ]) {
      final client = _UsernameClient();
      final repository = ForumRepository(client: client);
      await repository.restoreSession();
      client.pending = Completer<String>();
      final result = repository.fetchLoginUsername('901');
      final rejected =
          expectLater(result, _classified(ForumRequestKind.loginRequired));
      if (change == 'logout-login') await repository.clearSession();
      if (change == 'same-name-login' || change == 'logout-login') {
        await repository.login(
            username: 'fixture-owner',
            password: 'fixture-password',
            captcha: '1234');
      } else if (change == 'expiry') {
        client.loggedIn = false;
        await repository.restoreSession();
      } else if (change == 'restore-owner') {
        client.owner = 'fixture-other-owner';
        await repository.restoreSession();
      } else {
        await repository.updateNetworkConfig(ForumNetworkConfig(
          site: ForumNetworkConfig.sites.last,
          mode: ForumNetworkMode.native,
          dohProvider: ForumNetworkConfig.defaultProvider,
        ));
      }
      client.pending!.complete(client.response);
      await rejected;
    }
  });
}

Matcher _classified(ForumRequestKind kind) => throwsA(
    isA<ForumRequestException>().having((error) => error.kind, 'kind', kind));

class _UsernameClient extends ForumClient {
  final paths = <String>[];
  bool loggedIn = true;
  String owner = 'fixture-owner';
  String response = '<input name="sendtoname" value="fixture-login">';
  ForumRequestException? error;
  Completer<String>? pending;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<void> restoreCookies() async {}
  @override
  Future<void> clearSession() async {
    loggedIn = false;
  }

  @override
  Future<String> get(String path) async => '<a href="u.php">$owner</a>';
  @override
  Future<String> getOnce(String path) async {
    paths.add(path);
    if (error != null) throw error!;
    return pending?.future ?? response;
  }

  @override
  Future<
      ({
        String response,
        int credentialGeneration,
        bool installedCredentials
      })> postLogin(Map<String, String> form) async {
    final response = await post('login.php', form);
    return (
      response: response,
      credentialGeneration: credentialGeneration,
      installedCredentials: isLoggedIn
    );
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    if (path != 'login.php')
      throw StateError('Username lookup must never POST');
    loggedIn = true;
    owner = form['pwuser']!;
    return '<a href="u.php">$owner</a>';
  }
}
