import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';

/// The 收藏 tab: the signed-in account's favourite threads as one plain
/// list, newest first as the site orders them.
class FavoriteThreadsPage extends StatefulWidget {
  const FavoriteThreadsPage({
    super.key,
    required this.repository,
    this.onLoginTap,
  });

  final ForumRepository repository;
  final VoidCallback? onLoginTap;

  @override
  State<FavoriteThreadsPage> createState() => _FavoriteThreadsPageState();
}

/// Lists are centred at most this wide.
const _maxWidth = 840.0;

class _FavoriteThreadsPageState extends State<FavoriteThreadsPage> {
  Future<UserProfile>? _future;

  /// Thread URLs removed on the site since the last refresh started, and
  /// those being removed; by URL, so rows a refresh brings back as new
  /// objects keep their state.
  final _removed = <String>{};
  final _removing = <String>{};

  @override
  void initState() {
    super.initState();
    _primeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant FavoriteThreadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _future = null;
    }
    _primeIfNeeded();
  }

  void _primeIfNeeded() {
    if (!widget.repository.isLoggedIn) {
      _future = null;
      return;
    }
    _future ??= _loadFavorites();
  }

  Future<UserProfile> _loadFavorites() =>
      widget.repository.fetchUserProfileFavorites('u.php');

  Future<void> _refresh() async {
    if (!widget.repository.isLoggedIn) return;
    final next = _loadFavorites();
    setState(() {
      _future = next;
      _removed.clear();
    });
    await next;
  }

  Future<void> _remove(UserListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('「${item.title}」将从收藏中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取消收藏'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removing.add(item.url));
    String message;
    try {
      final result = await widget.repository.removeFavoriteFromList(item);
      message = result.success ? '已取消收藏' : '取消收藏失败：${result.message}';
      if (result.success) _removed.add(item.url);
    } catch (error) {
      message = '取消收藏失败：${forumErrorText(error)}';
    }
    if (!mounted) return;
    setState(() => _removing.remove(item.url));
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isLoggedIn) {
      return SafeArea(
        bottom: false,
        child: LoginPrompt(
          icon: Icons.star_outline,
          title: '收藏',
          message: '登录后，在帖子里收藏的主题会集中在这里。',
          onLogin:
              widget.onLoginTap ?? () => openLogin(context, widget.repository),
        ),
      );
    }

    final future = _future ??= _loadFavorites();
    return SafeArea(
      bottom: false,
      child: FutureBuilder<UserProfile>(
        future: future,
        builder: (context, snapshot) {
          final favorites = snapshot.data?.favorites
              .where((item) => !_removed.contains(item.url))
              .toList();
          final Widget body;
          if (snapshot.hasError) {
            body = AsyncErrorView(
              title: '收藏加载失败',
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          } else if (favorites == null) {
            body = DecoratedBox(
              decoration: appSurface(context),
              child: Semantics(
                label: '加载中',
                child: Column(
                  children: [
                    for (final width in const [0.9, 0.6, 0.75, 0.5, 0.8, 0.65])
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: width,
                              child: const SkeletonBlock(height: 14),
                            ),
                            const SizedBox(height: 10),
                            const SkeletonBlock(width: 96, height: 10),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          } else if (favorites.isEmpty) {
            body = const EmptyStateView(
              title: '还没有收藏',
              message: '在帖子页点「收藏」，主题会出现在这里。',
              icon: Icons.star_outline,
            );
          } else {
            body = DecoratedBox(
              decoration: appSurface(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, item) in favorites.indexed) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppColors.border.withValues(alpha: 0.6),
                      ),
                    _FavoriteRow(
                      item: item,
                      repository: widget.repository,
                      busy: _removing.contains(item.url),
                      onRemove: item.favoriteRemoval == null
                          ? null
                          : () => _remove(item),
                    ),
                  ],
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final side = math.max(
                  width < 600 ? 16.0 : 24.0,
                  (width - _maxWidth) / 2,
                );
                return ListView(
                  padding: EdgeInsets.fromLTRB(side, 8, side, 32),
                  children: [
                    _PageTitle(count: favorites?.length),
                    const SizedBox(height: 8),
                    body,
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 收藏 and, once loaded, how many.
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('收藏', style: Theme.of(context).textTheme.headlineSmall),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Text(
              '$count 个主题',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// A favourite: opens the thread; long-press or ⋯ offers 取消收藏 when
/// [onRemove] is set.
class _FavoriteRow extends StatefulWidget {
  const _FavoriteRow({
    required this.item,
    required this.repository,
    required this.busy,
    required this.onRemove,
  });

  final UserListItem item;
  final ForumRepository repository;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  State<_FavoriteRow> createState() => _FavoriteRowState();
}

class _FavoriteRowState extends State<_FavoriteRow> {
  final _menu = GlobalKey<PopupMenuButtonState<void>>();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final meta = [
      if (item.section != null) item.section!,
      if (item.author != null) item.author!,
      if (item.date != null) item.date!,
      if (item.replies != null) '${item.replies} 回复',
    ].join(' · ');
    final canRemove = widget.onRemove != null && !widget.busy;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailScreen(
            thread: ForumThread(
              title: item.title,
              url: item.url,
              replies: item.replies ?? 0,
              section: item.section ?? '收藏',
              author: item.author,
              authorUrl: item.authorUrl,
              lastPost: item.date,
            ),
            repository: widget.repository,
          ),
        ),
      ),
      onLongPress:
          canRemove ? () => _menu.currentState?.showButtonMenu() : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(16, 12, widget.onRemove == null ? 16 : 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.busy)
                const SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (widget.onRemove != null)
                PopupMenuButton<void>(
                  key: _menu,
                  tooltip: '更多',
                  icon: Icon(Icons.more_horiz, color: AppColors.textMuted),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      onTap: widget.onRemove,
                      child: const Row(
                        children: [
                          Icon(Icons.star_outline, size: 20),
                          SizedBox(width: 12),
                          Text('取消收藏'),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
