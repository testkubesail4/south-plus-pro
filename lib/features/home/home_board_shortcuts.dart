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

  // The home boards as the forum nests them; rebuilt only for new sections.
  List<ForumSection>? _treeSource;
  var _tree = const <_BoardGroup>[];
  final _byId = <String, _BoardNode>{};

  _BoardNode _node(ForumBoard board, _BoardNode? parent, String path) {
    final node = _BoardNode(
      path: path,
      label: board.name.trim(),
      id: widget.repository.searchBoardId(
          ForumCategory(name: board.name, slug: board.slug, url: board.url)),
      parent: parent,
    );
    for (final (i, child) in board.children.indexed) {
      node.children.add(_node(child, node, '$path/$i'));
    }
    final id = node.id;
    if (id != null) _byId.putIfAbsent(id, () => node);
    return node;
  }

  List<_BoardGroup> _boardTree() {
    final sections = widget.sections;
    if (!identical(sections, _treeSource)) {
      _treeSource = sections;
      _byId.clear();
      _tree = [
        for (final (s, section) in (sections ?? const <ForumSection>[]).indexed)
          _BoardGroup(path: 'g$s', title: section.title.trim(), nodes: [
            for (final (i, board) in section.items.indexed)
              _node(board, null, '$s/$i'),
          ]),
      ];
    }
    return _tree;
  }

  /// A pin with the board it sits under, so same-named boards tell apart. Pins
  /// saved as a bare name gain the parent from the current tree; storage keeps
  /// whatever was saved.
  String _pinLabel(ForumSearchPinnedBoard pin, {bool preferTree = false}) {
    final node = _byId[pin.id];
    if (node != null && preferTree) return node.pinLabel;
    final parent = node?.parent;
    if (node == null || parent == null) return pin.label;
    return pin.label.trim() == node.label || pin.label.contains(' / ')
        ? node.pinLabel : pin.label;
  }

  /// Recent and hot boards that no home section lists.
  List<ForumSearchPinnedBoard> _extras() {
    final found = <String, ForumSearchPinnedBoard>{};
    for (final board in widget.recent) {
      if (!_byId.containsKey(board.id))
        found.putIfAbsent(board.id, () => board);
    }
    for (final category in widget.hotBoards ?? const <ForumCategory>[]) {
      final id = widget.repository.searchBoardId(category);
      final label = category.name.trim();
      if (id != null && label.isNotEmpty && !_byId.containsKey(id)) {
        found.putIfAbsent(
            id, () => ForumSearchPinnedBoard(id: id, label: label));
      }
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
        groups: _boardTree(),
        extras: _extras(),
        pinLabel: _pinLabel,
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
    _boardTree();
    final boards = tab == _MyBoardsTab.pinned ? _pinned : widget.recent;
    final Widget content;
    if (boards.isNotEmpty) {
      content = _ChipRow(chips: [
        for (final board in boards)
          _boardChip(context,
              _pinLabel(board, preferTree: tab == _MyBoardsTab.recent),
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

/// A board of the home tree; [id] is its forum id, the identity of a pin.
class _BoardNode {
  _BoardNode({
    required this.path,
    required this.label,
    required this.id,
    required this.parent,
  });

  /// Unique place in the tree; boards of one name under other parents differ.
  final String path;
  final String label;
  final String? id;
  final _BoardNode? parent;
  final children = <_BoardNode>[];

  String get pinLabel => parent == null ? label : '${parent!.label} / $label';
}

class _BoardGroup {
  const _BoardGroup(
      {required this.path, required this.title, required this.nodes});
  final String path;
  final String title;
  final List<_BoardNode> nodes;
}

/// Edits the pin list: drag to reorder, remove, add from the board tree. Every
/// change is written at once through the search screen's own store.
class _PinnedBoardsSheet extends StatefulWidget {
  const _PinnedBoardsSheet({
    required this.repository,
    required this.account,
    required this.pinned,
    required this.recent,
    required this.groups,
    required this.extras,
    required this.pinLabel,
    required this.onSaved,
  });

  final ForumRepository repository;

  /// The storage scope the sheet was opened for.
  final String? account;
  final List<ForumSearchPinnedBoard> pinned;
  final List<ForumSearchPinnedBoard> recent;
  final List<_BoardGroup> groups;

  /// Boards that are on no home section.
  final List<ForumSearchPinnedBoard> extras;
  final String Function(ForumSearchPinnedBoard pin) pinLabel;
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
                          title: Text(widget.pinLabel(pin),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ],
                if (widget.groups.isNotEmpty || widget.extras.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xs),
                    child: Text('添加', style: textTheme.titleSmall),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                    child: Text('点箭头展开父版块；“+”只添加这一个版块，不会带上子版块。',
                        style: textTheme.bodySmall),
                  ),
                  _BoardPicker(
                    // Opened rows stay open when the list above changes length.
                    key: const ValueKey('board-picker'),
                    groups: widget.groups,
                    extras: widget.extras,
                    pinnedIds: pinnedIds,
                    enabled: !_saving,
                    onAdd: (board) => _commit([..._pins, board]),
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

/// The boards offered for pinning, as the forum nests them. A row with
/// children opens and closes; the “+” on any row pins that board alone.
class _BoardPicker extends StatefulWidget {
  const _BoardPicker({
    super.key,
    required this.groups,
    required this.extras,
    required this.pinnedIds,
    required this.enabled,
    required this.onAdd,
  });

  final List<_BoardGroup> groups;
  final List<ForumSearchPinnedBoard> extras;
  final Set<String> pinnedIds;
  final bool enabled;
  final ValueChanged<ForumSearchPinnedBoard> onAdd;

  @override
  State<_BoardPicker> createState() => _BoardPickerState();
}

class _BoardPickerState extends State<_BoardPicker> {
  // Opened rows, by place in the tree rather than by name or id.
  final _open = <String>{};

  void _toggle(String path) => setState(
      () => _open.contains(path) ? _open.remove(path) : _open.add(path));

  Widget _row({
    required String path,
    required String label,
    required int depth,
    required bool expandable,
    ForumSearchPinnedBoard? pin,
  }) {
    final theme = Theme.of(context);
    final open = _open.contains(path);
    final pinned = pin != null && widget.pinnedIds.contains(pin.id);
    final target = pin;
    final VoidCallback? add = target != null && !pinned && widget.enabled
        ? () => widget.onAdd(target)
        : null;
    return Semantics(
      container: true,
      expanded: expandable ? open : null,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey('board-row:$path'),
              onTap: expandable ? () => _toggle(path) : add,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: EdgeInsets.only(
                      left: AppSpace.lg + depth * AppSpace.lg,
                      right: AppSpace.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: expandable
                            ? Icon(
                                open ? Icons.expand_more : Icons.chevron_right,
                                size: 22,
                                semanticLabel: open ? '收起' : '展开',
                              )
                            : null,
                      ),
                      Expanded(
                        child: Text(label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: expandable
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (pin != null)
            IconButton(
              key: ValueKey('board-add:$path'),
              tooltip: pinned ? '$label 已在常用' : '添加 ${pin.label}',
              icon: Icon(pinned ? Icons.check : Icons.add_circle_outline),
              onPressed: add,
            ),
        ],
      ),
    );
  }

  List<Widget> _nodes(List<_BoardNode> nodes, int depth) => [
        for (final node in nodes) ...[
          _row(
            path: node.path,
            label: node.label,
            depth: depth,
            expandable: node.children.isNotEmpty,
            pin: node.id == null || node.label.isEmpty
                ? null
                : ForumSearchPinnedBoard(id: node.id!, label: node.pinLabel),
          ),
          if (_open.contains(node.path)) ..._nodes(node.children, depth + 1),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in widget.groups)
          if (group.nodes.isNotEmpty) ...[
            _row(
              path: group.path,
              label: group.title.isEmpty ? '版块' : group.title,
              depth: 0,
              expandable: true,
            ),
            if (_open.contains(group.path)) ..._nodes(group.nodes, 1),
          ],
        if (widget.extras.isNotEmpty) ...[
          _row(
            path: 'extras',
            label: '最近与热门',
            depth: 0,
            expandable: true,
          ),
          if (_open.contains('extras'))
            for (final board in widget.extras)
              _row(
                path: 'extra:${board.id}',
                label: board.label,
                depth: 1,
                expandable: false,
                pin: board,
              ),
        ],
      ],
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
