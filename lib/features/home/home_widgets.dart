part of 'home_shell.dart';

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.repository,
    this.onAccountTap,
    this.onToggleTheme,
  });

  final ForumRepository repository;
  final VoidCallback? onAccountTap;
  final VoidCallback? onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final nextThemeLabel = AppThemeController.isDark ? '切换为白天模式' : '切换为暗黑模式';
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
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
          if (repository.isLoggedIn)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onAccountTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: ValueListenableBuilder<ForumAccountIdentity?>(
                  valueListenable: repository.accountIdentity,
                  builder: (context, identity, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AccountAvatar(avatarUrl: identity?.avatarUrl, size: 24),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          accountDisplayName(identity) ??
                              repository.currentUsername ??
                              '已登录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.brand,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => openLogin(context, repository),
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

/// Reply-notice and short-message shortcuts, each dotted while unread.
class _NoticeChips extends StatelessWidget {
  const _NoticeChips({required this.repository, this.onMessagesTap});

  final ForumRepository repository;
  final VoidCallback? onMessagesTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForumNoticeFlags>(
      valueListenable: repository.noticeFlags,
      builder: (context, flags, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _NoticeChip(
              icon: Icons.mark_chat_unread_outlined,
              label: '回复提醒',
              unread: flags.replyNotice,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReplyNoticesScreen(repository: repository),
                ),
              ),
            ),
            _NoticeChip(
              icon: Icons.mail_outline,
              label: '短消息',
              unread: flags.unreadPm,
              onPressed: onMessagesTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeChip extends StatelessWidget {
  const _NoticeChip({
    required this.icon,
    required this.label,
    required this.unread,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool unread;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: unread ? '有新提醒' : null,
      child: ActionChip(
        avatar: Badge(
          isLabelVisible: unread,
          child: Icon(icon, size: 18, color: AppColors.brand),
        ),
        label: Text(label),
        labelStyle: TextStyle(
          color: AppColors.text,
          fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
        ),
        side: BorderSide(
          color: unread ? AppColors.brand : AppColors.border,
        ),
        backgroundColor: unread ? AppColors.brandSoft : AppColors.surface,
        onPressed: onPressed,
      ),
    );
  }
}

/// 最新讨论 and the site's other quick lists: tabs on phones, columns wider.
/// Lists the snapshot did not include load only when the user asks.
class _QuickLists extends StatefulWidget {
  const _QuickLists({
    super.key,
    required this.lists,
    required this.latest,
    required this.columns,
    required this.repository,
  });

  final List<ForumQuickList> lists;
  final List<ForumThread> latest;
  final int columns;
  final ForumRepository repository;

  @override
  State<_QuickLists> createState() => _QuickListsState();
}

class _QuickListsState extends State<_QuickLists> {
  late final _lists = widget.lists.isEmpty
      ? [ForumQuickList(title: '最新讨论', threads: widget.latest)]
      : widget.lists;
  final _loads = <int, Future<List<ForumThread>>>{};
  var _tab = 0;

  Future<List<ForumThread>>? _loaded(int index) {
    final threads = _lists[index].threads;
    return threads != null ? Future.value(threads) : _loads[index];
  }

  void _load(int index) {
    if (_loaded(index) != null) return;
    setState(() {
      _loads[index] = widget.repository.fetchQuickList(_lists[index]);
    });
  }

  void _retry(int index) {
    setState(() => _loads.remove(index));
    _load(index);
  }

  Widget _body(int index) => _QuickListBody(
        future: _loaded(index),
        onLoad: () => _load(index),
        onRetry: () => _retry(index),
        repository: widget.repository,
      );

  @override
  Widget build(BuildContext context) {
    final shortcut = _TaskShortcut(repository: widget.repository);
    if (widget.columns == 1) {
      return _SimpleSection(
        title: _lists.length == 1 ? _lists.single.title : '速览',
        icon: Icons.subject_outlined,
        trailing: shortcut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_lists.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _lists.length; i++)
                      ChoiceChip(
                        label: Text(_lists[i].title),
                        selected: _tab == i,
                        onSelected: (_) {
                          setState(() => _tab = i);
                          _load(i);
                        },
                      ),
                  ],
                ),
              ),
            _body(_tab),
          ],
        ),
      );
    }
    return _SimpleSection(
      title: '速览',
      icon: Icons.subject_outlined,
      trailing: shortcut,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = widget.columns.clamp(1, _lists.length);
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < _lists.length; i++)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _lists[i].title,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _body(i),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuickListBody extends StatelessWidget {
  const _QuickListBody({
    required this.future,
    required this.onLoad,
    required this.onRetry,
    required this.repository,
  });

  final Future<List<ForumThread>>? future;
  final VoidCallback onLoad;
  final VoidCallback onRetry;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    final Widget child;
    if (pending == null) {
      child = Center(
        child: TextButton.icon(
          onPressed: onLoad,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('点按加载'),
        ),
      );
    } else {
      child = FutureBuilder<List<ForumThread>>(
        future: pending,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('加载失败：${forumErrorText(snapshot.error)}'),
              ),
            );
          }
          final threads = snapshot.data;
          if (threads == null) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (threads.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Text('暂无内容', style: TextStyle(color: AppColors.textMuted)),
            );
          }
          return Column(
            children: [
              for (final (i, thread) in threads.take(5).indexed) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                InkWell(
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
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: ForumTitleText(
                      thread.title,
                      titleStyle: thread.titleStyle,
                      maxLines: 2,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
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
  var _autoClaimAttempted = false;
  var _autoClaimed = false;
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
    unawaited(_autoClaimRewards());
  }

  Future<void> _autoClaimRewards() async {
    ForumTraceLogger.log('UI', 'auto claim trigger requested');
    if (_autoClaimAttempted ||
        _running ||
        !mounted ||
        !widget.repository.isLoggedIn) {
      ForumTraceLogger.log(
        'UI',
        'auto claim skipped attempted=$_autoClaimAttempted running=$_running mounted=$mounted isLoggedIn=${widget.repository.isLoggedIn}',
      );
      return;
    }

    _autoClaimAttempted = true;
    setState(() => _running = true);
    try {
      ForumTraceLogger.log('UI', 'auto claim invoking repository');
      final result = await widget.repository.autoClaimForumTaskRewardsIfDue();
      if (!mounted) return;
      await _loadSnapshotOnly();
      if (!mounted || result == null) return;
      if (result.hasClaims) {
        setState(() => _autoClaimed = true);
        _showAutoClaimResult(result);
      }
    } catch (_) {
      // Keep passive auto sign-in quiet; the manual button still reports errors.
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _loadSnapshotOnly() async {
    final snapshot = await widget.repository.loadCachedForumTaskSnapshot();
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  Future<void> _claimRewards() async {
    ForumTraceLogger.log('UI', 'manual claim button tapped');
    if (!widget.repository.isLoggedIn) {
      ForumTraceLogger.log(
        'UI',
        'manual claim redirected to task page because not logged in',
      );
      _openTasks();
      return;
    }

    setState(() => _running = true);
    try {
      ForumTraceLogger.log('UI', 'manual claim invoking repository');
      final result = await widget.repository.claimForumTaskRewards();
      if (!mounted) return;
      await _loadSnapshotOnly();
      if (result.hasClaims) {
        setState(() => _autoClaimed = false);
      }
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

  void _showAutoClaimResult(ForumTaskQuickClaimResult result) {
    showForumTaskAutoClaimSnackBar(context, result);
  }

  void _showClaimError(Object error) {
    showForumTaskClaimErrorSnackBar(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final summary = snapshot?.autoTaskSummary;
    final hasClaimable = summary?.hasClaimable == true;
    final isHandled = summary?.isFullyHandled == true;
    final cooldownLabel = _cooldownLabel(snapshot);
    final success = isHandled;
    final label = _running
        ? '领取中'
        : hasClaimable
            ? '可领取'
            : isHandled
                ? _autoClaimed
                    ? '已自动签到'
                    : '已签到'
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
    final cooldowns = snapshot.autoTaskSummary
        .cooldownsFrom(now)
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

/// Boards of one section: rows on phones, [columns] of cards wider.
class _BoardGrid extends StatelessWidget {
  const _BoardGrid({
    required this.boards,
    required this.columns,
    required this.showCounts,
    required this.onOpen,
  });

  final List<ForumBoard> boards;
  final int columns;
  final bool showCounts;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return Column(
        children: [
          for (final board in boards)
            _BoardTile(
                board: board,
                card: false,
                showCounts: showCounts,
                onOpen: onOpen),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final board in boards)
              SizedBox(
                width: width,
                child: _BoardTile(
                  board: board,
                  card: true,
                  showCounts: showCounts,
                  onOpen: onOpen,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.card,
    required this.showCounts,
    required this.onOpen,
  });

  final ForumBoard board;
  final bool card;
  final bool showCounts;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    final today = board.todayCount ?? 0;
    final subtitle = board.subtitle;
    final lastPostTitle = board.lastPostTitle;
    final meta = [
      if (board.lastPostTime != null) board.lastPostTime!,
      if (showCounts && board.topicCount != null && board.postCount != null)
        '${board.topicCount} 主题 / ${board.postCount} 文章',
    ];
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              label: board.hasNew ? '有新帖' : null,
              child: Badge(
                isLabelVisible: board.hasNew,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.tag_outlined,
                      color: AppColors.brand, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          board.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (today > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '今日 $today',
                            style: TextStyle(
                              color: AppColors.brand,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (card && subtitle != null && subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted),
                  if (card && lastPostTitle != null)
                    Text(
                      lastPostTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 13),
                    ),
                  if (meta.isNotEmpty)
                    Text(meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted),
                ],
              ),
            ),
            if (!card) Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
        if (board.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 8, 0, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final child in board.children)
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
                    onPressed: () => onOpen(child),
                  ),
              ],
            ),
          ),
      ],
    );
    return Material(
      color: card ? AppColors.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: card ? BorderSide(color: AppColors.border) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onOpen(board),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: content,
        ),
      ),
    );
  }
}

/// Wide-window side panel: account, notices, and the boards pinned in
/// search (热门版块 until the user pins any).
class _SidePanel extends StatefulWidget {
  const _SidePanel({
    required this.repository,
    required this.hotBoards,
    required this.onOpenBoard,
    this.onAccountTap,
    this.onMessagesTap,
  });

  final ForumRepository repository;
  final List<ForumCategory> hotBoards;
  final ValueChanged<ForumCategory> onOpenBoard;
  final VoidCallback? onAccountTap;
  final VoidCallback? onMessagesTap;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  List<ForumSearchPinnedBoard> _pinned = const [];

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  // Home stays alive in the tab stack; re-read pins whenever it rebuilds
  // (tab switch, refresh) so pins changed in search show up.
  @override
  void didUpdateWidget(_SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPins();
  }

  void _loadPins() {
    ForumSearchPreferences.load(account: widget.repository.currentUsername)
        .then((prefs) {
      if (mounted) setState(() => _pinned = prefs.pinnedBoards);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final loggedIn = repository.isLoggedIn;
    final pinned = _pinned.isNotEmpty;
    final boards = pinned
        ? [
            for (final pin in _pinned)
              ForumCategory(name: pin.label, slug: 'fid-${pin.id}'),
          ]
        : widget.hotBoards;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (loggedIn) ...[
          ValueListenableBuilder<ForumAccountIdentity?>(
            valueListenable: repository.accountIdentity,
            builder: (context, identity, _) => ListTile(
              leading: AccountAvatar(avatarUrl: identity?.avatarUrl, size: 40),
              title: Text(
                accountDisplayName(identity) ??
                    repository.currentUsername ??
                    '已登录',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('我的'),
              onTap: widget.onAccountTap,
            ),
          ),
          _NoticeChips(
            repository: repository,
            onMessagesTap: widget.onMessagesTap,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => openLogin(context, repository),
              icon: const Icon(Icons.login),
              label: const Text('登录南+账号'),
            ),
          ),
        if (boards.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Icon(
                  pinned
                      ? Icons.push_pin_outlined
                      : Icons.local_fire_department_outlined,
                  color: AppColors.brand,
                  size: 20,
                ),
                const SizedBox(width: 7),
                Text(
                  pinned ? '常用版块' : '热门版块',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                for (final board in boards)
                  _ForumLink(
                    title: board.name,
                    subtitle: board.slug,
                    onTap: () => widget.onOpenBoard(board),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
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
                // Expanded so large system text wraps instead of overflowing.
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
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
