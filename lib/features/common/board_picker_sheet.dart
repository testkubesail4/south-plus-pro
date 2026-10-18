import 'dart:async' show scheduleMicrotask;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/search_board_hierarchy.dart';
import '../../theme/app_theme.dart';
import 'async_state_view.dart';

/// A board's name without the search form's tree prefixes such as "|- ".
String boardDisplayName(String name) =>
    name.replaceFirst(RegExp(r'^[\s|\-\u00a0>]+'), '').trim();

String _ownBoard(String name) => '仅 $name';

/// Picks one board from the search form's options, nested under the
/// homepage's parents. Pops the chosen [ForumSearchBoard], named by its path.
class BoardPickerSheet extends StatefulWidget {
  const BoardPickerSheet({
    super.key,
    required this.loadBoards,
    required this.loadSections,
    required this.selectedId,
    required this.baseUri,
    required this.session,
    required this.generation,
    this.allOption,
    this.ownRowLabel = _ownBoard,
  });

  /// A first row choosing every board (e.g. 全部版块); none when null.
  final ForumSearchBoard? allOption;

  /// The row inside an opened parent that picks the parent alone.
  final String Function(String name) ownRowLabel;

  final Future<List<ForumSearchBoard>> Function() loadBoards;
  final Future<List<ForumSection>> Function() loadSections;
  final String selectedId;

  /// The forum the account is on: the homepage's board links are read against
  /// it, whatever its origin.
  final Uri baseUri;

  /// Moves when the session changes; [generation] is its value when the sheet
  /// was asked for. Board names belong to one account.
  final ValueListenable<int> session;
  final int generation;

  @override
  State<BoardPickerSheet> createState() => _BoardPickerSheetState();
}

class _BoardPickerSheetState extends State<BoardPickerSheet> {
  final _filter = TextEditingController();
  late Future<List<ForumSearchBoard>> _boards = widget.loadBoards();
  List<ForumSection>? _sections;
  Object? _sectionsError;
  // Keys of the opened groups; lives with the sheet, not saved anywhere.
  final _open = <String>{};
  // The lists the selection's ancestors were last opened for.
  Object? _openedFor;

  bool get _stale => widget.session.value != widget.generation;

  @override
  void initState() {
    super.initState();
    if (_stale) {
      // Changed before this first frame: close once it is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    } else {
      widget.session.addListener(_check);
      _loadSections();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_check);
    _filter.dispose();
    super.dispose();
  }

  // Raised while the profile screen may be mid-build.
  void _check() => scheduleMicrotask(() {
        if (!mounted || !_stale) return;
        setState(() {});
        _close();
      });

  // Removes this sheet's own route, never one that lies above it.
  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _loadSections() async {
    try {
      final sections = await widget.loadSections();
      if (mounted && !_stale) setState(() => _sections = sections);
    } catch (error) {
      if (mounted && !_stale) setState(() => _sectionsError = error);
    }
  }

  void _retrySections() {
    setState(() {
      _sections = null;
      _sectionsError = null;
    });
    _loadSections();
  }

  // The search form's options stay the only source of boards; the homepage
  // sections only say which board sits under which.
  List<BoardNode> _tree(List<ForumSearchBoard> boards) {
    final real = [
      for (final board in boards)
        if (board.id != 'all') board,
    ];
    final sections = _sections;
    final roots = BoardNode.build(
      sections == null || sections.isEmpty
          ? real
          : mergeSearchBoardHierarchy(real, sections, baseUri: widget.baseUri),
    );
    final source = (boards, sections);
    if (_openedFor != source) {
      _openedFor = source;
      for (final node in BoardNode.flatten(roots)) {
        if (node.board.id == widget.selectedId) {
          for (var p = node.parent; p != null; p = p.parent) {
            _open.add(p.key);
          }
        }
      }
    }
    return roots;
  }

  double _indent(int level) => AppSpace.lg + AppSpace.lg * level.clamp(0, 4);

  void _pick(BoardNode node) {
    if (_stale) return;
    Navigator.of(context).pop(ForumSearchBoard(
        id: node.board.id, name: node.path, depth: node.board.depth));
  }

  Widget _tile(BoardNode node,
      {required int level,
      String? label,
      String? note,
      bool showContext = false}) {
    final selected = node.board.id == widget.selectedId;
    final parents = showContext ? node.context : null;
    return ListTile(
      key: ValueKey('board-filter:${node.board.id}'),
      contentPadding:
          EdgeInsetsDirectional.only(start: _indent(level), end: AppSpace.lg),
      title: Text(label ?? node.name),
      subtitle: (note ?? parents) == null ? null : Text((note ?? parents)!),
      selected: selected,
      selectedColor: AppColors.brandDark,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => _pick(node),
    );
  }

