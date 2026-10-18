import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/search_scope_bar.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/full_scan.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

void main() {
  final cases = <(String, ScanProgress, List<String>)>[
    (
      'loaded pages offer the full scan',
      const ScanProgress(scannedPages: 3, totalPages: 12),
      ['搜索全部页面'],
    ),
    (
      'a running scan can only stop',
      const ScanProgress(
        state: ScanState.running,
        scannedPages: 6,
        totalPages: 12,
      ),
      ['停止'],
    ),
    (
      'a waiting retry can only stop',
      ScanProgress(
        state: ScanState.waiting,
        scannedPages: 6,
        retryAt: DateTime.now().add(const Duration(seconds: 5)),
        attempt: 2,
        failure: ForumRequestKind.rateLimited,
      ),
      ['停止'],
    ),
    (
      'a stopped scan continues or goes back',
      const ScanProgress(
        state: ScanState.stopped,
        scannedPages: 6,
        canResume: true,
      ),
      ['继续', '返回已加载'],
    ),
    (
      'a capped scan cannot continue',
      const ScanProgress(state: ScanState.stopped, found: 200, capped: true),
      ['返回已加载'],
    ),
    (
      'a lost login is not retried here',
      const ScanProgress(
        state: ScanState.failed,
        failure: ForumRequestKind.loginRequired,
      ),
      ['返回已加载'],
    ),
    (
      'a finished scan goes back',
      const ScanProgress(
        state: ScanState.done,
        scannedPages: 12,
        totalPages: 12,
      ),
      ['返回已加载'],
    ),
  ];
  for (final (name, progress, labels) in cases) {
    testWidgets(name, (tester) async {
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
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
      // An unfinished scan never claims there is nothing.
      if (progress.state != ScanState.done) {
        expect(find.textContaining('没有'), findsNothing);
      }
    });
  }
}
