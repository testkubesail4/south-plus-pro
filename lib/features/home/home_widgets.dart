part of 'home_shell.dart';

// Home layout: a centred column (max 1200) of plain section titles on the
// background, each over one soft surface. Red dots appear only on reply
// notices and unread short messages.

const _homeMaxWidth = 1200.0;
const _noticeDot = Color(0xFFE5484D);

TextStyle _sectionTitleStyle() => TextStyle(
      color: AppColors.text,
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );

BoxDecoration _surface(BuildContext context) => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: Theme.of(context).brightness == Brightness.dark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
    );

/// Section title, with an optional muted note and a trailing action.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.note, this.trailing});

  final String title;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // Flexible so large system text wraps instead of overflowing.
                Flexible(child: Text(title, style: _sectionTitleStyle())),
                if (note != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    note!,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

String _displayName(
        ForumRepository repository, ForumAccountIdentity? identity) =>
    accountDisplayName(identity) ?? repository.currentUsername ?? '已登录';

void _openReplyNotices(BuildContext context, ForumRepository repository) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReplyNoticesScreen(repository: repository),
    ),
  );
}

/// Phone header: one 56px row. Signed in: avatar, name and the two notice
/// buttons; guests: the S+ mark, a welcome and 登录.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.repository,
    this.onAccountTap,
    this.onMessagesTap,
  });

  final ForumRepository repository;
  final VoidCallback? onAccountTap;
  final VoidCallback? onMessagesTap;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      color: AppColors.text,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    if (!repository.isLoggedIn) {
      return SizedBox(
        height: 56,
        child: Row(
          children: [
            const _BrandMark(size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '欢迎来到南+',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
            FilledButton(
              onPressed: () => openLogin(context, repository),
              child: const Text('登录'),
            ),
          ],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<ForumAccountIdentity?>(
              valueListenable: repository.accountIdentity,
              builder: (context, identity, _) => InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: onAccountTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      AccountAvatar(avatarUrl: identity?.avatarUrl, size: 32),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _displayName(repository, identity),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<ForumNoticeFlags>(
            valueListenable: repository.noticeFlags,
            builder: (context, flags, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NoticeIconButton(
                  icon: Icons.alternate_email_rounded,
                  label: '回复提醒',
                  unread: flags.replyNotice,
                  onPressed: () => _openReplyNotices(context, repository),
                ),
                _NoticeIconButton(
                  icon: Icons.mail_outline_rounded,
                  label: '短消息',
                  unread: flags.unreadPm,
                  onPressed: onMessagesTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeIconButton extends StatelessWidget {
  const _NoticeIconButton({
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
    return IconButton(
      tooltip: unread ? '$label，有未读' : label,
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: unread,
        smallSize: 8,
        backgroundColor: _noticeDot,
        child: Icon(icon, color: AppColors.textMuted),
      ),
    );
  }
}

/// Wide header: a softly tinted band with the account and notices, or a
/// welcome and 登录 for guests.
class _WideHeader extends StatelessWidget {
  const _WideHeader({
    required this.repository,
    this.onAccountTap,
    this.onMessagesTap,
  });

  final ForumRepository repository;
  final VoidCallback? onAccountTap;
  final VoidCallback? onMessagesTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chipColor =
        dark ? Colors.white.withValues(alpha: 0.07) : AppColors.surface;
    final nameStyle = TextStyle(
      color: AppColors.text,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    );
    final Widget content;
    if (repository.isLoggedIn) {
      content = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          ValueListenableBuilder<ForumAccountIdentity?>(
            valueListenable: repository.accountIdentity,
            builder: (context, identity, _) => InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onAccountTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AccountAvatar(avatarUrl: identity?.avatarUrl, size: 44),
                    const SizedBox(width: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        _displayName(repository, identity),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ValueListenableBuilder<ForumNoticeFlags>(
            valueListenable: repository.noticeFlags,
            builder: (context, flags, _) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _NoticeChip(
                  icon: Icons.alternate_email_rounded,
                  label: '回复提醒',
                  unread: flags.replyNotice,
                  color: chipColor,
                  onPressed: () => _openReplyNotices(context, repository),
                ),
                _NoticeChip(
                  icon: Icons.mail_outline_rounded,
                  label: '短消息',
                  unread: flags.unreadPm,
                  color: chipColor,
                  onPressed: onMessagesTap,
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      content = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('欢迎来到南+', style: nameStyle),
                const SizedBox(height: 4),
                Text(
                  '登录后可以查看回复提醒、短消息和收藏的帖子',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton(
            onPressed: () => openLogin(context, repository),
            child: const Text('登录'),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: dark
              ? const [Color(0xFF221C23), Color(0xFF1B1E28)]
              : const [Color(0xFFFFF2F3), Color(0xFFF2F3FC)],
        ),
      ),
      child: content,
    );
  }
}

class _NoticeChip extends StatelessWidget {
  const _NoticeChip({
    required this.icon,
    required this.label,
    required this.unread,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool unread;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: unread ? '有未读' : null,
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: AppColors.textMuted),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (unread) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _noticeDot,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        labelStyle: TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        backgroundColor: color,
        onPressed: onPressed,
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(
          'S+',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

/// 最新讨论 and the site's other quick lists: side-by-side columns of
/// one-line rows when there is room, tabs of up to two-line rows otherwise.
/// Lists the snapshot did not include load right after the home's first
/// frame, so they never delay it.
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
  final bool columns;
  final ForumRepository repository;

  @override
  State<_QuickLists> createState() => _QuickListsState();
}

const _quickListIcons = {
  '最新讨论': Icons.forum_outlined,
  '最新回复': Icons.mode_comment_outlined,
  '提问求物': Icons.help_outline_rounded,
};

class _QuickListsState extends State<_QuickLists> {
  late final _lists = widget.lists.isEmpty
      ? [ForumQuickList(title: '最新讨论', threads: widget.latest)]
      : widget.lists;
  final _loads = <int, Future<List<ForumThread>>>{};
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var i = 0; i < _lists.length; i++) {
        _load(i);
      }
    });
  }

  Future<List<ForumThread>>? _loaded(int index) {
    final threads = _lists[index].threads;
    return threads != null ? Future.value(threads) : _loads[index];
  }

  void _load(int index) {
    if (_loaded(index) != null) return;
    final load = widget.repository.fetchQuickList(_lists[index]);
    // A hidden tab has no FutureBuilder yet; its failure shows when opened.
    load.ignore();
    setState(() {
      _loads[index] = load;
    });
  }

  void _retry(int index) {
    _loads.remove(index);
    _load(index);
  }

  Widget _body(int index, {required int maxLines}) => _QuickListBody(
        future: _loaded(index),
        maxLines: maxLines,
        onRetry: () => _retry(index),
        repository: widget.repository,
      );

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    if (!widget.columns || _lists.length == 1) {
      return Container(
        decoration: _surface(context),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_lists.length > 1)
              Wrap(
                children: [
                  for (var i = 0; i < _lists.length; i++)
                    _QuickListTab(
                      title: _lists[i].title,
                      selected: _tab == i,
                      onTap: () => setState(() => _tab = i),
                    ),
                ],
              ),
            _body(_tab, maxLines: 2),
          ],
        ),
      );
    }
    return Container(
      decoration: _surface(context),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _lists.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Row(
                      children: [
                        Icon(
                          _quickListIcons[_lists[i].title] ??
                              Icons.subject_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lists[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: labelStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _body(i, maxLines: 1),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickListTab extends StatelessWidget {
  const _QuickListTab({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: selected ? AppColors.text : Colors.transparent,
                ),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: selected ? AppColors.text : AppColors.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickListBody extends StatelessWidget {
  const _QuickListBody({
    required this.future,
    required this.maxLines,
    required this.onRetry,
    required this.repository,
  });

  final Future<List<ForumThread>>? future;
  final int maxLines;
  final VoidCallback onRetry;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    if (pending == null) return const _QuickListSkeleton();
    return FutureBuilder<List<ForumThread>>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('加载失败：${forumErrorText(snapshot.error)}'),
            ),
          );
        }
        final threads = snapshot.data;
        if (threads == null) return const _QuickListSkeleton();
        if (threads.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('暂无内容', style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return Column(
          children: [
            for (final thread in threads.take(5))
              InkWell(
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
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  alignment: Alignment.centerLeft,
                  child: ForumTitleText(
                    thread.title,
                    titleStyle: thread.titleStyle,
                    maxLines: maxLines,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Placeholder rows, as tall as loaded rows, while a list loads.
class _QuickListSkeleton extends StatelessWidget {
  const _QuickListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '加载中',
      child: Column(
        children: [
          for (final widthFactor in const [0.8, 0.6, 0.7])
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.inkSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 常用版块 (boards pinned in search) for signed-in users, otherwise the
/// site's 热门版块, as a row of chips.
class _BoardChips extends StatefulWidget {
  const _BoardChips({
    required this.repository,
    required this.hotBoards,
    required this.scroll,
    required this.onOpen,
  });

  final ForumRepository repository;
  final List<ForumCategory> hotBoards;
  final bool scroll;
  final ValueChanged<ForumCategory> onOpen;

  @override
  State<_BoardChips> createState() => _BoardChipsState();
}

class _BoardChipsState extends State<_BoardChips> {
  List<ForumSearchPinnedBoard> _pinned = const [];

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  // Home stays alive in the tab stack; re-read pins whenever it rebuilds
  // (tab switch, refresh) so pins changed in search show up.
  @override
  void didUpdateWidget(_BoardChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPins();
  }

  void _loadPins() {
    if (!widget.repository.isLoggedIn) return;
    ForumSearchPreferences.load(account: widget.repository.currentUsername)
        .then((prefs) {
      if (mounted) setState(() => _pinned = prefs.pinnedBoards);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pinned = widget.repository.isLoggedIn && _pinned.isNotEmpty;
    final boards = pinned
        ? [
            for (final pin in _pinned)
              ForumCategory(name: pin.label, slug: 'fid-${pin.id}'),
          ]
        : widget.hotBoards;
    if (boards.isEmpty) return const SizedBox.shrink();
    final chips = [
      for (final board in boards)
        ActionChip(
          label: Text(board.name),
          labelStyle: TextStyle(
            color: AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          shape: const StadiumBorder(),
          side: BorderSide(color: AppColors.border),
          backgroundColor: AppColors.surface,
          onPressed: () => widget.onOpen(board),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(pinned ? '常用版块' : '热门版块'),
          if (!widget.scroll)
            Wrap(spacing: 8, runSpacing: 4, children: chips)
          else
            // A trailing fade shows the row continues past the edge.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                colors: const [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 1 - 24 / rect.width, 1],
              ).createShader(rect),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 24),
                child: Row(
                  children: [
                    for (final (i, chip) in chips.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      chip,
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Boards of one section on one surface: a list on phones, a grid of
/// [columns] wider. Each board shows its name, today's count, the last post
/// and its time with the topic total.
class _BoardGrid extends StatelessWidget {
  const _BoardGrid({
    required this.boards,
    required this.columns,
    required this.onOpen,
  });

  final List<ForumBoard> boards;
  final int columns;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return Container(
        decoration: _surface(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final (i, board) in boards.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: AppColors.border.withValues(alpha: 0.6),
                ),
              _BoardTile(
                board: board,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                onOpen: onOpen,
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      decoration: _surface(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var start = 0; start < boards.length; start += columns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: 8),
                  Expanded(
                    child: start + c < boards.length
                        ? _BoardTile(
                            board: boards[start + c],
                            padding: const EdgeInsets.all(12),
                            onOpen: onOpen,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

String _thousands(int value) => value
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.padding,
    required this.onOpen,
  });

  final ForumBoard board;
  final EdgeInsets padding;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    final today = board.todayCount ?? 0;
    final lastPostTitle = board.lastPostTitle;
    final meta = [
      if (board.lastPostTime != null) board.lastPostTime!,
      if (board.topicCount != null) '${_thousands(board.topicCount!)} 主题',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(board),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 48),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    board.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (today > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    '今日 $today',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            if (lastPostTitle != null) ...[
              const SizedBox(height: 6),
              Text(
                lastPostTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color.lerp(AppColors.textMuted, AppColors.text, 0.35),
                  fontSize: 13,
                ),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                meta.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            ],
          ],
        ),
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
    final foreground = success ? AppColors.success : AppColors.textMuted;
    final icon = success ? Icons.check_circle_outline : Icons.redeem_outlined;

    return TextButton.icon(
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
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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
