part of 'home_shell.dart';

// Home layout: a centred column (max 1200) of plain section titles on the
// background, each over one soft surface. Red dots appear only on reply
// notices and unread short messages. While the home loads, the same layout
// renders with placeholder bones, so loaded content lands where it stood.

const _homeMaxWidth = 1200.0;

TextStyle _sectionTitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium!;

Widget _hairline(double indent) => Divider(
      height: 1,
      indent: indent,
      endIndent: indent,
      color: AppColors.border.withValues(alpha: 0.6),
    );

/// A placeholder bar one line of [style] tall and as wide as [text] (or
/// [widthFactor] of the row), so the loaded text takes its exact place.
class _Bone extends StatelessWidget {
  const _Bone(this.style, {this.text = '\u3000', this.widthFactor});

  final TextStyle style;
  final String text;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final bone = Stack(
      children: [
        Text(
          text,
          maxLines: 1,
          style: style.copyWith(color: Colors.transparent),
        ),
        Positioned.fill(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: widthFactor ?? 1,
            heightFactor: 0.6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.inkSoft,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
    return ExcludeSemantics(
      child: widthFactor == null
          ? bone
          : SizedBox(width: double.infinity, child: bone),
    );
  }
}

/// Section title, with an optional muted note and a trailing action; a
/// null [title] is a placeholder. A non-null [collapsed] makes the header a
/// 48px toggle (chevron, [onToggle]); a null [onToggle] keeps the room but
/// is inert, so a placeholder holds the loaded height.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
    this.title, {
    super.key,
    this.note,
    this.trailing,
    this.collapsed,
    this.onToggle,
    this.onLongPress,
  });

  final String? title;
  final String? note;
  final Widget? trailing;
  final bool? collapsed;
  final VoidCallback? onToggle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final collapsed = this.collapsed;
    final row = Row(
      children: [
        // One line at any text size, so a placeholder's height holds: the
        // title keeps the room it needs and the note takes what is left.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: title == null
                      ? _Bone(_sectionTitleStyle(context), text: '　' * 4)
                      : Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _sectionTitleStyle(context),
                        ),
                ),
                if (note != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (trailing != null) trailing!,
        if (collapsed != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.sm),
            child: AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: _motion(context),
              curve: AppMotion.enter,
              child: Icon(
                Icons.expand_more,
                color:
                    onToggle == null ? Colors.transparent : AppColors.textMuted,
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: collapsed == null
          ? row
          : Semantics(
              button: onToggle != null,
              expanded: onToggle == null ? null : !collapsed,
              hint: onToggle == null ? null : (collapsed ? '展开' : '折叠'),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: onToggle,
                onLongPress: onLongPress,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: row,
                ),
              ),
            ),
    );
  }
}

/// Animation length, instant when the platform asks for reduced motion.
Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppMotion.short;

/// Folds [child] away to nothing. It stays mounted so the fold animates, but
/// a folded child takes no taps, focus or screen-reader attention. Only the
/// fold animates: when the child itself changes height (placeholders giving
/// way to boards) the section follows at once, so nothing shifts later.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.collapsed, required this.child});

  final bool collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: collapsed ? 0 : 1),
      duration: _motion(context),
      curve: AppMotion.enter,
      child: ExcludeFocus(
        excluding: collapsed,
        child: ExcludeSemantics(
          excluding: collapsed,
          child: IgnorePointer(ignoring: collapsed, child: child),
        ),
      ),
      builder: (context, open, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: open,
          child: child,
        ),
      ),
    );
  }
}

String _displayName(
        ForumRepository repository, ForumAccountIdentity? identity) =>
    accountDisplayName(identity) ?? repository.currentUsername ?? '已登录';

