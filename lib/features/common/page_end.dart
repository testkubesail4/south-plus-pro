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

/// One empty page of a list that has others: only this page is empty.
class PageEmptyNote extends StatelessWidget {
  const PageEmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall),
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
    this.onRefresh,
    this.nextNumbered = true,
    this.endConfirmed = true,
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

  /// Offered after the last page, where new rows may still arrive.
  final VoidCallback? onRefresh;

  /// Whether [next] is the page's real number; otherwise it is only
  /// 下一页, wherever the forum's link leads.
  final bool nextNumbered;

  /// Whether the page count confirms there is no [next]; otherwise the
  /// forum only gave no link to one, and the end is not claimed.
  final bool endConfirmed;

  @override
  Widget build(BuildContext context) {
    final page = next;
    final name = nextNumbered ? '第 $page 页' : '下一页';
    final muted = Theme.of(context).textTheme.bodySmall;
    final Widget child;
    if (loading) {
      child = Semantics(
        liveRegion: true,
        label: page == null ? '正在加载' : '正在加载$name',
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
                  ? '$name加载失败'
                  : '$name加载失败：${forumErrorText(error)}',
              textAlign: TextAlign.center,
              style: muted),
          TextButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      );
    } else if (page == null && !endConfirmed) {
      child =
          Text('论坛未给出下一页，页数未能确认', textAlign: TextAlign.center, style: muted);
    } else if (page == null) {
      final refresh = onRefresh;
      child = Column(
        children: [
          Text('已到最后一页', style: muted),
          if (refresh != null)
            TextButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新本页'),
            ),
        ],
      );
    } else if (paused) {
      child = Column(
        children: [
          Text('后续页面的内容已被过滤或重复', textAlign: TextAlign.center, style: muted),
          TextButton(
            onPressed: onNext,
            child: Text(nextLabel ?? '继续加载$name'),
          ),
        ],
      );
    } else if (manual) {
      child = FilledButton.icon(
        key: const ValueKey('page-end-next'),
        onPressed: onNext,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: Text(nextLabel ?? (nextNumbered ? '下一页 · $name' : name)),
      );
    } else {
      // Continuous, idle: the next page loads on reaching here; the button
      // covers a list too short to scroll.
      child = TextButton(
        onPressed: onNext,
        child: Text(nextLabel ?? '加载$name'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(child: child),
    );
  }
}
