import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, theme, palette) in [
    ('light', AppTheme.light, AppColors.lightPalette),
    ('dark', AppTheme.dark, AppColors.darkPalette),
  ]) {
    test('$name: the pairs the theme paints meet WCAG AA', () {
      final p = palette;
      // (foreground, background, where)
      final pairs = [
        (p.onBrand, p.brand, 'filled button, FAB'),
        (p.brand, p.surface, 'brand text on cards, nav bar label'),
        (p.brand, p.background, 'rail label, app bar actions'),
        (p.brand, p.brandSoft, 'selected chip label'),
        (p.brandDark, p.brandSoft, 'selected segment label'),
        (p.text, p.surface, 'body'),
        (p.text, p.surfaceTint, 'tonal button label'),
        (p.textMuted, p.surface, 'meta, subtitles'),
        (p.textMuted, p.background, 'meta on canvas'),
      ];
      for (final (fg, bg, where) in pairs) {
        expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: where);
      }
      expect(theme.colorScheme.primary, p.brand);
      expect(theme.navigationRailTheme.backgroundColor, p.background);
      expect(theme.navigationRailTheme.selectedLabelTextStyle?.color, p.brand);
      expect(theme.chipTheme.secondaryLabelStyle?.color, p.brand);
    });

    testWidgets('$name: filled is brand, tonal and outlined are neutral',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(children: [
            FilledButton(onPressed: () {}, child: const Text('primary')),
            FilledButton.tonal(onPressed: () {}, child: const Text('tonal')),
            OutlinedButton(onPressed: () {}, child: const Text('outlined')),
          ]),
        ),
      ));
      Material fill(String label) => tester.widget<Material>(find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first);
      expect(fill('primary').color, palette.brand);
      expect(fill('primary').textStyle?.color, palette.onBrand);
      for (final label in ['tonal', 'outlined']) {
        expect(fill(label).color, palette.surfaceTint, reason: label);
        expect(fill(label).textStyle?.color, palette.text, reason: label);
      }
    });
  }
}
