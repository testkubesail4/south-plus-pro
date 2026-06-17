part of 'home_shell.dart';

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.repository,
    this.onHistoryTap,
    this.onToggleTheme,
  });

  final ForumRepository repository;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final nextThemeLabel = AppThemeController.isDark ? '切换为白天模式' : '切换为暗黑模式';
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '菜单',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.search),
                        title: const Text('搜索'),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SearchScreen(repository: repository),
                            ),
                          );
                        },
                      ),
                      if (onHistoryTap != null)
                        ListTile(
                          leading: Icon(Icons.history_outlined),
                          title: const Text('浏览历史'),
                          onTap: () {
                            Navigator.of(context).pop();
                            onHistoryTap?.call();
                          },
                        ),
                      ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text(repository.isLoggedIn ? '个人中心' : '登录'),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => repository.isLoggedIn
                                  ? UserProfileScreen(
                                      userUrl: 'u.php',
                                      repository: repository,
                                    )
                                  : LoginScreen(repository: repository),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            icon: Icon(Icons.menu, color: AppColors.text, size: 30),
          ),
          Expanded(
            child: Center(
              child: Text(
                'southplus',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          if (onToggleTheme != null)
            IconButton(
              tooltip: nextThemeLabel,
              onPressed: onToggleTheme,
              icon: Icon(
                AppThemeController.isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                color: AppColors.text,
              ),
            ),
          IconButton(
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SearchScreen(repository: repository),
              ),
            ),
            icon: Icon(Icons.search, color: AppColors.text),
          ),
          if (repository.isLoggedIn)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    userUrl: 'u.php',
                    repository: repository,
                  ),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      color: AppColors.brand,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      repository.currentUsername ?? '已登录',
                      style: TextStyle(
                        color: AppColors.brand,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(repository: repository),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                minimumSize: const Size(56, 44),
              ),
              child: const Text(
                '登录',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _LatestThreads extends StatelessWidget {
  const _LatestThreads({
    required this.threads,
    required this.repository,
  });

  final List<ForumThread> threads;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return _SimpleSection(
      title: '最新讨论',
      icon: Icons.subject_outlined,
      trailing: _TaskShortcut(repository: repository),
      child: Column(
        children: threads.take(8).map((thread) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ThreadDetailScreen(
                    thread: thread,
                    repository: repository,
                  ),
                ),
              ),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 92),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          color: AppColors.textMuted,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            thread.section,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '[${thread.replies}]',
                          style: TextStyle(
                            color: AppColors.link,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TaskShortcut extends StatefulWidget {
  const _TaskShortcut({required this.repository});

  final ForumRepository repository;

  @override
  State<_TaskShortcut> createState() => _TaskShortcutState();
}

class _TaskShortcutState extends State<_TaskShortcut> {
  var _running = false;
  ForumTaskSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    final snapshot = await widget.repository.loadCachedForumTaskSnapshot();
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  Future<void> _claimRewards() async {
    if (!widget.repository.isLoggedIn) {
      _openTasks();
      return;
    }

    setState(() => _running = true);
    try {
      final result = await widget.repository.claimForumTaskRewards();
      if (!mounted) return;
      await _loadSnapshot();
      _showClaimResult(result);
    } catch (error) {
      if (!mounted) return;
      _showClaimError(error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _openTasks() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForumTasksScreen(repository: widget.repository),
      ),
    );
  }

  void _showClaimResult(ForumTaskQuickClaimResult result) {
    showForumTaskClaimSnackBar(context, result);
  }

  void _showClaimError(Object error) {
    showForumTaskClaimErrorSnackBar(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final done = snapshot?.tasks.where((task) => task.isDoneToday).length ?? 0;
    final hasClaimable = snapshot?.hasClaimableReward == true;
    final cooldownLabel = _cooldownLabel(snapshot);
    final success = done > 0 && !hasClaimable;
    final label = _running
        ? '领取中'
        : hasClaimable
            ? '可领取'
            : done > 0
                ? '已领 $done'
                : cooldownLabel ?? '任务奖励';
    final foreground = success ? AppColors.success : AppColors.brand;
    final border = success ? AppColors.successBorder : AppColors.brandSoft;
    final icon = success ? Icons.check_circle_outline : Icons.redeem_outlined;

    return OutlinedButton.icon(
      onPressed: _running ? null : _claimRewards,
      icon: _running
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textFaint,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        foregroundColor: foreground,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String? _cooldownLabel(ForumTaskSnapshot? snapshot) {
    if (snapshot == null) return null;
    final now = DateTime.now().toUtc();
    final cooldowns = snapshot.tasks
        .map((task) => task.cooldownRemainingFrom(now))
        .whereType<Duration>()
        .toList();
    if (cooldowns.isEmpty) return null;
    cooldowns.sort((a, b) => a.compareTo(b));
    final hours = cooldowns.first.inHours;
    if (hours <= 0) return '待刷新';
    return '${hours}h 后';
  }
}

class _ForumGroup extends StatelessWidget {
  const _ForumGroup({
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            collapsedIconColor: AppColors.brand,
            iconColor: AppColors.brand,
            leading: icon == null
                ? null
                : Icon(icon, color: AppColors.brand, size: 20),
            title: Text(
              title,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _ForumLink extends StatelessWidget {
  const _ForumLink({required this.title, required this.subtitle, this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.tag_outlined, color: AppColors.brand, size: 18),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.text,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

class _ForumBoardLink extends StatelessWidget {
  const _ForumBoardLink({
    required this.board,
    required this.onTap,
    required this.onChildTap,
  });

  final ForumBoard board;
  final VoidCallback onTap;
  final ValueChanged<ForumBoard> onChildTap;

  @override
  Widget build(BuildContext context) {
    final children = board.children;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ForumLink(
            title: board.name,
            subtitle: _boardSubtitle(board),
            onTap: onTap,
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final child in children)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(color: AppColors.border),
                      backgroundColor: AppColors.surfaceTint,
                      label: Text(
                        child.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.link,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => onChildTap(child),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _boardSubtitle(ForumBoard board) {
    final stats = board.topicCount == null || board.postCount == null
        ? null
        : '${board.topicCount} 主题 / ${board.postCount} 文章';
    final subtitle = board.subtitle;
    if (subtitle == null || subtitle.isEmpty) {
      return stats ?? board.section;
    }
    return stats == null ? subtitle : '$subtitle · $stats';
  }
}

class _SimpleSection extends StatelessWidget {
  const _SimpleSection({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: AppColors.brand, size: 20),
                  const SizedBox(width: 7),
                ],
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DesktopLink extends StatelessWidget {
  const _DesktopLink();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.desktop_windows_outlined,
                  size: 17, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                '桌面版',
                style: TextStyle(color: AppColors.brand, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Powered by SP Project v1.0',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
