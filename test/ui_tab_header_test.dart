import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/app_tab_header.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: AppTabHeader(
          title: '收藏',
          subtitle: '已加载 30 个主题 · 第 1/3 页',
          actions: [
            IconButton(
                tooltip: '搜索收藏',
                onPressed: () {},
                icon: const Icon(Icons.search)),
            TextButton(onPressed: () {}, child: const Text('选择')),
          ],
        ),
      ),
    ));
  }

  testWidgets('the note sits beside the title at normal sizes', (tester) async {
    await pump(tester, 1);
    final title = tester.getRect(find.text('收藏'));
    final note = tester.getRect(find.textContaining('已加载'));
    expect(note.left, greaterThan(title.right));
    expect(note.center.dy, moreOrLessEquals(title.center.dy, epsilon: 1));
  });

  testWidgets('large text moves the note under the title, actions stay whole',
      (tester) async {
    await pump(tester, 2.3);
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('收藏'));
    final note = tester.getRect(find.textContaining('已加载'));
    expect(note.top, greaterThanOrEqualTo(title.bottom));
    expect(note.left, title.left);
    // The ink (tap) area itself, not padding a platform may add around it.
    final inks = find.descendant(
        of: find.byType(AppTabHeader), matching: find.byType(InkWell));
    expect(inks, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      final size = tester.getSize(inks.at(i));
      expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
      await tester.tap(inks.at(i), warnIfMissed: true);
    }
    expect(tester.getRect(find.text('选择')).right, lessThanOrEqualTo(320));
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.linux}));
}
