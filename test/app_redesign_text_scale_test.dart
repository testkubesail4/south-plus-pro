import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_text_size_settings.dart';

import 'app_redesign_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('all primary pages fit system 2x and app large text ($mode)',
        (tester) async {
      await pumpRedesignShell(
        tester,
        size: const Size(320, 640),
        textScale: 2 * ForumTextSize.large.scale,
        mode: mode,
      );
      for (final tab in ['首页', '收藏', '搜索', '消息', '我的']) {
        await selectRedesignTab(tester, tab);
        final destination =
            find.descendant(of: redesignNavigation(), matching: find.text(tab));
        expect(destination.hitTestable(), findsOneWidget,
            reason: '$tab remains reachable at combined text scale 2.3');
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }
}
