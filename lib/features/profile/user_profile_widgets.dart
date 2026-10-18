part of 'user_profile_screen.dart';

/// Page padding that centres the profile at [AppWidths.list] (DESIGN.md §4).
/// The profile is a full-screen route, so the window width is its width.
double _gutter(BuildContext context) =>
    appGutter(MediaQuery.sizeOf(context).width, AppWidths.list);

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    this.onMessage,
    this.loginName,
    this.lookingUp = false,
    this.onShowLoginName,
    this.onCopyLoginName,
    this.onSearchByUser,
    this.note,
    this.tags = const [],
    this.onEditNote,
  });

  final UserProfile profile;
  final String? note;
  final List<String> tags;
  final VoidCallback? onEditNote;
  final VoidCallback? onMessage;
  final String? loginName;
  final bool lookingUp;
  final VoidCallback? onShowLoginName;
  final ValueChanged<String>? onCopyLoginName;
  final VoidCallback? onSearchByUser;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(_gutter(context), 8, _gutter(context), 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.chevron_left, size: 30),
              ),
              Text('用户中心', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          // Identity sits on the header itself; no tinted card around it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.inkSoft,
                      child: profile.avatarUrl == null
                          ? Text(
                              profile.displayName.characters.firstOrNull ?? '?',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            )
                          : ClipOval(
                              child: CachedForumImage(
                                url: profile.avatarUrl!,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                bypassLoadPolicy: true,
                              ),
                            ),
                    ),
                    Positioned(
                      right: -1,
                      bottom: 2,
                      child: _OnlineDot(isOnline: profile.isOnline),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              profile.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _OnlinePill(
                            isOnline: profile.isOnline,
                            text: profile.statusText,
                          ),
                        ],
                      ),
                      if (profile.displayName != profile.name) ...[
                        const SizedBox(height: AppSpace.xs),
                        Text('${profile.name} · UID ${profile.uid}',
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      if (onEditNote != null)
                        _NoteLine(note: note, onEdit: onEditNote!),
                      if (tags.isNotEmpty && onEditNote != null) ...[
                        const SizedBox(height: AppSpace.xs),
                        UserTagsInline(tags: tags, onShowAll: onEditNote!),
                      ],
                      if (profile.tagline != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          profile.tagline!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (onMessage != null)
                _ActionChip(
                  icon: Icons.mail_outline,
                  label: '发短消息',
                  onTap: onMessage,
                ),
              if (onSearchByUser != null)
                _ActionChip(
                  icon: Icons.manage_search,
                  label: '按人查找',
                  onTap: lookingUp ? null : onSearchByUser,
                ),
              if (loginName case final name?)
                Semantics(
                  liveRegion: true,
                  hint: '点按复制',
                  child: _ActionChip(
                    icon: Icons.badge_outlined,
                    label: '登录名 $name',
                    onTap: onCopyLoginName == null
                        ? null
                        : () => onCopyLoginName!(name),
                  ),
                )
              else if (onShowLoginName != null)
                Semantics(
                  label: lookingUp ? '正在查询登录名' : null,
                  child: _ActionChip(
                    icon: Icons.badge_outlined,
                    label: '查看登录名',
                    busy: lookingUp,
                    onTap: lookingUp ? null : onShowLoginName,
                  ),
                ),
              if (profile.displayName == profile.name)
                _MetricChip(label: 'UID', value: profile.uid),
              if (profile.level != null && profile.level!.isNotEmpty)
                _MetricChip(label: '等级', value: profile.level!),
              ...profile.stats.take(3).map(
                    (field) =>
                        _MetricChip(label: field.label, value: field.value),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The local, device-only note under the name: shown with an edit pencil, or
/// a single add button when none is set.
class _NoteLine extends StatelessWidget {
  const _NoteLine({required this.note, required this.onEdit});

  final String? note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = note;
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.textMuted,
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      minimumSize: const Size(48, 36),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: text == null
          ? TextButton.icon(
              style: style,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('添加备注'),
            )
          : Semantics(
              button: true,
              label: '编辑备注，当前：$text',
              excludeSemantics: true,
              child: TextButton(
                style: style,
                onPressed: onEdit,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '备注：$text',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    const Icon(Icons.edit_outlined, size: 16),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.isOnline});

  final bool? isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline == null
        ? AppColors.textFaint
        : isOnline!
            ? AppColors.success
            : AppColors.textFaint;
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 3),
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.isOnline, required this.text});

  final bool? isOnline;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final online = isOnline == true;
    final color = isOnline == null
        ? AppColors.textMuted
        : online
            ? AppColors.success
            : AppColors.textMuted;
    final background = isOnline == null
        ? AppColors.inkSoft
        : online
            ? AppColors.successSoft
            : AppColors.inkSoft;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.circle : Icons.circle_outlined,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            text ?? '未知',
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  // Secondary actions: small neutral tonal buttons (DESIGN.md §6).
  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(horizontal: _gutter(context) - AppSpace.lg),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppColors.brand,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.brand,
        tabs: [
          Tab(text: '首页'),
          Tab(text: '资料'),
          Tab(text: '主题'),
          Tab(text: '回复'),
          Tab(text: '收藏'),
        ],
      ),
    );
  }
}

