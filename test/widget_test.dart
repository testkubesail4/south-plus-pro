import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/thread/thread_rich_content.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

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

  testWidgets('deferred inline image placeholder stays compact',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ImageLoadingSettings.saveMode(ImageLoadMode.manual);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ThreadInlineImage(
              image: ThreadImage(url: 'https://example.com/image.jpg'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(ThreadInlineImage)).height, 160);
  });
}