/// The home's header, one 56px row at every width. Signed in: avatar and
/// name, opening 我的; guests: the S+ mark, a welcome and 登录. Notices live
/// in the 消息 tab, whose nav icon carries the unread dot.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.repository, this.onAccountTap});

  final ForumRepository repository;
  final VoidCallback? onAccountTap;

  @override
  Widget build(BuildContext context) {
    final nameStyle = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.w600);
    if (!repository.isLoggedIn) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            const BrandMark(size: 32),
            const SizedBox(width: AppSpace.md),
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
                      const SizedBox(width: AppSpace.md),
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
        ],
      ),
    );
  }
}

/// 最新讨论 and the site's other quick lists: side-by-side columns when
/// there is room, otherwise swipeable tabs. Every list area is
/// [_QuickLists.rows] one-line rows tall, so switching tabs and loading never
/// moves the page. Lists the snapshot did not include load right after the
/// home's first frame, so they never delay it. Null [lists] (the home is
/// loading) shows three placeholder lists.
class _QuickLists extends StatefulWidget {
  const _QuickLists({
    super.key,
    required this.lists,
    required this.latest,
    required this.columns,
    required this.rows,
    required this.repository,
    required this.onChangeSource,
  });

  final List<ForumQuickList>? lists;
  final List<ForumThread> latest;
  final bool columns;

  /// Rows shown per list, 3 to 8 (the repository always fetches 8).
  final int rows;
  final ForumRepository repository;

  /// Opens the 速览 settings, for a list whose board is gone or closed.
  final VoidCallback onChangeSource;

  @override
  State<_QuickLists> createState() => _QuickListsState();
}

const _quickListIcons = {
  '最新讨论': Icons.forum_outlined,
  '最新回复': Icons.mode_comment_outlined,
  '提问求物': Icons.help_outline,
};

bool _boardSource(ForumQuickList list) =>
    list.source.kind == HomeQuickSourceKind.board;

/// The title the snapshot gives; a board list without one is named by its
/// saved board and order.
String _quickTitle(ForumQuickList list) => list.title.isNotEmpty ||
        !_boardSource(list)
    ? list.title
    : '${list.source.boardPath?.split(' / ').last ?? '版块 ${list.source.fid}'} '
        '${list.source.order == QuickOrder.posted ? '新帖' : '回复'}';

IconData _quickIcon(ForumQuickList list) => _boardSource(list)
    ? Icons.dashboard_outlined
    : _quickListIcons[list.title] ?? Icons.subject_outlined;

/// The row title's style, as [ForumThreadRow] draws it.
TextStyle _quickTitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall!;

/// One row: 48 at 1x (the tap target), growing with the title line at
/// larger text sizes.
double _quickRowHeight(BuildContext context) {
  final style = _quickTitleStyle(context);
  return math.max(
    48,
    MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height! +
        2 * AppSpace.sm,
  );
}

/// [rows] rows and the hairlines between them.
double _quickListHeight(BuildContext context, int rows) =>
    rows * _quickRowHeight(context) + rows - 1;

/// Rows of exactly [_quickRowHeight], split by inset hairlines so
/// neighbours never read as one.
Widget _quickRows(BuildContext context, List<Widget> rows) => Column(
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) _hairline(AppSpace.lg),
          SizedBox(height: _quickRowHeight(context), child: row),
        ],
      ],
    );

