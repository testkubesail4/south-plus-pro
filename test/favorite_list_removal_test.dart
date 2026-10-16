import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/local_database.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ForumRepository repository(_FavoriteClient client) {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    return ForumRepository(
      client: client,
      profileCache: UserProfileCache(databaseProvider: () async => db),
    );
  }

  test('list removal uses the page token and row selection ID, not thread ID',
      () async {
    final client = _FavoriteClient();
    final repo = repository(client);
    final profile = await repo.fetchUserProfileFavorites('u.php');
    final item = profile.favorites.first;
    expect(item.favoriteRemoval?.id, '501');
    expect(item.author, 'Synthetic author');
    expect(item.section, isNull);
    expect(item.date, isNull);
    expect((await repo.removeFavoriteFromList(item)).success, isTrue);
    expect(client.posts.single.$1, 'u.php?action=favor&');
    expect(client.posts.single.$2, {
      'verify': 'synthetic-token',
      'selid[]': '501',
      'job': 'clear',
      'type': '0',
    });
    await expectLater(repo.removeFavoriteFromList(item), throwsException);
    expect(client.posts, hasLength(1),
        reason: 'successful actions are consumed');
    expect((await repo.removeFavoriteFromList(profile.favorites.last)).success,
        isTrue,
        reason: 'other rows remain usable');
  });

  test('failed deletion stays visible and can be retried', () async {
    final client = _FavoriteClient()..postResponse = '认证码错误';
    final repo = repository(client);
    final item =
        (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    expect((await repo.removeFavoriteFromList(item)).success, isFalse);
    client.postResponse = '操作完成';
    expect((await repo.removeFavoriteFromList(item)).success, isTrue);
  });

  test('missing form credentials and other users never expose removal actions',
      () async {
    for (final entry in [
      (_favorites.replaceFirst('value="synthetic-token"', 'value=""'), 'u.php'),
      (_favorites, 'u.php?action-show-uid-999.html'),
    ]) {
      final client = _FavoriteClient()..favorites = entry.$1;
      final repo = repository(client);
      final item =
          (await repo.fetchUserProfileFavorites(entry.$2)).favorites.first;
      expect(item.favoriteRemoval, isNull);
      await expectLater(repo.removeFavoriteFromList(item), throwsException);
      expect(client.posts, isEmpty);
    }
  });

  test('refresh, logout and forged row objects cannot replay a removal',
      () async {
    final client = _FavoriteClient();
    final repo = repository(client);
    final old = (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    final current =
        (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    await expectLater(repo.removeFavoriteFromList(old), throwsException);
    final forged = UserListItem(
      title: current.title,
      url: current.url,
      favoriteRemoval: current.favoriteRemoval,
    );
    await expectLater(repo.removeFavoriteFromList(forged), throwsException);
    await repo.clearSession();
    await expectLater(repo.removeFavoriteFromList(current), throwsException);
    expect(client.posts, isEmpty);
  });

  test('a favourites fetch completing after logout cannot publish actions',
      () async {
    final client = _FavoriteClient()..pendingFavorites = Completer<String>();
    final repo = repository(client);
    final pending = repo.fetchUserProfileFavorites('u.php');
    await client.favoritesRequested.future;
    await repo.clearSession();
    final assertion = expectLater(pending, throwsException);
    client.pendingFavorites!.complete(_favorites);
    await assertion;
    expect(client.posts, isEmpty);
  });
}

const _favorites = '''
<table class="u-table"><tr><td>Synthetic unrelated profile panel</td></tr></table>
<form action="u.php?action=favor&amp;">
  <input type="hidden" name="verify" value="synthetic-token">
  <table class="u-table">
    <tr><td width="65%">标题</td><td>作者</td><td>目录</td><td></td></tr>
    <tr><th><a href="read.php?tid-701.html">Synthetic favourite</a></th>
      <td><a href="u.php?uid-901.html">Synthetic author</a></td><td></td>
      <td><input type="checkbox" name="selid[]" value="501"></td></tr>
    <tr><th><a href="read.php?tid-702.html">Synthetic other favourite</a></th>
      <td><a href="u.php?uid-902.html">Synthetic other author</a></td><td></td>
      <td><input type="checkbox" name="selid[]" value="502"></td></tr>
  </table>
  <input type="radio" name="job" value="change"><select name="type"><option value="0"></option></select>
  <input type="radio" name="job" value="clear">
</form>
<form action="u.php?action=favor&amp;"><input name="verify" value="wrong-form-token">
  <input name="job" value="addtype"><input name="type"></form>
''';

class _FavoriteClient extends ForumClient {
  bool loggedIn = true;
  String favorites = _favorites;
  String postResponse = '操作完成';
  Completer<String>? pendingFavorites;
  final favoritesRequested = Completer<void>();
  final posts = <(String, Map<String, String>)>[];

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<void> clearSession() async => loggedIn = false;

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<String> get(String path) async {
    if (path == 'u.php') {
      return '<a href="u.php?action-show-uid-901.html">Synthetic account</a>';
    }
    if (path.contains('action-show')) {
      return '<div id="u-top"><h1 class="u-h1">Synthetic account</h1></div>';
    }
    if (!favoritesRequested.isCompleted) favoritesRequested.complete();
    if (pendingFavorites != null) return pendingFavorites!.future;
    return favorites;
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    posts.add((path, Map.of(form)));
    return postResponse;
  }
}
