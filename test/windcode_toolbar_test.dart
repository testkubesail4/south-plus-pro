import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/editor/windcode_toolbar.dart';
import 'package:south_plus_rewrite/features/messages/pm_compose_screen.dart';
import 'package:south_plus_rewrite/models/forum_emojis.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  Future<TextEditingController> pumpPmCompose(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PmComposeScreen(repository: _ComposeRepository()),
    ));
    await tester.pumpAndSettle();
    return tester
        .widget<WindCodeToolbar>(find.byType(WindCodeToolbar))
        .controller;
  }

  Future<void> tapAction(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('PM composer offers the site formats but no sale insertion',
      (tester) async {
    final body = await pumpPmCompose(tester);
    expect(find.text('出售'), findsNothing);

    body.value = const TextEditingValue(
      text: 'say hi now',
      selection: TextSelection(baseOffset: 4, extentOffset: 6),
    );
    await tapAction(tester, '颜色');
    await tester.tap(find.text('crimson'));
    await tester.pumpAndSettle();
    expect(body.text, 'say [color=crimson]hi[/color] now');

    body.value = const TextEditingValue(
      text: 'x',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tapAction(tester, '字号');
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(body.text, 'x[size=5]文字[/size]');
    expect(body.selection.textInside(body.text), '文字');

    body.value = const TextEditingValue(
      text: 'one\n two \n\nthree',
      selection: TextSelection(baseOffset: 0, extentOffset: 16),
    );
    await tapAction(tester, '列表');
    await tester.tap(find.text('字母列表'));
    await tester.pumpAndSettle();
    expect(
      body.text,
      '[list=a][li]one[/li][li]two[/li][li]three[/li][/list]',
    );

    body.value = const TextEditingValue(
      text: 'centre me',
      selection: TextSelection(baseOffset: 0, extentOffset: 9),
    );
    await tapAction(tester, '对齐');
    await tester.tap(find.text('居中'));
    await tester.pumpAndSettle();
    expect(body.text, '[align=center]centre me[/align]');

    await tapAction(tester, '粗体');
    expect(body.text, '[align=center][b]centre me[/b][/align]');
  });

  testWidgets('emoji picker offers every site category and inserts codes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(ImageLoadMode.noImages);
    addTearDown(() => ImageLoadingSettings.saveMode(ImageLoadMode.automatic));
    final body = await pumpPmCompose(tester);
    body.value = const TextEditingValue(
      text: 'hi',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tapAction(tester, '表情');

    expect(southPlusEmojiCategories, hasLength(5));
    for (final category in southPlusEmojiCategories) {
      expect(find.widgetWithText(Tab, category.name), findsOneWidget);
    }
    final last = southPlusEmojiCategories.last;
    await tester.tap(find.widgetWithText(Tab, last.name));
    await tester.pumpAndSettle();
    // No-images mode labels faces by code instead of fetching them.
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text(last.items.first.id));
    await tester.pumpAndSettle();
    expect(body.text, 'hi [s:${last.items.first.id}] ');
  });

  testWidgets('thread toolbar keeps sale insertion', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WindCodeToolbar(controller: controller)),
    ));
    await tester.ensureVisible(find.text('出售'));
    expect(find.text('出售'), findsOneWidget);
  });
}

class _ComposeRepository extends ForumRepository {
  @override
  Future<ForumPmCompose> fetchPmCompose({String? path}) async =>
      ForumPmCompose(actionPath: 'message.php', fields: const {});
}