class _QuickListsState extends State<_QuickLists>
    with SingleTickerProviderStateMixin {
  late final _lists = switch (widget.lists) {
    null => const [
        ForumQuickList(title: ''),
        ForumQuickList(title: ''),
        ForumQuickList(title: ''),
      ],
    [] => [ForumQuickList(title: '最新讨论', threads: widget.latest)],
    final lists => lists,
  };
  late final TabController _tabs;
  final _loads = <int, Future<List<ForumThread>>>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _lists.length, vsync: this);
    if (widget.lists == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var i = 0; i < _lists.length; i++) {
        _load(i);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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

  Widget _body(int index) => SizedBox(
        height: _quickListHeight(context, widget.rows),
        child: _QuickListBody(
          future: _loaded(index),
          board: _boardSource(_lists[index]),
          onChangeSource: widget.onChangeSource,
          onRetry: () => _retry(index),
          repository: widget.repository,
          rows: widget.rows,
        ),
      );

  Widget _tabBar() {
    final placeholder = widget.lists == null;
    final scaler = MediaQuery.textScalerOf(context);
    final style = Theme.of(context).textTheme.labelLarge!;
    final bar = TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      // Labels start where the rows' titles do.
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
      labelPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(
          width: 3,
          color: placeholder ? Colors.transparent : AppColors.brand,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      dividerColor: Colors.transparent,
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.textMuted,
      labelStyle: style,
      unselectedLabelStyle: style.copyWith(fontWeight: FontWeight.w500),
      splashBorderRadius: BorderRadius.circular(8),
      tabs: [
        for (final list in _lists)
          Tab(
            height: math.max(48, scaler.scale(style.fontSize!) * 1.4 + 20),
            // Placeholder tabs are as wide as the site's four-character titles.
            child: placeholder
                ? _Bone(style, text: '\u3000' * 4)
                : Text(_quickTitle(list)),
          ),
      ],
    );
    return placeholder ? IgnorePointer(child: bar) : bar;
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall!;
    if (!widget.columns || _lists.length == 1) {
      final scrolling = ScrollConfiguration.of(context);
      return Container(
        decoration: appSurface(context),
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_lists.length > 1) ...[
              _tabBar(),
              SizedBox(
                height: _quickListHeight(context, widget.rows),
                child: ScrollConfiguration(
                  // Mice swipe the lists too.
                  behavior: scrolling.copyWith(
                    dragDevices: {
                      ...scrolling.dragDevices,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: TabBarView(
                    controller: _tabs,
                    physics: widget.lists == null
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    children: [
                      for (var i = 0; i < _lists.length; i++) _body(i),
                    ],
                  ),
                ),
              ),
            ] else
              _body(0),
          ],
        ),
      );
    }
    return Container(
      decoration: appSurface(context),
      padding: const EdgeInsets.fromLTRB(
          AppSpace.sm, AppSpace.lg, AppSpace.sm, AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _lists.length; i++) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, 0, AppSpace.lg, AppSpace.xs),
                    child: Row(
                      children: [
                        if (widget.lists == null)
                          const SizedBox(width: 16, height: 16)
                        else
                          Icon(
                            _quickIcon(_lists[i]),
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: widget.lists == null
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: _Bone(labelStyle, text: '\u3000' * 4),
                                )
                              : Text(
                                  _quickTitle(_lists[i]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                        ),
                      ],
                    ),
                  ),
                  _body(i),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickListBody extends StatelessWidget {
  const _QuickListBody({
    required this.future,
    required this.board,
    required this.onChangeSource,
    required this.onRetry,
    required this.repository,
    required this.rows,
  });

  final Future<List<ForumThread>>? future;

  /// The list reads one chosen board, not the site's own list.
  final bool board;
  final VoidCallback onChangeSource;
  final VoidCallback onRetry;
  final ForumRepository repository;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final pending = future;
    if (pending == null) return _QuickListSkeleton(rows: rows);
    return FutureBuilder<List<ForumThread>>(
      future: pending,
      builder: (context, snapshot) {
        // A chosen board that is gone or closed is not fixed by retrying.
        final gone = switch (snapshot.error) {
          ForumRequestException(kind: ForumRequestKind.invalidInput) =>
            '来源版块不存在',
          ForumRequestException(kind: ForumRequestKind.forbidden) =>
            '没有权限查看此版块',
          _ => null,
        };
        if (board && gone != null) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.sm,
              children: [
                Text(gone, style: TextStyle(color: AppColors.textMuted)),
                TextButton(
                  onPressed: onChangeSource,
                  child: const Text('更换来源'),
                ),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.topLeft,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('加载失败：${forumErrorText(snapshot.error)}'),
            ),
          );
        }
        final threads = snapshot.data;
        if (threads == null) return _QuickListSkeleton(rows: rows);
        // Blocked authors' threads leave the list as soon as a rule changes.
        return ValueListenableBuilder(
          valueListenable: repository.blocking.notifier,
          builder: (context, rules, _) {
            final shown =
                threads.where((thread) => !rules.isThreadBlocked(thread));
            if (shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(board ? '此版块暂无主题' : '暂无内容',
                    style: TextStyle(color: AppColors.textMuted)),
              );
            }
            return _quickRows(context, [
              for (final thread in shown.take(rows))
                ForumThreadRow.dense(
                  title: thread.title,
                  titleStyle: thread.titleStyle,
                  count: thread.replies > 0 ? thread.replies : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ThreadDetailScreen(
                        thread: thread,
                        repository: repository,
                      ),
                    ),
                  ),
                ),
            ]);
          },
        );
      },
    );
  }
}

