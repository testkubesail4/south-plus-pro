import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/user_display_name_store.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

import 'profile_appendfix_support.dart';

class _NamedProfileRepository extends FakeProfileRepository {
  _NamedProfileRepository(this.profile);
  final UserProfile profile;
  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => profile;
  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => profile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openProfile(
      WidgetTester tester, FakeProfileRepository repository) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: UserProfileScreen(
        userUrl: profileFixture.url,
        repository: repository,
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final identity in [
    ('1834429', '3f365ae9', '禁止事项'),
    ('4', '1eb7ddbc', '可可萝')
  ]) {
    testWidgets(
        'nickname leads profile ${identity.$1} while hash and login actions remain',
        (tester) async {
      final repository = _NamedProfileRepository(UserProfile(
          uid: identity.$1,
          name: identity.$2,
          url: 'u.php?action-show-uid-${identity.$1}.html',
          info: [UserProfileField(label: '昵称', value: identity.$3)]));
      await openProfile(tester, repository);
      expect(find.text(identity.$3), findsNWidgets(2),
          reason: 'the header leads with it; 概览 lists it');
      expect(find.text('${identity.$2} · UID ${identity.$1}'), findsOneWidget);
      expect(find.text('查看登录名'), findsOneWidget);
      expect(find.text('按人查找'), findsOneWidget);
      await tester.tap(find.text('添加备注'));
      await tester.pumpAndSettle();
      expect(find.textContaining('原名 ${identity.$3}'), findsOneWidget);
    });
  }

