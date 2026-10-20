import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('blocking settings can bootstrap identity before the first home load',
      () async {
    final client = _BlockingClient();
    final repository = ForumRepository(client: client);
    expect(repository.accountIdentity.value, isNull);
    await repository.ensureAccountIdentity();
    await repository.blocking.load();
    expect(repository.accountIdentity.value?.uid, '101');
    expect(repository.blocking.canWriteNative, isTrue);
    expect(repository.blocking.notifier.value.isUserBlocked('202'), isTrue);
    await repository.ensureAccountIdentity();
    await repository.blocking.load();
    expect(client.gets, ['index.php']);
    expect(
        client.posts
            .map((post) => Uri.parse(post.$1).queryParameters['action']),
        ['getblocklist']);
  });

  test(
      'an identity bootstrap from a previous session cannot restore its account',
      () async {
    final client = _BlockingClient()..pendingIndex = Completer<String>();
    final repository = ForumRepository(client: client);
    final loading = repository.ensureAccountIdentity();
    final assertion =
        expectLater(loading, throwsA(isA<ForumRequestException>()));
    await repository.clearSession();
    client.pendingIndex!.complete(_BlockingClient.header);
    await assertion;
    expect(repository.accountIdentity.value, isNull);
    expect(repository.blocking.canWriteNative, isFalse);
    expect(client.posts, isEmpty);
  });

  test('guest identity bootstrap never requests private settings', () async {
    final client = _BlockingClient()..loggedIn = false;
    final repository = ForumRepository(client: client);
    await repository.ensureAccountIdentity();
    await repository.blocking.load();
    expect(client.gets, isEmpty);
    expect(client.posts, isEmpty);
  });

  test('session loads native rules once and posts only explicit edits',
      () async {
    final client = _BlockingClient();
    final repository = ForumRepository(client: client);
    await repository.restoreSession();
    await repository.blocking.load();
    await repository.blocking.load();
    expect(client.gets, ['index.php']);
    expect(
        client.posts
            .map((post) => Uri.parse(post.$1).queryParameters['action']),
        ['getblocklist']);
    expect(client.posts.single.$2, isEmpty);
    expect(repository.blocking.notifier.value.isUserBlocked('202'), isTrue);
    await repository.blocking
        .setUser('303', 'Synthetic target', blocked: true, avatarOnly: true);
    expect(
        client.posts
            .map((post) => Uri.parse(post.$1).queryParameters['action']),
        ['getblocklist', 'getblocklist', 'updateblocklist']);
    for (final post in client.posts) {
      expect(Uri.parse(post.$1).path, 'pw_ajax.php');
      expect(Uri.parse(post.$1).queryParameters['verify'], 'TEST1234');
    }
    final written = jsonDecode(client.posts.last.$2['blocklistconfig']!) as Map;
    expect(written['blist']['202']['level'], ['topic']);
    expect(written['blist']['303']['level'], ['avatar']);
    expect(repository.blocking.notifier.value.isAvatarBlocked('303'), isTrue);
    await repository.clearSession();
    expect(repository.blocking.notifier.value.users, isEmpty);
    expect(repository.blocking.canWriteNative, isFalse);
    await repository.blocking.load(refresh: true);
    expect(client.posts, hasLength(3));
  });
}

class _BlockingClient extends ForumClient {
  var loggedIn = true;
  final gets = <String>[];
  final posts = <(String, Map<String, String>)>[];
  Completer<String>? pendingIndex;
  static const header =
      '''<html><head><script>var verifyhash='TEST1234';</script></head>
      <body><div id="user-login"><a href="u.php">Synthetic account</a></div>
      <div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-101.html">查看个人资料</a></div></div>
      </body></html>''';

  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<void> restoreCookies() async {}
  @override
  Future<void> clearSession() async {
    loggedIn = false;
  }

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    final response = await get(path);
    requireCurrentSession?.call();
    return response;
  }

  @override
  Future<String> get(String path) async {
    gets.add(path);
    return pendingIndex == null ? header : pendingIndex!.future;
  }

  @override
  Future<String> post(String path, Map<String, String> fields) async {
    posts.add((path, Map.of(fields)));
    if (Uri.parse(path).queryParameters['action'] == 'getblocklist') {
      return '<ajax><![CDATA[{"version":"3.1","blist":{"202":{"name":"Synthetic blocked author","level":["topic"]}}}]]></ajax>';
    }
    return '<ajax><![CDATA[success]]></ajax>';
  }
}