class _LoadingProfileFrame extends StatelessWidget {
  const _LoadingProfileFrame({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, _) => const [
        SliverToBoxAdapter(child: _ProfileLoadingHeader()),
        SliverToBoxAdapter(child: _ProfileTabs()),
      ],
      body: TabBarView(
        children: [
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
          _RefreshTab(
            onRefresh: onRefresh,
            child: const _ProfileInfoLoadingTab(),
          ),
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
        ],
      ),
    );
  }
}

class _ProfileLoadingHeader extends StatelessWidget {
  const _ProfileLoadingHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(_gutter(context), 8, _gutter(context), 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.chevron_left, size: 30),
              ),
              Text('用户中心', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          // Identity sits on the header itself; no tinted card around it.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.inkSoft,
                      child: _SkeletonBox(width: 32, height: 32, radius: 16),
                    ),
                    Positioned(
                      right: -1,
                      bottom: 2,
                      child: _OnlineDot(isOnline: null),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SkeletonBox(
                              width: 132,
                              height: 26,
                              radius: 7,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const _SkeletonBox(width: 58, height: 28, radius: 14),
                        ],
                      ),
                      const SizedBox(height: 9),
                      const _SkeletonBox(width: 180, height: 14, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SkeletonBox(width: 92, height: 32, radius: 16),
              _SkeletonBox(width: 88, height: 32, radius: 16),
              _SkeletonBox(width: 118, height: 32, radius: 16),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.profile, required this.repository});

  final UserProfile profile;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(_gutter(context), 14, _gutter(context), 28),
      children: [
        _ActivitySection(
          title: '个人动态',
          items: profile.homeActivities,
          repository: repository,
        ),
        const SizedBox(height: 14),
        _ActivitySection(
          title: '最新回复',
          items: profile.homeReplies,
          repository: repository,
        ),
      ],
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.future, required this.builder});

  final Future<UserProfile>? future;
  final Widget Function(BuildContext context, UserProfile profile) builder;

  @override
  Widget build(BuildContext context) {
    final detailsFuture = future;
    if (detailsFuture == null) {
      return const _TabLoadingSkeleton();
    }
    return FutureBuilder<UserProfile>(
      future: detailsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            padding: EdgeInsets.symmetric(
                horizontal: _gutter(context), vertical: AppSpace.lg),
            children: [_TextPanel(title: '内容加载失败', text: '${snapshot.error}')],
          );
        }
        if (!snapshot.hasData) {
          return const _TabLoadingSkeleton();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(snapshot.data!.uid),
            child: builder(context, snapshot.data!),
          ),
        );
      },
    );
  }
}

class _ProfileInfoTab extends StatelessWidget {
  const _ProfileInfoTab({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(_gutter(context), 14, _gutter(context), 28),
      children: [
        _FieldSection(title: '个人信息', fields: profile.info),
        const SizedBox(height: 14),
        _FieldSection(title: '论坛资历', fields: profile.stats),
        if (profile.signature != null && profile.signature!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TextPanel(title: '帖间签名', text: profile.signature!),
        ],
      ],
    );
  }
}