  // Opening a group never selects it; a board that can be filtered on its
  // own has its own row inside.
  Widget _group(BoardNode node) {
    final open = _open.contains(node.key);
    return Semantics(
      expanded: open,
      child: ListTile(
        key: ValueKey('board-filter-group:${node.key}'),
        contentPadding: EdgeInsetsDirectional.only(
            start: _indent(node.level), end: AppSpace.lg),
        title: Text(node.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
        onTap: () => setState(() {
          if (!_open.remove(node.key)) _open.add(node.key);
        }),
      ),
    );
  }

  List<Widget> _rows(List<BoardNode> nodes) => [
        for (final node in nodes)
          if (node.children.isEmpty)
            node.board.selectable
                ? _tile(node, level: node.level)
                : Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(_indent(node.level),
                        AppSpace.md, AppSpace.lg, AppSpace.xs),
                    child: Semantics(
                      header: true,
                      child: Text(node.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  )
          else ...[
            _group(node),
            if (_open.contains(node.key)) ...[
              if (node.board.selectable)
                _tile(node,
                    level: node.level + 1,
                    label: widget.ownRowLabel(node.name),
                    note: '不含子版块'),
              ..._rows(node.children),
            ],
          ],
      ];

  Widget _allRow(ForumSearchBoard all) => ListTile(
        key: ValueKey('board-filter:${all.id}'),
        contentPadding: const EdgeInsetsDirectional.only(
            start: AppSpace.lg, end: AppSpace.lg),
        title: Text(all.name),
        selected: widget.selectedId == all.id,
        selectedColor: AppColors.brandDark,
        trailing: widget.selectedId == all.id ? const Icon(Icons.check) : null,
        onTap: () => Navigator.of(context).pop(all),
      );

  Widget _hierarchyStatus() {
    if (_sections == null && _sectionsError == null) {
      return const ListTile(
        dense: true,
        leading: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('正在加载版块层级…'),
      );
    }
    if (_sectionsError == null) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.info_outline),
      title: const Text('未能加载版块层级，按平铺列表显示'),
      trailing: TextButton(onPressed: _retrySections, child: const Text('重试')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stale) return const SizedBox.shrink();
    final needle = _filter.text.trim().toLowerCase();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '筛选版块',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ForumSearchBoard>>(
                future: _boards,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AsyncErrorView(
                      title: '版块列表加载失败',
                      message: forumErrorText(snapshot.error),
                      onRetry: () =>
                          setState(() => _boards = widget.loadBoards()),
                    );
                  }
                  final boards = snapshot.data;
                  if (boards == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Until the homepage says who is whose parent, no board is
                  // offered: same-named children could not be told apart.
                  if (_sections == null && _sectionsError == null) {
                    return ListView(children: [
                      if (widget.allOption case final all?) _allRow(all),
                      _hierarchyStatus()
                    ]);
                  }
                  final roots = _tree(boards);
                  if (needle.isNotEmpty) {
                    // A search lists matches flat, each with its parent so
                    // same-named children stay apart.
                    final hits = [
                      for (final node in BoardNode.flatten(roots))
                        if (node.board.selectable &&
                            node.name.toLowerCase().contains(needle))
                          node,
                    ];
                    // The warning stays: without the hierarchy these hits carry
                    // no parent, and the retry is here.
                    if (hits.isEmpty) {
                      return Column(children: [
                        _hierarchyStatus(),
                        const Expanded(child: EmptyStateView(title: '没有匹配的版块')),
                      ]);
                    }
                    return ListView(children: [
                      _hierarchyStatus(),
                      for (final node in hits)
                        _tile(node, level: 0, showContext: true),
                    ]);
                  }
                  return ListView(children: [
                    if (widget.allOption case final all?) _allRow(all),
                    _hierarchyStatus(),
                    ..._rows(roots),
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One board placed under its parent by the preorder depth.
class BoardNode {
  BoardNode(this.board, this.parent)
      : level = parent == null ? 0 : parent.level + 1;

  final ForumSearchBoard board;
  final BoardNode? parent;
  final int level;
  final children = <BoardNode>[];

  String get name => boardDisplayName(board.name);

  // A board that can be filtered on is its fid. A heading may carry no id or
  // a shared placeholder, so it is told apart by where it sits and its name.
  String get key => board.selectable
      ? board.id
      : 'heading:${parent?.key ?? ''}/${board.id}:${board.name}';

  /// The boards above this one that can be filtered on themselves
  /// (section headings are not), so same-named children stay apart.
  String? get context {
    final names = <String>[];
    for (var p = parent; p != null; p = p.parent) {
      if (p.board.selectable) names.insert(0, p.name);
    }
    return names.isEmpty ? null : names.join(' / ');
  }

  String get path => [if (context != null) context!, name].join(' / ');

  static List<BoardNode> build(List<ForumSearchBoard> boards) {
    final roots = <BoardNode>[];
    final open = <BoardNode>[];
    for (final board in boards) {
      while (open.isNotEmpty && open.last.board.depth >= board.depth) {
        open.removeLast();
      }
      final node = BoardNode(board, open.lastOrNull);
      (node.parent?.children ?? roots).add(node);
      open.add(node);
    }
    return roots;
  }

  static Iterable<BoardNode> flatten(List<BoardNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* flatten(node.children);
    }
  }
}