/// Placeholder rows, laid out like loaded rows.
class _QuickListSkeleton extends StatelessWidget {
  const _QuickListSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '加载中',
      child: _quickRows(context, [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Bone(
                _quickTitleStyle(context),
                widthFactor: const [0.8, 0.6, 0.7, 0.5, 0.65][i % 5],
              ),
            ),
          ),
      ]),
    );
  }
}

/// Boards of one section on one surface: a list on phones, a grid of
/// [columns] wider. Each board shows its name, today's count, the last post
/// and its time with the topic total. [bones] (the home is loading) holds
/// each placeholder board's [_tileLines] instead.
class _BoardGrid extends StatelessWidget {
  const _BoardGrid({
    super.key,
    required this.boards,
    required this.columns,
    required this.onOpen,
    this.onLongPress,
  });

  final List<ForumBoard> boards;
  final int columns;
  final ValueChanged<ForumBoard> onOpen;
  final ValueChanged<ForumBoard>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final count = boards.length;
    Widget tile(int i, EdgeInsets padding) => _BoardTile(
          board: boards[i],
          lines: 0,
          padding: padding,
          onOpen: onOpen,
          onLongPress: onLongPress,
        );
    if (columns == 1) {
      return Container(
        decoration: appSurface(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) _hairline(16),
              tile(i, const EdgeInsets.fromLTRB(16, 14, 16, 14)),
            ],
          ],
        ),
      );
    }
    return Container(
      decoration: appSurface(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (var start = 0; start < count; start += columns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: 8),
                  Expanded(
                    child: start + c < count
                        ? tile(start + c, const EdgeInsets.all(12))
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

/// Which optional lines a board tile shows: 1 the last post, 2 the meta.
int _tileLines(ForumBoard board) =>
    (board.lastPostTitle != null ? 1 : 0) |
    (board.lastPostTime != null || board.topicCount != null ? 2 : 0);

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.lines,
    required this.padding,
    required this.onOpen,
    this.onLongPress,
  });

  /// Null for a placeholder showing [lines] (see [_tileLines]).
  final ForumBoard? board;
  final int lines;
  final EdgeInsets padding;
  final ValueChanged<ForumBoard> onOpen;
  final ValueChanged<ForumBoard>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nameStyle = textTheme.titleSmall!;
    // The latest topic is a thread title, so it keeps the text colour.
    final lastPostStyle = textTheme.bodySmall!.copyWith(color: AppColors.text);
    final metaStyle = textTheme.bodySmall!;
    final board = this.board;
    if (board == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: padding,
        child: Column(
          children: [
            _Bone(nameStyle, widthFactor: 0.45),
            if (lines & 1 != 0) ...[
              const SizedBox(height: 6),
              _Bone(lastPostStyle, widthFactor: 0.8),
            ],
            if (lines & 2 != 0) ...[
              const SizedBox(height: 2),
              _Bone(metaStyle, widthFactor: 0.55),
            ],
          ],
        ),
      );
    }
    final today = board.todayCount ?? 0;
    final lastPostTitle = board.lastPostTitle;
    final meta = [
      if (board.lastPostTime != null) board.lastPostTime!,
      if (board.topicCount != null) '${_thousands(board.topicCount!)} 主题',
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(board),
      onLongPress: onLongPress == null ? null : () => onLongPress!(board),
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
                    style: nameStyle,
                  ),
                ),
                if (today > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    '今日 $today',
                    style: textTheme.labelMedium!
                        .copyWith(color: AppColors.textMuted),
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
                style: lastPostStyle,
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                meta.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _taskButton({
  required VoidCallback? onPressed,
  required Widget icon,
  required String label,
  required Color foreground,
}) =>
    TextButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: foreground),
    );