class _ProfileInfoLoadingTab extends StatelessWidget {
  const _ProfileInfoLoadingTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(_gutter(context), 14, _gutter(context), 28),
      children: const [
        _SkeletonPanel(),
        SizedBox(height: 14),
        _SkeletonPanel(),
      ],
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.emptyText,
    required this.repository,
    this.showAuthor = false,
  });

  final List<UserListItem> items;
  final String emptyText;
  final ForumRepository repository;

  /// Off where every item is the profile owner's own (主题, 回复).
  final bool showAuthor;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyList(text: emptyText);
    }
    // One grouped surface of shared thread rows (D§8).
    return ListView(
      padding: EdgeInsets.fromLTRB(_gutter(context), 14, _gutter(context), 28),
      children: [
        _threadGroup(context, items, repository, showAuthor: showAuthor),
      ],
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.title,
    required this.items,
    required this.repository,
  });

  final String title;
  final List<UserActivityItem> items;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _TextPanel(title: title, text: '暂无内容');
    return _Panel(
      title: title,
      child: Column(
        children: items
            .map((item) => _ActivityTile(item: item, repository: repository))
            .toList(),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item, required this.repository});

  final UserActivityItem item;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailScreen(
            thread: ForumThread(
              title: item.title,
              url: item.url,
              replies: 0,
              section: '用户动态',
              author: item.author,
              lastPost: item.date,
            ),
            repository: repository,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt_outlined, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.action ?? '动态',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (item.date != null)
                    Text(
                      item.date!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection({required this.title, required this.fields});

  final String title;
  final List<UserProfileField> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return _TextPanel(title: title, text: '暂无内容');
    return _Panel(
      title: title,
      child: Column(
        children: fields
            .map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A floor, not a fixed width: labels stay one line at large text.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 86),
                      child: Text(
                        field.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(field.value,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: Text(text, style: TextStyle(color: AppColors.textMuted)),
    );
  }
}

class _RefreshTab extends StatelessWidget {
  const _RefreshTab({required this.child, required this.onRefresh});

  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: onRefresh,
      child: child,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      // A neutral tag, centred against the buttons it wraps with.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '$label $value',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Center(
          child: Text(text, style: TextStyle(color: AppColors.textMuted)),
        ),
      ],
    );
  }
}

class _SkeletonPanel extends StatelessWidget {
  const _SkeletonPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 90, height: 18, radius: 6),
          SizedBox(height: 14),
          _SkeletonBox(width: double.infinity, height: 14, radius: 5),
          SizedBox(height: 10),
          _SkeletonBox(width: double.infinity, height: 14, radius: 5),
          SizedBox(height: 10),
          _SkeletonBox(width: 210, height: 14, radius: 5),
        ],
      ),
    );
  }
}

class _TabLoadingSkeleton extends StatelessWidget {
  const _TabLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(_gutter(context), 14, _gutter(context), 28),
      children: const [
        _SkeletonPanel(),
        SizedBox(height: 12),
        _SkeletonPanel(),
        SizedBox(height: 12),
        _SkeletonPanel(),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .45, end: .9),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: AppColors.inkSoft,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );
      },
      onEnd: () {},
    );
  }
}

const _allBoardsOption = ForumSearchBoard(id: 'all', name: '全部版块');

String _articleTypeLabel(UserContentArticleType type) => switch (type) {
      UserContentArticleType.all => '全部',
      UserContentArticleType.digest => '精华',
      UserContentArticleType.poll => '投票',
      UserContentArticleType.sale => '交易',
    };

/// The selectors of one 主题/回复 tab. Owned by the screen so a pull-to-refresh
/// that rebuilds the tab keeps what the user picked.
class _ContentSelection {
  ForumSearchBoard? board;
  UserContentArticleType type = UserContentArticleType.all;
  UserContentClassification? classification;
}

/// 主题 / 回复: the first page as loaded, plus board, type and classification
/// selectors. Every search step is one user action; nothing scans on its own.
class _ContentTab extends StatefulWidget {
  const _ContentTab({
    required this.uid,
    required this.tab,
    required this.defaultItems,
    required this.emptyText,
    required this.repository,
    required this.loadBoards,
    required this.loadSections,
    required this.selection,
    required this.refreshGeneration,
  });

