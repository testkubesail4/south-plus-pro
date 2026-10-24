import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_blocking_settings.dart';
import '../../services/full_scan.dart';
import '../../services/thread_search.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/search_scope_bar.dart';
import '../common/sub_tabs.dart';

/// 帖内查找's query and its optional scan of every page. The thread screen
/// owns it, so both outlive the sheet; a new keyword drops the scan.
///
/// The loaded pages and blocking rules are read when shown, never kept: the
/// screen calls [pagesChanged] when its pages change and [stop] when rules,
/// author scope or session do.
class ThreadFind extends ChangeNotifier {
  ThreadFind({
    required this.onScanEnded,
    required this.pages,
    required this.rules,
  });

  /// A scan finished, failed or hit its cap.
  final ValueChanged<ScanProgress> onScanEnded;

  /// The pages the thread screen holds now, in order.
  final List<ThreadDetail> Function() pages;
  final BlockingRules Function() rules;

  final query = TextEditingController();
  FullScan<ThreadSearchHit>? _scan;
  ScanState? _scanState;
  bool _disposed = false;

  /// Moves whenever the scope or keyword does; a scan asked for under an
  /// older value never starts.
  int get generation => _generation;
  int _generation = 0;

  FullScan<ThreadSearchHit>? get scan => _scan;

  /// 全部页面 is chosen: a keyword reads every page once the reader
  /// confirms. Otherwise only the loaded pages are searched, with no request.
  bool get eager => _eager || _scan != null;
  bool _eager = false;

  void chooseEager() {
    _eager = true;
    notifyListeners();
  }

  /// 仅已加载: any scan stops and its results go.
  void useLoaded() {
    _eager = false;
    stop();
  }

  String get keyword => query.text.trim();

  void keywordChanged() {
    _drop();
    notifyListeners();
  }

  void pagesChanged() => notifyListeners();

  /// Starts the scan [create] makes, unless the scope or keyword moved on
  /// since [generation] was read, or the thread is gone.
  bool startIfCurrent(
      int generation, FullScan<ThreadSearchHit> Function() create) {
    if (_disposed || generation != _generation) return false;
    _drop();
    _scan = create()..addListener(_onScan);
    _scanState = _scan!.progress.state;
    _scan!.start();
    notifyListeners();
    return true;
  }

  /// The scan stops where it is; its results and 继续 stay.
  void pause() {
    final state = _scan?.progress.state;
    if (state == ScanState.running || state == ScanState.waiting) {
      _scan!.stop();
    }
  }

  /// Back to the loaded pages: the scan stops and its results go.
  void stop() {
    _drop();
    notifyListeners();
  }

  /// Forgets the keyword too, for another thread or scope.
  void reset() {
    _eager = false;
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
    _generation++;
    _scan
      ?..removeListener(_onScan)
      ..dispose();
    _scan = null;
    _scanState = null;
  }

  @override
  void dispose() {
    _disposed = true;
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
    required this.authorFilterName,
    required this.createScan,
  });

  final ThreadFind find;

  /// Set while the thread shows one author's floors only.
  final String? authorFilterName;

  /// A scan of every page for the current keyword and scope.
  final FullScan<ThreadSearchHit> Function() createScan;

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
            final pages = find.pages();
            // Pages read at different times may disagree; the most is the
            // least the thread has.
            final total = pages.fold<int>(
                1, (most, page) => math.max(most, page.pagination.totalPages));
            final loaded = {
              for (final page in pages) page.pagination.currentPage,
            }.length;
            final remaining = total - loaded;
            final eager = find.eager && remaining > 0;
            // One scroll view, field included: a short window with the
            // keyboard up and large text still reaches every part.
            return CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
                  sliver: SliverToBoxAdapter(
                    child: ListSearchField(
                      controller: find.query,
                      hintText: '查找本帖内容',
                      autofocus: keyword.isEmpty,
                      onChanged: (_) => find.keywordChanged(),
                      onSubmitted: (_) {
                        if (eager && scan == null && find.keyword.isNotEmpty) {
                          _searchAll(context, remaining);
                        }
                      },
                    ),
                  ),
                ),
                if (authorFilterName != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 16, color: AppColors.textMuted),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: Text('只看 $authorFilterName',
                                style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Every page loaded: one scope, nothing to choose.
                if (remaining > 0)
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    sliver: SliverToBoxAdapter(
                      child: SubTabs<bool>(
                        tabs: [
                          (false, '已加载 $loaded 页'),
                          (true, '全部 $total 页'),
                        ],
                        selected: eager,
                        onSelected: (all) {
                          if (!all) {
                            find.useLoaded();
                          } else if (keyword.isEmpty) {
                            find.chooseEager();
                          } else {
                            _searchAll(context, remaining);
                          }
                        },
                      ),
                    ),
                  ),
                if (keyword.isNotEmpty)
                  ..._results(context, keyword, scan, pages,
                      loaded: loaded, total: total),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Asks for this keyword and scope, then reads every page; any change
  /// while asking cancels it.
  Future<void> _searchAll(BuildContext context, int remaining) async {
    final generation = find.generation;
    final go = await confirmFullScan(context,
        subject: '本帖', remainingPages: remaining);
    if (go && context.mounted) {
      find.chooseEager();
      find.startIfCurrent(generation, createScan);
    }
  }

  List<Widget> _results(
    BuildContext context,
    String keyword,
    FullScan<ThreadSearchHit>? scan,
    List<ThreadDetail> pages, {
    required int loaded,
    required int total,
  }) {
    final hits = scan?.hits ?? searchLoadedThread(pages, keyword, find.rules());
    final progress = scan?.progress ??
        ScanProgress(
            scannedPages: loaded, totalPages: total, found: hits.length);
    final allLoaded = loaded >= total;
    final complete =
        progress.state == ScanState.done || (scan == null && allLoaded);
    final bar = SearchScopeBar(
      progress: progress,
      onSearchAll: allLoaded ? null : () => _searchAll(context, total - loaded),
      onStop: scan?.stop,
      onResume: scan?.resume,
      onBackToLoaded: find.useLoaded,
    );
    final Widget empty = complete
        ? EmptyStateView(
            icon: Icons.manage_search_outlined,
            title: '本帖没有找到“$keyword”',
          )
        : scan == null
            ? EmptyStateView(
                icon: Icons.manage_search_outlined,
                title: '已加载的 $loaded 页中没有找到',
              )
            : const EmptyStateView(
                icon: Icons.manage_search_outlined,
                title: '暂未找到',
              );
    return [
      // The loaded pages are all there is: nothing to scan, no bar.
      if (!(scan == null && allLoaded))
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
    ];
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
