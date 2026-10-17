import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';

import 'profile_appendfix_support.dart';

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

  testWidgets('profile header adds, edits and clears a local UID note',
      (tester) async {
    final repository = FakeProfileRepository();
    await openProfile(tester, repository);

    expect(find.text('添加备注'), findsOneWidget);
    await tester.tap(find.text('添加备注'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原名：Alice'), findsOneWidget);
    expect(find.text('仅本机保存，不会同步到论坛'), findsOneWidget);
    expect(find.text('清除'), findsNothing);

    await tester.enterText(find.byType(TextField), '老朋友');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('备注：老朋友'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget, reason: 'original name stays');
    expect(await UserNoteStore.load(), {'123': '老朋友'});

    await tester.tap(find.text('备注：老朋友'));
    await tester.pumpAndSettle();
    expect(find.text('清除'), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(find.text('添加备注'), findsOneWidget);
    expect(await UserNoteStore.load(), isEmpty);
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
