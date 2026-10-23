import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/search_scope_bar.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);
  // Name, progress, the headline and detail shown, and the actions offered.
  final cases = <(String, ScanProgress, (String, String), List<String>)>[
    (
      'loaded pages offer the full scan',
      const ScanProgress(
          scannedPages: 3, totalPages: 12, found: 2, unresolved: 1),
      ('已加载的页面', '找到 2 条 · 已加载 3/12 页 · 待确认 1 条'),
      ['搜索全部页面'],
    ),
    (
      'a running scan can only stop',
      const ScanProgress(
          state: ScanState.running,
          scannedPages: 6,
          totalPages: 12,
          found: 7,
          pending: 2),
      ('正在搜索全部页面', '已搜索 6/12 页 · 已找到 7 条 · 待补资料 2 条'),
      ['停止'],
    ),
    (
      'a waiting retry counts down and can only stop',
      ScanProgress(
        state: ScanState.waiting,
        scannedPages: 6,
        retryAt: now.add(const Duration(milliseconds: 4200)),
        attempt: 2,
        failure: ForumRequestKind.rateLimited,
      ),
      ('请求过于频繁，等待重试', '5 秒后重试（第 2/3 次） · 已搜索 6 页 · 已找到 0 条'),
      ['停止'],
    ),
    (
      'a stopped scan continues or goes back',
      const ScanProgress(
          state: ScanState.stopped,
          scannedPages: 6,
          found: 3,
          unresolved: 1,
          canResume: true),
      ('已停止，结果不完整', '已搜索 6 页 · 找到 3 条 · 待确认 1 条'),
      ['继续', '返回已加载'],
    ),
    (
      'a cap counts the undecided rows it kept',
      const ScanProgress(
          state: ScanState.stopped, unresolved: 200, capped: true),
      ('已达结果上限，已停止', '已搜索 0 页 · 找到 0 条 · 待确认 200 条，结果不完整'),
      ['返回已加载'],
    ),
    (
      'a lost login is not retried here',
      const ScanProgress(
          state: ScanState.failed,
          scannedPages: 4,
          totalPages: 9,
          found: 1,
          failure: ForumRequestKind.loginRequired),
      ('搜索中断：登录失效', '已搜索 4/9 页 · 找到 1 条，结果不完整 · 请重新登录后再搜索'),
      ['返回已加载'],
    ),
    (
      'a finished scan goes back',
      const ScanProgress(
          state: ScanState.done,
          scannedPages: 12,
          totalPages: 12,
          found: 9,
          unresolved: 2),
      ('已搜索全部页面', '共 12 页 · 找到 9 条 · 2 条无法确认'),
      ['返回已加载'],
    ),
  ];
  for (final (name, progress, text, labels) in cases) {
    testWidgets(name, (tester) async {
      expect(scanStatusText(progress, now), text);
      // An unfinished scan never claims there is nothing.
      expect('${text.$1}${text.$2}', isNot(contains('没有')));

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SearchScopeBar(
            progress: progress,
            onSearchAll: () {},
            onStop: () {},
            onResume: () {},
            onBackToLoaded: () {},
          ),
        ),
      ));
      expect(find.text(text.$1), findsOneWidget);
      final shown = [
        for (final element in find
            .descendant(
              of: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              matching: find.byType(Text),
            )
            .evaluate())
          (element.widget as Text).data,
      ];
      expect(shown, labels);
    });
  }

  testWidgets(
      'the full-scan confirmation keeps its cost and its button at 320dp, '
      '2.3x text and a keyboard up', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? confirmed;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2.3),
          viewInsets: const EdgeInsets.only(bottom: 250),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => confirmed = await confirmFullScan(context,
                subject: '本帖', remainingPages: 200),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final line in ['剩余 200 页，约 4 分钟', '频繁读取可能触发限流']) {
      await tester.scrollUntilVisible(find.text(line), 50,
          scrollable: find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Scrollable)));
      expect(find.text(line).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.text('开始搜索').hitTestable());
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
