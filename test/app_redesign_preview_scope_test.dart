import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/editor/windcode_preview.dart';

void main() {
  testWidgets(
      'a preview revoked before its first build closes its route and future',
      (tester) async {
    final epoch = ValueNotifier(0);
    addTearDown(epoch.dispose);
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              showWindCodePreview(context,
                      source: 'fixture-owner-a private preview', closeOn: epoch)
                  .then((_) => completed = true);
            },
            child: const Text('Open preview'),
          ),
        ),
      ),
    ));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
    await tester.tap(find.text('Open preview'));
    expect(navigator.canPop(), isTrue,
        reason: 'The helper must have actually pushed a preview route');
    expect(completed, isFalse);
    // The scope can change before Navigator first builds the new sheet.
    epoch.value++;
    await tester.pump();
    expect(
        find.textContaining('fixture-owner-a',
            findRichText: true, skipOffstage: false),
        findsNothing);
    await tester.pumpAndSettle();
    debugPrint(
        'PREVIEW_EARLY completed=$completed canPop=${navigator.canPop()} '
        'rootHits=${find.text('Open preview').hitTestable().evaluate().length}');
    expect(completed, isTrue,
        reason: 'An empty child is not a closed preview route');
    expect(navigator.canPop(), isFalse);
    expect(find.text('Open preview').hitTestable(), findsOneWidget,
        reason: 'No invisible modal barrier may block the new scope');
    expect(tester.takeException(), isNull);
  });
}
