import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/local_database.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

void main() {
  test('UserProfileCache stores and loads overview by equivalent profile URLs',
      () async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final cache = UserProfileCache(databaseProvider: () async => db);
    const profile = UserProfile(
      uid: '123',
      name: 'Alice',
      url: 'https://south-plus.net/u.php?action-show-uid-123.html',
      tagline: '签名',
      level: 'Lv.3',
      isOnline: true,
      statusText: '在线',
      info: [UserProfileField(label: 'UID', value: '123')],
      stats: [UserProfileField(label: '在线时间', value: '9 小时')],
    );

    await cache.saveOverview('u.php?action-show-uid-123.html', profile);

    final loaded = await cache.loadOverview(
      'https://south-plus.net/u.php?action-show-uid-123.html',
    );

    expect(loaded?.name, 'Alice');
    expect(loaded?.tagline, '签名');
    expect(loaded?.isOnline, isTrue);
    expect(loaded?.info.single.label, 'UID');
  });

  test('UserProfileCache ignores expired overview entries', () async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final cache = UserProfileCache(
      maxAge: Duration.zero,
      databaseProvider: () async => db,
    );
    const profile = UserProfile(
      uid: '123',
      name: 'Alice',
      url: 'https://south-plus.net/u.php?action-show-uid-123.html',
    );

    await cache.saveOverview(profile.url, profile);

    expect(await cache.loadOverview(profile.url), isNull);
  });
}
