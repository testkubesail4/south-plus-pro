import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';
import 'user_profile_screen.dart';

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

class _FavoriteThreadsPageState extends State<FavoriteThreadsPage> {
  Future<UserProfile>? _future;

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

  Future<UserProfile> _loadFavorites() async {
    final overview = await widget.repository.fetchUserProfileOverview('u.php');
    return widget.repository.fetchUserProfileDetails(overview);
  }

  Future<void> _refresh() async {
    if (!widget.repository.isLoggedIn) return;
    final next = _loadFavorites();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isLoggedIn) {
      return _FavoriteLoginPrompt(
        repository: widget.repository,
        onLoginTap: widget.onLoginTap,
      );
    }

    final future = _future ??= _loadFavorites();
    return SafeArea(
      bottom: false,
      child: FutureBuilder<UserProfile>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorView(
              title: '收藏加载失败',
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          }
          if (!snapshot.hasData) {
            return const ThreadListSkeleton(itemCount: 6);
          }

          final profile = snapshot.data!;
          return RefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _FavoriteHeader(
                    profile: profile, repository: widget.repository),
                const SizedBox(height: 16),
                if (profile.favorites.isEmpty)
                  const EmptyStateView(
                    title: '还没有公开收藏',
                    message: '先去帖子详情里点收藏，之后会在这里集中查看。',
                    icon: Icons.star_border_rounded,
                  )
                else
                  ...profile.favorites.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FavoriteThreadTile(
                        item: item,
                        repository: widget.repository,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteHeader extends StatelessWidget {
  const _FavoriteHeader({
    required this.profile,
    required this.repository,
  });

  final UserProfile profile;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    final count = profile.favorites.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brandSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('我的收藏', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.name} 公开收藏的主题都会集中显示在这里。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _FavoriteStat(
                  label: '公开收藏',
                  value: '$count',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FavoriteStat(
                  label: '账号状态',
                  value: repository.currentUsername ?? '已登录',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfileScreen(
                  userUrl: 'u.php',
                  repository: repository,
                ),
              ),
            ),
            icon: const Icon(Icons.person_outline),
            label: const Text('查看完整个人中心'),
          ),
        ],
      ),
    );
  }
}

class _FavoriteStat extends StatelessWidget {
  const _FavoriteStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FavoriteThreadTile extends StatelessWidget {
  const _FavoriteThreadTile({
    required this.item,
    required this.repository,
  });

  final UserListItem item;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.section != null) item.section!,
      if (item.date != null) item.date!,
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ThreadDetailScreen(
              thread: ForumThread(
                title: item.title,
                url: item.url,
                replies: item.replies ?? 0,
                section: item.section ?? '我的收藏',
                author: item.author,
                authorUrl: item.authorUrl,
                lastPost: item.date,
              ),
              repository: repository,
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
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
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: AppColors.brand,
                    ),
                  ),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
              if (item.author != null ||
                  item.replies != null ||
                  item.views != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (item.author != null)
                      _MetaPill(
                        icon: Icons.person_outline,
                        label: item.author!,
                      ),
                    if (item.replies != null)
                      _MetaPill(
                        icon: Icons.forum_outlined,
                        label: '${item.replies}',
                      ),
                    if (item.views != null)
                      _MetaPill(
                        icon: Icons.visibility_outlined,
                        label: '${item.views}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteLoginPrompt extends StatelessWidget {
  const _FavoriteLoginPrompt({
    required this.repository,
    this.onLoginTap,
  });

  final ForumRepository repository;
  final VoidCallback? onLoginTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.star_border_rounded,
                    color: AppColors.brand,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text('收藏', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '这里会展示你收藏过的主题。登录后可以更快回看想追的帖子，不用再从版块里翻。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onLoginTap ?? () => _openLogin(context),
                  icon: const Icon(Icons.login),
                  label: const Text('去登录'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LoginScreen(repository: repository),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开登录页'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(repository: repository),
      ),
    );
  }
}
