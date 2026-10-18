import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_search_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectWrites = false;
  var throwWrites = false;
  Completer<bool>? heldWrite;
  Completer<void>? writeStarted;
  Completer<void>? allowLaterWrites;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectWrites = false;
    throwWrites = false;
    heldWrite = null;
    writeStarted = null;
    allowLaterWrites = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final held = heldWrite;
      if (held != null) {
        heldWrite = null;
        writeStarted!.complete();
        if (!await held.future) return false;
      }
      if (rejectWrites) {
        if (throwWrites) throw PlatformException(code: 'fixture-write-failure');
        return false;
      }
      if (allowLaterWrites != null) await allowLaterWrites!.future;
      final args = call.arguments as Map;
      persisted[args['key'] as String] = args['value'] as Object;
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  const account = 'fixture/reader';
  const pins = [
    ForumSearchPinnedBoard(id: '42', label: '保留甲'),
    ForumSearchPinnedBoard(id: '43', label: '保留乙'),
  ];

  Future<void> seed() async {
    await ForumSearchPreferences.saveDefaultMatch(ForumSearchMatch.partial,
        account: account);
    await ForumSearchPreferences.saveDefaultTime(ForumSearchTime.year,
        account: account);
    await ForumSearchPreferences.savePinnedBoards(pins, account: account);
    await ForumSearchPreferences.recordKeyword('保留乙', account: account);
    await ForumSearchPreferences.recordKeyword('保留甲', account: account);
  }

  final mutations = <String, Future<void> Function()>{
    'keyword record': () async {
      await ForumSearchPreferences.recordKeyword('未保存', account: account);
    },
    'keyword clear': () async {
      await ForumSearchPreferences.clearKeywords(account: account);
    },
    'pin clear': () =>
        ForumSearchPreferences.savePinnedBoards([], account: account),
    'default match': () => ForumSearchPreferences.saveDefaultMatch(
        ForumSearchMatch.exact,
        account: account),
    'default time': () => ForumSearchPreferences.saveDefaultTime(
        ForumSearchTime.day,
        account: account),
  };

  for (final mutation in mutations.entries) {
    for (final throws in [false, true]) {
      test(
          '${mutation.key} ${throws ? 'exception' : 'rejection'} preserves '
          'acknowledged pins and defaults for later writes', () async {
        await seed();
        final before = Map<String, Object>.of(persisted);
        rejectWrites = true;
        throwWrites = throws;
        await expectLater(mutation.value(),
            throwsA(throws ? isA<PlatformException>() : isA<StateError>()));
        expect(persisted, before);
        final restored = await ForumSearchPreferences.load(account: account);
        expect(restored.defaultMatch, ForumSearchMatch.partial);
        expect(restored.defaultTime, ForumSearchTime.year);
        expect(restored.recentKeywords, ['保留甲', '保留乙']);
        expect(restored.pinnedBoards.map((pin) => (pin.id, pin.label)),
            [('42', '保留甲'), ('43', '保留乙')]);

        rejectWrites = false;
        await ForumSearchPreferences.savePinnedBoards([
          ...restored.pinnedBoards,
          const ForumSearchPinnedBoard(id: '44', label: '新增'),
        ], account: account);
        await ForumSearchPreferences.saveDefaultMatch(ForumSearchMatch.exact,
            account: account);
        await ForumSearchPreferences.saveDefaultTime(ForumSearchTime.day,
            account: account);
        await ForumSearchPreferences.recordKeyword('新增', account: account);
        await (await SharedPreferences.getInstance()).reload();
        final saved = await ForumSearchPreferences.load(account: account);
        expect(saved.defaultMatch, ForumSearchMatch.exact);
        expect(saved.defaultTime, ForumSearchTime.day);
        expect(saved.recentKeywords, ['新增', '保留甲', '保留乙']);
        expect(saved.pinnedBoards.map((pin) => (pin.id, pin.label)),
            [('42', '保留甲'), ('43', '保留乙'), ('44', '新增')]);
        expect((await ForumSearchPreferences.load()).pinnedBoards, isEmpty);
      });
    }
  }

  test('pin reads and concurrent default writes wait for rejected pin recovery',
      () async {
    await seed();
    final gate = Completer<bool>();
    heldWrite = gate;
    writeStarted = Completer<void>();
    final failedClear =
        ForumSearchPreferences.savePinnedBoards([], account: account);
    final rejected = expectLater(failedClear, throwsStateError);
    await writeStarted!.future;
    allowLaterWrites = Completer<void>();
    final matchWrite = ForumSearchPreferences.saveDefaultMatch(
        ForumSearchMatch.exact,
        account: account);
    final timeWrite = ForumSearchPreferences.saveDefaultTime(
        ForumSearchTime.day,
        account: account);
    final pendingRead = ForumSearchPreferences.load(account: account);
    // Let unqueued writes reach the held platform acknowledgement, if any.
    await Future<void>.delayed(Duration.zero);
    gate.complete(false);
    await rejected;
    allowLaterWrites!.complete();
    await Future.wait([matchWrite, timeWrite]);
    final saved = await pendingRead;
    expect(saved.defaultMatch, ForumSearchMatch.exact);
    expect(saved.defaultTime, ForumSearchTime.day);
    expect(saved.pinnedBoards.map((pin) => pin.id), ['42', '43']);
    await (await SharedPreferences.getInstance()).reload();
    final durable = await ForumSearchPreferences.load(account: account);
    expect(durable.defaultMatch, saved.defaultMatch);
    expect(durable.defaultTime, saved.defaultTime);
    expect(durable.pinnedBoards.map((pin) => pin.id), ['42', '43']);
  });
}
