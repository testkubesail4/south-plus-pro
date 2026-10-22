import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/forum_request_exception.dart';
import '../../services/full_scan.dart';
import '../../theme/app_theme.dart';
import 'async_state_view.dart';

/// The search box above a list that filters it in place.
///
/// With [onClose] its trailing button closes the search (the owner clears
/// and hides it); without, the button clears the text.
class ListSearchField extends StatelessWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClose,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClose;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final close = onClose;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: close != null
            ? IconButton(
                tooltip: '关闭搜索',
                onPressed: close,
                icon: const Icon(Icons.close),
              )
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => controller.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
      ),
    );
  }
}

/// Where a list search stands and its one next step: the loaded pages
/// ([ScanState.idle]), or a scan of every page and how far it got.
///
/// A scan that has not finished never reads as "nothing found".
class SearchScopeBar extends StatefulWidget {
  const SearchScopeBar({
    super.key,
    required this.progress,
    this.onSearchAll,
    this.onStop,
    this.onResume,
    this.onBackToLoaded,
  });

  final ScanProgress progress;

  /// Offered while searching the loaded pages; null when they are all.
  final VoidCallback? onSearchAll;
  final VoidCallback? onStop;
  final VoidCallback? onResume;

  /// Drops the scan's results and searches the loaded pages again.
  final VoidCallback? onBackToLoaded;

  @override
  State<SearchScopeBar> createState() => _SearchScopeBarState();
}

class _SearchScopeBarState extends State<SearchScopeBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(SearchScopeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // Counts down only while a retry is waiting.
  void _syncTimer() {
    final waiting = widget.progress.state == ScanState.waiting &&
        widget.progress.retryAt != null;
    if (!waiting) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.progress;
    final (headline, detail) = scanStatusText(p, DateTime.now());
    final scanning =
        p.state == ScanState.running || p.state == ScanState.waiting;
    final total = p.totalPages;
    final actions = <Widget>[
      if (p.state == ScanState.idle && widget.onSearchAll != null)
        FilledButton.tonalIcon(
          onPressed: widget.onSearchAll,
          icon: const Icon(Icons.travel_explore),
          label: const Text('搜索全部页面'),
        ),
      if (scanning && widget.onStop != null)
        TextButton.icon(
          onPressed: widget.onStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('停止'),
        ),
      if ((p.state == ScanState.stopped || p.state == ScanState.failed) &&
          p.canResume &&
          !p.capped &&
          widget.onResume != null)
        TextButton.icon(
          onPressed: widget.onResume,
          icon: const Icon(Icons.play_arrow_outlined),
          label: Text(p.state == ScanState.failed ? '重试' : '继续'),
        ),
      if ((p.state == ScanState.stopped ||
              p.state == ScanState.failed ||
              p.state == ScanState.done) &&
          widget.onBackToLoaded != null)
        TextButton(
          onPressed: widget.onBackToLoaded,
          child: const Text('返回已加载'),
        ),
    ];
    return DecoratedBox(
      decoration: appSurface(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.sm,
          AppSpace.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only the state is announced; counts and the countdown change
            // too often to read out.
            Semantics(
              liveRegion: true,
              child: Text(headline, style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: Text(detail, style: theme.textTheme.bodySmall),
            ),
            if (scanning) ...[
              const SizedBox(height: AppSpace.sm),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: LinearProgressIndicator(
                  value: total == null || total == 0
                      ? null
                      : (p.scannedPages / total).clamp(0, 1).toDouble(),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(999),
                  semanticsLabel: '搜索进度',
                  semanticsValue: _pages(p),
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpace.sm,
                children: actions,
              ),
            ] else
              const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
    );
  }
}

String _pages(ScanProgress p) => p.totalPages == null
    ? '${p.scannedPages} 页'
    : '${p.scannedPages}/${p.totalPages} 页';

String _reason(ForumRequestKind? kind) =>
    kind == null ? '请求失败' : forumRequestErrorText(kind);

/// The headline and detail lines [SearchScopeBar] shows for [p] at [now].
(String, String) scanStatusText(ScanProgress p, DateTime now) {
  final pages = _pages(p);
  // What a stopped scan keeps: matches and rows it could not decide.
  final kept = [
    '找到 ${p.found} 条',
    if (p.unresolved > 0) '待确认 ${p.unresolved} 条',
  ].join(' · ');
  return switch (p.state) {
    ScanState.idle => (
        '搜索范围：已加载内容',
        [
          '在已加载的 ${p.scannedPages} 页中找到 ${p.found} 条',
          if (p.totalPages case final total? when total > p.scannedPages)
            '共 $total 页',
          if (p.unresolved > 0) '待确认 ${p.unresolved} 条',
        ].join(' · '),
      ),
    ScanState.running => (
        '正在搜索全部页面',
        [
          '已搜索 $pages',
          '已找到 ${p.found} 条',
          if (p.pending > 0) '待补资料 ${p.pending} 条',
        ].join(' · '),
      ),
    ScanState.waiting => (
        '${_reason(p.failure)}，等待重试',
        [
          if (p.retryAt case final at?)
            '${(at.difference(now).inMilliseconds / 1000).ceil().clamp(0, 999)} 秒后重试'
                '（第 ${p.attempt}/${p.maxAttempts} 次）',
          '已搜索 $pages',
          '已找到 ${p.found} 条',
        ].join(' · '),
      ),
    // Only a caller's explicit cap; user-started scans have none.
    ScanState.stopped when p.capped => (
        '已达结果上限，已停止',
        '已搜索 $pages · $kept，结果不完整',
      ),
    ScanState.stopped => ('已停止，结果不完整', '已搜索 $pages · $kept'),
    ScanState.failed => (
        '搜索中断：${_reason(p.failure)}',
        [
          '已搜索 $pages · $kept，结果不完整',
          if (p.failure == ForumRequestKind.loginRequired) '请重新登录后再搜索',
        ].join(' · '),
      ),
    ScanState.done => (
        '已搜索全部页面',
        [
          '共 ${p.totalPages ?? p.scannedPages} 页',
          '找到 ${p.found} 条',
          if (p.unresolved > 0) '${p.unresolved} 条无法确认',
        ].join(' · '),
      ),
  };
}

/// Asks before reading every page of [subject] (e.g. 本帖, 收藏).
Future<bool> confirmFullScan(
  BuildContext context, {
  required String subject,
  required int? remainingPages,
  // What the scan is for: 搜索 or 排序.
  String verb = '搜索',
}) async {
  final pages = remainingPages;
  // The forum's pacer starts about one read a second.
  final time = pages == null
      ? null
      : pages >= 60
          ? '约 ${(pages / 60).ceil()} 分钟'
          : '约 ${pages < 1 ? 1 : pages} 秒';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$verb全部页面？'),
      content: Text(
        [
          pages == null
              ? '$subject的页数未知，可能需要较长时间。'
              : '将逐页读取$subject剩余的 $pages 页，至少需要$time。',
          '读取期间可随时停止，已找到的结果会保留。频繁读取会增加站点负担，可能触发限流或失败。',
        ].join('\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('开始$verb'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