  testWidgets(
      'saving from a fetched profile remembers its nickname and native hash',
      (tester) async {
    final repository = _NamedProfileRepository(const UserProfile(
        uid: '1834429',
        name: '3f365ae9',
        nativeHashName: '3f365ae9',
        url: 'u.php?action-show-uid-1834429.html',
        info: [UserProfileField(label: '昵称', value: '禁止事项')]));
    await openProfile(tester, repository);
    expect(await UserDisplayNameStore.load(), isEmpty,
        reason: 'unannotated users are not recorded');
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '熟人');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final names = await UserDisplayNameStore.load();
    expect(names['1834429']?.nickname, '禁止事项');
    expect(names['1834429']?.hashName, '3f365ae9');
  });

  testWidgets('a generated profile name is never remembered', (tester) async {
    final repository = _NamedProfileRepository(const UserProfile(
        uid: '77', name: '', url: 'u.php?action-show-uid-77.html'));
    await openProfile(tester, repository);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    expect(find.text('UID 77'), findsOneWidget,
        reason: 'a generated 用户 77 is no name');
    expect(find.textContaining('原名'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '无名');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['77'], '无名');
    expect(await UserDisplayNameStore.load(), isEmpty);
  });

  testWidgets('profile header adds, edits and clears a local UID note',
      (tester) async {
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);

    expect(find.text('添加备注'), findsOneWidget);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原名 Alice'), findsOneWidget);
    expect(find.text('清除备注'), findsNothing);

    await tester.enterText(find.byType(TextField), '老朋友');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('备注 老朋友'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget, reason: 'original name stays');
    expect(await UserNoteStore.load(), {'123': '老朋友'});

    await tester.tap(find.text('备注 老朋友'));
    await tester.pumpAndSettle();
    expect(find.text('清除备注'), findsOneWidget);
    await tester.tap(find.text('清除备注'));
    await tester.pumpAndSettle();
    // Clearing is a draft edit: nothing is written until 保存.
    expect(find.text('清除备注'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(await UserNoteStore.load(), {'123': '老朋友'});
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('添加备注'), findsOneWidget);
    expect(await UserNoteStore.load(), isEmpty);
  });

  testWidgets('clearing the note never commits a pending tag removal',
      (tester) async {
    await UserNoteStore.save('123', '老朋友');
    await UserTagStore.save('123', ['Keep me', 'Other']);
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);
    await tester.tap(find.text('备注 老朋友'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除 Keep me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除备注'));
    await tester.pumpAndSettle();
    expect(await UserNoteStore.load(), {'123': '老朋友'});
    expect((await UserTagStore.load())['123'], ['Keep me', 'Other'],
        reason: 'a note-only clear must not persist the tag draft');
    expect(find.widgetWithText(InputChip, 'Keep me'), findsNothing,
        reason: 'the pending tag draft is preserved');
    expect(find.widgetWithText(InputChip, 'Other'), findsOneWidget);
    expect(find.text('备注与标签'), findsOneWidget, reason: 'the editor stays open');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await UserNoteStore.load(), isEmpty);
    expect((await UserTagStore.load())['123'], ['Other']);
  });

  testWidgets(
      'editor header names a known user once and an unknown one by UID alone',
      (tester) async {
    final repository = FakeProfileRepository();
    Future<void> open(String? name) async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showUserNoteEditor(context,
                          repository: repository, uid: '123', name: name),
                      child: const Text('open'),
                    ),
                  ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open(null);
    expect(find.text('UID 123'), findsOneWidget);
    expect(find.textContaining('原名'), findsNothing);
    expect(
        find.byKey(const ValueKey('annotation-editor-profile')), findsNothing,
        reason: 'no profile route unless the caller offers one');
    await tester.pumpWidget(const SizedBox());

    // A numeric-looking nickname is a real name, shown as given.
    await open('2860844');
    expect(find.text('原名 2860844 · UID 123'), findsOneWidget);
  });

  Future<void> openTagPicker(WidgetTester tester) async {
    await openProfile(tester, FakeProfileRepository());
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 添加标签'));
    await tester.pumpAndSettle();
  }

  Finder suggestion(String label) =>
      find.byKey(ValueKey('tag-suggestion:$label'));

  testWidgets(
      'the tag picker offers this account\'s tags with user counts and reuses the stored spelling',
      (tester) async {
    await UserTagStore.save('7', ['Artist', '资源佬']);
    await UserTagStore.save('8', ['资源佬']);
    await UserTagStore.save('123', ['Keep']);
    await openTagPicker(tester);
    expect(find.text('资源佬 · 2'), findsOneWidget);
    expect(find.text('Artist · 1'), findsOneWidget);
    expect(suggestion('Keep'), findsNothing,
        reason: 'tags already on this user are not offered');
    expect(tester.getTopLeft(suggestion('资源佬')).dx,
        lessThan(tester.getTopLeft(suggestion('Artist')).dx),
        reason: 'more users first');

    // A case-only match is the stored word, never a second spelling.
    await tester.enterText(
        find.byKey(const ValueKey('user-tag-input')), 'ARTIST');
    await tester.pump();
    expect(find.byKey(const ValueKey('tag-suggestion-new')), findsNothing);
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Artist'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'ARTIST'), findsNothing);

    // One tap picks; the field stays for the next one.
    await tester.tap(suggestion('资源佬'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '资源佬'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-tag-input')), findsOneWidget);

    // A word nobody uses yet is offered as new.
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), '新词');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tag-suggestion-new')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '新词'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final stored = await UserTagStore.load();
    expect(stored['123'], ['Keep', 'Artist', '资源佬', '新词']);
    expect(stored['7'], ['Artist', '资源佬'],
        reason: 'other users are never written');
    expect(stored['8'], ['资源佬']);
  });

  testWidgets(
      'a word another user gained after the editor opened is resolved before adding',
      (tester) async {
    await UserTagStore.save('123', ['Keep']);
    await openTagPicker(tester);
    expect(suggestion('Artist'), findsNothing);
    await UserTagStore.save('7', ['Artist']);
    await tester.enterText(
        find.byKey(const ValueKey('user-tag-input')), 'ARTIST');
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Artist'), findsOneWidget,
        reason: 'the moved store is read again and its spelling wins');
    expect(find.widgetWithText(InputChip, 'ARTIST'), findsNothing);
  });

  testWidgets(
      'an exact match beyond the twelve shown still supplies the stored spelling',
      (tester) async {
    for (var i = 1; i <= 13; i++) {
      await UserTagStore.save('${100 + i}', ['ab$i']);
      await UserTagStore.save('${200 + i}', ['ab$i']);
    }
    await UserTagStore.save('300', ['Ab']);
    await openTagPicker(tester);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), 'AB');
    await tester.pump();
    expect(find.byKey(const ValueKey('tag-suggestion-new')), findsNothing);
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Ab'), findsOneWidget);
  });

  testWidgets('prefix matches rank before substring matches', (tester) async {
    await UserTagStore.save('1', ['xab']);
    await UserTagStore.save('2', ['xab']);
    await UserTagStore.save('3', ['abc']);
    await openTagPicker(tester);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), 'ab');
    await tester.pump();
    expect(tester.getTopLeft(suggestion('abc')).dx,
        lessThan(tester.getTopLeft(suggestion('xab')).dx));
  });

  testWidgets('a too long tag says why, and an eighth tag closes adding',
      (tester) async {
    await UserTagStore.save('123', ['1', '2', '3', '4', '5', '6', '7']);
    await UserTagStore.save('9', ['eighth']);
    await openTagPicker(tester);
    await tester.enterText(
        find.byKey(const ValueKey('user-tag-input')), '字' * 17);
    await tester.pump();
    expect(find.text('最多 16 个字符，这个标签太长'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-suggestion-new')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), '');
    await tester.pump();
    await tester.tap(suggestion('eighth'));
    await tester.pumpAndSettle();
    expect(find.text('已达 8 个标签上限'), findsOneWidget);
    expect(find.byKey(const ValueKey('user-tag-input')), findsNothing);
    expect(find.text('+ 添加标签'), findsNothing,
        reason: 'no way to add a ninth tag');
  });

  testWidgets('note editor limits the note to 40 characters', (tester) async {
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '字' * 60);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['123'], hasLength(userNoteMaxLength));
  });

  testWidgets(
      'invalid tag draft blocks both saves and the rune counter matches validation',
      (tester) async {
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新备注');
    await tester.tap(find.text('+ 添加标签'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('user-tag-input')), '字' * 17);
    await tester.pump();
    expect(find.text('17/16'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await UserNoteStore.load(), isEmpty);
    expect(await UserTagStore.load(), isEmpty);
    expect(find.text('备注与标签'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('user-tag-input')), '😀' * 16);
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect((await UserNoteStore.load())['123'], '新备注');
    expect((await UserTagStore.load())['123'], ['😀' * 16]);
  });

  testWidgets('UserNoteLabel cuts the note before the original name',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 120,
          child: UserNoteLabel(name: 'Alice', note: '很长很长很长很长很长的备注'),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.textSpan!.toPlainText(), startsWith('Alice'));
    expect(
      tester.getSemantics(find.byType(UserNoteLabel)).label,
      'Alice，备注 很长很长很长很长很长的备注',
    );
    // Before the body returns: the end-of-test check runs before tearDowns.
    semantics.dispose();
  });
}
