import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/settings_screen.dart';
import 'package:south_plus_rewrite/services/forum_text_size_settings.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

import 'app_redesign_fixture.dart';

Future<void> _pump(WidgetTester tester, {double scale = 1}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: const LoadingSettingsScreen(),
  ));
  await tester.pumpAndSettle();
}

Finder _row(LoadingDomain domain) =>
    find.byKey(ValueKey('loading-${domain.name}'));
// On is 自动接续, off 手动翻页.
Finder _switch(LoadingDomain domain) =>
    find.descendant(of: _row(domain), matching: find.byType(Switch));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  final writes = <String>[];
  var rejectReads = false;
  var rejectWrites = false;
  var throwWrites = false;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    writes.clear();
    rejectReads = rejectWrites = throwWrites = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'fixture-read-failure');
        return Map<String, Object>.of(persisted);
      }
      final args = call.arguments as Map;
      writes.add(args['key'] as String);
      if (throwWrites) throw PlatformException(code: 'fixture-write-failure');
      if (rejectWrites) return false;
      persisted[args['key'] as String] = args['value'] as Object;
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'all eight loading switches remain readable and operable at 320px and scale 2.3',
      (tester) async {
    await LoadingPreferences.load();
    await _pump(tester, scale: 2 * ForumTextSize.large.scale);
    expect(tester.takeException(), isNull);
    for (final domain in LoadingDomain.values) {
      await tester.ensureVisible(_row(domain));
      await tester.pumpAndSettle();
      expect(_switch(domain).hitTestable(), findsOneWidget,
          reason: '$domain retains its switch');
      final title = tester.renderObject<RenderParagraph>(
          find.descendant(of: _row(domain), matching: find.byType(Text)).first);
      expect(title.didExceedMaxLines, isFalse, reason: '$domain title whole');
      expect(tester.getRect(_switch(domain)).right,
          lessThanOrEqualTo(tester.getRect(_row(domain)).right + 0.5));
      final next = LoadingPreferences.modeFor(domain) == LoadingMode.manual
          ? LoadingMode.continuous
          : LoadingMode.manual;
      await tester.tap(_switch(domain));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(_switch(domain)).value,
          next == LoadingMode.continuous);
      // Readers get one named control carrying its state.
      expect(
          tester.getSemantics(_switch(domain)),
          containsSemantics(
            label: title.text.toPlainText(),
            hasToggledState: true,
            isToggled: next == LoadingMode.continuous,
            hasTapAction: true,
          ));
      expect(LoadingPreferences.modeFor(domain), next,
          reason: 'The visible $domain row must save its own domain');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'failed reads disable choice writes until the visible retry succeeds',
      (tester) async {
    rejectReads = true;
    // A failed startup must leave the actual service unread, not a test-only flag.
    await expectLater(
        LoadingPreferences.load(), throwsA(isA<PlatformException>()));
    await _pump(tester);
    expect(find.text('加载设置读取失败'), findsOneWidget);
    expect(
        tester.widget<Switch>(_switch(LoadingDomain.thread)).onChanged, isNull);
    await tester.tap(_switch(LoadingDomain.thread), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    rejectReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('加载设置读取失败'), findsNothing);
    await tester.tap(_switch(LoadingDomain.thread));
    await tester.pumpAndSettle();
    expect(persisted['flutter.settings.autoLoadNextPage'], true);
  });

  testWidgets(
      'a failed save keeps the visible choice and reports failure before retry',
      (tester) async {
    await LoadingPreferences.load();
    await _pump(tester);
    rejectWrites = true;
    final control = _switch(LoadingDomain.thread);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(control).value, isFalse);
    expect(find.text('无法保存加载设置'), findsOneWidget);
    expect(persisted['flutter.settings.autoLoadNextPage'], isNull);
    rejectWrites = false;
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(persisted['flutter.settings.autoLoadNextPage'], true);
    expect(tester.widget<Switch>(control).value, isTrue);
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        repository: AppRedesignRepository(),
        packageInfoLoader: () async => PackageInfo(
            appName: 'fixture',
            packageName: 'fixture',
            version: '0.0.0',
            buildNumber: '0'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a choice menu announces the current option and Escape keeps it',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpSettings(tester);
    expect(find.text('系统'), findsOneWidget);
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    // The option itself carries the state, on the node that takes the tap.
    expect(tester.getSemantics(find.bySemanticsLabel('系统')),
        containsSemantics(isSelected: true, hasTapAction: true));
    expect(tester.getSemantics(find.bySemanticsLabel('深色')),
        containsSemantics(isSelected: false, hasTapAction: true));
    expect(tester.getRect(find.widgetWithText(MenuItemButton, '深色')).height,
        greaterThanOrEqualTo(48));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.text('系统'), findsOneWidget);
    expect(writes, isEmpty);
    semantics.dispose();
  });

  testWidgets('a settings choice that fails to save says so and keeps the row',
      (tester) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('图片加载'), 180,
        scrollable: find.byType(Scrollable).first);
    throwWrites = true;
    await tester.tap(find.text('图片加载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无图模式'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败，请稍后重试'), findsOneWidget);
    expect(find.text('自动加载'), findsOneWidget);
    expect(find.text('无图模式'), findsNothing);
  });
}
