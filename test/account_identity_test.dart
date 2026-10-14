import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';
import 'package:south_plus_rewrite/services/parsers/user_profile_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('home gives immediate name/avatar and nickname loads once on demand',
      () async {
    final client = _AccountClient();
    final repository = ForumRepository(client: client, profileCache: _Cache());
    await repository.restoreSession();
    await repository.fetchHome();
    expect(repository.accountIdentity.value!.systemName, 'fixture-login');
    expect(
        repository.accountIdentity.value!.avatarUrl, endsWith('/avatar.png'));
    expect(repository.accountIdentity.value!.nickname, isNull);
    expect(client.gets, ['index.php', 'simple/index.php']);
    await Future.wait(
        [repository.loadAccountNickname(), repository.loadAccountNickname()]);
    expect(repository.accountIdentity.value!.nickname, 'Fixture nickname');
    expect(client.gets,
        ['index.php', 'simple/index.php', 'u.php?action-show-uid-42.html']);
    await repository.loadAccountNickname();
    expect(client.gets, hasLength(3));
    await repository.clearSession();
    expect(repository.accountIdentity.value, isNull);
  });

  test(
      'fresh UID-keyed cache avoids a profile request and blank nickname stays absent',
      () async {
    final cache = _Cache()
      ..profile = const UserProfile(
        uid: '42',
        name: 'fixture-login',
        url: 'u.php?action-show-uid-42.html',
        info: [UserProfileField(label: '昵称', value: '  ')],
      );
    final client = _AccountClient();
    final repository = ForumRepository(client: client, profileCache: cache);
    await repository.restoreSession();
    await repository.fetchHome();
    await repository.loadAccountNickname();
    expect(repository.accountIdentity.value!.nickname, isNull);
    expect(cache.requested, endsWith('u.php?action-show-uid-42.html'));
    expect(client.gets, hasLength(2));
  });

  test('a cache response from an old session cannot restore account identity',
      () async {
    final cache = _Cache()..pending = Completer<UserProfile?>();
    final repository =
        ForumRepository(client: _AccountClient(), profileCache: cache);
    await repository.restoreSession();
    final loading = repository.loadAccountNickname();
    await repository.clearSession();
    cache.pending!.complete(const UserProfile(
        uid: '42', name: 'Old name', url: 'u.php?action-show-uid-42.html'));
    await loading;
    expect(repository.accountIdentity.value, isNull);
  });

  test('index UID fallback is scoped and avatar must use HTTP', () {
    final identity = UserProfileParser().parseAccountIdentity(html.parse(
      '<div id="user-login"><a href="u.php">Fixture name</a></div>'
      '<div id="showface"><span class="user-infoWraptwo">UID: 42</span></div>'
      '<table><tr><td id="user_info"><a href="u.php"><img src="javascript:bad"></a></td></tr></table>'
      '<a href="u.php?action-show-uid-99.html">Other user</a>',
    ));
    expect(identity!.uid, '42');
    expect(identity.avatarUrl, isNull);
  });
}

class _Cache extends UserProfileCache {
  UserProfile? profile;
  String? requested;
  Completer<UserProfile?>? pending;
  @override
  Future<UserProfile?> loadOverview(String url) async {
    requested = url;
    if (pending != null) return pending!.future;
    return profile;
  }

  @override
  Future<void> saveOverview(String requestedUrl, UserProfile profile) async {
    this.profile = profile;
  }
}

class _AccountClient extends ForumClient {
  final gets = <String>[];
  @override
  bool get isLoggedIn => true;
  @override
  Future<void> restoreCookies() async {}
  @override
  Future<void> clearSession() async {}
  @override
  Future<String> get(String path) async {
    gets.add(path);
    if (path == 'index.php') {
      return '<div id="user-login"><a href="u.php">fixture-login</a></div>'
          '<a href="login.php?action-quit">退出</a>'
          '<div id="menu_profile"><ul class="ul2"><li>'
          '<a href="u.php?action-show-uid-42.html">查看个人资料</a></li></ul></div>'
          '<table><tr><td id="user_info"><a href="u.php">'
          '<img src="/avatar.png"></a></td></tr></table>';
    }
    if (path == 'simple/index.php') {
      return '<a href="read.php?tid-123.html">Fixture title</a>'
          '<table><tr><th><h2>Fixture section</h2></th></tr><tr><th>'
          '<h3><a href="thread.php?fid-42.html">Fixture board</a></h3>'
          '</th><td>1 / 2</td></tr></table>';
    }
    return '<div id="u-top"><h1 class="u-h1">fixture-login</h1></div>'
        '<div id="u-profile"><table><tr><td>昵称</td><th>Fixture nickname</th>'
        '</tr></table></div>';
  }
}
