import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/account_scoped_keys.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/forum_account_id.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:south_plus_rewrite/services/local_database.dart';
import 'package:south_plus_rewrite/services/thread_read_position_store.dart';

final _originA = Uri.parse('https://forum-a.example/');
final _originB = Uri.parse('https://forum-b.example/');

ForumThread _thread(String tid, {String title = 't'}) => ForumThread(
      title: title,
      url: 'https://forum-a.example/read.php?tid-$tid.html',
      replies: 0,
      section: 'board',
    );

String _schemaVersionAt(String path) {
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return database
        .select("SELECT value FROM schema_meta WHERE key = 'version'")
        .single['value'] as String;
  } finally {
    database.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('AccountScope encodes account and guest independently', () {
    final a = ForumAccountId(origin: _originA, uid: '101');
    final sameUidOtherOrigin = ForumAccountId(origin: _originB, uid: '101');
    expect(AccountScope.account(a), a.value);
    expect(AccountScope.account(a),
        isNot(AccountScope.account(sameUidOtherOrigin)));
    expect(AccountScope.guest(_originA), isNot(AccountScope.guest(_originB)));
    expect(AccountScope.isGuest(AccountScope.guest(_originA)), isTrue);
  });

  test('history A/B/guest and same-uid cross-origin isolate; A clear leaves B',
      () async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final store = BrowsingHistoryStore(databaseProvider: () async => db);
    final scopeA = AccountScope.accountFrom(origin: _originA, uid: '101');
    final scopeB = AccountScope.accountFrom(origin: _originA, uid: '102');
    final scopeA2 = AccountScope.accountFrom(origin: _originB, uid: '101');
    final guestA = AccountScope.guest(_originA);

    await store.recordThreadForScope(scopeA, _thread('1', title: 'A1'));
    await store.recordThreadForScope(scopeB, _thread('2', title: 'B1'));
    await store.recordThreadForScope(
        scopeA2, _thread('3', title: 'A2-other-origin'));
    await store.recordThreadForScope(guestA, _thread('4', title: 'guest'));

    expect((await store.recentForScope(scopeA)).single.thread.title, 'A1');
    expect((await store.recentForScope(scopeB)).single.thread.title, 'B1');
    expect((await store.recentForScope(scopeA2)).single.thread.title,
        'A2-other-origin');
    expect((await store.recentForScope(guestA)).single.thread.title, 'guest');

    await store.clearForScope(scopeA);
    expect(await store.recentForScope(scopeA), isEmpty);
    expect((await store.recentForScope(scopeB)).single.thread.title, 'B1');
    expect((await store.recentForScope(scopeA2)).single.thread.title,
        'A2-other-origin');
    expect((await store.recentForScope(guestA)).single.thread.title, 'guest');
  });

  test('legacy unowned history remains and is not visible to scoped recent',
      () async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final store = BrowsingHistoryStore(databaseProvider: () async => db);
    final scopeA = AccountScope.accountFrom(origin: _originA, uid: '101');

    await store.recordThread(_thread('9', title: 'legacy'));
    await store.recordThreadForScope(scopeA, _thread('10', title: 'scoped-A'));

    expect((await store.recent()).single.thread.title, 'legacy');
    expect(
        (await store.recentForScope(scopeA)).single.thread.title, 'scoped-A');
    expect(db.browsingHistory().single.thread.title, 'legacy');
    await store.clearForScope(scopeA);
    expect(await store.recentForScope(scopeA), isEmpty);
    expect((await store.recent()).single.thread.title, 'legacy');
  });

  test('schema upgrade on real temp file keeps legacy and survives reopen', () {
    final dir = Directory.systemTemp.createTempSync('southplus-cp3a-db-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final path = '${dir.path}/legacy_then_v2.sqlite';

    // Seed a legacy-only DB (no schema_meta / browsing_history_v2).
    final raw = sqlite3.open(path);
    raw.execute('''
      CREATE TABLE browsing_history (
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
    raw.execute(
      'INSERT INTO browsing_history('
      'thread_url, title, replies, section, is_sticky, viewed_at) '
      "VALUES (?, 'keep-unowned', 0, 'board', 0, ?);",
      [
        'https://forum-a.example/read.php?tid-77.html',
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      ],
    );
    raw.close();

    final scopeA = AccountScope.accountFrom(origin: _originA, uid: '101');
    final scopeB = AccountScope.accountFrom(origin: _originA, uid: '102');

    final migrated = LocalDatabase.open(path);
    expect(_schemaVersionAt(path), '2');
    expect(migrated.browsingHistory().single.thread.title, 'keep-unowned');
    migrated.saveBrowsingHistoryForScope(
      accountScope: scopeA,
      thread: _thread('88', title: 'scoped-A'),
      viewedAt: DateTime.utc(2026, 1, 2),
    );
    migrated.saveBrowsingHistoryForScope(
      accountScope: scopeB,
      thread: _thread('89', title: 'scoped-B'),
      viewedAt: DateTime.utc(2026, 1, 3),
    );
    migrated.close();

    final reopened = LocalDatabase.open(path);
    addTearDown(reopened.close);
    expect(_schemaVersionAt(path), '2');
    expect(reopened.browsingHistory().single.thread.title, 'keep-unowned');
    expect(reopened.browsingHistoryForScope(scopeA).single.thread.title,
        'scoped-A');
    expect(reopened.browsingHistoryForScope(scopeB).single.thread.title,
        'scoped-B');

    reopened.clearBrowsingHistoryForScope(scopeA);
    expect(reopened.browsingHistoryForScope(scopeA), isEmpty);
    expect(reopened.browsingHistory().single.thread.title, 'keep-unowned',
        reason: 'clearForScope must not delete legacy unowned rows');
    expect(reopened.browsingHistoryForScope(scopeB).single.thread.title,
        'scoped-B');
  });

  test('read positions isolate by scope and leave legacy v1 unowned', () async {
    final store = ThreadReadPositionStore();
    final scopeA = AccountScope.accountFrom(origin: _originA, uid: '101');
    final scopeB = AccountScope.accountFrom(origin: _originA, uid: '102');
    const posA = ThreadReadPosition(page: 2, anchor: 'tpc');
    const posB = ThreadReadPosition(page: 5, anchor: '99');
    const posLegacy = ThreadReadPosition(page: 3);

    await store.save('tid-1', posLegacy);
    await store.saveForScope(scopeA, 'tid-1', posA);
    await store.saveForScope(scopeB, 'tid-1', posB);

    expect((await store.load('tid-1'))!.page, 3);
    expect((await store.loadForScope(scopeA, 'tid-1'))!.page, 2);
    expect((await store.loadForScope(scopeB, 'tid-1'))!.anchor, '99');

    await store.clearForScope(scopeA);
    expect(await store.loadForScope(scopeA, 'tid-1'), isNull);
    expect((await store.loadForScope(scopeB, 'tid-1'))!.page, 5);
    expect((await store.load('tid-1'))!.page, 3);
  });

  test('blocking owner uses origin+uid scope; no cross-origin uid share',
      () async {
    final scopeA = AccountScope.accountFrom(origin: _originA, uid: '101');
    final scopeB = AccountScope.accountFrom(origin: _originB, uid: '101');
    var currentScope = scopeA;
    final server = _NativeServer();
    final settings = ForumBlockingSettings(
      accountUid: () => ForumAccountId.parse(currentScope).uid,
      accountScope: () => currentScope,
      request: server.request,
    );

    await settings.setContent('noise-a', blocked: true);
    expect(settings.notifier.value.isContentBlocked('noise-a'), isTrue);

    currentScope = scopeB;
    await settings.load();
    expect(settings.notifier.value.contentKeys, isEmpty);
    await settings.setContent('noise-b', blocked: true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('blocking.local.$scopeA'), isNotNull);
    expect(prefs.getString('blocking.local.$scopeB'), isNotNull);
    expect(prefs.getString('blocking.local.101'), isNull,
        reason: 'must not use uid-only key when scope is set');

    currentScope = scopeA;
    await settings.load();
    expect(settings.notifier.value.isContentBlocked('noise-a'), isTrue);
    expect(settings.notifier.value.isContentBlocked('noise-b'), isFalse);
  });

  test('blocking late write rejects after owner switch mid-flight', () async {
    final scopeA = AccountScope.accountFrom(origin: _originA, uid: '101');
    final scopeB = AccountScope.accountFrom(origin: _originA, uid: '102');
    var currentScope = scopeA;
    final settings = ForumBlockingSettings(
      accountUid: () => ForumAccountId.parse(currentScope).uid,
      accountScope: () => currentScope,
      request: _NativeServer().request,
    );
    await settings.load();
    final pending = settings.setContent('late', blocked: true);
    currentScope = scopeB;
    settings.reset();
    await expectLater(pending, throwsA(isA<ForumRequestException>()));
    final prefs = await SharedPreferences.getInstance();
    final rawB = prefs.getString('blocking.local.$scopeB');
    expect(rawB == null || !rawB.contains('late'), isTrue);
    // Captured owner A may or may not have completed before reset; B must stay clean.
  });
}

class _NativeServer {
  Future<String> request(String action, Map<String, String> fields) async {
    if (action == 'getblocklist') {
      final config = jsonEncode({
        'version': '3.1',
        'blist': <String, dynamic>{},
        'curiosity': false,
        'showBTN': true,
      });
      return '<ajax><![CDATA[$config]]></ajax>';
    }
    return '<ajax><![CDATA[success]]></ajax>';
  }
}
