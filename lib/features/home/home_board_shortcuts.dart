part of 'home_shell.dart';

// Board shortcuts: 热门版块 (the site's list, always shown) and below it
// 我的版块, a 常用 | 最近 choice for signed-in users. 常用 is the pin list the
// search screen edits too (ForumSearchPreferences); 最近 is the visit history.

/// One single-line, horizontally scrolling row of chips; a trailing fade
/// shows it continues past the edge.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final scrolling = ScrollConfiguration.of(context);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: const [Colors.black, Colors.black, Colors.transparent],
        stops: [0, 1 - 24 / rect.width, 1],
      ).createShader(rect),
      child: ScrollConfiguration(
        // Mice drag it too, as desktops have no horizontal wheel.
        behavior: scrolling.copyWith(
          dragDevices: {...scrolling.dragDevices, PointerDeviceKind.mouse},
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
    );
  }
}

/// A board chip; a null [onTap] is a blank placeholder of the same size.
Widget _boardChip(
  BuildContext context,
  String label, {
  VoidCallback? onTap,
  IconData? icon,
}) =>
    ActionChip(
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
            color: onTap == null ? Colors.transparent : AppColors.text,
          ),
      shape: const StadiumBorder(),
      side: BorderSide(
          color: onTap == null ? AppColors.inkSoft : AppColors.border),
      backgroundColor: onTap == null ? AppColors.inkSoft : AppColors.surface,
      onPressed: onTap,
    );

/// 热门版块: the site's hot boards. While [hotBoards] is null (the home is
/// loading) [boneCount] blank chips stand in.
class _HotBoards extends StatelessWidget {
  const _HotBoards({
    required this.hotBoards,
    required this.boneCount,
    required this.onOpen,
  });

  final List<ForumCategory>? hotBoards;
  final int boneCount;
  final ValueChanged<ForumCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    final boards = hotBoards;
    if (boards == null ? boneCount == 0 : boards.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader('热门版块'),
          _ChipRow(
            chips: boards == null
                ? [
                    for (var i = 0; i < boneCount; i++)
                      ExcludeSemantics(
                          child: _boardChip(context, '\u3000' * 4)),
                  ]
                : [
                    for (final board in boards)
                      _boardChip(context, board.name,
                          onTap: () => onOpen(board)),
                  ],
          ),
        ],
      ),
    );
  }
}

enum _MyBoardsTab { pinned, recent }

bool _samePins(
  List<ForumSearchPinnedBoard> a,
  List<ForumSearchPinnedBoard> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id || a[i].label != b[i].label) return false;
  }
  return true;
}

/// 我的版块 for signed-in users: 常用 (editable pins) or 最近 (visits, newest
/// first). The section always renders, so its height never depends on the
/// pins loading.
class _MyBoards extends StatefulWidget {
  const _MyBoards({
    required this.repository,
    required this.recent,
    required this.hotBoards,
    required this.sections,
    required this.onOpen,
  });

  final ForumRepository repository;
  final List<ForumSearchPinnedBoard> recent;

  /// With [sections], the boards the edit sheet offers (null while loading).
  final List<ForumCategory>? hotBoards;
  final List<ForumSection>? sections;
  final ValueChanged<ForumCategory> onOpen;

  @override
  State<_MyBoards> createState() => _MyBoardsState();
}

class _MyBoardsState extends State<_MyBoards> {
  late final String? _account = widget.repository.localPreferenceAccount;
  List<ForumSearchPinnedBoard> _pinned = const [];
  // The user's choice this visit; unset follows what exists.
  _MyBoardsTab? _chosen;

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  // Home stays alive in the tab stack; re-read pins whenever it rebuilds
  // (tab switch, refresh) so pins changed in search show up.
  @override
  void didUpdateWidget(_MyBoards oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPins();
  }

  void _loadPins() {
    if (!widget.repository.isLoggedIn) return;
    ForumSearchPreferences.load(account: _account).then((prefs) {
      if (mounted && !_samePins(_pinned, prefs.pinnedBoards)) {
        setState(() => _pinned = prefs.pinnedBoards);
      }
    }, onError: (Object _) {
      // Pins stay as shown.
    });
  }

