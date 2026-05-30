import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

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
      statement.close();
    }
  }

  void close() {
    _db.close();
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
