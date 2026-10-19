import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/tag_color_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('same normalized label shares one durable colour within an account',
      () async {
    await UserTagStore.save('11', ['Example'], account: 'owner/a');
    await UserTagStore.save('12', ['example'], account: 'owner/a');
    final revision = TagColorStore.revision.value;
    await TagColorStore.save('  EXAMPLE ', 'blue', account: 'owner/a');
    expect(TagColorStore.revision.value, revision + 1);
    expect(await TagColorStore.load(account: 'owner/a'), {'example': 'blue'});
    expect(TagColorStore.key(' Example '), 'example');
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('account/owner%2Fa/user_tag_colors_v1')!),
        {'example': 'blue'});
    expect(await TagColorStore.load(account: 'other'), isEmpty);
    expect(await TagColorStore.load(), isEmpty);
    await TagColorStore.save('Example', null, account: 'owner/a');
    expect(await TagColorStore.load(account: 'owner/a'), isEmpty);
    expect(await UserTagStore.load(account: 'owner/a'), {
      '11': ['Example'],
      '12': ['example'],
    });
  });

  test('existing tags migrate without invented colours or changed labels',
      () async {
    SharedPreferences.setMockInitialValues({
      'account/fixture/user_tags_v1': jsonEncode({
        '11': ['Old tag', '其他']
      }),
    });
    expect(await TagColorStore.load(account: 'fixture'), isEmpty);
    await TagColorStore.save('OLD TAG', 'green', account: 'fixture');
    expect(await UserTagStore.load(account: 'fixture'), {
      '11': ['Old tag', '其他']
    });
    expect(await TagColorStore.load(account: 'fixture'), {'old tag': 'green'});
    expect(await TagColorStore.load(), isEmpty);
  });

  test('corrupt entries are ignored individually and valid keys normalize',
      () async {
    SharedPreferences.setMockInitialValues({
      'anonymous/user_tag_colors_v1': jsonEncode({
        ' Valid ': 'red',
        'valid': 'blue',
        'another': 'green',
        'unknown': 'not-a-palette-id',
        '': 'red',
        'bad\nlabel': 'red',
        'too long label to accept': 'pink',
        'not-string': 3,
      }),
    });
    expect(await TagColorStore.load(), {'valid': 'blue', 'another': 'green'});
    await TagColorStore.save('new', 'teal');
    expect(await TagColorStore.load(),
        {'valid': 'blue', 'another': 'green', 'new': 'teal'});
  });

  for (final corrupt in [false, 'not json', '[]', 'null']) {
    test('invalid colour store $corrupt can be safely replaced', () async {
      SharedPreferences.setMockInitialValues(
          {'anonymous/user_tag_colors_v1': corrupt});
      expect(await TagColorStore.load(), isEmpty);
      await TagColorStore.save('valid', 'purple');
      expect(await TagColorStore.load(), {'valid': 'purple'});
    });
  }

  test('invalid writes leave prior colours and revision untouched', () async {
    await TagColorStore.save('valid', 'amber');
    final revision = TagColorStore.revision.value;
    for (final label in [
      '',
      'bad\nlabel',
      'this label exceeds sixteen runes'
    ]) {
      await expectLater(TagColorStore.save(label, 'red'), throwsArgumentError);
    }
    await expectLater(
        TagColorStore.save('valid', 'invalid'), throwsArgumentError);
    expect(TagColorStore.revision.value, revision);
    expect(await TagColorStore.load(), {'valid': 'amber'});
  });

  test('concurrent saves serialize without losing another label', () async {
    await Future.wait([
      TagColorStore.save('one', 'red'),
      TagColorStore.save('two', 'brown'),
      TagColorStore.save('three', 'pink'),
    ]);
    expect(await TagColorStore.load(),
        {'one': 'red', 'two': 'brown', 'three': 'pink'});
  });
}