  ForumCategory _category(ForumSearchPinnedBoard board) =>
      ForumCategory(name: board.label, slug: 'fid-${board.id}');

  /// Recent, hot and every home board, once per board id.
  List<ForumSearchPinnedBoard> _candidates() {
    final found = <String, ForumSearchPinnedBoard>{};
    void add(ForumCategory category) {
      final id = widget.repository.searchBoardId(category);
      final label = category.name.trim();
      if (id != null && label.isNotEmpty) {
        found.putIfAbsent(
            id, () => ForumSearchPinnedBoard(id: id, label: label));
      }
    }

    void addBoard(ForumBoard board) {
      add(ForumCategory(name: board.name, slug: board.slug, url: board.url));
      board.children.forEach(addBoard);
    }

    for (final board in widget.recent) {
      found.putIfAbsent(board.id, () => board);
    }
    widget.hotBoards?.forEach(add);
    for (final section in widget.sections ?? const <ForumSection>[]) {
      section.items.forEach(addBoard);
    }
    return found.values.toList();
  }

  Future<void> _edit() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (_) => _PinnedBoardsSheet(
        repository: widget.repository,
        account: _account,
        pinned: _pinned,
        recent: widget.recent,
        candidates: _candidates(),
        onSaved: (pins) {
          if (mounted) setState(() => _pinned = pins);
        },
      ),
    );
    if (mounted) _loadPins();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isLoggedIn) return const SizedBox.shrink();
    final tab = _chosen ??
        (_pinned.isNotEmpty || widget.recent.isEmpty
            ? _MyBoardsTab.pinned
            : _MyBoardsTab.recent);
    final boards = tab == _MyBoardsTab.pinned ? _pinned : widget.recent;
    final Widget content;
    if (boards.isNotEmpty) {
      content = _ChipRow(chips: [
        for (final board in boards)
          _boardChip(context, board.label,
              onTap: () => widget.onOpen(_category(board))),
      ]);
    } else if (tab == _MyBoardsTab.pinned) {
      content = _ChipRow(chips: [
        _boardChip(context, '添加常用版块', icon: Icons.add, onTap: _edit),
      ]);
    } else {
      content = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '还没有浏览过的版块',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            '我的版块',
            trailing: tab == _MyBoardsTab.pinned && _pinned.isNotEmpty
                ? TextButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<_MyBoardsTab>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _MyBoardsTab.pinned, label: Text('常用')),
                ButtonSegment(value: _MyBoardsTab.recent, label: Text('最近')),
              ],
              selected: {tab},
              onSelectionChanged: (value) =>
                  setState(() => _chosen = value.first),
            ),
          ),
          content,
        ],
      ),
    );
  }
}

/// Edits the pin list: drag to reorder, remove, add from [candidates]. Every
/// change is written at once through the search screen's own store.
class _PinnedBoardsSheet extends StatefulWidget {
  const _PinnedBoardsSheet({
    required this.repository,
    required this.account,
    required this.pinned,
    required this.recent,
    required this.candidates,
    required this.onSaved,
  });

  final ForumRepository repository;

  /// The storage scope the sheet was opened for.
  final String? account;
  final List<ForumSearchPinnedBoard> pinned;
  final List<ForumSearchPinnedBoard> recent;
  final List<ForumSearchPinnedBoard> candidates;
  final ValueChanged<List<ForumSearchPinnedBoard>> onSaved;

  @override
  State<_PinnedBoardsSheet> createState() => _PinnedBoardsSheetState();
}

