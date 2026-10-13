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

  const labels = [
    '表情', '粗体', '斜体', '下划线', '字号', '颜色', '字体', //
    '对齐', '列表', '引用', '链接', '图片', '代码',
  ];
  for (final size in const [Size(360, 640), Size(731, 411), Size(800, 360)]) {
    for (final scale in const [1.0, 2.0]) {
      // A keyboard covering about half of a phone screen.
      for (final keyboard in [0.0, size.height * 0.45]) {
        testWidgets(
            'every action is in view and tappable: $size, text x$scale, '
            'keyboard $keyboard', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: PmComposeScreen(repository: _ComposeRepository()),
          ));
          await tester.pumpAndSettle();

          // The message body keeps its eight lines.
          final list = find.byType(Scrollable).first;
          final body = find.widgetWithText(TextField, '内容');
          await tester.scrollUntilVisible(body, 100, scrollable: list);
          expect(tester.getSize(body).height,
              greaterThanOrEqualTo(8 * 14 * scale));

          // No action may sit past the edge, even before any scrolling.
          await tester.scrollUntilVisible(
            find.byType(WindCodeToolbar),
            100,
            scrollable: list,
          );
          await tester.pumpAndSettle();
          Finder chip(String label) => find.ancestor(
              of: find.text(label), matching: find.byType(ActionChip));
          for (final label in labels) {
            final rect = tester.getRect(chip(label));
            expect(rect.left, greaterThanOrEqualTo(0), reason: label);
            expect(rect.right, lessThanOrEqualTo(size.width), reason: label);
          }
          for (final label in labels) {
            await tester.ensureVisible(chip(label));
            await tester.pumpAndSettle();
            expect(tester.getSize(chip(label)).height, greaterThanOrEqualTo(48),
                reason: label);
            expect(chip(label).hitTestable(), findsOneWidget, reason: label);
          }
          // The rightmost action reaches the message body.
          final controller = tester
              .widget<WindCodeToolbar>(find.byType(WindCodeToolbar))
              .controller;
          await tester.tap(chip('图片'));
          await tester.pumpAndSettle();
          expect(controller.text, '[img]图片地址[/img]');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

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
