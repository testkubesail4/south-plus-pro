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
    test('$name: brand actions and text meet WCAG AA', () {
      final s = theme.colorScheme;
      expect(_contrast(s.primary, s.onPrimary), greaterThanOrEqualTo(4.5));
      expect(_contrast(s.primary, s.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(_contrast(theme.textTheme.bodySmall!.color!, s.surface),
          greaterThanOrEqualTo(4.5));
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
