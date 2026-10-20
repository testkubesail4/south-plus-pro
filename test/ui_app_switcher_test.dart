import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/app_switcher.dart';

void main() {
  Widget app(String shown, {bool reduce = false, List<String>? taps}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(
            body: AppSwitcher(
              id: shown,
              direction: 1,
              child: TextButton(
                onPressed: () => taps?.add(shown),
                child: Text(shown),
              ),
            ),
          ),
        ),
      );

  testWidgets('mid-swap both show; only the new one is tapped or read',
      (tester) async {
    final taps = <String>[];
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app('A', taps: taps));
    await tester.pumpWidget(app('B', taps: taps));
    await tester.pump(const Duration(milliseconds: 80));

    final a = tester.widget<FadeTransition>(find
        .ancestor(of: find.text('A'), matching: find.byType(FadeTransition))
        .first);
    final b = tester.widget<FadeTransition>(find
        .ancestor(of: find.text('B'), matching: find.byType(FadeTransition))
        .first);
    expect(a.opacity.value, inExclusiveRange(0, 1));
    expect(b.opacity.value, inExclusiveRange(0, 1));
    // Linear: together never fainter than one whole child.
    expect(a.opacity.value + b.opacity.value, closeTo(1, 0.01));
    // Read from the semantics tree itself.
    expect(find.semantics.byLabel('A'), findsNothing);
    expect(find.semantics.byLabel('B'), findsOneWidget);

    expect(find.text('A').hitTestable(), findsNothing);
    await tester.tap(find.text('B'));
    expect(taps, ['B']);

    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a new scope drops the leaving child in the same frame',
      (tester) async {
    Widget scoped(String shown, int scope) => MaterialApp(
          home: AppSwitcher(id: shown, scope: scope, child: Text(shown)),
        );
    await tester.pumpWidget(scoped('A', 1));
    await tester.pumpWidget(scoped('B', 1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('A'), findsOneWidget, reason: 'mid-swap');
    await tester.pumpWidget(scoped('B', 2));
    expect(find.text('A', skipOffstage: false), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('reduced motion swaps at once', (tester) async {
    await tester.pumpWidget(app('A', reduce: true));
    await tester.pumpWidget(app('B', reduce: true));
    await tester.pump();
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('a sliver reveal starts at 65%, never blank', (tester) async {
    Widget list(int id) => MaterialApp(
          home: CustomScrollView(slivers: [
            AppSliverReveal(
              id: id,
              sliver: SliverToBoxAdapter(child: Text('page $id')),
            ),
          ]),
        );
    double opacity() => tester
        .widget<SliverFadeTransition>(find.byType(SliverFadeTransition))
        .opacity
        .value;
    await tester.pumpWidget(list(1));
    expect(opacity(), 1, reason: 'first content shows as is');
    await tester.pumpWidget(list(2));
    expect(opacity(), 0.65);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), inExclusiveRange(0.65, 1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });

  testWidgets('the leaving child keeps its text but loses focus and keys',
      (tester) async {
    Widget app(String shown) => MaterialApp(
          home: Scaffold(
            body: AppSwitcher(
              id: shown,
              child: shown == 'A'
                  ? const TextField(autofocus: true)
                  : const Text('B'),
            ),
          ),
        );
    await tester.pumpWidget(app('A'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'typed');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpWidget(app('B'));
    await tester.pump(const Duration(milliseconds: 80));
    // Still shown as it was while it fades, but no longer typed into.
    expect(find.text('typed'), findsOneWidget);
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
