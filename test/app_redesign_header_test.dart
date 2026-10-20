import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_redesign_fixture.dart';

const _tabs = ['首页', '收藏', '搜索', '消息', '我的'];
const _headings = ['fixture-owner-a', '收藏', '搜索', '消息', '我的'];

Finder _heading(WidgetTester tester, String label) {
  final matches = find.text(label).evaluate().toList()
    ..sort((a, b) => tester
        .getTopLeft(find.byWidget(a.widget))
        .dy
        .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
  expect(matches, isNotEmpty, reason: 'The $label page has a visible heading');
  return find.byWidget(matches.first.widget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [360.0, 900.0]) {
    testWidgets(
        'five primary headings share a hierarchy and baseline at $width',
        (tester) async {
      await pumpRedesignShell(tester, size: Size(width, 800));
      final headings =
          <({double? size, FontWeight? weight, double baseline})>[];
      for (var i = 0; i < _tabs.length; i++) {
        await selectRedesignTab(tester, _tabs[i]);
        final heading = _heading(tester, _headings[i]);
        final paragraph = tester.renderObject<RenderParagraph>(heading);
        headings.add((
          size: paragraph.text.style?.fontSize,
          weight: paragraph.text.style?.fontWeight,
          baseline: tester.getTopLeft(heading).dy +
              paragraph.getDryBaseline(
                  paragraph.constraints, TextBaseline.alphabetic)!,
        ));
        expect(tester.takeException(), isNull, reason: _tabs[i]);
      }
      expect(headings.map((h) => (h.size, h.weight)).toSet(),
          {(20.0, FontWeight.w700)},
          reason: 'Top-level pages have the same visible title hierarchy');
      final baseline = headings.first.baseline;
      for (var i = 1; i < headings.length; i++) {
        expect(headings[i].baseline, closeTo(baseline, 1),
            reason: '${_tabs[i]} aligns with 首页');
      }
    });
  }
}
