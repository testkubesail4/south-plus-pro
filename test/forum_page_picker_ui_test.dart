import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/forum_pager.dart';

void main() {
  Future<List<String>> openSheet(WidgetTester tester, double textScale) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showForumPagePicker(
            context,
            current: 3,
            total: 12,
            shortcuts: [
              for (final (label, icon) in [
                ('首楼', Icons.first_page),
                ('回到顶部', Icons.vertical_align_top),
                ('到底部', Icons.vertical_align_bottom),
                ('最新回复', Icons.last_page),
              ])
                (label, icon, () => tapped.add(label)),
            ],
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tapped;
  }

  double top(WidgetTester tester, String label) =>
      tester.getTopLeft(find.text(label)).dy;

  testWidgets('shortcuts share one row and close the sheet when used',
      (tester) async {
    final tapped = await openSheet(tester, 1);

    expect(top(tester, '最新回复'), top(tester, '首楼'));
    await tester.tap(find.text('到底部'));
    await tester.pumpAndSettle();
    expect(tapped, ['到底部']);
    expect(find.text('跳转'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('large text puts two shortcuts per row, never breaking a label',
      (tester) async {
    await openSheet(tester, 2);

    expect(top(tester, '回到顶部'), top(tester, '首楼'));
    expect(top(tester, '到底部'), greaterThan(top(tester, '首楼')));
    expect(top(tester, '最新回复'), top(tester, '到底部'));
    for (final label in ['回到顶部', '最新回复']) {
      expect(tester.getSize(find.text(label)).height, lessThan(24 * 2),
          reason: label);
    }
  });
}
