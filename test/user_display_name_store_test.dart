import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/user_display_name_store.dart';
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
  var writes = 0;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectWrites = false;
    throwWrites = false;
    writes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      writes++;
      if (rejectWrites) {
        if (throwWrites) throw PlatformException(code: 'name-write-failure');
        return false;
      }
      final args = call.arguments as Map;
      if (call.method == 'remove') {
        persisted.remove(args['key']);
      } else {
        persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
  });
  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
      'merge learns names without guessing numeric hashes and only explicit flags clear fields',
      () async {
    await UserDisplayNameStore.save('42', hashName: ' 12345678 ');
    var name = (await UserDisplayNameStore.load())['42']!;
    expect(name.displayName, '12345678');
    expect(name.nickname, isNull);
    await UserDisplayNameStore.save('42', nickname: ' 穆之 ');
    name = (await UserDisplayNameStore.load())['42']!;
    expect(name.displayName, '穆之');
    expect(name.hashName, '12345678');
    final revision = UserDisplayNameStore.revision.value;
    final before = writes;
    await UserDisplayNameStore.save('42');
    await UserDisplayNameStore.save('42', nickname: '穆之');
    expect(writes, before);
    expect(UserDisplayNameStore.revision.value, revision);
    await UserDisplayNameStore.save('42', clearNickname: true);
    expect((await UserDisplayNameStore.load())['42']!.displayName, '12345678');
    await UserDisplayNameStore.save('42', nickname: 'UID 42');
    expect((await UserDisplayNameStore.load())['42']!.displayName, 'UID 42',
        reason:
            'a proven UID-looking native name is not heuristically stripped');
    await UserDisplayNameStore.clear('42');
    expect(await UserDisplayNameStore.load(), isEmpty);
    expect(persisted.keys.where((key) => key.endsWith('user_display_names_v1')),
        isEmpty);
  });

  test(
      'unknown names do not create entries and account encodings remain isolated',
      () async {
    final before = writes;
    await UserDisplayNameStore.save('42');
    await UserDisplayNameStore.clear('42');
    expect(writes, before);
    await UserDisplayNameStore.save('42', nickname: '访客');
    await UserDisplayNameStore.save('42', nickname: '甲', account: 'a/b');
    await UserDisplayNameStore.save('42', nickname: '乙', account: 'a%2Fb');
    await UserDisplayNameStore.save('42',
        nickname: '自定义访客', account: 'https://custom.invalid:anonymous');
    expect((await UserDisplayNameStore.load(account: 'a/b'))['42']!.displayName,
        '甲');
    expect(
        (await UserDisplayNameStore.load(account: 'a%2Fb'))['42']!.displayName,
        '乙');
    expect(
        (await UserDisplayNameStore.load(
                account: 'https://custom.invalid:anonymous'))['42']!
            .displayName,
        '自定义访客');
    expect((await UserDisplayNameStore.load(account: ''))['42']!.displayName,
        '访客');
    await UserDisplayNameStore.clear('42', account: 'a/b');
    expect(await UserDisplayNameStore.load(account: 'a/b'), isEmpty);
    expect(
        (await UserDisplayNameStore.load(account: 'a%2Fb'))['42']!.displayName,
        '乙');
  });

  test(
      'validation enforces positive UID and 64 runes with no accidental empty clearing',
      () async {
    await UserDisplayNameStore.save('42',
        nickname: '😀' * 64, hashName: 'a1b2');
    final before = writes;
    final revision = UserDisplayNameStore.revision.value;
    for (final value in [
      '',
      '  ',
      '字' * 65,
      'a\nb',
      '\u0085name',
      'a\u2028b',
      'a\u0000b'
    ]) {
      await expectLater(UserDisplayNameStore.save('42', nickname: value),
          throwsArgumentError);
      await expectLater(UserDisplayNameStore.save('42', hashName: value),
          throwsArgumentError);
    }
    for (final uid in ['', '0', '01', '-1', '42 ', 'name']) {
      await expectLater(UserDisplayNameStore.save(uid, nickname: 'valid'),
          throwsArgumentError);
    }
    await expectLater(
        UserDisplayNameStore.save('42', nickname: 'valid', clearNickname: true),
        throwsArgumentError);
    await expectLater(
        UserDisplayNameStore.save('42', hashName: 'valid', clearHashName: true),
        throwsArgumentError);
    expect(writes, before);
    expect(UserDisplayNameStore.revision.value, revision);
    final name = (await UserDisplayNameStore.load())['42']!;
    expect(name.nickname, '😀' * 64);
    expect(name.hashName, 'a1b2');
  });

  test(
      'malformed metadata salvages fields independently and loads never migrate or mutate other stores',
      () async {
    await UserNoteStore.save('42', '备注');
    await UserTagStore.save('42', ['标签']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'anonymous/user_display_names_v1',
        jsonEncode({
          '0': {'nickname': 'invalid uid'},
          '42': {'nickname': ' bad\nname ', 'hashName': ' 12345678 '},
          '43': {
            'nickname': ' 真名 ',
            'hashName': ['wrong type']
          },
          '44': {'nickname': ' ', 'hashName': null},
          '45': 'wrong shape',
        }));
    final before = writes;
    final names = await UserDisplayNameStore.load();
    expect(names.keys, ['42', '43']);
    expect(names['42']!.nickname, isNull);
    expect(names['42']!.hashName, '12345678');
    expect(names['43']!.nickname, '真名');
    expect(names['43']!.hashName, isNull);
    expect(() => names['99'] = const UserDisplayName(), throwsUnsupportedError);
    expect(writes, before,
        reason: 'load does not migrate UID-only annotations or repair disk');
    expect(await UserNoteStore.load(), {'42': '备注'});
    expect(await UserTagStore.load(), {
      '42': ['标签']
    });
    await UserDisplayNameStore.clear('42');
    expect(await UserNoteStore.load(), {'42': '备注'});
    expect(await UserTagStore.load(), {
      '42': ['标签']
    });
    for (final raw in ['{bad', '[]', 'null']) {
      await prefs.setString('anonymous/user_display_names_v1', raw);
      expect(await UserDisplayNameStore.load(), isEmpty);
    }
  });

  test(
      'queued concurrent same-UID field merges and different-UID writes lose no known names',
      () async {
    await Future.wait([
      UserDisplayNameStore.save('42', nickname: '甲'),
      UserDisplayNameStore.save('42', hashName: 'a1b2'),
      UserDisplayNameStore.save('43', nickname: '乙'),
    ]);
    final names = await UserDisplayNameStore.load();
    expect(names['42']!.nickname, '甲');
    expect(names['42']!.hashName, 'a1b2');
    expect(names['43']!.nickname, '乙');
  });

  for (final clear in [false, true]) {
    for (final throws in [false, true]) {
      test(
          'failed name ${clear ? 'clear' : 'update'} via ${throws ? 'exception' : 'false'} preserves names and does not poison later note/tag writes',
          () async {
        await UserDisplayNameStore.save('42',
            nickname: '已保存', hashName: 'a1b2');
        await UserNoteStore.save('42', '旧备注');
        await UserTagStore.save('42', ['旧标签']);
        final before = Map<String, Object>.of(persisted);
        final revision = UserDisplayNameStore.revision.value;
        final noteRevision = UserNoteStore.revision.value;
        final tagRevision = UserTagStore.revision.value;
        rejectWrites = true;
        throwWrites = throws;
        await expectLater(
            clear
                ? UserDisplayNameStore.clear('42')
                : UserDisplayNameStore.save('42', nickname: '未保存'),
            throwsA(throws ? isA<PlatformException>() : isA<StateError>()));
        expect(persisted, before);
        expect(UserDisplayNameStore.revision.value, revision);
        expect(UserNoteStore.revision.value, noteRevision);
        expect(UserTagStore.revision.value, tagRevision);
        expect(await UserNoteStore.load(), {'42': '旧备注'});
        expect(await UserTagStore.load(), {'42': ['旧标签']});
        expect((await UserDisplayNameStore.load())['42']!.nickname, '已保存');
        rejectWrites = false;
        await Future.wait([
          UserNoteStore.save('43', '新备注'),
          UserTagStore.save('43', ['新标签']),
          UserDisplayNameStore.save('43', nickname: '新名称'),
        ]);
        await (await SharedPreferences.getInstance()).reload();
        final names = await UserDisplayNameStore.load();
        expect(names['42']!.nickname, '已保存');
        expect(names['42']!.hashName, 'a1b2');
        expect(names['43']!.nickname, '新名称');
        expect(await UserNoteStore.load(), {'42': '旧备注', '43': '新备注'});
        expect(await UserTagStore.load(), {
          '42': ['旧标签'],
          '43': ['新标签']
        });
      });
    }
  }
}
