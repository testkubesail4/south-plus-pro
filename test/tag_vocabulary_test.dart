import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/tag_vocabulary.dart';

void main() {
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

  test('each tag counts distinct UIDs even when many users have case variants',
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
    expect(tagVocabulary(byUid, query: 'ARTIST', exclude: ['artist']), isEmpty);
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
        tagVocabulary(byUid, exclude: ['popular']).map((entry) => entry.label),
        ['alpha', 'Beta']);
  });

  test('vocabulary is immutable and never changes any users tags', () {
    final byUid = <String, List<String>>{
      '42': [' Artist ', 'Friend'],
      '43': ['ARTIST', 'Other'],
    };
    final before = {
      for (final entry in byUid.entries) entry.key: List<String>.of(entry.value)
    };
    final entries = tagVocabulary(byUid, query: 'art', exclude: ['friend']);
    expect(byUid, before);
    expect(
        () => entries.add(const TagVocabularyEntry(label: 'New', userCount: 1)),
        throwsUnsupportedError);
    expect(entries.single.label, 'Artist');
    expect(entries.single.userCount, 2);
  });
}
