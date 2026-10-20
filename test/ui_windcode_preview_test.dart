import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/editor/windcode_preview.dart';

void main() {
  testWidgets('a session change before the preview first builds closes it',
      (tester) async {
    final session = ValueNotifier(0);
    addTearDown(session.dispose);
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWindCodePreview(
              context,
              source: 'Private draft',
              closeOn: session,
            ).whenComplete(() => done++),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    final barriers = find.byType(ModalBarrier).evaluate().length;

    // Opened, and the account changes before the sheet's first frame.
    await tester.tap(find.text('open'));
    session.value++;
    await tester.pump();
    expect(
        find.textContaining('Private draft', findRichText: true), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ModalBarrier).evaluate().length, barriers);
    expect(done, 1);

    // The page under it answers again.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Private draft', findRichText: true),
        findsOneWidget);
  });
}
