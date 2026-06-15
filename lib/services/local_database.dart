import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/forum_models.dart';

class LocalDatabase {
  LocalDatabase._(this._db) {
    _migrate();
  }

  factory LocalDatabase.openForTesting() {
    return LocalDatabase._(sqlite3.openInMemory());
  }

  static LocalDatabase? _instance;

  static Future<LocalDatabase> instance() async {
    final existing = _instance;
    if (existing != null) return existing;

    final dir = await getApplicationSupportDirectory();
    final db = sqlite3.open(p.join(dir.path, 'south_plus.sqlite'));
    _instance = LocalDatabase._(db);
    return _instance!;
  }

  final Database _db;

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS profile_overview_cache (
        cache_key TEXT PRIMARY KEY,
        profile_url TEXT NOT NULL,
        uid TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_profile_overview_cache_uid
      ON profile_overview_cache(uid);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS browsing_history (
        thread_url TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        replies INTEGER NOT NULL,
        section TEXT NOT NULL,
        body_preview TEXT,
        last_post TEXT,
        author TEXT,
        author_url TEXT,
        author_avatar_url TEXT,
        author_posts_url TEXT,
        is_sticky INTEGER NOT NULL DEFAULT 0,
        viewed_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_browsing_history_viewed_at
      ON browsing_history(viewed_at DESC);
    ''');
  }

  CachedProfileOverviewRow? profileOverview(String cacheKey) {
    final rows = _db.select(
      '''
      SELECT cache_key, profile_url, uid, payload_json, cached_at
      FROM profile_overview_cache
      WHERE cache_key = ?
      LIMIT 1;
      ''',
      [cacheKey],
    );
    if (rows.isEmpty) return null;
    return CachedProfileOverviewRow.fromSql(rows.first);
  }

  void saveProfileOverview({
    required Iterable<String> cacheKeys,
    required String profileUrl,
    required String uid,
    required String payloadJson,
    required DateTime cachedAt,
  }) {
    final statement = _db.prepare('''
      INSERT INTO profile_overview_cache (
        cache_key, profile_url, uid, payload_json, cached_at
      )
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(cache_key) DO UPDATE SET
        profile_url = excluded.profile_url,
        uid = excluded.uid,
        payload_json = excluded.payload_json,
        cached_at = excluded.cached_at;
    ''');
    try {
      _db.execute('BEGIN TRANSACTION;');
      for (final cacheKey in cacheKeys) {
        statement.execute([
          cacheKey,
          profileUrl,
          uid,
          payloadJson,
          cachedAt.millisecondsSinceEpoch,
        ]);
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      statement.dispose();
    }
  }

  List<BrowsingHistoryEntry> browsingHistory({int limit = 100}) {
    final normalizedLimit = limit.clamp(1, 500).toInt();
    final rows = _db.select(
      '''
      SELECT thread_url, title, replies, section, body_preview, last_post,
        author, author_url, author_avatar_url, author_posts_url, is_sticky,
        viewed_at
      FROM browsing_history
      ORDER BY viewed_at DESC
      LIMIT ?;
      ''',
      [normalizedLimit],
    );
    return rows.map(BrowsingHistoryRow.fromSql).toList(growable: false);
  }

  void saveBrowsingHistory({
    required ForumThread thread,
    required DateTime viewedAt,
    int maxEntries = 200,
  }) {
    final statement = _db.prepare('''
      INSERT INTO browsing_history (
        thread_url, title, replies, section, body_preview, last_post,
        author, author_url, author_avatar_url, author_posts_url, is_sticky,
        viewed_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(thread_url) DO UPDATE SET
        title = excluded.title,
        replies = excluded.replies,
        section = excluded.section,
        body_preview = excluded.body_preview,
        last_post = excluded.last_post,
        author = excluded.author,
        author_url = excluded.author_url,
        author_avatar_url = excluded.author_avatar_url,
        author_posts_url = excluded.author_posts_url,
        is_sticky = excluded.is_sticky,
        viewed_at = excluded.viewed_at;
    ''');
    try {
      _db.execute('BEGIN TRANSACTION;');
      statement.execute([
        thread.url,
        thread.title,
        thread.replies,
        thread.section,
        thread.bodyPreview,
        thread.lastPost,
        thread.author,
        thread.authorUrl,
        thread.authorAvatarUrl,
        thread.authorPostsUrl,
        thread.isSticky ? 1 : 0,
        viewedAt.toUtc().millisecondsSinceEpoch,
      ]);
      _db.execute(
        '''
        DELETE FROM browsing_history
        WHERE thread_url NOT IN (
          SELECT thread_url
          FROM browsing_history
          ORDER BY viewed_at DESC
          LIMIT ?
        );
        ''',
        [maxEntries.clamp(1, 1000).toInt()],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      statement.dispose();
    }
  }

  void clearBrowsingHistory() {
    _db.execute('DELETE FROM browsing_history;');
  }

  void close() {
    _db.dispose();
  }
}

class CachedProfileOverviewRow {
  const CachedProfileOverviewRow({
    required this.cacheKey,
    required this.profileUrl,
    required this.uid,
    required this.payloadJson,
    required this.cachedAt,
  });

  factory CachedProfileOverviewRow.fromSql(Row row) {
    return CachedProfileOverviewRow(
      cacheKey: row['cache_key'] as String,
      profileUrl: row['profile_url'] as String,
      uid: row['uid'] as String,
      payloadJson: row['payload_json'] as String,
      cachedAt: DateTime.fromMillisecondsSinceEpoch(
        row['cached_at'] as int,
        isUtc: true,
      ),
    );
  }

  final String cacheKey;
  final String profileUrl;
  final String uid;
  final String payloadJson;
  final DateTime cachedAt;
}

class BrowsingHistoryRow {
  static BrowsingHistoryEntry fromSql(Row row) {
    return BrowsingHistoryEntry(
      thread: ForumThread(
        title: row['title'] as String,
        url: row['thread_url'] as String,
        replies: row['replies'] as int,
        section: row['section'] as String,
        bodyPreview: row['body_preview'] as String?,
        lastPost: row['last_post'] as String?,
        author: row['author'] as String?,
        authorUrl: row['author_url'] as String?,
        authorAvatarUrl: row['author_avatar_url'] as String?,
        authorPostsUrl: row['author_posts_url'] as String?,
        isSticky: (row['is_sticky'] as int) == 1,
      ),
      viewedAt: DateTime.fromMillisecondsSinceEpoch(
        row['viewed_at'] as int,
        isUtc: true,
      ),
    );
  }
}
