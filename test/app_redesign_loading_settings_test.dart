import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/settings_screen.dart';
import 'package:south_plus_rewrite/services/forum_text_size_settings.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

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
Finder _choice(LoadingDomain domain, String label) =>
    find.descendant(of: _row(domain), matching: find.text(label));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  final writes = <String>[];
  var rejectReads = false;
  var rejectWrites = false;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    writes.clear();
    rejectReads = rejectWrites = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'fixture-read-failure');
        return Map<String, Object>.of(persisted);
      }
      final args = call.arguments as Map;
      writes.add(args['key'] as String);
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
      'all eight loading choices remain readable and operable at 320px and scale 2.3',
      (tester) async {
    await LoadingPreferences.load();
    await _pump(tester, scale: 2 * ForumTextSize.large.scale);
    expect(tester.takeException(), isNull);
    for (final domain in LoadingDomain.values) {
      await tester.ensureVisible(_row(domain));
      await tester.pumpAndSettle();
      final control = find.descendant(
          of: _row(domain),
          matching: find.byType(SegmentedButton<LoadingMode>));
      for (final label in ['手动翻页', '自动接续']) {
        final choice = _choice(domain, label);
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        expect(choice.hitTestable(), findsOneWidget,
            reason: '$domain retains its $label control');
        final rect = tester.getRect(choice);
        final bounds = tester.getRect(control);
        expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.5));
        expect(rect.right, lessThanOrEqualTo(bounds.right + 0.5));
        expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.5));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.5));
        final paragraph = tester.renderObject<RenderParagraph>(choice);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
            paragraph.size.height,
            greaterThanOrEqualTo(
                paragraph.getMinIntrinsicHeight(paragraph.size.width) - 0.5));
      }
      final next = LoadingPreferences.modeFor(domain) == LoadingMode.manual
          ? LoadingMode.continuous
          : LoadingMode.manual;
      final choice =
          _choice(domain, next == LoadingMode.manual ? '手动翻页' : '自动接续');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
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
    await tester.tap(_choice(LoadingDomain.thread, '自动接续'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    rejectReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('加载设置读取失败'), findsNothing);
    await tester.tap(_choice(LoadingDomain.thread, '自动接续'));
    await tester.pumpAndSettle();
    expect(persisted['flutter.settings.autoLoadNextPage'], true);
  });

  testWidgets(
      'a failed save keeps the visible choice and reports failure before retry',
      (tester) async {
    await LoadingPreferences.load();
    await _pump(tester);
    rejectWrites = true;
    await tester.tap(_choice(LoadingDomain.thread, '自动接续'));
    await tester.pumpAndSettle();
    final control = find.descendant(
        of: _row(LoadingDomain.thread),
        matching: find.byType(SegmentedButton<LoadingMode>));
    expect(tester.widget<SegmentedButton<LoadingMode>>(control).selected,
        {LoadingMode.manual});
    expect(find.text('无法保存加载设置'), findsOneWidget);
    expect(persisted['flutter.settings.autoLoadNextPage'], isNull);
    rejectWrites = false;
    await tester.tap(_choice(LoadingDomain.thread, '自动接续'));
    await tester.pumpAndSettle();
    expect(persisted['flutter.settings.autoLoadNextPage'], true);
    expect(tester.widget<SegmentedButton<LoadingMode>>(control).selected,
        {LoadingMode.continuous});
  });
}