/// The task shortcut's idle look, disabled until the home has loaded.
Widget _taskButtonPlaceholder() => _taskButton(
      onPressed: null,
      icon: const Icon(Icons.redeem_outlined, size: 18),
      label: '任务奖励',
      foreground: AppColors.textMuted,
    );

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

  /// Both tasks are known to be claimed or cooling down: nothing to do until
  /// the site reopens them. A missing or unknown task keeps the button
  /// usable, so a failed refresh can be retried. Never a countdown, only how
  /// recent the claim must be.
  bool _claimed(ForumAutoTaskSummary? summary) =>
      summary != null &&
      summary.hasAllTasks &&
      summary.tasks.every((task) => task.isDoneToday) &&
      summary.tasks.any((task) =>
          task.availability == ForumTaskAvailability.coolingDown ||
          task.cooldownThreshold != null);

  String? _claimedHint(ForumAutoTaskSummary summary) {
    var hours = 0;
    for (final task in summary.tasks) {
      final threshold = task.cooldownThreshold?.inHours ?? 0;
      if (threshold > hours) hours = threshold;
    }
    return hours > 0 ? '上次领取未超过 $hours 小时' : null;
  }

  @override
  Widget build(BuildContext context) {
    final summary = _snapshot?.autoTaskSummary;
    final hasClaimable = summary?.hasClaimable == true;
    final isHandled = summary?.isFullyHandled == true;
    final claimed = !_running && !hasClaimable && _claimed(summary);
    final success = isHandled || claimed;
    final label = _running
        ? '领取中'
        : hasClaimable
            ? '可领取'
            : claimed
                ? '已领取'
                : isHandled
                    ? _autoClaimed
                        ? '已自动签到'
                        : '已签到'
                    : '任务奖励';
    final foreground = success ? AppColors.success : AppColors.textMuted;
    final icon = success ? Icons.check_circle_outline : Icons.redeem_outlined;

    final button = _taskButton(
      onPressed: _running || claimed ? null : _claimRewards,
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
      label: label,
      foreground: foreground,
    );
    final hint = claimed ? _claimedHint(summary!) : null;
    return hint == null ? button : Tooltip(message: hint, child: button);
  }
}

/// Long-press actions for a home section or parent board. Hiding only shortens
/// the home list; order and every restore live in 首页版块.
class _HomeActionsSheet extends StatelessWidget {
  const _HomeActionsSheet({
    required this.title,
    required this.caption,
    required this.board,
    required this.onPick,
  });

  final String title;
  final String? caption;
  final bool board;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String action, IconData icon, String label, [String? note]) =>
        ListTile(
          leading: Icon(icon, color: AppColors.textMuted),
          title: Text(label),
          subtitle: note == null ? null : Text(note),
          onTap: () => onPick(action),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title.trim(), style: theme.textTheme.titleMedium),
                ),
                if (caption != null && caption!.isNotEmpty)
                  Text(caption!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        if (board) row('open', Icons.arrow_forward, '打开版块'),
        row(
          'hide',
          Icons.visibility_off_outlined,
          board ? '在首页隐藏此版块及子版块' : '隐藏此分区',
          '仅隐藏首页列表；最近、搜索、收藏和常用仍可进入',
        ),
        if (!board) row('manage', Icons.tune, '调整顺序与显示…'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
          child: FilledButton.tonal(
            onPressed: () => onPick(null),
            child: const Text('取消'),
          ),
        ),
      ],
    );
  }
}

/// One quiet centred line at the end of the home list.
class _HomeFootnote extends StatelessWidget {
  const _HomeFootnote({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodySmall),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.brand),
            onPressed: onAction,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
