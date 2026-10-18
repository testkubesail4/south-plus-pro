import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/keyword_match.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/thread_row.dart';
import '../thread/thread_detail_screen.dart';

class BrowsingHistoryScreen extends StatefulWidget {
  const BrowsingHistoryScreen({
    super.key,
    required this.repository,
    this.onBrowseHome,
  });

  final ForumRepository repository;
  final VoidCallback? onBrowseHome;

  @override
  State<BrowsingHistoryScreen> createState() => _BrowsingHistoryScreenState();
}

class _BrowsingHistoryScreenState extends State<BrowsingHistoryScreen> {
  late Future<List<BrowsingHistoryEntry>> _future = _fetch();
  List<BrowsingHistoryEntry> _items = const [];
  bool _clearing = false;
  final _query = TextEditingController();
  bool _searchOpen = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _openSearch() => setState(() => _searchOpen = true);

  void _closeSearch() => setState(() {
        _searchOpen = false;
        _query.clear();
      });

  Future<List<BrowsingHistoryEntry>> _fetch() async {
    final items = await widget.repository.browsingHistory();
    if (mounted) {
      setState(() {
        _items = items;
      });
    } else {
      _items = items;
    }
    return items;
  }

  Future<void> _refresh() async {
    final next = _fetch();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error state.
    }
  }

  Future<void> _clearHistory() async {
    if (_items.isEmpty || _clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空浏览历史'),
        content: const Text('只会清除本机记录，不会影响帖子、收藏或账号数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _clearing = true;
    });
    try {
      await widget.repository.clearBrowsingHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('浏览历史已清空')),
      );
      await _refresh();
    } finally {
      if (!mounted) return;
      setState(() {
        _clearing = false;
      });
    }
  }

  Future<void> _openThread(BrowsingHistoryEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          thread: entry.thread,
          repository: widget.repository,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Widget _historyRow(BrowsingHistoryEntry entry) {
    final thread = entry.thread;
    final viewed = entry.viewedAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return ForumThreadRow(
      title: thread.title,
      titleStyle: thread.titleStyle,
      meta: [
        if (thread.section.isNotEmpty) thread.section,
        if (thread.author case final author?) author,
        '${thread.replies} 回复',
        // The day is the group's label; the row adds when.
        '${two(viewed.hour)}:${two(viewed.minute)}',
      ],
      onTap: () => _openThread(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back closes the search before it leaves the page.
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _searchOpen ? BackButton(onPressed: _closeSearch) : null,
          title: _searchOpen ? _searchField() : const Text('浏览历史'),
          // Clearing always clears everything, so it is not offered beside
          // a filtered list.
          actions: _searchOpen
              ? null
              : [
                  IconButton(
                    tooltip: '搜索浏览历史',
                    onPressed: _items.isEmpty ? null : _openSearch,
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: '清空浏览历史',
                    onPressed:
                        _items.isEmpty || _clearing ? null : _clearHistory,
                    icon: _clearing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                  ),
                ],
        ),
        body: FutureBuilder<List<BrowsingHistoryEntry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AsyncErrorView(
                title: '浏览历史加载失败',
                message: '${snapshot.error}',
                onRetry: _refresh,
              );
            }

            final items = snapshot.data;
            if (items == null) {
              return const ThreadListSkeleton(itemCount: 6);
            }
            _items = items;
            final query = _searchOpen ? _query.text.trim() : '';
            final shown = query.isEmpty
                ? items
                : [
                    for (final entry in items)
                      if (matchKeyword(query, [
                            entry.thread.title,
                            entry.thread.author,
                            entry.thread.section,
                          ]) ==
                          true)
                        entry,
                  ];

            return RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _refresh,
              child: items.isEmpty
                  ? _EmptyHistory(onBrowseHome: widget.onBrowseHome)
                  : shown.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          children: [
                            EmptyStateView(
                              icon: Icons.manage_search_outlined,
                              title: '没有符合的浏览记录',
                              message:
                                  '已在全部 ${items.length} 条本机记录的标题、作者和版块中查找。',
                            ),
                          ],
                        )
                      : _historyList(shown, counted: query.isNotEmpty),
            );
          },
        ),
      ),
    );
  }

  Widget _searchField() => TextField(
        controller: _query,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索标题、作者或版块',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  onPressed: () => setState(_query.clear),
                  icon: const Icon(Icons.close),
                ),
        ),
      );

  /// Day groups built as slivers, so only the rows on screen are built.
  Widget _historyList(List<BrowsingHistoryEntry> items,
      {required bool counted}) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = appGutter(constraints.maxWidth, AppWidths.list);
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  gutter, AppSpace.md, gutter, AppSpace.xxl),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (counted)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
                        child: Semantics(
                          liveRegion: true,
                          child: Text('找到 ${items.length} 条',
                              style: theme.textTheme.bodySmall),
                        ),
                      ),
                    ),
                  for (final (i, (label, entries))
                      in _byDay(items, DateTime.now()).indexed) ...[
                    // The AppGroup label, above a lazily built surface.
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(AppSpace.lg,
                            i == 0 ? 0 : AppSpace.xl, AppSpace.lg, AppSpace.sm),
                        child: Semantics(
                          header: true,
                          child: Text(
                            label,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    DecoratedSliver(
                      decoration: appSurface(context),
                      sliver: SliverList.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, __) =>
                            const Divider(indent: AppSpace.lg),
                        itemBuilder: (_, index) => _historyRow(entries[index]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Consecutive entries grouped under 今天 / 昨天 / the date they were viewed.
List<(String, List<BrowsingHistoryEntry>)> _byDay(
  List<BrowsingHistoryEntry> items,
  DateTime now,
) {
  final today = DateUtils.dateOnly(now);
  // Calendar days, not 24 h spans: a DST day is 23 or 25 hours long.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  String label(DateTime viewed) {
    final day = DateUtils.dateOnly(viewed.toLocal());
    if (DateUtils.isSameDay(day, today)) return '今天';
    if (DateUtils.isSameDay(day, yesterday)) return '昨天';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  final groups = <(String, List<BrowsingHistoryEntry>)>[];
  for (final entry in items) {
    final key = label(entry.viewedAt);
    if (groups.isEmpty || groups.last.$1 != key) groups.add((key, []));
    groups.last.$2.add(entry);
  }
  return groups;
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.onBrowseHome});

  final VoidCallback? onBrowseHome;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      children: [
        const EmptyStateView(
          title: '还没有浏览历史',
          message: '打开帖子后会自动记录在这里，之后可以快速找回看过的内容。',
          icon: Icons.history_outlined,
          padding: EdgeInsets.zero,
        ),
        if (onBrowseHome != null) ...[
          const SizedBox(height: 18),
          Center(
            child: FilledButton.icon(
              onPressed: onBrowseHome,
              icon: Icon(Icons.home_outlined),
              label: const Text('去首页看看'),
            ),
          ),
        ],
      ],
    );
  }
}
