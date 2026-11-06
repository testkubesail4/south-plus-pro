import '../models/forum_models.dart';
import 'local_database.dart';

class BrowsingHistoryStore {
  BrowsingHistoryStore({
    Future<LocalDatabase> Function()? databaseProvider,
    this.maxEntries = browsingHistoryLimit,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<LocalDatabase> Function() _databaseProvider;
  final int maxEntries;

  /// Legacy unowned history (pre-multi-account). Not scoped isolation.
  Future<List<BrowsingHistoryEntry>> recent(
      {int limit = browsingHistoryLimit}) async {
    final db = await _databaseProvider();
    return db.browsingHistory(limit: limit);
  }

  /// Scoped v2 history. Pass scope captured at request start.
  Future<List<BrowsingHistoryEntry>> recentForScope(
    String scope, {
    int limit = browsingHistoryLimit,
  }) async {
    final db = await _databaseProvider();
    return db.browsingHistoryForScope(scope, limit: limit);
  }

  /// Legacy unowned write path.
  Future<void> recordThread(
    ForumThread thread, {
    DateTime? viewedAt,
  }) async {
    if (thread.url.trim().isEmpty || thread.title.trim().isEmpty) return;
    final db = await _databaseProvider();
    db.saveBrowsingHistory(
      thread: thread,
      viewedAt: viewedAt ?? DateTime.now().toUtc(),
      maxEntries: maxEntries,
    );
  }

  /// Scoped v2 write. Callers must pass captured scope (not a live singleton).
  Future<void> recordThreadForScope(
    String scope,
    ForumThread thread, {
    DateTime? viewedAt,
  }) async {
    if (thread.url.trim().isEmpty || thread.title.trim().isEmpty) return;
    final db = await _databaseProvider();
    db.saveBrowsingHistoryForScope(
      accountScope: scope,
      thread: thread,
      viewedAt: viewedAt ?? DateTime.now().toUtc(),
      maxEntries: maxEntries,
    );
  }

  /// Clears legacy unowned rows only.
  Future<void> clear() async {
    final db = await _databaseProvider();
    db.clearBrowsingHistory();
  }

  /// Clears one scope's v2 rows only.
  Future<void> clearForScope(String scope) async {
    final db = await _databaseProvider();
    db.clearBrowsingHistoryForScope(scope);
  }
}
