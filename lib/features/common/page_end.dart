import 'package:flutter/material.dart';

import 'async_state_view.dart' show forumErrorText;

/// Where an appended page starts in a continuous list: 第 N 页 between rules.
class PageBoundary extends StatelessWidget {
  const PageBoundary({super.key, required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '第 $page 页',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// What a paged list shows under its last row, the same in every list:
/// the page loading, a failed page to retry, the next page to load, or the
/// end. [next] is the page a tap loads; null once the last page is shown.
///
/// [manual] lists only ever load on a tap: 下一页 · 第 N 页. Continuous ones
/// load by themselves and show the button only once they [paused] after
/// pages that added nothing new.
class PageEndFooter extends StatelessWidget {
  const PageEndFooter({
    super.key,
    required this.next,
    required this.onNext,
    this.manual = false,
    this.loading = false,
    this.failed = false,
    this.error,
    this.paused = false,
    this.nextLabel,
  });

  final int? next;
  final VoidCallback? onNext;
  final bool manual;
  final bool loading;

  /// Loading [next] failed, for [error] when known; the button retries it.
  final bool failed;
  final Object? error;
  final bool paused;

  /// Replaces 下一页 · 第 N 页 where a tap appends instead (加载更多).
  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final page = next;
    final muted = Theme.of(context).textTheme.bodySmall;
    final Widget child;
    if (loading) {
      child = Semantics(
        liveRegion: true,
        label: page == null ? '正在加载' : '正在加载第 $page 页',
        child: const SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (failed && page != null) {
      child = Column(
        children: [
          Text(
              error == null
                  ? '第 $page 页加载失败'
                  : '第 $page 页加载失败：${forumErrorText(error)}',
              textAlign: TextAlign.center,
              style: muted),
          TextButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      );
    } else if (page == null) {
      child = Text('已到最后一页', style: muted);
    } else if (paused) {
      child = Column(
        children: [
          Text('后续页面的内容已被过滤或重复', textAlign: TextAlign.center, style: muted),
          TextButton(
            onPressed: onNext,
            child: Text(nextLabel ?? '继续加载第 $page 页'),
          ),
        ],
      );
    } else if (manual) {
      child = FilledButton.icon(
        key: const ValueKey('page-end-next'),
        onPressed: onNext,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: Text(nextLabel ?? '下一页 · 第 $page 页'),
      );
    } else {
      // Continuous, idle: the next page loads on reaching here; the button
      // covers a list too short to scroll.
      child = TextButton(
        onPressed: onNext,
        child: Text(nextLabel ?? '加载第 $page 页'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: child),
    );
  }
}
