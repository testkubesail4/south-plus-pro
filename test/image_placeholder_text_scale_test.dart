import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/cached_forum_image.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';

// A small preview box in manual image mode at text scale 2, where the
// label wraps to more lines than the box holds.
void main() {
  testWidgets('the tap-to-load placeholder fits a small box at text scale 2',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .runAsync(() => ImageLoadingSettings.saveMode(ImageLoadMode.manual));
    addTearDown(() => ImageLoadingSettings.saveMode(ImageLoadMode.automatic));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: CachedForumImage(
            url: 'https://fixture.invalid/preview.png',
            width: 100,
            height: 80,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('点击加载图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