  final String uid;
  final UserProfileTab tab;

  /// The page the profile already loaded; shown while no selector is set.
  final List<UserListItem> defaultItems;
  final String emptyText;
  final ForumRepository repository;
  final Future<List<ForumSearchBoard>> Function() loadBoards;
  final Future<List<ForumSection>> Function() loadSections;

  final _ContentSelection selection;

  /// Counts the screen's refreshes. A new value restarts the active query
  /// with fresh service state; the first query after one also passes
  /// `refresh: true`.
  final int refreshGeneration;

  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab>
    with AutomaticKeepAliveClientMixin {
  ForumSearchBoard? get _board => widget.selection.board;
  set _board(ForumSearchBoard? value) => widget.selection.board = value;
  UserContentArticleType get _type => widget.selection.type;
  set _type(UserContentArticleType value) => widget.selection.type = value;
  UserContentClassification? get _classification =>
      widget.selection.classification;
  set _classification(UserContentClassification? value) =>
      widget.selection.classification = value;
  List<UserContentClassification>? _classifications;
  bool _loadingClassifications = false;

  UserContentResult? _result;
  bool _loading = false;
  Object? _error;
  bool _unresolvedOpen = false;
  late bool _restart = widget.refreshGeneration > 0;
  // Bumped on every selector change; results of older queries are dropped.
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    // Selectors survive a rebuilt tab: carry on with the same query.
    if (!_isDefault) _advanceAfterFrame();
  }

