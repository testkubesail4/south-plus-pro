import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../services/forum_search_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';

const _allBoards = ForumSearchBoard(id: 'all', name: '全部版块');

const _matchLabels = {
  ForumSearchMatch.partial: '部分匹配',
  ForumSearchMatch.exact: '完全匹配',
};

const _timeLabels = {
  ForumSearchTime.all: '全部时间',
  ForumSearchTime.newTopics: '最新主题',
  ForumSearchTime.day: '一天内',
  ForumSearchTime.twoDays: '两天内',
  ForumSearchTime.week: '一周内',
  ForumSearchTime.month: '一个月内',
  ForumSearchTime.twoMonths: '两个月内',
  ForumSearchTime.threeMonths: '三个月内',
  ForumSearchTime.halfYear: '半年内',
  ForumSearchTime.year: '一年内',
};

const _orderLabels = {
  ForumThreadOrder.postedAt: '发表时间',
  ForumThreadOrder.lastPost: '最后发表',
  ForumThreadOrder.replies: '回复',
  ForumThreadOrder.hits: '人气',
};

/// Advanced thread search: one scrolling page whose form folds into a
/// summary once results arrive. Initial values let other screens open it
/// pre-filled (a board, a user, a title).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    this.initialKeyword = '',
    this.initialUsername = '',
    this.initialBoard,
  });

  final ForumRepository repository;
  final String initialKeyword;
  final String initialUsername;
  final ForumSearchBoard? initialBoard;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _keyword = TextEditingController(text: widget.initialKeyword);
  late final _username = TextEditingController(text: widget.initialUsername);
  final _scroll = ScrollController();

  ForumSearchPreferences _prefs = const ForumSearchPreferences();
  String? _prefsAccount;
  ForumSearchMatch _match = ForumSearchMatch.partial;
  late ForumSearchBoard _board = widget.initialBoard ?? _allBoards;
  ForumSearchTime _time = ForumSearchTime.year;
  ForumThreadOrder _order = ForumThreadOrder.postedAt;
  bool _ascending = false;
  bool _digest = false;
  // Saved defaults apply only until the user picks something.
  bool _matchTouched = false;
  bool _timeTouched = false;

  List<ForumSearchBoard>? _boards;
  // Per owner: board visibility differs between accounts.
  final _boardLoads = <String?, Future<List<ForumSearchBoard>>>{};

  bool _filtersOpen = false;
  bool _editing = true;
  String? _formError;

  ForumSearchQuery? _query;
  ForumSearchPage? _page;
  Future<ForumSearchPage> Function()? _lastRequest;
  Object? _error;
  bool _searching = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // A board known only by id (e.g. from a link) gets its name from the list.
    if (_board.name.isEmpty) _loadBoards().ignore();
  }

  String get _boardLabel =>
      _board.name.isEmpty ? '版块 ${_board.id}' : _board.name;

  @override
  void dispose() {
    _keyword.dispose();
    _username.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Preferences belong to the signed-in account (anonymous otherwise).
  String? get _account => widget.repository.currentUsername;

  Future<void> _loadPrefs() async {
    final account = _account;
    final prefs = await ForumSearchPreferences.load(account: account);
    // A login switch during the read must not apply the old owner's prefs.
    if (!mounted || account != _account) return;
    setState(() {
      _prefsAccount = account;
      _prefs = prefs;
      if (!_matchTouched) _match = prefs.defaultMatch;
      if (!_timeTouched) _time = prefs.defaultTime;
    });
  }

  // Board options cost a search.php request, so load them only when needed.
  Future<List<ForumSearchBoard>> _loadBoards() {
    final account = _account;
    return _boardLoads[account] ??= widget.repository.fetchSearchBoards().then(
      (boards) {
        final list = boards.any((board) => board.id == _allBoards.id)
            ? boards
            : [_allBoards, ...boards];
        if (mounted && account == _account) {
          setState(() {
            _boards = list;
            if (_board.name.isEmpty) {
              _board = list
                      .where((b) => b.selectable && b.id == _board.id)
                      .firstOrNull ??
                  _board;
            }
          });
        }
        return list;
      },
      onError: (Object error) {
        // A failed load may be retried.
        _boardLoads.remove(account);
        throw error;
      },
    );
  }

  bool get _filtersAtDefault =>
      _match == _prefs.defaultMatch &&
      _board.id == _allBoards.id &&
      _time == _prefs.defaultTime &&
      _order == ForumThreadOrder.postedAt &&
      !_ascending &&
      !_digest;

  void _resetFilters() {
    setState(() {
      _match = _prefs.defaultMatch;
      _board = _allBoards;
      _time = _prefs.defaultTime;
      _order = ForumThreadOrder.postedAt;
      _ascending = false;
      _digest = false;
    });
  }

  Future<void> _search() async {
    if (_searching) return;
    if (_prefsAccount != _account) {
      // Another login since the defaults were read: apply its defaults.
      setState(() => _searching = true);
      await _loadPrefs();
      if (!mounted) return;
      _searching = false;
    }
    final query = ForumSearchQuery(
      keyword: _keyword.text.trim(),
      username: _username.text.trim(),
      match: _match,
      boardId: _board.id,
      time: _time,
      order: _order,
      ascending: _ascending,
      digest: _digest,
    );
    if (query.keyword.isEmpty && query.username.isEmpty) {
      setState(() => _formError = '请输入关键词或用户名');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _query = query;
      _page = null;
    });
    _run(() => widget.repository.searchForum(query));
  }

  void _openPage(String pagePath) {
    // Pages follow the submitted query, never the form being edited.
    final query = _query;
    if (_searching || query == null) return;
    FocusScope.of(context).unfocus();
    _run(() => widget.repository.searchForumPage(query, pagePath));
  }

  Future<void> _run(Future<ForumSearchPage> Function() request) async {
    final id = ++_requestId;
    setState(() {
      _searching = true;
      _error = null;
      _lastRequest = request;
    });
    try {
      final page = await request();
      if (!mounted || id != _requestId) return;
      setState(() {
        _page = page;
        _searching = false;
        if (page.threads.isNotEmpty) _editing = false;
      });
      // Each new result page starts at its summary and first result.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
    } catch (error) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = error;
        _searching = false;
      });
    }
  }

  void _retry() {
    final request = _lastRequest;
    if (request != null && !_searching) _run(request);
  }

  Future<void> _pickTime() async {
    final value = await _showChoiceSheet<ForumSearchTime>(
      context,
      title: '时间范围',
      selected: _time,
      options: _timeLabels,
    );
    if (value == null || !mounted) return;
    setState(() {
      _time = value;
      _timeTouched = true;
    });
  }

  Future<void> _pickBoard() async {
    final account = _account;
    final picked = await showModalBottomSheet<ForumSearchBoard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BoardPickerSheet(
        selectedId: _board.id,
        loadBoards: _loadBoards,
        loadPinned: () async =>
            (await ForumSearchPreferences.load(account: account)).pinnedBoards,
        savePinned: (boards) =>
            ForumSearchPreferences.savePinnedBoards(boards, account: account),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _board = picked);
    // Pins may have changed inside the sheet.
    _loadPrefs();
  }

  Future<void> _saveDefaultMatch() async {
    await ForumSearchPreferences.saveDefaultMatch(_match, account: _account);
    await _loadPrefs();
  }

  Future<void> _saveDefaultTime() async {
    await ForumSearchPreferences.saveDefaultTime(_time, account: _account);
    await _loadPrefs();
  }

  List<String> _filterSummary(ForumSearchQuery? query) {
    final match = query?.match ?? _match;
    final time = query?.time ?? _time;
    final order = query?.order ?? _order;
    final ascending = query?.ascending ?? _ascending;
    final digest = query?.digest ?? _digest;
    final boardName = query == null || query.boardId == _board.id
        ? _boardLabel
        : _boards
                ?.where((board) => board.id == query.boardId)
                .firstOrNull
                ?.name ??
            '版块 ${query.boardId}';
    return [
      boardName,
      _timeLabels[time]!,
      _matchLabels[match]!,
      '${_orderLabels[order]} ${ascending ? '↑' : '↓'}',
      if (digest) '精华帖',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _editing || _query == null
                    ? _buildForm(context)
                    : _SearchSummary(
                        query: _query!,
                        filters: _filterSummary(_query),
                        onEdit: () => setState(() => _editing = true),
                      ),
              ),
            ),
            if (page != null && page.threads.isNotEmpty) ...[
              SliverPadding(
                // A fresh list per page, so old row offsets can't shift it.
                key: ObjectKey(page),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverList.list(
                  children: [
                    Text(
                      [
                        if (page.total != null) '共 ${page.total} 条结果',
                        '第 ${page.currentPage} 页',
                      ].join(' · '),
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 10),
                    for (final thread in page.threads) ...[
                      _SearchResultTile(
                        thread: thread,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ThreadDetailScreen(
                              thread: thread,
                              repository: widget.repository,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(child: _buildPager(page)),
              ),
            ] else
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildStatus(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final error = _error;
    if (error != null) {
      return AsyncErrorView(
        title: '搜索失败',
        message: _errorText(error),
        onRetry: _retry,
      );
    }
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final query = _query;
    if (_page != null && query != null) {
      return EmptyStateView(
        icon: Icons.manage_search_outlined,
        title: '没有找到相关主题',
        message: [
          if (query.keyword.isNotEmpty) '关键词：“${query.keyword}”',
          if (query.username.isNotEmpty) '用户名：“${query.username}”',
          '可尝试部分匹配、放宽时间范围或更换版块。',
        ].join('\n'),
      );
    }
    return const EmptyStateView(
      icon: Icons.search,
      title: '搜索主题',
      message: '输入关键词或用户名后搜索主题。',
    );
  }

  Widget _buildPager(ForumSearchPage page) {
    final previous = page.previousPagePath;
    final next = page.nextPagePath;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Text(
            '加载失败：${_errorText(error)}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _searching ? null : _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
          const SizedBox(height: 8),
        ],
        if (_searching) const LinearProgressIndicator(),
        if (previous != null || next != null || page.pageLinks.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: previous == null || _searching
                    ? null
                    : () => _openPage(previous),
                icon: const Icon(Icons.chevron_left),
                label: const Text('上一页'),
              ),
              if (page.pageLinks.isNotEmpty)
                TextButton(
                  onPressed: _searching ? null : () => _pickPage(page),
                  child: Text('第 ${page.currentPage} 页'),
                ),
              OutlinedButton.icon(
                onPressed:
                    next == null || _searching ? null : () => _openPage(next),
                icon: const Icon(Icons.chevron_right),
                label: const Text('下一页'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _pickPage(ForumSearchPage page) async {
    final path = await _showChoiceSheet<String>(
      context,
      title: '跳转页码',
      selected: null,
      options: {
        for (final link in page.pageLinks) link.path: '第 ${link.page} 页',
      },
    );
    if (path != null && mounted) _openPage(path);
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _keyword,
          autofocus:
              widget.initialKeyword.isEmpty && widget.initialUsername.isEmpty,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '关键词',
            hintText: '搜索主题标题',
            helperText: '多个关键词用空格或 | 分隔',
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _keyword.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空',
                    onPressed: () => setState(_keyword.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            labelText: '用户名',
            hintText: '只看该用户的主题',
            helperText: '可用 * 通配，例如 abc*',
            helperMaxLines: 2,
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 8),
        _FiltersHeader(
          open: _filtersOpen,
          summary: _filterSummary(null),
          onToggle: () {
            setState(() => _filtersOpen = !_filtersOpen);
            if (_filtersOpen) {
              _loadBoards().ignore();
              // This tab outlives logins; refresh prefs for a new owner.
              if (_prefsAccount != _account) _loadPrefs();
            }
          },
        ),
        if (_filtersOpen) ...[
          _SectionLabel(
            '匹配方式',
            action: _match == _prefs.defaultMatch
                ? null
                : _SetDefaultButton(onPressed: _saveDefaultMatch),
          ),
          _ChoiceWrap<ForumSearchMatch>(
            labels: _matchLabels,
            selected: _match,
            onSelected: (value) => setState(() {
              _match = value;
              _matchTouched = true;
            }),
          ),
          const SizedBox(height: 12),
          _PickerTile(
            label: '版块',
            value: _boardLabel,
            icon: Icons.dashboard_outlined,
            onTap: _pickBoard,
          ),
          const SizedBox(height: 8),
          _PickerTile(
            label: '时间范围',
            value: _timeLabels[_time]!,
            icon: Icons.schedule_outlined,
            onTap: _pickTime,
            trailing: _time == _prefs.defaultTime
                ? null
                : _SetDefaultButton(onPressed: _saveDefaultTime),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('排序'),
          _ChoiceWrap<ForumThreadOrder>(
            labels: _orderLabels,
            selected: _order,
            onSelected: (value) => setState(() => _order = value),
          ),
          const SizedBox(height: 8),
          _ChoiceWrap<bool>(
            labels: const {false: '降序', true: '升序'},
            selected: _ascending,
            onSelected: (value) => setState(() => _ascending = value),
          ),
          CheckboxListTile(
            value: _digest,
            onChanged: (value) => setState(() => _digest = value ?? false),
            title: const Text('只搜精华帖'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
        if (_formError != null) ...[
          const SizedBox(height: 4),
          Text(
            _formError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!_filtersAtDefault)
              OutlinedButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.restart_alt),
                label: const Text('重置筛选'),
              ),
            FilledButton.icon(
              key: const ValueKey('search-submit'),
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search),
              label: Text(_searching ? '搜索中...' : '搜索'),
            ),
          ],
        ),
      ],
    );
  }
}

String _errorText(Object error) => switch (error) {
      ForumRequestException(:final kind) => forumRequestErrorText(kind),
      ForumRepositoryException(:final message) => message,
      _ => '$error',
    };

Future<T?> _showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required T? selected,
  required Map<T, String> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final MapEntry(:key, :value) in options.entries)
                    ListTile(
                      title: Text(value),
                      selected: key == selected,
                      trailing:
                          key == selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(context).pop(key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FiltersHeader extends StatelessWidget {
  const _FiltersHeader({
    required this.open,
    required this.summary,
    required this.onToggle,
  });

  final bool open;
  final List<String> summary;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '筛选条件',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (!open) ...[
                    const SizedBox(height: 6),
                    _ChipSummary(items: summary),
                  ],
                ],
              ),
            ),
            Icon(open ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _ChipSummary extends StatelessWidget {
  const _ChipSummary({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceTint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _SetDefaultButton extends StatelessWidget {
  const _SetDefaultButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.push_pin_outlined, size: 16),
      label: const Text('设为默认'),
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(:key, :value) in labels.entries)
          ChoiceChip(
            label: Text(value),
            selected: key == selected,
            onSelected: (_) => onSelected(key),
          ),
      ],
    );
  }
}

/// A full-width field whose label sits above a freely wrapping value.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(value, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({
    required this.query,
    required this.filters,
    required this.onEdit,
  });

  final ForumSearchQuery query;
  final List<String> filters;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (query.keyword.isNotEmpty)
                  Text(query.keyword, style: theme.textTheme.titleMedium),
                if (query.username.isNotEmpty)
                  Text('用户：${query.username}',
                      style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                _ChipSummary(items: filters),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.tune),
            label: const Text('修改'),
          ),
        ],
      ),
    );
  }
}

