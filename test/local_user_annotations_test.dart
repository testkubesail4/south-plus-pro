import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/local_user_annotations_screen.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/user_display_name_store.dart';
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
  Future<UserProfile?> cachedUserProfileOverview(String url) async {
    profileRequests++;
    return null;
  }
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
  var rejectWrites = false;
  Completer<void>? holdReads;
  var writes = 0;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectReads = false;
    rejectWrites = false;
    holdReads = null;
    writes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (holdReads != null) await holdReads!.future;
        if (rejectReads) throw PlatformException(code: 'read-unavailable');
        return Map<String, Object>.of(persisted);
      }
      writes++;
      if (rejectWrites) return false;
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
    expect(find.text('备注 旧备注'), findsOneWidget, reason: 'a note is labelled, never mistaken for a tag');
    expect(find.text('备注 组合'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('annotation-edit:43')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新增备注');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['43'], '新增备注');
    expect((await UserTagStore.load())['43'], ['Artist']);
    expect(find.text('备注 新增备注'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('annotation-edit:42')));
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

  testWidgets('a row opens that UID\'s forum profile; the pencil edits; nothing is fetched to draw rows', (tester) async {
    await UserNoteStore.save('2860844', '233');
    final repo = _Repo();
    await pump(tester, repo);
    expect(repo.profileRequests, 0);
    expect(find.byTooltip('编辑备注与标签'), findsOneWidget);
    await tester.tap(find.text('UID 2860844'));
    await tester.pumpAndSettle();
    final page = tester.widget<UserProfileScreen>(find.byType(UserProfileScreen));
    expect(page.userUrl, repo.userProfileUrl('2860844'));
    expect(page.userUrl, endsWith('u.php?action-show-uid-2860844.html'));
  });

  testWidgets('the editor names the user once and opens the profile only without unsaved drafts', (tester) async {
    await UserNoteStore.save('2860844', '233');
    final repo = _Repo();
    await pump(tester, repo);
    await tester.tap(find.byKey(const ValueKey('annotation-edit:2860844')));
    await tester.pumpAndSettle();
    expect(find.text('UID 2860844'), findsNWidgets(2), reason: 'the row behind and the header, once each');
    expect(find.textContaining('原名'), findsNothing);
    TextButton link() => tester.widget<TextButton>(find.byKey(const ValueKey('annotation-editor-profile')));
    expect(link().onPressed, isNotNull);
    await tester.enterText(find.byType(TextField).last, '改了');
    await tester.pump();
    expect(link().onPressed, isNull, reason: 'an unsaved draft is never discarded by navigating');
    await tester.enterText(find.byType(TextField).last, '233');
    await tester.pump();
    expect(link().onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('annotation-editor-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfileScreen), findsOneWidget);
    expect((await UserNoteStore.load())['2860844'], '233');
  });

  for (final throughEditor in [false, true]) {
    testWidgets('a scope switch before the profile\'s first frame cancels it without a request, editor=$throughEditor', (tester) async {
      await UserNoteStore.save('42', 'private old-scope note');
      final repo = _Repo();
      await pump(tester, repo);
      if (throughEditor) {
        await tester.tap(find.byKey(const ValueKey('annotation-edit:42')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('annotation-editor-profile')));
      } else {
        await tester.tap(find.text('UID 42'));
      }
      // The route is asked for; its builder has not run yet.
      repo.scope = 'new account';
      repo.epoch.value++;
      await tester.pumpAndSettle();
      expect(repo.profileRequests, 0, reason: 'no old UID is read under the new account');
      expect(find.byType(UserProfileScreen), findsNothing);
      expect(find.text('private old-scope note'), findsNothing);
      expect(find.text('open local'), findsOneWidget, reason: 'only the bound routes went');
    });
  }

  testWidgets('an unreadable vocabulary is said, typing stays possible, and a new label waits for a readable source', (tester) async {
    await UserTagStore.save('42', ['old']);
    final repo = _Repo();
    await pump(tester, repo);
    // A refused write leaves the store unreadable until a reload succeeds.
    rejectWrites = true;
    rejectReads = true;
    await expectLater(UserNoteStore.save('99', 'x'), throwsA(anything));
    rejectWrites = false;
    await tester.tap(find.byKey(const ValueKey('annotation-edit:42')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 添加标签'));
    await tester.pumpAndSettle();
    expect(find.text('已有标签暂时无法读取'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), 'typed');
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    expect(find.text('已有标签暂时无法读取，请重试'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'typed'), findsNothing, reason: 'no spelling is invented');
    expect(find.text('typed'), findsOneWidget, reason: 'the typed text stays');
    rejectReads = false;
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'typed'), findsOneWidget);
  });

  testWidgets('rows lead with a learned name and keep the real UID in the caption', (tester) async {
    for (final uid in ['42', '43', '44', '45']) {
      await UserNoteStore.save(uid, 'n$uid');
    }
    await UserDisplayNameStore.save('42', nickname: '禁止事项', hashName: '3f365ae9');
    await UserDisplayNameStore.save('43', hashName: '49371b5d');
    await UserDisplayNameStore.save('45', hashName: '12345');
    await UserDisplayNameStore.save('46', nickname: '只有名字');
    final repo = _Repo();
    await pump(tester, repo);
    String? caption(String uid) => tester
        .widgetList<Text>(find.byKey(ValueKey('annotation-caption:$uid')))
        .map((t) => t.data)
        .firstOrNull;
    expect(find.text('禁止事项'), findsOneWidget);
    expect(caption('42'), '3f365ae9 · UID 42');
    expect(find.text('49371b5d'), findsOneWidget);
    expect(caption('43'), 'UID 43');
    expect(find.text('UID 44'), findsOneWidget);
    expect(caption('44'), isNull, reason: 'the UID is never said twice');
    expect(find.text('12345'), findsOneWidget, reason: 'a numeric hash is still a name');
    expect(caption('45'), 'UID 45');
    expect(find.text('只有名字'), findsNothing, reason: 'a name alone is no annotation row');
    expect(find.text('用户 4'), findsOneWidget);
    expect(repo.profileRequests, 0);

    await tester.enterText(find.byType(TextField).first, '禁止');
    await tester.pump();
    expect(find.text('禁止事项'), findsOneWidget);
    expect(find.text('49371b5d'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '4937');
    await tester.pump();
    expect(find.text('49371b5d'), findsOneWidget);
    expect(find.text('禁止事项'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('annotation-edit:42')));
    await tester.pumpAndSettle();
    expect(find.text('原名 禁止事项 · UID 42'), findsOneWidget);
    // Opening the profile route still uses the record UID.
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('禁止事项'));
    await tester.pumpAndSettle();
    expect(tester.widget<UserProfileScreen>(find.byType(UserProfileScreen)).userUrl,
        repo.userProfileUrl('42'));
  });

  testWidgets('names learned under one account never show under another', (tester) async {
    await UserNoteStore.save('42', 'mine');
    await UserDisplayNameStore.save('42', nickname: '别的账号的名字', account: 'other');
    await pump(tester, _Repo());
    expect(find.text('别的账号的名字'), findsNothing);
    expect(find.text('UID 42'), findsOneWidget);
  });

  // Opens the editor for UID 42 with the tag source unreadable, then lets the
  // next read through only when the test completes the returned hold.
  Future<Completer<void>> editorWithHeldSource(WidgetTester tester) async {
    await UserNoteStore.save('42', 'old');
    await pump(tester, _Repo());
    rejectWrites = true;
    rejectReads = true;
    await expectLater(UserNoteStore.save('99', 'x'), throwsA(anything));
    rejectWrites = false;
    await tester.tap(find.byKey(const ValueKey('annotation-edit:42')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 添加标签'));
    await tester.pumpAndSettle();
    rejectReads = false;
    final hold = holdReads = Completer<void>();
    // A read left waiting would stall the shared preference queue for later
    // tests.
    addTearDown(() {
      if (!hold.isCompleted) hold.complete();
    });
    return hold;
  }

  Finder noteField() => find.widgetWithText(TextField, '备注');

  testWidgets('Save locks the fields while it resolves a pending tag, so no later typing is lost', (tester) async {
    final hold = await editorWithHeldSource(tester);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), 'typed');
    await tester.enterText(noteField(), 'newer');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(tester.widget<TextField>(noteField()).enabled, isFalse,
        reason: 'nothing can be typed that the running save would not keep');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('user-tag-input'))).enabled, isFalse);
    holdReads = null;
    hold.complete();
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['42'], 'newer');
    expect((await UserTagStore.load())['42'], ['typed']);
  });

  testWidgets('a query typed while an add resolves survives that add', (tester) async {
    final hold = await editorWithHeldSource(tester);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), 'First');
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('user-tag-input'))).enabled, isTrue,
        reason: 'typing stays responsive while the source is read');
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), 'Second');
    holdReads = null;
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'First'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('user-tag-input'))).controller!.text, 'Second');
  });
}
