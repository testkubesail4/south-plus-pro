import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color ink, Color fill) {
  final a = Color.alphaBlend(ink, fill).computeLuminance() + 0.05;
  final b = fill.computeLuminance() + 0.05;
  return a > b ? a / b : b / a;
}

/// The busy spinner in [button] stands out from the fill the button really
/// paints at least as well as the button's own label does.
void expectSpinnerReadsLikeLabel(WidgetTester tester, Finder button) {
  Finder inside(Type type) =>
      find.descendant(of: button, matching: find.byType(type));
  final spinnerAt = inside(CircularProgressIndicator);
  final spinner = tester.widget<CircularProgressIndicator>(spinnerAt);
  final context = tester.element(spinnerAt);
  final theme = Theme.of(context);
  // The order CircularProgressIndicator itself resolves its colour in.
  final ink = spinner.valueColor?.value ??
      spinner.color ??
      ProgressIndicatorTheme.of(context).color ??
      theme.colorScheme.primary;
  final label =
      tester.widget<RichText>(inside(RichText).last).text.style!.color!;
  final fill = Color.alphaBlend(
    tester.widget<Material>(inside(Material).first).color ?? Colors.transparent,
    theme.scaffoldBackgroundColor,
  );
  expect(
    _contrast(ink, fill),
    greaterThanOrEqualTo(_contrast(label, fill) - 0.01),
    reason: 'spinner $ink and label $label on fill $fill',
  );
}