  @override
  void didUpdateWidget(_ContentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshGeneration == widget.refreshGeneration) return;
    // Refreshed: whatever the old query accumulated is stale. Drop it (and any
    // reply still in flight), keep the selectors, restart from page one.
    _epoch++;
    _result = null;
    _error = null;
    _loading = false;
    _unresolvedOpen = false;
    _classifications = null;
    _loadingClassifications = false;
    _restart = true;
    if (!_isDefault) _advanceAfterFrame();
  }

  void _advanceAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _advance();
      });

  @override
  bool get wantKeepAlive => true;

  bool get _isDefault => _board == null && _type == UserContentArticleType.all;

  UserContentQuery get _query => UserContentQuery(
        uid: widget.uid,
        tab: widget.tab,
        boardId: _board?.id,
        articleType: _type,
        classificationId: _classification?.id,
      );

  List<UserListItem> get _items =>
      _result?.items ??
      (_isDefault ? widget.defaultItems : const <UserListItem>[]);

  bool get _canContinue {
    if (_loading || _error != null) return false;
    final result = _result;
    return result == null
        ? _isDefault && widget.defaultItems.isNotEmpty
        : result.hasMore;
  }

  void _select({
    ForumSearchBoard? board,
    bool clearBoard = false,
    UserContentArticleType? type,
    UserContentClassification? classification,
    bool clearClassification = false,
  }) {
    setState(() {
      if (clearBoard || board != null) {
        _board = board;
        _classification = null;
        _classifications = null;
      }
      if (type != null) _type = type;
      if (clearClassification || classification != null) {
        _classification = classification;
      }
      _epoch++;
      _result = null;
      _error = null;
      _loading = false;
      _unresolvedOpen = false;
    });
    if (!_isDefault) _advance();
  }

  Future<void> _advance() async {
    if (_loading) return;
    final epoch = _epoch;
    final restart = _restart;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await widget.repository.fetchUserContent(_query, refresh: restart);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _result = result;
        _loading = false;
        _restart = false;
      });
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      // The accumulated result stays on screen under the error.
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _pickBoard() async {
    final session = widget.repository.sessionEpoch;
    final generation = session.value;
    final picked = await showModalBottomSheet<ForumSearchBoard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (_) => BoardPickerSheet(
        allOption: _allBoardsOption,
        ownRowLabel: (name) => '仅筛选 $name',
        loadBoards: widget.loadBoards,
        loadSections: widget.loadSections,
        selectedId: _board?.id ?? _allBoardsOption.id,
        baseUri: widget.repository.networkConfig.baseUri,
        session: session,
        generation: generation,
      ),
    );
    // A pick made for another session is dropped.
    if (picked == null ||
        !mounted ||
        session.value != generation ||
        picked.id == (_board?.id ?? 'all')) {
      return;
    }
    picked.id == 'all' ? _select(clearBoard: true) : _select(board: picked);
  }

  Future<void> _pickType() async {
    final picked = await _showChoiceSheet<UserContentArticleType>(
      context,
      title: '文章类型',
      selected: _type,
      options: [
        for (final type in UserContentArticleType.values)
          (type, _articleTypeLabel(type)),
      ],
    );
    if (picked != null && picked != _type && mounted) _select(type: picked);
  }

  Future<void> _pickClassification() async {
    final board = _board;
    if (board == null || _loadingClassifications) return;
    var options = _classifications;
    if (options == null) {
      setState(() => _loadingClassifications = true);
      final epoch = _epoch;
      try {
        options =
            await widget.repository.fetchUserContentBoardFilters(board.id);
      } catch (error) {
        if (!mounted) return;
        setState(() => _loadingClassifications = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分类加载失败：${forumErrorText(error)}')),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _loadingClassifications = false);
      if (epoch != _epoch) return;
      setState(() => _classifications = options);
    }
    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该版块没有分类')),
      );
      return;
    }
    final picked = await _showChoiceSheet<String>(
      context,
      title: '${boardDisplayName(board.name)} 分类',
      selected: _classification?.id ?? '',
      options: [
        ('', '全部分类'),
        for (final item in options) (item.id, item.label),
      ],
    );
    if (picked == null || !mounted || picked == (_classification?.id ?? '')) {
      return;
    }
    picked.isEmpty
        ? _select(clearClassification: true)
        : _select(
            classification: options.firstWhere((item) => item.id == picked));
  }

  // totalPages is unknown (<= 0) until the first page is read.
  String _scanned(UserContentResult result) => result.totalPages > 0
      ? '已扫描 ${result.scannedPages}/${result.totalPages} 页'
      : '已扫描 ${result.scannedPages} 页';

  String _statusText(UserContentResult result) {
    return [
      _scanned(result),
      if (result.checkedThreads > 0) '已核对 ${result.checkedThreads} 帖',
      if (result.lookupPagesTotal > 0)
        '分类列表已查 ${result.lookupPagesScanned}/${result.lookupPagesTotal} 页',
      if (result.pendingMetadataCount > 0)
        '未核对 ${result.pendingMetadataCount} 条',
      if (result.unresolvedItems.isNotEmpty)
        '待确认 ${result.unresolvedItems.length} 条',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final result = _result;
    final items = _items;
    final unresolved = result?.unresolvedItems ?? const <UserListItem>[];
    final gutter = _gutter(context);
    final filtered = !_isDefault;
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.extentAfter < 240 &&
            items.isNotEmpty &&
            _canContinue) {
          _advance();
        }
        return false;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.sm, gutter, 28),
        children: [
          Wrap(
            spacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FilterChipButton(
                label: '版块',
                value: _board == null ? '全部' : boardDisplayName(_board!.name),
                active: _board != null,
                onTap: _pickBoard,
              ),
              _FilterChipButton(
                label: '类型',
                value: _articleTypeLabel(_type),
                active: _type != UserContentArticleType.all,
                onTap: _pickType,
              ),
              _FilterChipButton(
                label: '分类',
                value: _classification?.label ?? '全部',
                active: _classification != null,
                busy: _loadingClassifications,
                // Needs a board: classifications belong to one board.
                onTap: _board == null ? null : _pickClassification,
              ),
            ],
          ),
          // Before the first answer the footer carries the loading/error state.
          if (filtered && result != null) ...[
            const SizedBox(height: AppSpace.xs),
            Semantics(
              liveRegion: true,
              child:
                  Text(_statusText(result), style: theme.textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: AppSpace.sm),
          if (items.isNotEmpty)
            _threadGroup(context, items, widget.repository, showAuthor: false)
          else if (_loading && result == null)
            const _SkeletonPanel()
          else if (result != null || (!filtered && _error == null))
            _InlineEmpty(
              text: !filtered
                  ? widget.emptyText
                  : result!.hasMore || unresolved.isNotEmpty
                      ? '${_scanned(result)}，暂未找到匹配'
                      : '没有符合条件的内容',
            ),
          if (unresolved.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            UnresolvedGroup(
              title: '未确认分类 (${unresolved.length})',
              description: '这些内容的版块、分类或类型暂时无法核实，可能符合条件。',
              expanded: _unresolvedOpen,
              onToggle: () =>
                  setState(() => _unresolvedOpen = !_unresolvedOpen),
              child: _threadGroup(context, unresolved, widget.repository,
                  showAuthor: false),
            ),
          ],
          _ContentFooter(
            loading: _loading,
            error: _error,
            canContinue: _canContinue,
            filtered: filtered,
            finished: result != null && !result.hasMore,
            unresolvedCount: unresolved.length,
            onContinue: _advance,
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final String label;
  final String value;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final color = !enabled && !busy
        ? AppColors.textFaint
        : active
            ? AppColors.brandDark
            : AppColors.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label筛选，当前$value',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, maxWidth: 220),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.xs + 2,
              ),
              decoration: ShapeDecoration(
                color: active ? AppColors.brandSoft : null,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: active ? AppColors.brandSoft : AppColors.border,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '$label：$value',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: color),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.arrow_drop_down, size: 20, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer of the content list: one state at a time, never a silent end.
class _ContentFooter extends StatelessWidget {
  const _ContentFooter({
    required this.loading,
    required this.error,
    required this.canContinue,
    required this.filtered,
    required this.finished,
    required this.unresolvedCount,
    required this.onContinue,
  });

  final bool loading;
  final Object? error;
  final bool canContinue;
  final bool filtered;
  final bool finished;
  final int unresolvedCount;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final Widget child;
    if (loading) {
      child = Semantics(
        liveRegion: true,
        label: '正在查找',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpace.sm),
            Text('正在查找…', style: style),
          ],
        ),
      );
    } else if (error != null) {
      child = Column(
        children: [
          Text('查找失败：${forumErrorText(error)}',
              textAlign: TextAlign.center, style: style),
          TextButton(onPressed: onContinue, child: const Text('重试')),
        ],
      );
    } else if (canContinue) {
      child = TextButton(
        onPressed: onContinue,
        child: Text(filtered ? '继续查找' : '加载更多'),
      );
    } else if (finished) {
      child = Text(
        unresolvedCount > 0 ? '已查完，另有 $unresolvedCount 条无法确认' : '已到最后一页',
        textAlign: TextAlign.center,
        style: style,
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Center(child: child),
    );
  }
}

