import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/settings_screen.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

Future<PackageInfo> _info() async => PackageInfo(
    appName: 'sp', packageName: 'sp', version: '1.0.0', buildNumber: '1');

void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          repository: ForumRepository(), packageInfoLoader: _info),
    ));
    await tester.pumpAndSettle();
  }

  // 加载与分页 opens its own page, one choice per list.
  Future<void> openLoading(WidgetTester tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('加载与分页'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('加载与分页'));
    await tester.pumpAndSettle();
  }

  Set<LoadingMode> shown(WidgetTester tester, LoadingDomain domain) => tester
      .widget<SegmentedButton<LoadingMode>>(find.descendant(
        of: find.byKey(ValueKey('loading-${domain.name}')),
        matching: find.byType(SegmentedButton<LoadingMode>),
      ))
      .selected;

  testWidgets('加载与分页 shows each list\'s default and saves a change',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openLoading(tester);
    expect(shown(tester, LoadingDomain.thread), {LoadingMode.manual});
    expect(shown(tester, LoadingDomain.board), {LoadingMode.continuous});

    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('loading-thread')),
      matching: find.text('自动接续'),
    ));
    await tester.pumpAndSettle();
    expect(shown(tester, LoadingDomain.thread), {LoadingMode.continuous});
    // The thread keeps the key it has always used.
    expect(
      (await SharedPreferences.getInstance())
          .getBool('settings.autoLoadNextPage'),
      isTrue,
    );
  });

  testWidgets(
      'a guest can reach local home personalization without the account group',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('首页版块'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('个性化'), findsOneWidget);
    expect(find.text('账号'), findsNothing);
    final tile = find
        .ancestor(of: find.text('首页版块'), matching: find.byType(InkWell))
        .first;
    expect(tester.widget<InkWell>(tile).onTap, isNotNull);
  });

  testWidgets('加载与分页 fits a 320 phone at system 2x × App 1.15', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2.3)),
        child: child!,
      ),
      home: const LoadingSettingsScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('loading-avatars')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载与分页 shows the saved choices', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.autoLoadNextPage': true,
      'settings.loading.board': 'manual',
    });
    await LoadingPreferences.load();
    await openLoading(tester);
    expect(shown(tester, LoadingDomain.thread), {LoadingMode.continuous});
    expect(shown(tester, LoadingDomain.board), {LoadingMode.manual});
  });

  testWidgets('the version row is information, not a disabled control',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SettingsScreen(
          repository: ForumRepository(), packageInfoLoader: _info),
    ));
    await tester.pumpAndSettle();
    final version = find.text('v1.0.0+1');
    await tester.scrollUntilVisible(version, 180,
        scrollable: find.byType(Scrollable).first);
    Color? color(Finder text) =>
        tester.renderObject<RenderParagraph>(text).text.style?.color;
    expect(color(find.text('版本')), AppColors.lightPalette.text);
    expect(color(version), AppColors.lightPalette.textMuted);
  });
}
