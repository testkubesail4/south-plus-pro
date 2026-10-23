import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_blocking_settings.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('local rules persist per account without writing the native config',
      () async {
    var owner = '101';
    final server = _NativeServer();
    final settings = ForumBlockingSettings(
      accountUid: () => owner,
      request: server.request,
    );
    await settings.setContent('synthetic short reply', blocked: true);
    await settings.setLocalUser('404', 'Synthetic local author',
        scope: LocalBlockScope.topics);
    expect(server.actions, isEmpty);
    expect(settings.notifier.value.isContentBlocked('synthetic short reply'),
        isTrue);
    expect(
        settings.notifier.value.isContentBlocked('synthetic short reply extra'),
        isFalse);
    expect(settings.notifier.value.isUserBlocked('404', topic: true), isTrue);
    expect(settings.notifier.value.isUserBlocked('404'), isFalse);
    owner = '102';
    await settings.load();
    expect(settings.notifier.value.contentKeys, isEmpty);
    expect(settings.notifier.value.localUsers, isEmpty);
    owner = '101';
    await settings.load();
    expect(settings.notifier.value.contentKeys, {'synthetic short reply'});
    expect(settings.notifier.value.localUsers.single.uid, '404');
    await settings.setLocalUser('404', 'Synthetic local author',
        scope: LocalBlockScope.all);
    expect(
        settings.notifier.value
            .floorBlock(uid: '404', contentKey: null, isOpeningPost: true),
        FloorBlock.user);
    expect(
        settings.notifier.value.floorBlock(
            uid: '505',
            contentKey: 'synthetic short reply',
            isOpeningPost: true),
        FloorBlock.none);
    expect(
        settings.notifier.value
            .floorBlock(uid: '505', contentKey: 'synthetic short reply'),
        FloorBlock.content);
    await settings.setContent('synthetic short reply', blocked: false);
    await settings.setLocalUser('404', 'Synthetic local author', scope: null);
    expect(settings.notifier.value.contentKeys, isEmpty);
    expect(settings.notifier.value.localUsers, isEmpty);
    expect(
        server.actions.where((action) => action == 'updateblocklist'), isEmpty);
  });

  test('removing a content rule removes equivalent normalized terms', () async {
    final server = _NativeServer();
    final settings =
        ForumBlockingSettings(accountUid: () => '101', request: server.request);
    await settings.setContent('repeaaat<EMOJI>', blocked: true);
    expect(settings.notifier.value.isContentBlocked('repeat<EMOJI>'), isTrue);
    await settings.setContent('repeat<EMOJI>', blocked: false);
    expect(settings.notifier.value.contentKeys, isEmpty);
  });

  for (final config in [
    <String, dynamic>{'version': '4.0', 'blist': {}},
    <String, dynamic>{
      'version': '3.1',
      'blist': {
        '202': {'name': 'Synthetic', 'level': 'topic'}
      }
    },
  ]) {
    test('unsupported native config is never overwritten: ${config['version']}',
        () async {
      final server = _NativeServer()..config = config;
      final settings = ForumBlockingSettings(
          accountUid: () => '101', request: server.request);
      await expectLater(
          settings.setUser('303', 'Synthetic target', blocked: true),
          throwsA(isA<ForumRequestException>()));
      expect(server.actions, ['getblocklist']);
      expect(settings.notifier.value.users, isEmpty);
    });
  }

  for (final response in [
    '',
    '{}',
    '<ajax><![CDATA[]]></ajax>',
    '<ajax><![CDATA[{}]]></ajax>'
  ]) {
    test(
        'an uninitialized native list loads empty and initializes only on explicit edit: $response',
        () async {
      final actions = <String>[];
      Map<String, dynamic>? written;
      final settings = ForumBlockingSettings(
          accountUid: () => '101',
          request: (action, fields) async {
            actions.add(action);
            if (action == 'getblocklist') return response;
            written =
                jsonDecode(fields['blocklistconfig']!) as Map<String, dynamic>;
            return '<ajax><![CDATA[success]]></ajax>';
          });
      await settings.load();
      expect(settings.notifier.value.users, isEmpty);
      expect(actions, ['getblocklist']);
      await settings.setUser('202', 'Synthetic author', blocked: true);
      expect(actions, ['getblocklist', 'getblocklist', 'updateblocklist']);
      expect(written, {
        'version': '3.1',
        'curiosity': false,
        'showBTN': true,
        'blist': {
          '202': {
            'name': 'Synthetic author',
            'level': ['topic']
          }
        }
      });
    });
  }

  for (final payload in [
    'not-json',
    '<br>',
    '{"version":"3.1","blist":null}'
  ]) {
    test(
        'nonempty malformed native data is never treated as uninitialized: $payload',
        () async {
      final actions = <String>[];
      final settings = ForumBlockingSettings(
          accountUid: () => '101',
          request: (action, fields) async {
            actions.add(action);
            return '<ajax><![CDATA[$payload]]></ajax>';
          });
      await expectLater(
          settings.setUser('202', 'Synthetic author', blocked: true),
          throwsA(isA<ForumRequestException>()));
      expect(actions, ['getblocklist']);
    });
  }

  test('guests cannot write either native or account-scoped local rules',
      () async {
    final server = _NativeServer();
    final settings =
        ForumBlockingSettings(accountUid: () => null, request: server.request);
    await settings.load();
    expect(settings.canWriteNative, isFalse);
    await expectLater(settings.setUser('202', 'Synthetic', blocked: true),
        throwsA(isA<ForumRequestException>()));
    await expectLater(settings.setContent('synthetic', blocked: true),
        throwsA(isA<ForumRequestException>()));
    expect(server.actions, isEmpty);
  });

  test(
      'a read from a previous account cannot publish or submit a native update',
      () async {
    String? owner = '101';
    final pending = Completer<String>();
    final actions = <String>[];
    final settings = ForumBlockingSettings(
        accountUid: () => owner,
        request: (action, fields) {
          actions.add(action);
          return pending.future;
        });
    final editing = settings.setUser('202', 'Synthetic', blocked: true);
    final assertion =
        expectLater(editing, throwsA(isA<ForumRequestException>()));
    await Future<void>.delayed(Duration.zero);
    owner = '102';
    settings.reset();
    pending.complete('<ajax><![CDATA[{"version":"3.1","blist":{}}]]></ajax>');
    await assertion;
    expect(actions, ['getblocklist']);
    expect(settings.notifier.value.users, isEmpty);
  });

  test('simultaneous native edits retain both independent flags', () async {
    final server = _NativeServer();
    final settings =
        ForumBlockingSettings(accountUid: () => '101', request: server.request);
    await Future.wait([
      settings.setUser('303', 'Synthetic', blocked: true),
      settings.setUser('303', 'Synthetic', blocked: true, avatarOnly: true),
    ]);
    expect(
        (server.config['blist'] as Map)['303']['level'], ['topic', 'avatar']);
    expect(settings.notifier.value.isAvatarBlocked('303'), isTrue);
    expect(settings.notifier.value.isUserBlocked('303'), isTrue);
  });

  test('native load decodes the XML text and HTML entities before JSON',
      () async {
    final settings = ForumBlockingSettings(
        accountUid: () => '101',
        request: (action, fields) async =>
            '<ajax>{&quot;version&quot;:&quot;3.1&quot;,&quot;blist&quot;:{&quot;202&quot;:{&quot;name&quot;:&quot;Synthetic A&amp;amp;B&quot;,&quot;level&quot;:[&quot;topic&quot;]}}}</ajax>');
    await settings.load();
    expect(settings.notifier.value.users.single.name, 'Synthetic A&B');
    expect(settings.notifier.value.isUserBlocked('202'), isTrue);
  });

  test('a failed native save retains visible cached rules', () async {
    final server = _NativeServer();
    var failUpdates = false;
    final settings = ForumBlockingSettings(
        accountUid: () => '101',
        request: (action, fields) async =>
            failUpdates && action == 'updateblocklist'
                ? '<ajax><![CDATA[denied]]></ajax>'
                : server.request(action, fields));
    await settings.load();
    failUpdates = true;
    await expectLater(
        settings.setUser('202', 'Synthetic author', blocked: true),
        throwsA(isA<ForumRequestException>()));
    expect(settings.notifier.value.isUserBlocked('202'), isFalse);
    expect(settings.notifier.value.isAvatarBlocked('202'), isTrue);
  });

  for (final stored in <Object>['{damaged', 42]) {
    test('damaged local storage is retained with a safe error: $stored',
        () async {
      SharedPreferences.setMockInitialValues({'blocking.local.101': stored});
      final server = _NativeServer();
      final settings = ForumBlockingSettings(
          accountUid: () => '101', request: server.request);
      await expectLater(settings.setContent('synthetic', blocked: true),
          throwsA(isA<ForumRequestException>()));
      expect((await SharedPreferences.getInstance()).get('blocking.local.101'),
          stored);
      expect(server.actions, isEmpty);
    });
  }

  test('native edits refresh first and preserve unrelated config and levels',
      () async {
    final server = _NativeServer();
    final settings = ForumBlockingSettings(
      accountUid: () => '101',
      request: server.request,
    );
    await settings.load();
    expect(server.actions, ['getblocklist']);
    expect(settings.notifier.value.isAvatarBlocked('202'), isTrue);
    // Another client adds a rule after our cached read.
    (server.config['blist'] as Map<String, dynamic>)['303'] = {
      'name': 'Synthetic remote author',
      'level': ['topic'],
    };
    await settings.setUser('202', 'Synthetic author', blocked: true);
    expect(server.actions, ['getblocklist', 'getblocklist', 'updateblocklist']);
    expect(server.config['futureOption'], {'retained': true});
    expect(server.config['curiosity'], isTrue);
    final users = server.config['blist'] as Map<String, dynamic>;
    expect(users['202'], {
      'name': 'Synthetic author',
      'level': ['avatar', 'futureLevel', 'topic'],
      'futureField': 7,
    });
    expect(users['303'], {
      'name': 'Synthetic remote author',
      'level': ['topic'],
    });
    expect(settings.notifier.value.isUserBlocked('202'), isTrue);
    await settings.setUser('202', 'Synthetic author', blocked: false);
    expect((server.config['blist'] as Map)['202']['level'],
        ['avatar', 'futureLevel']);
    expect(settings.notifier.value.isUserBlocked('202'), isFalse);
    expect(settings.notifier.value.isAvatarBlocked('202'), isTrue);
  });
}

class _NativeServer {
  final actions = <String>[];
  Map<String, dynamic> config = {
    'version': '3.1',
    'curiosity': true,
    'showBTN': false,
    'futureOption': {'retained': true},
    'blist': {
      '202': {
        'name': 'Synthetic author',
        'level': ['avatar', 'futureLevel'],
        'futureField': 7,
      },
    },
  };

  Future<String> request(String action, Map<String, String> fields) async {
    actions.add(action);
    if (action == 'getblocklist') {
      expect(fields, isEmpty);
      return '<ajax><![CDATA[${jsonEncode(config)}]]></ajax>';
    }
    expect(action, 'updateblocklist');
    config = jsonDecode(fields['blocklistconfig']!) as Map<String, dynamic>;
    return '<ajax><![CDATA[success]]></ajax>';
  }
}
