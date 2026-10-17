import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

import 'support/native_favorite_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ForumRepository repository(NativeFavoriteClient client) {
    final result = ForumRepository(client: client);
    addTearDown(result.clearSession);
    return result;
  }

  test(
      'native all and query-only folder reads expose sidebar create and independent row IDs',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final all = await repo.fetchFavoriteCollections();
    expect(all.categoryId, isNull);
    expect(all.categories.map((c) => c.id), ['0', '1', '2']);
    expect(all.categories.map((c) => c.count), [1, 1, 0]);
    expect(all.categories.map((c) => c.canDelete), [false, true, true]);
    expect(all.canCreate, isTrue);
    expect(all.nameMaxLength, isNull, reason: 'size=6 is not maxlength');
    expect(all.items.map((item) => item.id), ['501', '502']);
    expect(all.items.map((item) => item.thread.threadId), ['701', '702']);
    expect(all.items.map((item) => item.categoryId), ['0', '1']);
    final folder = await repo.fetchFavoriteCollections(categoryId: '1');
    expect(folder.items.single.id, '502');
    expect(client.reads.last.toString(), 'u.php?action=favor&type=1');
    expect(client.writes, isEmpty);
  });

  test(
      'creation confirms fresh unique names even when a data-triggered transport exception follows the write',
      () async {
    for (final name in ['操作完成', '收藏成功', '请求过于频繁', 'A  B']) {
      final client = NativeFavoriteClient()
        ..categories = []
        ..rows = [(id: '501', tid: '701', category: '')]
        ..throwAfterWrite = true;
      final repo = repository(client);
      final before = await repo.fetchFavoriteCollections();
      final result = await repo.createFavoriteCategory(before, ' $name ');
      expect(result.status, FavoriteMutationStatus.confirmed);
      expect(result.createdCategory!.label, name);
      expect(result.collections!.categories.last.label, name);
      expect(client.writes, hasLength(1));
      expect(_values(client, 'verify'), ['token-2']);
      expect(_values(client, 'job'), ['addtype']);
      expect(_values(client, 'type'), [name]);
      await expectLater(repo.createFavoriteCategory(before, 'again'), _invalid);
      expect(client.writes, hasLength(1),
          reason: 'the original snapshot is retired');
    }
  });

  test(
      'one native batch preserves exact selected row IDs and confirms each destination',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    final result = await repo.moveFavorites(snapshot, snapshot.items, '2');
    expect(result.status, FavoriteMutationStatus.confirmed);
    expect(result.items.map((item) => item.id), ['501', '502']);
    expect(
        result.items
            .every((item) => item.status == FavoriteMutationStatus.confirmed),
        isTrue);
    expect(_values(client, 'selid[]'), ['501', '502']);
    expect(_values(client, 'type'), ['2']);
    expect(_values(client, 'job'), ['change']);
    expect(client.writes, hasLength(1));
    expect(result.collections!.items.every((item) => item.categoryId == '2'),
        isTrue);
  });

  test(
      'external category renumber resolves original add move and delete intent, not stale IDs',
      () async {
    for (final operation in ['add', 'move', 'delete']) {
      final client = NativeFavoriteClient();
      final repo = repository(client);
      final snapshot = await repo.fetchFavoriteCollections();
      client.beforeNextRead = () {
        client.categories.removeAt(0);
        client.rows = [
          (id: '501', tid: '701', category: ''),
          (id: '502', tid: '702', category: '')
        ];
      };
      final result = operation == 'add'
          ? await repo.addFavoriteToCollection(
              snapshot, const ThreadFavorite(tid: '703', verify: 'token'), '2')
          : operation == 'move'
              ? await repo.moveFavorites(snapshot, [snapshot.items.first], '2')
              : await repo.deleteFavoriteCategory(snapshot, '2');
      expect(result.status, FavoriteMutationStatus.confirmed,
          reason: operation);
      final type = operation == 'add'
          ? Uri.parse(client.writes.single.$1).queryParameters['type']
          : _values(client, 'type').single;
      expect(type, '1', reason: 'old B id2 became id1');
      if (operation == 'delete') {
        expect(result.collections!.categories.map((category) => category.id),
            ['0']);
      } else {
        expect(client.rows.any((row) => row.category == 'B'), isTrue);
        expect(result.collections!.categories.last.id, '1');
        expect(result.collections!.categories.last.label, 'B');
      }
      expect(client.writes, hasLength(1));
    }
  });

  test(
      'delete nonempty category preserves posts in default and publishes renumbered IDs',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    await expectLater(repo.deleteFavoriteCategory(snapshot, '0'), _invalid);
    final result = await repo.deleteFavoriteCategory(snapshot, '1');
    expect(result.status, FavoriteMutationStatus.confirmed);
    expect(client.rows.map((row) => row.tid), ['701', '702']);
    expect(client.rows.every((row) => row.category.isEmpty), isTrue);
    expect(result.collections!.categories.map((c) => '${c.id}:${c.label}'),
        ['0:默认分类', '1:B']);
    expect(result.collections!.items.every((item) => item.categoryId == '0'),
        isTrue);
    expect(_values(client, 'job'), ['deltype']);
    expect(client.writes, hasLength(1));
  });

  test(
      'ambiguous category names, forged rows, repeated IDs and external source moves never dispatch',
      () async {
    for (final scenario in ['duplicate', 'forged', 'repeated', 'source']) {
      final client = NativeFavoriteClient();
      final repo = repository(client);
      final snapshot = await repo.fetchFavoriteCollections();
      var selected = [snapshot.items.first];
      if (scenario == 'duplicate')
        client.beforeNextRead = () {
          client.categories = ['B', 'B'];
        };
      if (scenario == 'forged')
        selected = [
          FavoriteCollectionEntry(
              id: selected.first.id,
              thread: selected.first.thread,
              categoryId: selected.first.categoryId)
        ];
      if (scenario == 'repeated') selected = [selected.first, selected.first];
      if (scenario == 'source')
        client.beforeNextRead = () {
          client.rows[0] = (id: '501', tid: '701', category: 'A');
        };
      await expectLater(repo.moveFavorites(snapshot, selected, '2'), _invalid);
      expect(client.writes, isEmpty, reason: scenario);
    }
  });

  test(
      'unknown clear ACK confirms only from complete fresh absence, not identical 操作完成 text',
      () async {
    for (final apply in [true, false]) {
      final client = NativeFavoriteClient()
        ..applyWrite = apply
        ..postResponse = apply ? 'unknown' : nativeFavoriteAck;
      final repo = repository(client);
      final snapshot = await repo.fetchFavoriteCollections();
      final result =
          await repo.removeFavorites(snapshot, [snapshot.items.first]);
      expect(
          result.status,
          apply
              ? FavoriteMutationStatus.confirmed
              : FavoriteMutationStatus.rejected);
      expect(result.collections!.items.map((item) => item.id).contains('501'),
          !apply);
      expect(client.writes, hasLength(1));
    }
  });

  test(
      'partial native batch reports per-row completion and retains a fresh retry capability',
      () async {
    final client = NativeFavoriteClient()..applyOnlyIds = {'501'};
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    final result = await repo.moveFavorites(snapshot, snapshot.items, '2');
    expect(result.status, FavoriteMutationStatus.rejected);
    expect(result.items.map((item) => item.status),
        [FavoriteMutationStatus.confirmed, FavoriteMutationStatus.rejected]);
    expect(result.collections, isNotNull);
    client.applyOnlyIds = null;
    final fresh = result.collections!;
    final remaining = fresh.items.where((item) => item.id == '502').toList();
    expect((await repo.moveFavorites(fresh, remaining, '2')).status,
        FavoriteMutationStatus.confirmed);
    expect(client.writes, hasLength(2),
        reason: 'retry is a separate user action on a fresh snapshot');
  });

  test(
      'unreadable or paginated absence stays unknown and never auto-replays a write',
      () async {
    for (final failure in ['readback', 'pagination', 'destination']) {
      final client = NativeFavoriteClient();
      final repo = repository(client);
      if (failure == 'pagination') client.pageCount = 2;
      final snapshot = await repo.fetchFavoriteCollections();
      if (failure == 'pagination') {
        expect(snapshot.categories.every((category) => category.count == null),
            isTrue);
        expect(snapshot.pageCount, 2);
      }
      if (failure == 'readback') client.failReadback = true;
      if (failure == 'destination') client.failDestination = true;
      final result = failure == 'destination'
          ? await repo.moveFavorites(snapshot, [snapshot.items.first], '2')
          : await repo.removeFavorites(snapshot, [snapshot.items.first]);
      expect(result.status, FavoriteMutationStatus.unknown);
      if (failure == 'readback') expect(result.collections, isNull);
      expect(client.writes, hasLength(1));
      await expectLater(
          repo.removeFavorites(snapshot, [snapshot.items.first]), _invalid);
      expect(client.writes, hasLength(1));
    }
  });

  test(
      'present but unreadable pagination never turns absent rows into clear confirmation',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    client.pageTransform = (html) => html.replaceFirst(
        '</body>', '<ul class="pages"><li>unreadable counter</li></ul></body>');
    final result = await repo.removeFavorites(snapshot, [snapshot.items.first]);
    expect(result.status, FavoriteMutationStatus.unknown);
    expect(result.collections!.pageCount, isNull);
    expect(
        result.collections!.categories
            .every((category) => category.count == null),
        isTrue);
    expect(client.writes, hasLength(1));
    await expectLater(
        repo.removeFavorites(result.collections!, result.collections!.items),
        _invalid,
        reason: 'an uncertain result is display data, not a retry capability');
    expect(client.writes, hasLength(1));
  });

  test(
      'disabled native verify name jobs selections and destinations cannot be forged in a write',
      () async {
    for (final (operation, from, to) in [
      ('move', 'name="verify"', 'name="verify" disabled'),
      (
        'create',
        'name="job" value="addtype"',
        'name="job" value="addtype" disabled'
      ),
      ('create', 'name="type" size="6"', 'name="type" size="6" disabled'),
      (
        'move',
        'name="job" value="change"',
        'name="job" value="change" disabled'
      ),
      (
        'clear',
        'name="job" value="clear"',
        'name="job" value="clear" disabled'
      ),
      (
        'move',
        '<option value="2">B</option>',
        '<optgroup disabled><option value="2">B</option></optgroup>'
      ),
      ('clear', '<option value="0">', '<option value="0" disabled>'),
      ('move', '<select name="type">', '<select name="type" disabled>'),
      (
        'move',
        'name="selid[]" value="501"',
        'name="selid[]" value="501" disabled'
      ),
      (
        'create',
        '<input class="input" type="text" name="type" size="6">',
        '<fieldset disabled><input class="input" type="text" name="type" size="6"></fieldset>'
      ),
    ]) {
      final client = NativeFavoriteClient();
      final repo = repository(client);
      final snapshot = await repo.fetchFavoriteCollections();
      client.pageTransform = (html) => html.replaceAll(from, to);
      final pending = operation == 'create'
          ? repo.createFavoriteCategory(snapshot, 'C')
          : operation == 'clear'
              ? repo.removeFavorites(snapshot, [snapshot.items.first])
              : repo.moveFavorites(snapshot, [snapshot.items.first], '2');
      await expectLater(pending, throwsA(isA<ForumRequestException>()),
          reason: '$operation $from');
      expect(client.writes, isEmpty, reason: '$operation $from');
    }
  });

  test(
      'typed favorite is one chosen-folder write with fresh verify and membership proof',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    final result = await repo.addFavoriteToCollection(snapshot,
        const ThreadFavorite(tid: '703', verify: 'old-thread-token'), '2');
    expect(result.status, FavoriteMutationStatus.confirmed);
    final write = Uri.parse(client.writes.single.$1);
    expect(write.path, 'pw_ajax.php');
    expect(write.queryParameters['type'], '2');
    expect(write.queryParameters['verify'], 'token-2');
    expect(int.tryParse(write.queryParameters['nowtime']!), isNotNull);
    expect(
        result.collections!.items
            .singleWhere((item) => item.thread.threadId == '703')
            .categoryId,
        '2');
    final fresh = await repo.fetchFavoriteCollections();
    final existing = await repo.addFavoriteToCollection(
        fresh, const ThreadFavorite(tid: '701', verify: 'token'), '2');
    expect(existing.status, FavoriteMutationStatus.rejected,
        reason:
            'already-favorite ACK does not move a default favorite to the chosen folder');
    expect(client.rows.first.category, '');
  });

  test(
      'literal native add rejection is distinct from a user category named 收藏成功',
      () async {
    final client = NativeFavoriteClient()
      ..applyWrite = false
      ..favoriteResponse = '<ajax><![CDATA[非法请求，请返回重试!]]></ajax>';
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    final result = await repo.addFavoriteToCollection(
        snapshot, const ThreadFavorite(tid: '703', verify: 'token'), '1');
    expect(result.status, FavoriteMutationStatus.rejected);
    expect(result.message, '非法请求，请返回重试!');
    expect(result.collections, isNotNull);
    expect(client.writes, hasLength(1));
  });

  test(
      'session replacement after dispatch cannot publish another account readback',
      () async {
    final client = NativeFavoriteClient()..writeGate = Completer<void>();
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    final pending = repo.createFavoriteCategory(snapshot, 'C');
    final rejected = expectLater(pending, _stale);
    await client.writeStarted.future;
    final before = client.reads.length;
    await repo.clearSession();
    client.writeGate!.complete();
    await rejected;
    expect(client.writes, hasLength(1));
    expect(client.reads, hasLength(before),
        reason: 'never read the next account to confirm an old write');
  });

  test(
      'missing native table is failure, not empty folder or successful readback',
      () async {
    final client = NativeFavoriteClient()..missingTable = true;
    final repo = repository(client);
    await expectLater(
        repo.fetchFavoriteCollections(), throwsA(isA<ForumRequestException>()));
    expect(client.writes, isEmpty);
  });

  test(
      'legacy failed or unconfirmed thread removal preserves its original state',
      () async {
    for (final state in [
      ThreadFavoriteState.unknown,
      ThreadFavoriteState.notFavorite
    ]) {
      for (final unknown in [false, true]) {
        final client = NativeFavoriteClient()
          ..applyWrite = unknown
          ..failReadback = unknown;
        final repo = repository(client);
        final result = await repo.removeFavorite(
            ThreadFavorite(tid: '701', verify: 'old', state: state));
        expect(result.success, isFalse);
        expect(result.state, state);
        expect(client.writes, hasLength(1));
      }
    }
  });

  test(
      'foreign snapshots and session changes cannot publish or dispatch stale operations',
      () async {
    final client = NativeFavoriteClient();
    final repo = repository(client);
    final snapshot = await repo.fetchFavoriteCollections();
    final other = repository(client);
    await expectLater(other.createFavoriteCategory(snapshot, 'C'), _invalid);
    await repo.clearSession();
    await expectLater(repo.createFavoriteCategory(snapshot, 'C'), _stale);
    expect(client.writes, isEmpty);

    final pendingClient = NativeFavoriteClient()..readGate = Completer<void>();
    final pendingRepo = repository(pendingClient);
    final pending = pendingRepo.fetchFavoriteCollections();
    final rejected = expectLater(pending, _stale);
    await pendingRepo.clearSession();
    pendingClient.readGate!.complete();
    await rejected;
  });
}

List<String> _values(NativeFavoriteClient client, String name) =>
    client.writes.single.$2
        .where((field) => field.key == name)
        .map((field) => field.value)
        .toList();
final _invalid = throwsA(isA<ForumRequestException>()
    .having((error) => error.kind, 'kind', ForumRequestKind.invalidInput));
final _stale = throwsA(isA<ForumRequestException>()
    .having((error) => error.kind, 'kind', ForumRequestKind.loginRequired));
