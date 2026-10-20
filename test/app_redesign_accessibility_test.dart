import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_text_size_settings.dart';

import 'app_redesign_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'favorites count stays readable with reachable actions at scale 2.3',
      (tester) async {
    await pumpRedesignShell(tester,
        size: const Size(320, 640), textScale: 2 * ForumTextSize.large.scale);
    await selectRedesignTab(tester, '收藏');
    expect(tester.takeException(), isNull);
    final count = find.textContaining('已加载 8 个主题');
    expect(count, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(count);
    final text = paragraph.text.toPlainText();
    final lines = paragraph
        .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length))
        .length;
    debugPrint(
        'FAVORITES_320_2.3 noteLines=$lines note=${tester.getRect(count)} '
        'search=${tester.getRect(find.byTooltip('搜索收藏'))} '
        'select=${tester.getRect(find.byKey(const ValueKey('favorite-select-start')))}');
    expect(
      lines,
      lessThanOrEqualTo(2),
      reason:
          'The count is a readable subtitle, not a column of single characters',
    );
    for (final action in [
      find.byTooltip('搜索收藏'),
      find.byKey(const ValueKey('favorite-select-start')),
    ]) {
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    }
  });

  for (final width in [360.0, 900.0]) {
    testWidgets('header actions have 48px reachable targets at $width',
        (tester) async {
      await pumpRedesignShell(tester, size: Size(width, 800));
      await selectRedesignTab(tester, '收藏');
      for (final action in [
        find.byTooltip('搜索收藏'),
        find.byKey(const ValueKey('favorite-select-start')),
      ]) {
        debugPrint('HEADER_ACTION_$width ${tester.getRect(action)}');
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(48));
      }
      await tester.tapAt(
          tester.getCenter(find.byTooltip('搜索收藏')) + const Offset(0, 23));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget,
          reason: 'The search action responds at the edge of its 48px target');
      await tester.tapAt(tester
              .getCenter(find.byKey(const ValueKey('favorite-select-start'))) +
          const Offset(0, 23));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favorite-select-exit')), findsOneWidget,
          reason: 'The selection action responds at its 48px edge too');
      await selectRedesignTab(tester, '我的');
      final settings = find.byTooltip('设置');
      debugPrint('HEADER_SETTINGS_$width ${tester.getRect(settings)}');
      expect(settings.hitTestable(), findsOneWidget);
      expect(tester.getSize(settings).shortestSide, greaterThanOrEqualTo(48));
    },
        variant: TargetPlatformVariant({
          width >= 600 ? TargetPlatform.linux : TargetPlatform.android,
        }));
  }
}
