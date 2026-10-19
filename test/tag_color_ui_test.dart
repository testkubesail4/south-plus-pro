import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/features/common/user_tags_inline.dart';
import 'package:south_plus_rewrite/features/profile/local_user_annotations_screen.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/tag_color_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

class _Repo extends ForumRepository {
  _Repo() : super(client: ForumClient(httpClient: HttpClient()));
  final epoch = ValueNotifier<int>(0);
  @override
  ValueListenable<int> get sessionEpoch => epoch;
  @override
  String? get localPreferenceAccount => 'reader';
}

Color? _fill(WidgetTester tester, String tag) => (tester
        .widget<Container>(find
            .ancestor(of: find.text(tag), matching: find.byType(Container))
            .first)
        .decoration as BoxDecoration)
    .color;

double _contrast(Color a, Color b) {
  final (hi, lo) = a.computeLuminance() > b.computeLuminance()
      ? (a.computeLuminance(), b.computeLuminance())
      : (b.computeLuminance(), a.computeLuminance());
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every palette pair reads at AA or better in both themes', () {
    for (final id in TagColorStore.ids) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        AppThemeController.notifier.value = mode;
        final (fill, text) = AppTagColors.of(id)!;
        expect(_contrast(fill, text), greaterThanOrEqualTo(4.5),
            reason: '$id $mode');
      }
    }
    AppThemeController.notifier.value = ThemeMode.system;
  });

  testWidgets('a capsule wears its label colour in any letter case; unset stays neutral',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TagColorScope(
        colors: {'test': 'teal'},
        child: Row(children: [
          UserTagCapsule(tag: 'Test'),
          UserTagCapsule(tag: 'other'),
        ]),
      ),
    ));
    expect(_fill(tester, 'Test'), AppTagColors.of('teal')!.$1);
    expect(_fill(tester, 'other'), AppColors.inkSoft);
  });

  testWidgets('the editor colours a tag for the account at once', (tester) async {
    final repo = _Repo();
    await UserTagStore.save('7', ['test'], account: 'reader');
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showUserNoteEditor(context,
              repository: repo, uid: '7', name: null, tags: const ['test']),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('点按标签可设置颜色'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('user-tag-chip:test')));
    await tester.pumpAndSettle();
    expect(find.text('「test」的颜色'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('蓝，标签颜色'));
    await tester.pumpAndSettle();

    expect(await TagColorStore.load(account: 'reader'), {'test': 'blue'});
    final chip = tester.widget<InputChip>(
        find.byKey(const ValueKey('user-tag-chip:test')));
    expect(chip.backgroundColor, AppTagColors.of('blue')!.$1);

    // 无颜色 returns it to neutral.
    await tester.tap(find.byKey(const ValueKey('user-tag-chip:test')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-color:none')));
    await tester.pumpAndSettle();
    expect(await TagColorStore.load(account: 'reader'), isEmpty);
  });

  testWidgets('the tag manager colours a label and every capsule follows',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await UserTagStore.save('7', ['test'], account: 'reader');
    await UserTagStore.save('8', ['Test', 'x'], account: 'reader');
    await tester.pumpWidget(
        MaterialApp(home: LocalUserAnnotationsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('标签 '));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tag-color-button:test')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-color:red')));
    await tester.pumpAndSettle();
    expect(_fill(tester, 'test'), AppTagColors.of('red')!.$1);
    expect(_fill(tester, 'x'), AppColors.inkSoft);

    await tester.tap(find.textContaining('用户 '));
    await tester.pumpAndSettle();
    expect(_fill(tester, 'Test'), AppTagColors.of('red')!.$1,
        reason: 'same label, same colour');
  });
}
