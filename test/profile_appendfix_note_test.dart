import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
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

  for (final identity in [('1834429', '3f365ae9', '禁止事项'), ('4', '1eb7ddbc', '可可萝')]) {
    testWidgets('nickname leads profile ${identity.$1} while hash and login actions remain', (tester) async {
      final repository = _NamedProfileRepository(UserProfile(uid: identity.$1, name: identity.$2,
          url: 'u.php?action-show-uid-${identity.$1}.html',
          info: [UserProfileField(label: '昵称', value: identity.$3)]));
      await openProfile(tester, repository);
      expect(find.text(identity.$3), findsOneWidget);
      expect(find.text('${identity.$2} · UID ${identity.$1}'), findsOneWidget);
      expect(find.text('查看登录名'), findsOneWidget);
      expect(find.text('按人查找'), findsOneWidget);
      await tester.tap(find.text('添加备注'));
      await tester.pumpAndSettle();
      expect(find.textContaining('原名：${identity.$3}'), findsOneWidget);
    });
  }

  testWidgets('profile header adds, edits and clears a local UID note',
      (tester) async {
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);

    expect(find.text('添加备注'), findsOneWidget);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原名：Alice'), findsOneWidget);
    expect(find.text('仅本机保存，不会同步到论坛'), findsOneWidget);
    expect(find.text('清除备注'), findsNothing);

    await tester.enterText(find.byType(TextField), '老朋友');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('备注：老朋友'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget, reason: 'original name stays');
    expect(await UserNoteStore.load(), {'123': '老朋友'});

    await tester.tap(find.text('备注：老朋友'));
    await tester.pumpAndSettle();
    expect(find.text('清除备注'), findsOneWidget);
    await tester.tap(find.text('清除备注'));
    await tester.pumpAndSettle();
    // Clearing is a draft edit: nothing is written until 保存.
    expect(find.text('清除备注'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    expect(await UserNoteStore.load(), {'123': '老朋友'});
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('添加备注'), findsOneWidget);
    expect(await UserNoteStore.load(), isEmpty);
  });

  testWidgets('clearing the note never commits a pending tag removal', (tester) async {
    await UserNoteStore.save('123', '老朋友');
    await UserTagStore.save('123', ['Keep me', 'Other']);
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);
    await tester.tap(find.text('备注：老朋友'));
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

  testWidgets('invalid tag draft blocks both saves and the rune counter matches validation', (tester) async {
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新备注');
    await tester.tap(find.text('+ 添加标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), '字' * 17);
    await tester.pump();
    expect(find.text('17/16'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(await UserNoteStore.load(), isEmpty);
    expect(await UserTagStore.load(), isEmpty);
    expect(find.text('备注与标签'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('user-tag-input')), '😀' * 16);
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
