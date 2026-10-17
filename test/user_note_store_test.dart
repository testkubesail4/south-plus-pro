import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('UID notes add, update and clear without touching other users',
      () async {
    expect(await UserNoteStore.load(), isEmpty);
    final revision = UserNoteStore.revision.value;
    await UserNoteStore.save('42', '  可信作者\n同名时按 UID 区分  ');
    await UserNoteStore.save('43', '<本地备注>');
    expect(await UserNoteStore.load(), {
      '42': '可信作者\n同名时按 UID 区分',
      '43': '<本地备注>',
    });
    await UserNoteStore.save('42', '新备注');
    expect((await UserNoteStore.load())['42'], '新备注');
    await UserNoteStore.clear('42');
    expect(await UserNoteStore.load(), {'43': '<本地备注>'});
    await UserNoteStore.save('43', ' \n ');
    expect(await UserNoteStore.load(), isEmpty);
    expect(UserNoteStore.revision.value, revision + 5);
  });

  test('notes are isolated by exact account and anonymous namespace', () async {
    await UserNoteStore.save('42', '访客');
    await UserNoteStore.save('42', '甲', account: 'reader/a');
    await UserNoteStore.save('42', '乙', account: 'reader%2Fa');
    await UserNoteStore.clear('42', account: 'reader/a');
    expect(await UserNoteStore.load(account: 'reader/a'), isEmpty);
    expect(await UserNoteStore.load(account: 'reader%2Fa'), {'42': '乙'});
    expect(await UserNoteStore.load(account: ''), {'42': '访客'});
  });

  test('invalid UIDs are rejected without changing persisted notes', () async {
    await UserNoteStore.save('42', '保留');
    for (final uid in ['', '0', '042', '-1', 'uid-42', '42 ']) {
      await expectLater(UserNoteStore.save(uid, '无效'), throwsArgumentError);
    }
    expect(await UserNoteStore.load(), {'42': '保留'});
  });

  test('corrupt local notes recover and malformed entries are discarded',
      () async {
    for (final raw in [false, '{bad json', '[]', 'null']) {
      SharedPreferences.setMockInitialValues({'anonymous/user_notes_v1': raw});
      expect(await UserNoteStore.load(), isEmpty);
    }
    SharedPreferences.setMockInitialValues({
      'anonymous/user_notes_v1':
          '{"42":" 保留 ","0":"bad","043":"bad","44":8,"45":" "}',
    });
    expect(await UserNoteStore.load(), {'42': '保留'});
    await UserNoteStore.save('46', '新增');
    expect(await UserNoteStore.load(), {'42': '保留', '46': '新增'});
  });

  test('simultaneous notes for distinct UIDs both persist', () async {
    await Future.wait([
      UserNoteStore.save('42', '甲'),
      UserNoteStore.save('43', '乙'),
    ]);
    expect(await UserNoteStore.load(), {'42': '甲', '43': '乙'});
  });
}
