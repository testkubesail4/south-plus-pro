import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/local_user_annotations_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

class _Repo extends ForumRepository {
  _Repo() : super(client: ForumClient(httpClient: HttpClient()));
  final epoch = ValueNotifier<int>(0);
  String? scope;
  int profileRequests = 0;
  @override
  ValueListenable<int> get sessionEpoch => epoch;
  @override
  String? get localPreferenceAccount => scope;
  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async {
    profileRequests++;
    throw StateError('manager must not fetch profiles');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectReads = false;
  var writes = 0;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectReads = false;
    writes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'read-unavailable');
        return Map<String, Object>.of(persisted);
      }
      writes++;
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

  Future<void> pump(WidgetTester tester, _Repo repo) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () {
        final page = LocalUserAnnotationsScreen(repository: repo);
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
      }, child: const Text('open local')),
    ))));
    await tester.tap(find.text('open local'));
    await tester.pumpAndSettle();
  }

  testWidgets('union includes old note-only and tag-only UIDs; tag index counts distinct users without writes or network', (tester) async {
    await UserNoteStore.save('42', '旧备注');
    await UserTagStore.save('43', ['Artist']);
    await UserTagStore.save('44', ['artist']);
    await UserNoteStore.save('44', '组合');
    final repo = _Repo();
    await pump(tester, repo);
    for (final uid in ['42', '43', '44']) {
      expect(find.text('UID $uid'), findsOneWidget);
    }
    expect(find.text('用户 3'), findsOneWidget);
    final before = writes;
    await tester.tap(find.text('标签 1'));
    await tester.pumpAndSettle();
    expect(find.text('2 位用户'), findsOneWidget);
    await tester.tap(find.text('2 位用户'));
    await tester.pumpAndSettle();
    expect(find.text('UID 42'), findsNothing);
    expect(find.text('UID 43'), findsOneWidget);
    expect(find.text('UID 44'), findsOneWidget);
    expect(writes, before, reason: 'derived index changes no storage');
    expect(repo.profileRequests, 0);
    await tester.tap(find.text('UID 43'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新增备注');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['43'], '新增备注');
    expect((await UserTagStore.load())['43'], ['Artist']);
    expect(find.text('新增备注'), findsOneWidget);
  });

  testWidgets('failed reads expose retry instead of an authoritative empty list or counts', (tester) async {
    rejectReads = true;
    await pump(tester, _Repo());
    expect(find.text('备注与标签加载失败'), findsOneWidget);
    expect(find.text('暂无标记'), findsNothing);
    expect(find.text('用户 0'), findsNothing);
    rejectReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无标记'), findsOneWidget);
    expect(find.text('用户 0'), findsOneWidget);
  });

  testWidgets('scope change revokes manager and its open full-list editor without showing another account', (tester) async {
    await UserTagStore.save('42', ['old scope']);
    final repo = _Repo();
    await pump(tester, repo);
    await tester.tap(find.text('UID 42'));
    await tester.pumpAndSettle();
    expect(find.text('old scope'), findsWidgets);
    repo.scope = 'new account';
    repo.epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('old scope'), findsNothing);
    expect(find.text('open local'), findsOneWidget);
    expect(await UserTagStore.load(account: 'new account'), isEmpty);
    expect((await UserTagStore.load())['42'], ['old scope']);
  });
}