Future<T?> _showChoiceSheet<T extends Object>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<(T, String)> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final (value, label) in options)
            ListTile(
              title: Text(label),
              selected: value == selected,
              selectedColor: AppColors.brandDark,
              trailing: value == selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(value),
            ),
        ],
      ),
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// One grouped surface of shared thread rows. Replies keep one row per post
/// (postId), so several replies in one thread stay separate.
Widget _threadGroup(
  BuildContext context,
  List<UserListItem> items,
  ForumRepository repository, {
  required bool showAuthor,
}) {
  return AppGroup(
    dividerIndent: AppSpace.lg,
    children: [
      for (final item in items)
        ForumThreadRow(
          key: ValueKey(item.postId ?? item.url),
          title: item.title,
          meta: [
            if (item.section case final section?) section,
            if (showAuthor && item.author != null) item.author!,
            if (item.date case final date?) date,
            if (item.replies case final replies?) '$replies 回复',
            if (item.views case final views?) '$views 浏览',
          ],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadDetailScreen(
                thread: ForumThread(
                  title: item.title,
                  url: item.url,
                  replies: item.replies ?? 0,
                  section: item.section ?? '用户中心',
                  author: item.author,
                  authorUrl: item.authorUrl,
                  lastPost: item.date,
                ),
                repository: repository,
              ),
            ),
          ),
        ),
    ],
  );
}
