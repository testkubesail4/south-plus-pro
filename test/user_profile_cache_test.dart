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

  test('LocalDatabase stores browsing history by most recent view', () {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final firstView = DateTime.utc(2026, 5, 30, 10);
    final secondView = DateTime.utc(2026, 5, 30, 11);
    const firstThread = ForumThread(
      title: '旧标题',
      url: 'https://south-plus.net/read.php?tid-1.html',
      replies: 2,
      section: '茶馆',
      author: 'Alice',
    );
    const secondThread = ForumThread(
      title: '另一个帖子',
      url: 'https://south-plus.net/read.php?tid-2.html',
      replies: 0,
      section: '事务受理',
    );

    db.saveBrowsingHistory(thread: firstThread, viewedAt: firstView);
    db.saveBrowsingHistory(thread: secondThread, viewedAt: secondView);
    db.saveBrowsingHistory(
      thread: firstThread.copyWith(title: '新标题', replies: 3),
      viewedAt: secondView.add(const Duration(minutes: 1)),
    );

    final history = db.browsingHistory();

    expect(history, hasLength(2));
    expect(history.first.thread.title, '新标题');
    expect(history.first.thread.replies, 3);
    expect(history.first.thread.author, 'Alice');
    expect(history.last.thread.title, '另一个帖子');
  });

  test('LocalDatabase caps browsing history entries', () {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);

    for (var index = 0; index < 3; index++) {
      db.saveBrowsingHistory(
        thread: ForumThread(
          title: '帖子 $index',
          url: 'https://south-plus.net/read.php?tid-$index.html',
          replies: index,
          section: '茶馆',
        ),
        viewedAt: DateTime.utc(2026, 5, 30, 10, index),
        maxEntries: 2,
      );
    }

    final history = db.browsingHistory(limit: 10);

    expect(history.map((entry) => entry.thread.title), ['帖子 2', '帖子 1']);
  });
}
