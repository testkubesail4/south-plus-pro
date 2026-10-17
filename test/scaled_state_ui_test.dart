import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/editor/south_plus_emoji_picker.dart';
import 'package:south_plus_rewrite/features/thread/thread_sale_box_view.dart';
import 'package:south_plus_rewrite/models/forum_emojis.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  tearDown(() => AppThemeController.notifier.value = ThemeMode.system);

  for (final width in [72.0, 320.0, 360.0, 400.0, 600.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('emoji tiles are 48 px targets at $width px, x$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(body: SouthPlusEmojiPicker(onSelected: (_) {})),
          ),
        ));
        final id = southPlusEmojiCategories.first.items.first.id;
        final tile = tester.getSize(find
            .ancestor(of: find.text(id), matching: find.byType(InkWell))
            .first);
        expect(tile.width, greaterThanOrEqualTo(48));
        expect(tile.height, greaterThanOrEqualTo(48));
      });
    }
  }

  testWidgets('emoji code labels fit their tiles at large text',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 800),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(body: SouthPlusEmojiPicker(onSelected: (_) {})),
      ),
    ));

    // Without images the code is the only label a face has.
    final id = southPlusEmojiCategories.first.items.first.id;
    // A label too wide for its tile wraps, and the tile clips the rest.
    final label = tester.renderObject<RenderParagraph>(find.text(id));
    expect(label.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(label.size.width + 0.5));
    expect(label.getMinIntrinsicHeight(label.size.width),
        lessThanOrEqualTo(label.size.height + 0.5));
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the sale summary reads at 4.5:1 on its panel ($mode)',
        (tester) async {
      AppThemeController.notifier.value = mode;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          body: ThreadSaleBoxView(
            saleBox: const ThreadSaleBox(summary: '售价 5', buyPath: 'buy.php'),
            isBuying: false,
            onBuy: () {},
          ),
        ),
      ));
      final color = tester.widget<Text>(find.text('售价 5')).style!.color!;
      expect(_contrast(color, AppColors.inkSoft), greaterThanOrEqualTo(4.5));
    });

    testWidgets('a busy purchase shows a visible spinner ($mode)',
        (tester) async {
      AppThemeController.notifier.value = mode;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: Scaffold(
          body: ThreadSaleBoxView(
            saleBox: const ThreadSaleBox(summary: '售价 5', buyPath: 'buy.php'),
            isBuying: true,
            // A live callback: only the busy state may disable the button.
            onBuy: () {},
          ),
        ),
      ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: 'no second purchase');
      final context = tester.element(find.byType(FilledButton));
      const disabled = {WidgetState.disabled};
      final fill = Theme.of(context)
              .filledButtonTheme
              .style
              ?.backgroundColor
              ?.resolve(disabled) ??
          button.defaultStyleOf(context).backgroundColor!.resolve(disabled)!;
      final spinner = tester
          .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator))
          .color!;
      // The button sits on the sale box's inkSoft panel.
      final shown = Color.alphaBlend(fill, AppColors.inkSoft);
      expect(_contrast(spinner, shown), greaterThanOrEqualTo(3));
    });
  }
}
