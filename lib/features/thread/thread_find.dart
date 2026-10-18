import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_blocking_settings.dart';
import '../../services/full_scan.dart';
import '../../services/thread_search.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/search_scope_bar.dart';

/// 帖内查找's query and its optional scan of every page. The thread screen
/// owns it, so both outlive the sheet; a new keyword drops the scan.
class ThreadFind extends ChangeNotifier {
  ThreadFind({required this.onScanEnded});

  /// A scan finished, failed or hit its cap.
  final ValueChanged<ScanProgress> onScanEnded;

  final query = TextEditingController();
  FullScan<ThreadSearchHit>? _scan;
  ScanState? _scanState;

  FullScan<ThreadSearchHit>? get scan => _scan;

  String get keyword => query.text.trim();

  void keywordChanged() {
    _drop();
    notifyListeners();
  }

  void start(FullScan<ThreadSearchHit> scan) {
    _drop();
    _scan = scan..addListener(_onScan);
    _scanState = scan.progress.state;
    scan.start();
    notifyListeners();
  }

  /// Back to the loaded pages: the scan stops and its results go.
  void stop() {
    if (_scan == null) return;
    _drop();
    notifyListeners();
  }

  /// Forgets the keyword too, for another thread or scope.
  void reset() {
    _drop();
    query.clear();
    notifyListeners();
  }

  void _onScan() {
    final progress = _scan!.progress;
    final ended = progress.state != _scanState &&
        (progress.state == ScanState.done ||
            progress.state == ScanState.failed ||
            (progress.state == ScanState.stopped && progress.capped));
    _scanState = progress.state;
    notifyListeners();
    if (ended) onScanEnded(progress);
  }

  void _drop() {
    _scan
      ?..removeListener(_onScan)
      ..dispose();
    _scan = null;
    _scanState = null;
  }

  @override
  void dispose() {
    _drop();
    query.dispose();
    super.dispose();
  }
}

/// The 帖内查找 panel: hits in the loaded pages, or in every page once the
/// reader starts that; a tap pops the sheet with the hit to show.
class ThreadFindSheet extends StatelessWidget {
  const ThreadFindSheet({
    super.key,
    required this.find,
    required this.pages,
    required this.totalPages,
    required this.rules,
    required this.authorFilterName,
    required this.onStartScan,
  });

  final ThreadFind find;

  /// The pages the thread screen holds, in order.
  final List<ThreadDetail> pages;
  final int totalPages;
  final BlockingRules rules;

  /// Set while the thread shows one author's floors only.
  final String? authorFilterName;
  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: ListenableBuilder(
          listenable: find,
          builder: (context, _) {
            final keyword = find.keyword;
            final scan = find.scan;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
                  child: ListSearchField(
                    controller: find.query,
                    hintText: '查找本帖内容',
                    autofocus: keyword.isEmpty,
                    onChanged: (_) => find.keywordChanged(),
                  ),
                ),
                if (authorFilterName != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
                    child: Text('范围：只看 $authorFilterName',
                        style: theme.textTheme.bodySmall),
                  ),
                Expanded(
                  child: keyword.isEmpty
                      ? EmptyStateView(
                          icon: Icons.find_in_page_outlined,
                          title: '查找本帖内容',
                          message: [
                            '输入关键词，查找已加载的 ${pages.length} 页内容',
                            if (totalPages > pages.length)
                              '（本帖共 $totalPages 页）',
                          ].join(),
                        )
                      : _results(context, keyword, scan),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _results(
    BuildContext context,
    String keyword,
    FullScan<ThreadSearchHit>? scan,
  ) {
    final hits = scan?.hits ?? searchLoadedThread(pages, keyword, rules);
    final progress = scan?.progress ??
        ScanProgress(
          scannedPages: pages.length,
          totalPages: totalPages,
          found: hits.length,
        );
    final complete = progress.state == ScanState.done ||
        (scan == null && pages.length >= totalPages);
    final bar = SearchScopeBar(
      progress: progress,
      onSearchAll: pages.length < totalPages
          ? () async {
              final go = await confirmFullScan(context,
                  subject: '本帖', remainingPages: totalPages - pages.length);
              if (go) onStartScan();
            }
          : null,
      onStop: scan?.stop,
      onResume: scan?.resume,
      onBackToLoaded: find.stop,
    );
    final Widget empty = complete
        ? EmptyStateView(
            icon: Icons.manage_search_outlined,
            title: '本帖没有找到“$keyword”',
            message: '不含已屏蔽楼层、图片、附件和未解锁内容。',
          )
        : scan == null
            ? EmptyStateView(
                icon: Icons.manage_search_outlined,
                title: '已加载的 ${pages.length} 页中没有找到',
                message: '本帖共 $totalPages 页，可搜索全部页面。',
              )
            : const EmptyStateView(
                icon: Icons.manage_search_outlined,
                title: '暂未找到',
                message: '搜索未完成，结果可能不全。',
              );
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        // The loaded pages are all there is: nothing to scan, no bar.
        if (!(scan == null && pages.length >= totalPages))
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
            sliver: SliverToBoxAdapter(child: bar),
          ),
        if (hits.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: empty)
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
            sliver: DecoratedSliver(
              decoration: appSurface(context),
              sliver: SliverList.separated(
                itemCount: hits.length,
                separatorBuilder: (_, __) => const Divider(indent: AppSpace.lg),
                itemBuilder: (context, index) => _HitRow(
                  hit: hits[index],
                  keyword: keyword,
                  onTap: () => Navigator.of(context).pop(hits[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.keyword,
    required this.onTap,
  });

  final ThreadSearchHit hit;
  final String keyword;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 ${hit.page} 页 · ${hit.floorLabel} · ${hit.author}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpace.xs),
              Text.rich(
                TextSpan(
                  children: highlightKeyword(
                    hit.snippet,
                    keyword,
                    base.copyWith(
                      color: AppColors.brandDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                style: base,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [text] split into spans, every occurrence of a word of [keyword] (any
/// case) in [mark].
List<TextSpan> highlightKeyword(String text, String keyword, TextStyle mark) {
  final lower = text.toLowerCase();
  final words = [
    for (final word in keyword.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];
  // Lower-casing that changes lengths would misplace the marks.
  if (words.isEmpty || lower.length != text.length) {
    return [TextSpan(text: text)];
  }
  final spans = <TextSpan>[];
  var at = 0;
  while (at < text.length) {
    var start = -1;
    var length = 0;
    for (final word in words) {
      final found = lower.indexOf(word, at);
      if (found >= 0 &&
          (start < 0 ||
              found < start ||
              (found == start && word.length > length))) {
        start = found;
        length = word.length;
      }
    }
    if (start < 0) {
      spans.add(TextSpan(text: text.substring(at)));
      break;
    }
    if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
    spans.add(
        TextSpan(text: text.substring(start, start + length), style: mark));
    at = start + length;
  }
  return spans;
}
