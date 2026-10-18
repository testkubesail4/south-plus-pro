import '../models/forum_models.dart';
import 'local_database.dart';

class BrowsingHistoryStore {
  BrowsingHistoryStore({
    Future<LocalDatabase> Function()? databaseProvider,
    this.maxEntries = browsingHistoryLimit,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<LocalDatabase> Function() _databaseProvider;
  final int maxEntries;

  Future<List<BrowsingHistoryEntry>> recent(
      {int limit = browsingHistoryLimit}) async {
    final db = await _databaseProvider();
    return db.browsingHistory(limit: limit);
  }

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

  Future<void> clear() async {
    final db = await _databaseProvider();
    db.clearBrowsingHistory();
  }
}
