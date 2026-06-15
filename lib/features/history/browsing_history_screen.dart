import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览历史'),
        actions: [
          IconButton(
            tooltip: '清空浏览历史',
            onPressed: _items.isEmpty || _clearing ? null : _clearHistory,
            icon: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.delete_outline),
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

          return RefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refresh,
            child: items.isEmpty
                ? _EmptyHistory(onBrowseHome: widget.onBrowseHome)
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = items[index];
                      return _HistoryItem(
                        entry: entry,
                        onTap: () => _openThread(entry),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
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

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({
    required this.entry,
    required this.onTap,
  });

  final BrowsingHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thread = entry.thread;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
                ],
              ),
              if (thread.bodyPreview != null) ...[
                const SizedBox(height: 6),
                Text(
                  thread.bodyPreview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 9),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 5,
                children: [
                  _HistoryMetaChip(
                    icon: Icons.schedule_outlined,
                    label: _formatViewedAt(entry.viewedAt),
                  ),
                  _HistoryMetaChip(
                    icon: Icons.forum_outlined,
                    label: thread.section,
                  ),
                  _HistoryMetaChip(
                    icon: Icons.chat_bubble_outline,
                    label: '${thread.replies} 回',
                  ),
                  if (thread.author != null)
                    _HistoryMetaChip(
                      icon: Icons.person_outline,
                      label: thread.author!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatViewedAt(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (!diff.isNegative) {
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
      if (diff.inDays < 1) return '${diff.inHours} 小时前';
      if (diff.inDays < 7) return '${diff.inDays} 天前';
    }
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }
}

class _HistoryMetaChip extends StatelessWidget {
  const _HistoryMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
