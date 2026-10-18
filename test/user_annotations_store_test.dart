import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/tag_vocabulary.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('notes', () {
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

    test('notes are isolated by exact account and anonymous namespace',
        () async {
      await UserNoteStore.save('42', '访客');
      await UserNoteStore.save('42', '甲', account: 'reader/a');
      await UserNoteStore.save('42', '乙', account: 'reader%2Fa');
      await UserNoteStore.clear('42', account: 'reader/a');
      expect(await UserNoteStore.load(account: 'reader/a'), isEmpty);
      expect(await UserNoteStore.load(account: 'reader%2Fa'), {'42': '乙'});
      expect(await UserNoteStore.load(account: ''), {'42': '访客'});
    });

    test('invalid UIDs are rejected without changing persisted notes',
        () async {
      await UserNoteStore.save('42', '保留');
      for (final uid in ['', '0', '042', '-1', 'uid-42', '42 ']) {
        await expectLater(UserNoteStore.save(uid, '无效'), throwsArgumentError);
      }
      expect(await UserNoteStore.load(), {'42': '保留'});
    });

    test('corrupt local notes recover and malformed entries are discarded',
        () async {
      for (final raw in [false, '{bad json', '[]', 'null']) {
        SharedPreferences.setMockInitialValues(
            {'anonymous/user_notes_v1': raw});
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
  });

  group('tags', () {
    test(
        'tags trim and dedupe case preserving first spelling and order without changing notes',
        () async {
      await UserNoteStore.save('42', '保留备注');
      await UserTagStore.save('42', ['  Artist ', '熟人', 'artist', 'a,b', '😀']);
      expect(await UserTagStore.load(), {
        '42': ['Artist', '熟人', 'a,b', '😀']
      });
      await UserNoteStore.clear('42');
      expect((await UserTagStore.load())['42'], hasLength(4));
      await UserNoteStore.save('42', '保留备注');
      await UserTagStore.clear('42');
      expect(await UserTagStore.load(), isEmpty);
      expect(await UserNoteStore.load(), {'42': '保留备注'});
    });

    test(
        'write bounds use runes and reject bad UIDs, controls, empty and ninth distinct tag',
        () async {
      await UserTagStore.save('42', ['😀' * 16]);
      final revision = UserTagStore.revision.value;
      for (final tags in <List<String>>[
        [''],
        ['  '],
        ['a\nb'],
        ['a\u0085b'],
        ['字' * 17],
        [for (var i = 0; i < 9; i++) 'tag$i'],
      ]) {
        await expectLater(UserTagStore.save('42', tags), throwsArgumentError);
      }
      await expectLater(UserTagStore.save('0', ['有效']), throwsArgumentError);
      expect(UserTagStore.revision.value, revision);
      expect((await UserTagStore.load())['42'], ['😀' * 16]);
    });

    test('corrupt reads salvage valid entries and snapshots cannot be mutated',
        () async {
      SharedPreferences.setMockInitialValues({
        'anonymous/user_tags_v1': jsonEncode({
          '0': ['invalid'],
          '42': [' First ', 'first', null, 'a\nb', '熟人'],
          '43': 'wrong',
          '44': [for (var i = 0; i < 12; i++) 'tag$i'],
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

    test('queued writes isolate encoded accounts and preserve concurrent UIDs',
        () async {
      await Future.wait([
        UserTagStore.save('42', ['甲'], account: 'a/b'),
        UserTagStore.save('43', ['乙'], account: 'a/b'),
        UserTagStore.save('42', ['独立'], account: 'a%2Fb'),
        UserTagStore.save('42', ['访客']),
      ]);
      expect(await UserTagStore.load(account: 'a/b'), {
        '42': ['甲'],
        '43': ['乙']
      });
      expect(await UserTagStore.load(account: 'a%2Fb'), {
        '42': ['独立']
      });
      expect(await UserTagStore.load(), {
        '42': ['访客']
      });
      await UserTagStore.save('42', [], account: 'a/b');
      expect(await UserTagStore.load(account: 'a/b'), {
        '43': ['乙']
      });
    });
  });

  group('vocabulary', () {
    test(
        'case grouping keeps the first spelling in store map order, not numeric UID order',
        () {
      final entries = tagVocabulary({
        '900': [' Artist ', 'artist', 'ARTIST'],
        '1': ['aRtIsT'],
      });
      expect(entries, hasLength(1));
      expect(entries.single.label, 'Artist');
      expect(entries.single.userCount, 2);
    });

    test(
        'each tag counts distinct UIDs even when many users have case variants',
        () {
      final entries = tagVocabulary({
        for (var uid = 1; uid <= 100; uid++)
          '$uid': ['Shared', 'shared', 'SHARED'],
        '101': ['Other'],
      });
      expect(entries.map((entry) => entry.label), ['Shared', 'Other']);
      expect(entries.first.userCount, 100);
      expect(entries.last.userCount, 1);
    });

    test(
        'prefix matches precede more popular substring matches, then count and normalized label rank',
        () {
      final entries = tagVocabulary({
        '1': ['xArt', 'Arctic', 'Artist', 'Arbor'],
        '2': ['xart', 'Artist'],
        '3': ['xART'],
      }, query: ' AR ');
      expect(entries.map((entry) => entry.label),
          ['Artist', 'Arbor', 'Arctic', 'xArt']);
      expect(entries.map((entry) => entry.userCount), [2, 1, 1, 3]);
    });

    test(
        'exclusions trim and ignore case while search returns the stored spelling',
        () {
      const byUid = {
        '1': ['Artist', 'Friend'],
        '2': ['artist', 'Friendly'],
      };
      expect(tagVocabulary(byUid, query: 'aRTist').single.label, 'Artist');
      expect(
          tagVocabulary(byUid, query: 'fri', exclude: [' FRIEND '])
              .map((entry) => entry.label),
          ['Friendly']);
      expect(
          tagVocabulary(byUid, query: 'ARTIST', exclude: ['artist']), isEmpty);
      expect(tagVocabulary(byUid, query: 'new label'), isEmpty);
    });

    test(
        'empty null and whitespace queries return all, ranked by count then normalized label',
        () {
      const byUid = {
        '1': ['Beta', 'alpha', 'Popular'],
        '2': ['Popular'],
      };
      for (final query in [null, '', '  ']) {
        expect(tagVocabulary(byUid, query: query).map((entry) => entry.label),
            ['Popular', 'alpha', 'Beta']);
      }
      expect(tagVocabulary({}), isEmpty);
      expect(
          tagVocabulary(byUid, exclude: ['popular'])
              .map((entry) => entry.label),
          ['alpha', 'Beta']);
    });

    test('vocabulary is immutable and never changes any users tags', () {
      final byUid = <String, List<String>>{
        '42': [' Artist ', 'Friend'],
        '43': ['ARTIST', 'Other'],
      };
      final before = {
        for (final entry in byUid.entries)
          entry.key: List<String>.of(entry.value)
      };
      final entries = tagVocabulary(byUid, query: 'art', exclude: ['friend']);
      expect(byUid, before);
      expect(
          () =>
              entries.add(const TagVocabularyEntry(label: 'New', userCount: 1)),
          throwsUnsupportedError);
      expect(entries.single.label, 'Artist');
      expect(entries.single.userCount, 2);
    });
  });
}
