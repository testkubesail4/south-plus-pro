import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectWrites = false;
  var throwWrites = false;
  var rejectReads = false;
  Completer<bool>? heldWrite;
  Completer<void>? writeStarted;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectWrites = false;
    throwWrites = false;
    rejectReads = false;
    heldWrite = null;
    writeStarted = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'fixture-read-failure');
        return Map<String, Object>.of(persisted);
      }
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
      final args = call.arguments as Map;
      final key = args['key'] as String;
      if (call.method == 'remove') {
        persisted.remove(key);
      } else {
        persisted[key] = args['value'] as Object;
      }
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  const board42 = ForumCategory(name: '原版块', slug: 'fid-42');
  const board43 = ForumCategory(name: '新版块', slug: 'fid-43');

  Future<void> seed() async {
    await UserNoteStore.save('42', '原备注');
    await UserTagStore.save('42', ['原标签']);
    await HomeReadingPreferences.saveQuickRowCount(5);
    await HomeReadingPreferences.setCollapsed('board:42', true);
    await HomeReadingPreferences.recordBoardVisit(board42);
  }

  final mutations = <String, Future<void> Function()>{
    'note update': () => UserNoteStore.save('42', '失败的更新'),
    'tag update': () => UserTagStore.save('42', ['未保存']),
    'last tag clear': () => UserTagStore.clear('42'),
    'last note clear': () => UserNoteStore.clear('42'),
    'quick row change': () => HomeReadingPreferences.saveQuickRowCount(3),
    'collapse removal': () =>
        HomeReadingPreferences.setCollapsed('board:42', false),
    'recent visit': () => HomeReadingPreferences.recordBoardVisit(board43),
    'recent clear': () => HomeReadingPreferences.clearRecentBoards(),
    'layout section hide': () => HomeReadingPreferences.setSectionHidden('section-id:7', true),
    'layout parent hide': () => HomeReadingPreferences.setParentHidden('42', true),
    'layout order': () => HomeReadingPreferences.saveSectionOrder(['section-id:7']),
    'layout restore': () => HomeReadingPreferences.restoreLayout(),
  };

  for (final mutation in mutations.entries) {
    for (final throws in [false, true]) {
      test(
          '${mutation.key} rejected by ${throws ? 'exception' : 'false'} '
          'preserves acknowledged state for later writes', () async {
        await seed();
        final restoring = mutation.key == 'layout restore';
        if (restoring) {
          await HomeReadingPreferences.saveSectionOrder(['section-id:39', 'section-id:7']);
          await HomeReadingPreferences.setSectionHidden('section-id:7', true);
          await HomeReadingPreferences.setParentHidden('42', true);
        }
        final expectedOrder = restoring ? ['section-id:39', 'section-id:7'] : <String>[];
        final expectedSections = restoring ? {'section-id:7'} : <String>{};
        final expectedParents = restoring ? {'42'} : <String>{};
        final before = Map<String, Object>.of(persisted);
        final notesRevision = UserNoteStore.revision.value;
        final tagsRevision = UserTagStore.revision.value;
        final homeRevision = HomeReadingPreferences.revision.value;
        rejectWrites = true;
        throwWrites = throws;
        await expectLater(mutation.value(),
            throwsA(throws ? isA<PlatformException>() : isA<StateError>()));
        expect(persisted, before);
        expect(UserNoteStore.revision.value, notesRevision);
        expect(UserTagStore.revision.value, tagsRevision);
        expect(HomeReadingPreferences.revision.value, homeRevision);
        expect(await UserNoteStore.load(), {'42': '原备注'});
        expect(await UserTagStore.load(), {'42': ['原标签']});
        await (await SharedPreferences.getInstance()).reload();
        final restored = await HomeReadingPreferences.load();
        expect(restored.sectionOrder, expectedOrder);
        expect(restored.hiddenSectionIds, expectedSections);
        expect(restored.hiddenParentFids, expectedParents);
        expect(restored.quickRowCount, 5);
        expect(restored.collapsedIds, {'board:42'});
        expect(restored.recentBoards.map((board) => board.id), ['42']);

        rejectWrites = false;
        await UserNoteStore.save('43', '新备注');
        await UserTagStore.save('43', ['新标签']);
        await HomeReadingPreferences.saveQuickRowCount(6);
        await HomeReadingPreferences.setCollapsed('board:43', true);
        await HomeReadingPreferences.recordBoardVisit(board43);
        await (await SharedPreferences.getInstance()).reload();
        expect(await UserNoteStore.load(), {'42': '原备注', '43': '新备注'});
        expect(await UserTagStore.load(), {'42': ['原标签'], '43': ['新标签']});
        final retried = await HomeReadingPreferences.load();
        expect(retried.sectionOrder, expectedOrder);
        expect(retried.hiddenSectionIds, expectedSections);
        expect(retried.hiddenParentFids, expectedParents);
        expect(retried.quickRowCount, 6);
        expect(retried.collapsedIds, {'board:42', 'board:43'});
        expect(retried.recentBoards.map((board) => board.id), ['43', '42']);
      });
    }
  }

  test('overlapping notes and home reads wait for failed-write recovery',
      () async {
    await seed();
    final gate = Completer<bool>();
    heldWrite = gate;
    writeStarted = Completer<void>();
    final failedClear = UserNoteStore.clear('42');
    final rejected = expectLater(failedClear, throwsStateError);
    await writeStarted!.future;
    final nextNote = UserNoteStore.save('43', '新备注');
    final nextHome = HomeReadingPreferences.saveQuickRowCount(3);
    final notesRead = UserNoteStore.load();
    final homeRead = HomeReadingPreferences.load();
    gate.complete(false);
    await rejected;
    await Future.wait([nextNote, nextHome]);
    expect(await notesRead, {'42': '原备注', '43': '新备注'});
    expect((await homeRead).quickRowCount, 3);
    await (await SharedPreferences.getInstance()).reload();
    expect(await UserNoteStore.load(), {'42': '原备注', '43': '新备注'});
    expect((await HomeReadingPreferences.load()).quickRowCount, 3);
  });

  test('failed recovery blocks cached reads until persisted state is available',
      () async {
    await seed();
    rejectWrites = true;
    rejectReads = true;
    await expectLater(UserNoteStore.clear('42'), throwsStateError);
    await expectLater(UserNoteStore.load(), throwsA(isA<PlatformException>()));
    rejectWrites = false;
    rejectReads = false;
    await UserNoteStore.save('43', '新备注');
    await (await SharedPreferences.getInstance()).reload();
    expect(await UserNoteStore.load(), {'42': '原备注', '43': '新备注'});
  });
}
