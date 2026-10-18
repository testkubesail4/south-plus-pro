import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('tags trim and dedupe case preserving first spelling and order without changing notes', () async {
    await UserNoteStore.save('42', '保留备注');
    await UserTagStore.save('42', ['  Artist ', '熟人', 'artist', 'a,b', '😀']);
    expect(await UserTagStore.load(), {'42': ['Artist', '熟人', 'a,b', '😀']});
    await UserNoteStore.clear('42');
    expect((await UserTagStore.load())['42'], hasLength(4));
    await UserNoteStore.save('42', '保留备注');
    await UserTagStore.clear('42');
    expect(await UserTagStore.load(), isEmpty);
    expect(await UserNoteStore.load(), {'42': '保留备注'});
  });

  test('write bounds use runes and reject bad UIDs, controls, empty and ninth distinct tag', () async {
    await UserTagStore.save('42', ['😀' * 16]);
    final revision = UserTagStore.revision.value;
    for (final tags in <List<String>>[
      [''], ['  '], ['a\nb'], ['a\u0085b'], ['字' * 17],
      [for (var i = 0; i < 9; i++) 'tag$i'],
    ]) {
      await expectLater(UserTagStore.save('42', tags), throwsArgumentError);
    }
    await expectLater(UserTagStore.save('0', ['有效']), throwsArgumentError);
    expect(UserTagStore.revision.value, revision);
    expect((await UserTagStore.load())['42'], ['😀' * 16]);
  });

  test('corrupt reads salvage valid entries and snapshots cannot be mutated', () async {
    SharedPreferences.setMockInitialValues({
      'anonymous/user_tags_v1': jsonEncode({
        '0': ['invalid'], '42': [' First ', 'first', null, 'a\nb', '熟人'],
        '43': 'wrong', '44': [for (var i = 0; i < 12; i++) 'tag$i'],
      }),
    });
    final tags = await UserTagStore.load();
    expect(tags['42'], ['First', '熟人']);
    expect(tags['44'], hasLength(8));
    expect(tags.keys, containsAll(['42', '44']));
    expect(tags.keys, isNot(contains('0')));
    expect(() => tags['42']!.add('new'), throwsUnsupportedError);
    expect(() => tags['45'] = [], throwsUnsupportedError);
  });

  test('queued writes isolate encoded accounts and preserve concurrent UIDs', () async {
    await Future.wait([
      UserTagStore.save('42', ['甲'], account: 'a/b'),
      UserTagStore.save('43', ['乙'], account: 'a/b'),
      UserTagStore.save('42', ['独立'], account: 'a%2Fb'),
      UserTagStore.save('42', ['访客']),
    ]);
    expect(await UserTagStore.load(account: 'a/b'), {'42': ['甲'], '43': ['乙']});
    expect(await UserTagStore.load(account: 'a%2Fb'), {'42': ['独立']});
    expect(await UserTagStore.load(), {'42': ['访客']});
    await UserTagStore.save('42', [], account: 'a/b');
    expect(await UserTagStore.load(account: 'a/b'), {'43': ['乙']});
  });
}
