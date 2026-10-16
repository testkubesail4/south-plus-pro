part of 'home_shell.dart';

// Home layout: a centred column (max 1200) of plain section titles on the
// background, each over one soft surface. Red dots appear only on reply
// notices and unread short messages. While the home loads, the same layout
// renders with placeholder bones, so loaded content lands where it stood.

const _homeMaxWidth = 1200.0;

TextStyle _sectionTitleStyle() => TextStyle(
      color: AppColors.text,
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );

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
                borderRadius: BorderRadius.circular(6),
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
/// null [title] is a placeholder.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {super.key, this.note, this.trailing});

  final String? title;
  final String? note;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
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
                        ? _Bone(_sectionTitleStyle(), text: '\u3000' * 4)
                        : Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _sectionTitleStyle(),
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
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
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
/// [_quickRowCount] one-line rows tall, so switching tabs and loading never
/// moves the page. Lists the snapshot did not include load right after the
/// home's first frame, so they never delay it. Null [lists] (the home is
/// loading) shows three placeholder lists.
class _QuickLists extends StatefulWidget {
  const _QuickLists({
    super.key,
    required this.lists,
    required this.latest,
    required this.columns,
    required this.repository,
  });

  final List<ForumQuickList>? lists;
  final List<ForumThread> latest;
  final bool columns;
  final ForumRepository repository;

  @override
  State<_QuickLists> createState() => _QuickListsState();
}

/// Rows per 速览 list; the repository asks the site for this many.
const _quickRowCount = 8;

const _quickListIcons = {
  '最新讨论': Icons.forum_outlined,
  '最新回复': Icons.mode_comment_outlined,
  '提问求物': Icons.help_outline,
};

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

/// [_quickRowCount] rows and the hairlines between them.
double _quickListHeight(BuildContext context) =>
    _quickRowCount * _quickRowHeight(context) + _quickRowCount - 1;

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
        height: _quickListHeight(context),
        child: _QuickListBody(
          future: _loaded(index),
          onRetry: () => _retry(index),
          repository: widget.repository,
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
        borderRadius: BorderRadius.circular(2),
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
                : Text(list.title),
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
                height: _quickListHeight(context),
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
                            _quickListIcons[_lists[i].title] ??
                                Icons.subject_outlined,
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
                                  _lists[i].title,
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
    required this.onRetry,
    required this.repository,
  });

  final Future<List<ForumThread>>? future;
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
            alignment: Alignment.topLeft,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('加载失败：${forumErrorText(snapshot.error)}'),
            ),
          );
        }
        final threads = snapshot.data;
        if (threads == null) return const _QuickListSkeleton();
        // Blocked authors' threads leave the list as soon as a rule changes.
        return ValueListenableBuilder(
          valueListenable: repository.blocking.notifier,
          builder: (context, rules, _) {
            final shown =
                threads.where((thread) => !rules.isThreadBlocked(thread));
            if (shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child:
                    Text('暂无内容', style: TextStyle(color: AppColors.textMuted)),
              );
            }
            return _quickRows(context, [
              for (final thread in shown.take(_quickRowCount))
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
  const _QuickListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '加载中',
      child: _quickRows(context, [
        for (var i = 0; i < _quickRowCount; i++)
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

/// 常用版块 (boards pinned in search) for signed-in users, otherwise the
/// site's 热门版块, as a row of chips. While [hotBoards] is null (the home
/// is loading) [boneCount] blank chips stand in.
class _BoardChips extends StatefulWidget {
  const _BoardChips({
    required this.repository,
    required this.hotBoards,
    required this.boneCount,
    required this.onOpen,
  });

  final ForumRepository repository;
  final List<ForumCategory>? hotBoards;
  final int boneCount;
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
        : widget.hotBoards ?? const <ForumCategory>[];
    final bones = !pinned && widget.hotBoards == null;
    if (bones ? widget.boneCount == 0 : boards.isEmpty) {
      return const SizedBox.shrink();
    }
    Widget chip(String label, {ForumCategory? board}) => ActionChip(
          label: Text(label),
          labelStyle: TextStyle(
            color: board == null ? Colors.transparent : AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          shape: const StadiumBorder(),
          side: BorderSide(
              color: board == null ? AppColors.inkSoft : AppColors.border),
          backgroundColor:
              board == null ? AppColors.inkSoft : AppColors.surface,
          onPressed: board == null ? null : () => widget.onOpen(board),
        );
    final chips = bones
        ? [
            for (var i = 0; i < widget.boneCount; i++)
              ExcludeSemantics(child: chip('\u3000' * 4)),
          ]
        : [for (final board in boards) chip(board.name, board: board)];
    final scrolling = ScrollConfiguration.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(pinned ? '常用版块' : '热门版块'),
          // One row at every width, so its height never depends on the
          // boards; a trailing fade shows it continues past the edge.
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              colors: const [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 1 - 24 / rect.width, 1],
            ).createShader(rect),
            child: ScrollConfiguration(
              // Mice drag it too, as desktops have no horizontal wheel.
              behavior: scrolling.copyWith(
                dragDevices: {
                  ...scrolling.dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
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
          ),
        ],
      ),
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
    this.bones,
    required this.columns,
    required this.onOpen,
  });

  final List<ForumBoard> boards;
  final List<int>? bones;
  final int columns;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    final bones = this.bones;
    final count = bones?.length ?? boards.length;
    Widget tile(int i, EdgeInsets padding) => _BoardTile(
          board: bones == null ? boards[i] : null,
          lines: bones?[i] ?? 0,
          padding: padding,
          onOpen: onOpen,
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
  });

  /// Null for a placeholder showing [lines] (see [_tileLines]).
  final ForumBoard? board;
  final int lines;
  final EdgeInsets padding;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      color: AppColors.text,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );
    final lastPostStyle = TextStyle(
      color: Color.lerp(AppColors.textMuted, AppColors.text, 0.35),
      fontSize: 13,
    );
    final metaStyle = TextStyle(color: AppColors.textFaint, fontSize: 12);
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
      // Styled on the Text so it keeps the theme's font family.
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
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

    return _taskButton(
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
      label: label,
      foreground: foreground,
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