class _BoardPickerSheet extends StatefulWidget {
  const _BoardPickerSheet({
    required this.selectedId,
    required this.loadBoards,
    required this.loadPinned,
    required this.savePinned,
  });

  final String selectedId;
  final Future<List<ForumSearchBoard>> Function() loadBoards;
  final Future<List<ForumSearchPinnedBoard>> Function() loadPinned;
  final Future<void> Function(List<ForumSearchPinnedBoard>) savePinned;

  @override
  State<_BoardPickerSheet> createState() => _BoardPickerSheetState();
}

class _BoardPickerSheetState extends State<_BoardPickerSheet> {
  final _filter = TextEditingController();
  late Future<List<ForumSearchBoard>> _boards = widget.loadBoards();
  List<ForumSearchPinnedBoard> _pinned = const [];

  @override
  void initState() {
    super.initState();
    widget.loadPinned().then((pinned) {
      if (mounted) setState(() => _pinned = pinned);
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _togglePin(ForumSearchBoard board) async {
    final pinned = _pinned.any((pin) => pin.id == board.id);
    List<ForumSearchPinnedBoard> next;
    if (pinned) {
      next = [
        for (final pin in _pinned)
          if (pin.id != board.id) pin,
      ];
    } else {
      final label = await _askLabel(board.name.trim());
      if (label == null || label.trim().isEmpty) return;
      next = [
        ..._pinned,
        ForumSearchPinnedBoard(id: board.id, label: label.trim()),
      ];
    }
    await widget.savePinned(next);
    final saved = await widget.loadPinned();
    if (mounted) setState(() => _pinned = saved);
  }

  Future<String?> _askLabel(String initial) => showDialog<String>(
        context: context,
        builder: (_) => _PinLabelDialog(initial: initial),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '查找版块',
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<ForumSearchBoard>>(
                  future: _boards,
                  builder: (context, snapshot) {
                    final boards = snapshot.data;
                    final filter = _filter.text.trim().toLowerCase();
                    final known = {
                      for (final board in boards ?? const <ForumSearchBoard>[])
                        if (board.selectable) board.id,
                    };
                    return ListView(
                      children: [
                        if (_pinned.isNotEmpty) ...[
                          _SheetHeader('版块捷径'),
                          for (final pin in _pinned)
                            if (filter.isEmpty ||
                                pin.label.toLowerCase().contains(filter))
                              _pinTile(
                                pin,
                                // Unknown until the server list is in.
                                boards == null ? null : known.contains(pin.id),
                              ),
                          const Divider(),
                        ],
                        _SheetHeader('全部版块'),
                        if (snapshot.hasError)
                          ListTile(
                            leading: Icon(Icons.error_outline,
                                color: theme.colorScheme.error),
                            title: const Text('版块列表加载失败'),
                            trailing: TextButton(
                              onPressed: () => setState(() {
                                _boards = widget.loadBoards();
                              }),
                              child: const Text('重试'),
                            ),
                          )
                        else if (boards == null)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          for (final board in boards)
                            if (filter.isEmpty ||
                                board.name.toLowerCase().contains(filter))
                              _boardTile(board),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinTile(ForumSearchPinnedBoard pin, bool? exists) {
    return ListTile(
      leading: Icon(
        switch (exists) {
          true => Icons.bookmark,
          false => Icons.warning_amber_outlined,
          null => Icons.bookmark_border,
        },
        color: exists == false
            ? Theme.of(context).colorScheme.error
            : AppColors.brand,
      ),
      title: Text(pin.label),
      subtitle: switch (exists) {
        true => null,
        false => const Text('此版块已不存在，无法搜索'),
        null => const Text('版块列表加载后可选'),
      },
      selected: pin.id == widget.selectedId,
      enabled: exists == true,
      onTap: () => Navigator.of(context)
          .pop(ForumSearchBoard(id: pin.id, name: pin.label)),
      trailing: IconButton(
        tooltip: '删除捷径',
        icon: const Icon(Icons.close),
        onPressed: () =>
            _togglePin(ForumSearchBoard(id: pin.id, name: pin.label)),
      ),
    );
  }

  Widget _boardTile(ForumSearchBoard board) {
    final indent = 16.0 + 16.0 * board.depth.clamp(0, 4);
    if (!board.selectable) {
      return Padding(
        padding: EdgeInsets.fromLTRB(indent, 12, 16, 4),
        child: Text(
          board.name,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      );
    }
    final pinned = _pinned.any((pin) => pin.id == board.id);
    final canPin = board.id != _allBoards.id;
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent, right: 4),
      title: Text(board.name),
      selected: board.id == widget.selectedId,
      onTap: () => Navigator.of(context).pop(board),
      trailing: canPin
          ? IconButton(
              tooltip: pinned ? '删除捷径' : '存为捷径',
              icon: Icon(pinned ? Icons.bookmark : Icons.bookmark_add_outlined),
              onPressed: () => _togglePin(board),
            )
          : null,
    );
  }
}

// Owns its controller so the closing animation never sees it disposed.
class _PinLabelDialog extends StatefulWidget {
  const _PinLabelDialog({required this.initial});

  final String initial;

  @override
  State<_PinLabelDialog> createState() => _PinLabelDialogState();
}

class _PinLabelDialogState extends State<_PinLabelDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('存为捷径'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '显示名称'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.thread, required this.onTap});

  final ForumThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                thread.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (thread.section.isNotEmpty)
                    _SearchMetaChip(
                      icon: Icons.tag_outlined,
                      text: thread.section,
                    ),
                  if (thread.author != null)
                    _SearchMetaChip(
                      icon: Icons.person_outline,
                      text: thread.author!,
                    ),
                  if (thread.lastPost != null)
                    _SearchMetaChip(
                      icon: Icons.schedule_outlined,
                      text: thread.lastPost!,
                    ),
                  _SearchMetaChip(
                    icon: Icons.chat_bubble_outline,
                    text: '${thread.replies} 回复',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchMetaChip extends StatelessWidget {
  const _SearchMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
