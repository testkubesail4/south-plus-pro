import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/home_reading_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/board_picker_sheet.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../profile/favorite_collections_sheets.dart' show SessionBound;

String quickOrderLabel(QuickOrder order) => switch (order) {
      QuickOrder.posted => '新帖',
      QuickOrder.replied => '最新回复',
    };

/// 速览: how many rows each list shows and where each of its three lists
/// comes from. Every change is saved at once; the home page follows.
class QuickListSettingsScreen extends StatefulWidget {
  const QuickListSettingsScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<QuickListSettingsScreen> createState() =>
      _QuickListSettingsScreenState();
}

class _QuickListSettingsScreenState extends State<QuickListSettingsScreen> {
  // Settings belong to the account and session the page opened in.
  late final _account = widget.repository.localPreferenceAccount;
  late final _epoch = widget.repository.sessionEpoch.value;
  int? _rows;
  List<HomeQuickSource>? _sources;
  Object? _error;
  bool _busy = false;

  bool get _current =>
      mounted &&
      _account == widget.repository.localPreferenceAccount &&
      _epoch == widget.repository.sessionEpoch.value;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSession);
    _load();
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final prefs = await HomeReadingPreferences.load(account: _account);
      if (!_current) return;
      setState(() {
        _rows = prefs.quickRowCount;
        _sources = prefs.quickSources;
      });
    } catch (error) {
      if (_current) setState(() => _error = error);
    }
  }

  // One write at a time; a failed one leaves what was saved before on screen.
  Future<void> _save(
    VoidCallback apply,
    VoidCallback undo,
    Future<void> Function() write,
    String failure,
  ) async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      apply();
    });
    try {
      await write();
    } catch (_) {
      if (!_current) return;
      setState(undo);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRows() async {
    final current = _rows!;
    final rows = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      // Another login's choices close with it.
      builder: (context) => SessionBound(
        session: widget.repository.sessionEpoch,
        generation: _epoch,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SheetTitle('显示行数'),
                for (var rows = 3; rows <= 8; rows++)
                  AppRow(
                    title: Text('$rows 行'),
                    selected: rows == current,
                    onTap: () => Navigator.of(context).pop(rows),
                  ),
                const SizedBox(height: AppSpace.sm),
              ],
            ),
          ),
        ),
      ),
    );
    if (rows == null || rows == current) return;
    await _save(
      () => _rows = rows,
      () => _rows = current,
      () => HomeReadingPreferences.saveQuickRowCount(rows, account: _account),
      '无法保存显示行数',
    );
  }

  Future<void> _saveSources(List<HomeQuickSource> next) {
    final before = _sources!;
    return _save(
      () => _sources = next,
      () => _sources = before,
      () => HomeReadingPreferences.saveQuickSources(next, account: _account),
      '无法保存速览来源',
    );
  }

  Future<void> _editSlot(int index) async {
    final sources = _sources!;
    final shown =
        sources.where((s) => s.kind != HomeQuickSourceKind.hidden).length;
    final picked = await showModalBottomSheet<HomeQuickSource>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (_) => SessionBound(
        session: widget.repository.sessionEpoch,
        generation: _epoch,
        child: _SlotSheet(
          title: '栏目 ${index + 1}',
          initial: sources[index],
          // The home page always keeps one list.
          canHide:
              sources[index].kind == HomeQuickSourceKind.hidden || shown > 1,
          pickBoard: _pickBoard,
        ),
      ),
    );
    // Equal sources read the same feed; a new path for the same board is
    // still the user's to keep.
    if (picked == null ||
        !_current ||
        (picked == sources[index] &&
            picked.boardPath == sources[index].boardPath)) {
      return;
    }
    await _saveSources([
      for (final (i, source) in sources.indexed) i == index ? picked : source,
    ]);
  }

  Future<ForumSearchBoard?> _pickBoard(String? selectedId) {
    final repository = widget.repository;
    return showModalBottomSheet<ForumSearchBoard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (_) => BoardPickerSheet(
        loadBoards: repository.fetchSearchBoards,
        loadSections: repository.fetchForumSections,
        selectedId: selectedId ?? '',
        baseUri: repository.networkConfig.baseUri,
        session: repository.sessionEpoch,
        generation: _epoch,
        ownRowLabel: (name) => '$name（本版）',
        // Feeds exist per board: a search category or 全部 is no source.
        canPick: (board) =>
            board.selectable && board.id != 'all' && !isSearchCategory(board),
      ),
    );
  }

  String _describe(HomeQuickSource source) => switch (source.kind) {
        HomeQuickSourceKind.site => '原站默认',
        HomeQuickSourceKind.hidden => '不显示',
        HomeQuickSourceKind.board =>
          '${source.boardPath ?? '版块 ${source.fid}'} · ${quickOrderLabel(source.order)}',
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final sources = _sources;
    final Widget body;
    if (!_current) {
      body = const EmptyStateView(
        icon: Icons.manage_accounts_outlined,
        title: '登录状态已变化',
        message: '请返回后重新打开。',
      );
    } else if (_error != null) {
      body = AsyncErrorView(
        title: '速览设置加载失败',
        message: forumErrorText(_error),
        onRetry: _load,
      );
    } else if (rows == null || sources == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final atDefault =
          _sameSources(sources, HomeReadingPreferences.defaultQuickSources);
      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
        children: [
          AppContentWidth(
            maxWidth: AppWidths.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                AppGroup(
                  label: '显示',
                  children: [
                    AppRow(
                      icon: Icons.view_list_outlined,
                      title: const Text('显示行数'),
                      value: '$rows 行',
                      onTap: _busy ? null : _pickRows,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  label: '栏目',
                  description: '每个栏目可显示原站默认内容，或指定版块的新帖、最新回复。',
                  children: [
                    for (final (i, source) in sources.indexed)
                      AppRow(
                        icon: Icons.view_agenda_outlined,
                        title: Text('栏目 ${i + 1}'),
                        subtitle: Text(_describe(source)),
                        onTap: _busy ? null : () => _editSlot(i),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                Center(
                  child: TextButton(
                    onPressed: atDefault || _busy
                        ? null
                        : () => _saveSources(
                            HomeReadingPreferences.defaultQuickSources),
                    child: const Text('恢复默认'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('速览')), body: body);
  }
}

bool _sameSources(List<HomeQuickSource> a, List<HomeQuickSource> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
}

/// Where one 速览 list comes from; pops the chosen [HomeQuickSource].
class _SlotSheet extends StatefulWidget {
  const _SlotSheet({
    required this.title,
    required this.initial,
    required this.canHide,
    required this.pickBoard,
  });

  final String title;
  final HomeQuickSource initial;
  final bool canHide;
  final Future<ForumSearchBoard?> Function(String? selectedId) pickBoard;

  @override
  State<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends State<_SlotSheet> {
  late var _kind = widget.initial.kind;
  late var _fid = widget.initial.fid;
  late var _path = widget.initial.boardPath;
  late var _order = widget.initial.order;

  Future<void> _chooseBoard() async {
    final board = await widget.pickBoard(_fid);
    if (board == null || !mounted) return;
    setState(() {
      _fid = board.id;
      _path = board.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final board = _kind == HomeQuickSourceKind.board;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetTitle(widget.title),
            AppRow(
              title: const Text('原站默认'),
              selected: _kind == HomeQuickSourceKind.site,
              onTap: () => setState(() => _kind = HomeQuickSourceKind.site),
            ),
            AppRow(
              title: const Text('指定版块'),
              selected: board,
              onTap: () => setState(() => _kind = HomeQuickSourceKind.board),
            ),
            if (board) ...[
              AppRow(
                icon: Icons.dashboard_outlined,
                title: const Text('版块'),
                value: _path ?? '请选择',
                onTap: _chooseBoard,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.sm),
                child: SegmentedButton<QuickOrder>(
                  segments: [
                    for (final order in QuickOrder.values)
                      ButtonSegment(
                          value: order, label: Text(quickOrderLabel(order))),
                  ],
                  selected: {_order},
                  onSelectionChanged: (picked) =>
                      setState(() => _order = picked.single),
                ),
              ),
            ],
            AppRow(
              title: const Text('不显示'),
              subtitle: widget.canHide ? null : const Text('至少保留一个栏目'),
              selected: _kind == HomeQuickSourceKind.hidden,
              onTap: widget.canHide
                  ? () => setState(() => _kind = HomeQuickSourceKind.hidden)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                onPressed: board && _fid == null
                    ? null
                    : () => Navigator.of(context).pop(HomeQuickSource(
                          kind: _kind,
                          fid: board ? _fid : null,
                          boardPath: board ? _path : null,
                          // Only a board list has an order to keep.
                          order: board ? _order : QuickOrder.posted,
                        )),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
