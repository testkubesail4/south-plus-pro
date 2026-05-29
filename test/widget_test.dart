import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';

void main() {
  testWidgets('app boots to simple home screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SouthPlusApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('southplus'), findsOneWidget);
    expect(find.text('dlkd'), findsOneWidget);
  });

  testWidgets('skeleton card fits compact three-line layouts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: SkeletonCard(height: 86, lines: [0.92, 0.58, 0.36]),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
