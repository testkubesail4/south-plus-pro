import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/account_screen.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/thread_paging_settings.dart';

Future<PackageInfo> _info() async => PackageInfo(
    appName: 'sp', packageName: 'sp', version: '1.0.0', buildNumber: '1');

void main() {
  tearDown(() => ThreadPagingSettings.notifier.value = false);

  Future<Finder> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          repository: ForumRepository(), packageInfoLoader: _info),
    ));
    await tester.pumpAndSettle();
    final title = find.text('自动加载下一页');
    await tester.scrollUntilVisible(title, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    return find.descendant(
      of: find.ancestor(of: title, matching: find.byType(InkWell)).first,
      matching: find.byType(Switch),
    );
  }

  testWidgets('自动加载下一页 is off by default and turns on persistently',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final toggle = await pumpSettings(tester);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('滑到页尾时自动接上下一页；关闭时用页尾的「下一页」翻页'), findsOneWidget);

    await tester.tap(find.text('自动加载下一页'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(ThreadPagingSettings.notifier.value, isTrue);
    expect(
      (await SharedPreferences.getInstance())
          .getBool('settings.autoLoadNextPage'),
      isTrue,
    );
  });

  testWidgets('自动加载下一页 shows the saved choice', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.autoLoadNextPage': true});
    final toggle = await pumpSettings(tester);
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });
}
