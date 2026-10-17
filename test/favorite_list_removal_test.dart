import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/local_database.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

import 'support/native_favorite_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ForumRepository repository(NativeFavoriteClient client) {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    return ForumRepository(
        client: client,
        profileCache: UserProfileCache(databaseProvider: () async => db));
  }

  test(
      'legacy list removal delegates fresh native controls and row ID, not thread ID',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final profile = await repo.fetchUserProfileFavorites('u.php');
    final item = profile.favorites.first;
    expect(item.favoriteRemoval?.id, '501');
    expect(item.author, 'Synthetic author');
    expect((await repo.removeFavoriteFromList(item)).success, isTrue);
    expect(client.writes.single.$1, 'u.php?action=favor&');
    expect(Map.fromEntries(client.writes.single.$2), {
      'verify': 'token-3',
      'selid[]': '501',
      'job': 'clear',
      'type': '0',
    });
    await expectLater(repo.removeFavoriteFromList(item), throwsException);
    expect(client.writes, hasLength(1));
    expect((await repo.removeFavoriteFromList(profile.favorites.last)).success,
        isTrue,
        reason:
            'unrelated original rows revalidate against the fresh native list');
  });

  test(
      'unfinished legacy deletion requires a refreshed row capability before retry',
      () async {
    final client = NativeFavoriteClient()..applyWrite = false;
    final repo = repository(client);
    final item =
        (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    expect((await repo.removeFavoriteFromList(item)).success, isFalse);
    await expectLater(repo.removeFavoriteFromList(item), throwsException);
    client.applyWrite = true;
    final fresh =
        (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    expect((await repo.removeFavoriteFromList(fresh)).success, isTrue);
    expect(client.writes, hasLength(2));
  });

  test('other-user and forged objects never expose a legacy removal capability',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final other =
        (await repo.fetchUserProfileFavorites('u.php?action-show-uid-999.html'))
            .favorites
            .first;
    expect(other.favoriteRemoval, isNull);
    await expectLater(repo.removeFavoriteFromList(other), throwsException);
    final current =
        (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    final forged = UserListItem(
        title: current.title,
        url: current.url,
        favoriteRemoval: current.favoriteRemoval);
    await expectLater(repo.removeFavoriteFromList(forged), throwsException);
    expect(client.writes, isEmpty);
  });

  test('refresh and logout retire legacy row capabilities', () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final old = (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    final current =
        (await repo.fetchUserProfileFavorites('u.php')).favorites.first;
    await expectLater(repo.removeFavoriteFromList(old), throwsException);
    await repo.clearSession();
    await expectLater(repo.removeFavoriteFromList(current), throwsException);
    expect(client.writes, isEmpty);
  });

  test(
      'a legacy favorites fetch completing after logout cannot publish actions',
      () async {
    final client = NativeFavoriteClient()..readGate = Completer<void>();
    final repo = repository(client);
    final pending = repo.fetchUserProfileFavorites('u.php');
    final assertion = expectLater(pending, throwsException);
    await Future<void>.delayed(Duration.zero);
    await repo.clearSession();
    client.readGate!.complete();
    await assertion;
    expect(client.writes, isEmpty);
  });
}
