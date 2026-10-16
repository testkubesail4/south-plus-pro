import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/async_state_view.dart';
import 'package:south_plus_rewrite/features/common/content_width.dart';
import 'package:south_plus_rewrite/features/common/grouped_list.dart';
import 'package:south_plus_rewrite/features/common/thread_row.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)),
    );

void main() {
  test('appGutter centres the content and keeps the page gutter', () {
    expect(appGutter(400, AppWidths.list), AppSpace.lg);
    expect(appGutter(700, AppWidths.list), AppSpace.xl);
    expect(appGutter(1440, AppWidths.list), (1440 - 840) / 2);
  });

  testWidgets('empty and error views sit in the upper third', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, const EmptyStateView(title: '暂无内容'));
    expect(tester.getCenter(find.text('暂无内容')).dy, lessThan(800 / 2));
    expect(tester.widget<Icon>(find.byType(Icon)).color,
        AppColors.lightPalette.textFaint);

    await _pump(tester,
        AsyncErrorView(title: '加载失败', message: '网络失败', onRetry: () {}));
    expect(tester.getCenter(find.text('加载失败')).dy, lessThan(800 / 2));
    // An error is information, not a placeholder.
    expect(tester.widget<Icon>(find.byIcon(Icons.cloud_off_outlined)).color,
        AppColors.lightPalette.textMuted);
  });

  testWidgets('a row shows a chevron, a check or nothing by its role',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      AppGroup(label: '分组', children: [
        AppRow(title: const Text('打开'), onTap: () => taps++),
        AppRow(title: const Text('已选'), selected: true, onTap: () {}),
        AppRow(title: const Text('未选'), selected: false, onTap: () {}),
        AppRow(title: const Text('退出'), destructive: true, onTap: () {}),
        const AppRow(title: Text('版本'), value: 'v1', enabled: true),
        const AppRow(title: Text('不可用')),
      ]),
    );
    Finder inRow(String title, IconData icon) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(AppRow)),
        matching: find.byIcon(icon));
    expect(inRow('打开', Icons.chevron_right), findsOneWidget);
    expect(inRow('已选', Icons.check), findsOneWidget);
    expect(inRow('未选', Icons.check), findsNothing);
    expect(inRow('未选', Icons.chevron_right), findsNothing);
    expect(inRow('退出', Icons.chevron_right), findsNothing);
    expect(inRow('版本', Icons.chevron_right), findsNothing);
    expect(find.text('v1'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(5));
    Color? color(String text) =>
        tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;
    expect(color('版本'), AppColors.lightPalette.text, reason: 'static info');
    expect(color('不可用'), AppColors.lightPalette.textFaint, reason: 'disabled');
    await tester.tap(find.text('打开'));
    expect(taps, 1);
  });

  testWidgets('thread rows: one meta line; dense rows read the count',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const Column(children: [
        ForumThreadRow(title: '主题', meta: ['茶馆', '作者', '3 回复'], tag: '置顶'),
        ForumThreadRow.dense(title: '速览', count: 17),
      ]),
    );
    expect(find.text('茶馆 · 作者 · 3 回复'), findsOneWidget);
    expect(find.text('置顶'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('17 回复')), findsOneWidget);
    // A count is information: muted, not the faint disabled colour.
    expect(tester.renderObject<RenderParagraph>(find.text('17')).text.style?.color,
        AppColors.lightPalette.textMuted);
    expect(tester.getSize(find.byType(ForumThreadRow).last).height,
        greaterThanOrEqualTo(48));
    semantics.dispose();
  });
}