class _PinnedBoardsSheetState extends State<_PinnedBoardsSheet> {
  late List<ForumSearchPinnedBoard> _pins = List.of(widget.pinned);
  late bool _hasRecent = widget.recent.isNotEmpty;
  late final Listenable _sessionSignals = Listenable.merge(
      [widget.repository.sessionUser, widget.repository.sessionEpoch]);
  // Set once the scope moved; the sheet never shows or writes again.
  bool _stale = false;
  // One save at a time: an edit made on top of an unacknowledged list could
  // commit what a failed save was meant to undo.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sessionSignals.addListener(_onSessionSignal);
  }

  @override
  void dispose() {
    _sessionSignals.removeListener(_onSessionSignal);
    super.dispose();
  }

  /// Still the scope the sheet shows. The modal barrier only blocks taps; a
  /// logout or origin change can still arrive, and then the sheet closes.
  bool get _inScope =>
      !_stale && widget.repository.localPreferenceAccount == widget.account;

  // The epoch moves before the repository adopts a new origin, so the final
  // scope is read one microtask later.
  void _onSessionSignal() => scheduleMicrotask(() {
        if (!mounted || _inScope) return;
        // Blank at once; the route's closing animation then shows nothing.
        setState(() => _stale = true);
        Navigator.of(context).maybePop();
      });

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _commit(List<ForumSearchPinnedBoard> next) async {
    if (_saving || !_inScope) return;
    final previous = _pins;
    setState(() {
      _pins = next;
      _saving = true;
    });
    try {
      await ForumSearchPreferences.savePinnedBoards(next,
          account: widget.account);
      if (_inScope) widget.onSaved(next);
    } catch (_) {
      if (mounted) setState(() => _pins = previous);
      _fail('保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearRecent() async {
    if (!_inScope) return;
    try {
      await HomeReadingPreferences.clearRecentBoards(account: widget.account);
      if (mounted) setState(() => _hasRecent = false);
    } catch (_) {
      _fail('清除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Another scope's pins and boards never show, even for the frame before
    // the sheet closes.
    if (!_inScope) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final pinnedIds = {for (final pin in _pins) pin.id};
    final addable = [
      for (final board in widget.candidates)
        if (!pinnedIds.contains(board.id)) board,
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.sm, AppSpace.xs),
            child: Row(
              children: [
                Expanded(child: Text('编辑常用版块', style: textTheme.titleMedium)),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 2,
            child: _saving ? const LinearProgressIndicator() : null,
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpace.xl),
              children: [
                if (_pins.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.lg, vertical: AppSpace.md),
                    child: Text('还没有常用版块，从下方添加。', style: textTheme.bodySmall),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, 0, AppSpace.lg, AppSpace.xs),
                    child: Text('长按拖动调整顺序', style: textTheme.bodySmall),
                  ),
                  ReorderableListView(
                    shrinkWrap: true,
                    buildDefaultDragHandles: !_saving,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (from, to) {
                      if (_saving) return;
                      final next = List.of(_pins);
                      next.insert(to > from ? to - 1 : to, next.removeAt(from));
                      _commit(next);
                    },
                    children: [
                      for (final pin in _pins)
                        ListTile(
                          key: ValueKey(pin.id),
                          // The default drag handle sits at the trailing end.
                          leading: IconButton(
                            tooltip: '移除 ${pin.label}',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _saving
                                ? null
                                : () => _commit([
                                      for (final other in _pins)
                                        if (other.id != pin.id) other,
                                    ]),
                          ),
                          title: Text(pin.label,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ],
                if (addable.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.sm),
                    child: Text('添加', style: textTheme.titleSmall),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                    child: Wrap(
                      spacing: AppSpace.sm,
                      children: [
                        for (final board in addable)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: Text(board.label),
                            onPressed: _saving
                                ? null
                                : () => _commit([..._pins, board]),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_hasRecent)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.sm, AppSpace.lg, AppSpace.sm, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearRecent,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清除最近访问'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 速览 row count: 3 to 8 rows per list.
class _QuickRowsSheet extends StatelessWidget {
  const _QuickRowsSheet({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('显示行数', style: textTheme.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text('速览里每个列表显示的帖子数', style: textTheme.bodySmall),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                for (var rows = 3; rows <= 8; rows++)
                  ChoiceChip(
                    label: Text('$rows'),
                    selected: rows == current,
                    onSelected: (_) => Navigator.of(context).pop(rows),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
