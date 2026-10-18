import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../services/forum_url_resolver.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/thread_row.dart';
import '../thread/thread_detail_screen.dart';
import 'favorite_collections_sheets.dart';

/// The 收藏 tab: the signed-in account's favourite threads, by category.
///
/// Every list is a snapshot of what the forum returned for one view (all, or
/// one category). Each change is one request answered with a fresh snapshot;
/// nothing is assumed from an acknowledgement alone, and a result that is not
/// known locks writing until the list has been read again.
class FavoriteThreadsPage extends StatefulWidget {
  const FavoriteThreadsPage({
    super.key,
    required this.repository,
    this.onLoginTap,
  });

  final ForumRepository repository;
  final VoidCallback? onLoginTap;

  @override
  State<FavoriteThreadsPage> createState() => _FavoriteThreadsPageState();
}

/// Why 移动到… is off when every category already holds the rows.
const _noTarget = '暂无其他分类，请先新建';

class _FavoriteThreadsPageState extends State<FavoriteThreadsPage> {
  FavoriteCollections? _data;
  Object? _error;
  bool _loading = false;

  /// The category asked for; null is every favourite.
  String? _view;

  /// Moves on every load and every session change; a reply for an older
  /// value is dropped.
  int _epoch = 0;

  /// Native row ids, not addresses.
  final _selected = <String>{};
  bool _selecting = false;

  /// One write at a time.
  bool _busy = false;

  /// Set while the outcome of a write is not known: nothing is written until
  /// the list has been read again.
  String? _unconfirmed;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prime());
  }

  @override
  void didUpdateWidget(covariant FavoriteThreadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.sessionEpoch.removeListener(_onSession);
      widget.repository.sessionEpoch.addListener(_onSession);
      _forget();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _prime());
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_onSession);
    super.dispose();
  }

  // Another account's categories and rows must not stay visible.
  void _forget() {
    _epoch++;
    _data = null;
    _error = null;
    _loading = false;
    _view = null;
    _selected.clear();
    _selecting = false;
    _busy = false;
    _unconfirmed = null;
  }

  void _onSession() {
    if (!mounted) return;
    setState(_forget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _prime());
  }

  void _prime() {
    if (!mounted || !widget.repository.isLoggedIn) return;
    if (_data == null && !_loading && _error == null) _load();
  }

  /// [keep]: rows still to be chosen once the list is back (what a partial
  /// answer left unfinished), if the forum still lists them.
  Future<void> _load({String? view, Set<String> keep = const {}}) async {
    // Category numbers can shift on the forum; the name tells which one this is.
    final asked = view == null ? null : _labelOf(_data, view);
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
      _view = view;
      _selected.clear();
      _selecting = false;
    });
    try {
      final data =
          await widget.repository.fetchFavoriteCollections(categoryId: view);
      if (!mounted || epoch != _epoch) return;
      if (view != null && asked != null && _labelOf(data, view) != asked) {
        // Another category has that number now: start from all instead.
        _load(keep: keep);
        return;
      }
      setState(() {
        _data = data;
        _view = data.categoryId;
        final present = {for (final e in data.items) e.id};
        _selected.addAll(keep.where(present.contains));
        _selecting = _selected.isNotEmpty;
        _loading = false;
        _unconfirmed = null;
      });
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() {
    if (_busy || !widget.repository.isLoggedIn) return Future.value();
    // After an unknown result the view's number may be gone or reused: read
    // the list of everything, which always exists.
    return _unconfirmed != null ? _load() : _load(view: _view);
  }

  List<FavoriteCollectionEntry> get _chosen => [
        for (final entry in _data?.items ?? const <FavoriteCollectionEntry>[])
          if (_selected.contains(entry.id)) entry,
      ];

  /// No write while one runs, while a result is unknown, while rows load, or
  /// while the rows shown are not the ones asked for (a failed load).
  bool get _locked =>
      _busy || _unconfirmed != null || _loading || _error != null;

  /// Switching views waits for a running request and for an unknown result
  /// to be read again; a failed load can be left by choosing another view.
  bool get _switching => _busy || _loading || _unconfirmed != null;

  /// Runs one write against the snapshot on screen and shows only what the
  /// forum's fresh answer proves.
  Future<FavoriteMutationStatus?> _write(
    Future<FavoriteCollectionMutation> Function(FavoriteCollections snapshot)
        run, {
    required String Function(int done) done,
    int count = 1,
    bool reloadAfter = false,
    bool keepSelection = false,
  }) async {
    final snapshot = _data;
    if (snapshot == null || _locked) return null;
    final epoch = _epoch;
    final viewBefore = _view;
    final labelBefore =
        viewBefore == null ? null : _labelOf(snapshot, viewBefore);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final FavoriteCollectionMutation result;
    try {
      result = await run(snapshot);
    } catch (error) {
      if (!mounted || epoch != _epoch) return null;
      // Whether the forum took the write is known only when it said so.
      final unknown = error is ForumRequestException &&
          (error.kind == ForumRequestKind.server ||
              error.kind == ForumRequestKind.network);
      setState(() {
        _busy = false;
        if (unknown) _unconfirmed = '结果未确认，请刷新核对';
      });
      messenger.showSnackBar(SnackBar(content: Text(forumErrorText(error))));
      return null;
    }
    if (!mounted || epoch != _epoch) return null;
    final fresh = result.collections;
    final unfinished = {
      for (final item in result.items)
        if (item.status != FavoriteMutationStatus.confirmed) item.id,
    };
    final finished =
        result.items.isEmpty ? count : result.items.length - unfinished.length;
    var text = '';
    setState(() {
      _busy = false;
      if (fresh != null) {
        _data = fresh;
        _view = fresh.categoryId;
      }
      switch (result.status) {
        case FavoriteMutationStatus.confirmed:
          if (unfinished.isEmpty) {
            if (!keepSelection) {
              _selected.clear();
              _selecting = false;
            }
            text = done(finished);
          } else {
            // Those the forum still holds stay selected for another try.
            _keepUnfinished(unfinished, fresh);
            text = '已完成 $finished 个，还有 ${unfinished.length} 个未完成';
          }
        case FavoriteMutationStatus.rejected:
          if (finished > 0 && unfinished.isNotEmpty) {
            // Some went through: only what the forum still holds stays chosen.
            _keepUnfinished(unfinished, fresh);
            text = '已完成 $finished 个，还有 ${unfinished.length} 个未完成';
          } else {
            text = result.message;
            if (fresh != null) {
              final present = {for (final e in fresh.items) e.id};
              _selected.retainAll(present);
            }
          }
        case FavoriteMutationStatus.unknown:
          // Whatever else came back, the result as a whole is not known.
          _unconfirmed = '结果未确认，请刷新核对';
          _selected.clear();
          _selecting = false;
          text = result.message.isEmpty ? _unconfirmed! : result.message;
      }
    });
    messenger.showSnackBar(SnackBar(content: Text(text)));
    if (_unconfirmed != null) return result.status;
    if (keepSelection) {
      if (fresh == null) await _load(keep: Set.of(_selected));
      return result.status;
    }
    // Without a fresh list the screen holds an old one: read it again.
    if (fresh == null) {
      _load(view: _view);
    } else if (reloadAfter) {
      // Numbers shift when a category goes: start from all again.
      if (viewBefore != null) _load();
    } else if (viewBefore != null) {
      // The answer is the list of everything; go back to the category asked
      // for, found again by its name, never by its old number. Not found or
      // ambiguous: the list of everything stays.
      final named = [
        for (final c in fresh.categories)
          if (c.label == labelBefore) c,
      ];
      if (named.length == 1) {
        _load(view: named.single.id, keep: Set.of(_selected));
      }
    }
    return result.status;
  }

  Future<void> _remove(List<FavoriteCollectionEntry> entries) async {
    if (entries.isEmpty || _locked) return;
    final epoch = _epoch;
    final ok = await showRemoveFavoritesDialog(
      context,
      session: widget.repository.sessionEpoch,
      titles: [for (final e in entries) e.thread.title],
    );
    if (!ok || !mounted || epoch != _epoch) return;
    await _write(
      (snapshot) => widget.repository.removeFavorites(snapshot, entries),
      done: (n) => n == 1 ? '已取消收藏' : '已取消收藏 $n 个',
      count: entries.length,
    );
  }

  String? _tid(FavoriteCollectionEntry entry) => entry.thread.threadId ??
      ForumUrlResolver(baseUri: widget.repository.networkConfig.baseUri).tidFromUrl(entry.thread.url);

  bool _knownSources(List<FavoriteCollectionEntry> entries) => entries.isNotEmpty && entries.every((entry) =>
      _tid(entry) != null && entry.categoryId != null &&
      _data!.categories.where((c) => c.id == entry.categoryId).length == 1);

  List<FavoriteCategory> _destinations(List<FavoriteCollectionEntry> entries) =>
      _data == null || !_knownSources(entries) ? [] : [
        for (final category in _data!.categories)
          if (!entries.every((entry) => entry.categoryId == category.id)) category,
      ];

  String? _moveHint(List<FavoriteCollectionEntry> entries) {
    if (entries.isEmpty) return null;
    if (!_knownSources(entries)) return '分类信息未确认，请刷新';
    return _destinations(entries).isEmpty ? _noTarget : null;
  }

  Future<void> _move(List<FavoriteCollectionEntry> entries) async {
    if (entries.isEmpty || _data == null || _locked || !_knownSources(entries)) return;
    final session = widget.repository.sessionEpoch.value;
    final wasSelecting = _selecting;
    final pending = {for (final entry in entries) entry.id: _tid(entry)!};
    var categoryChanged = false;
    // A category create/delete answers with the list of everything. Closing
    // the sheet afterwards goes back to the category the user came from, found
    // again by name, with the pending choice kept. Not after an unknown
    // result, a failed read or a session change; and a deleted source stays
    // in 全部.
    final viewLabel = _view == null ? null : _labelOf(_data, _view);
    Future<void> restoreView() async {
      if (!categoryChanged || viewLabel == null || _view != null) return;
      if (!mounted || session != widget.repository.sessionEpoch.value || _locked) return;
      final named = [
        for (final c in _data!.categories)
          if (c.label == viewLabel) c,
      ];
      if (named.length != 1) return;
      await _load(
          view: named.single.id,
          keep: wasSelecting ? Set.of(_selected) : const {});
    }
    while (mounted && session == widget.repository.sessionEpoch.value && !_locked) {
      final data = _data!;
      final rebound = <FavoriteCollectionEntry>[];
      for (final request in pending.entries) {
        final matches = data.items.where((entry) => entry.id == request.key && _tid(entry) == request.value).toList();
        if (matches.length == 1) rebound.add(matches.single);
      }
      if (rebound.length != pending.length) {
        // Said now, not queued behind the create/delete confirmation.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('部分所选主题不在当前页，请重新选择')));
        pending.removeWhere((id, _) => !rebound.any((entry) => entry.id == id));
      }
      if (wasSelecting) setState(() {
        _selected..clear()..addAll(pending.keys);
        _selecting = _selected.isNotEmpty;
      });
      if (rebound.isEmpty || !_knownSources(rebound)) return;
      final action = await showMoveSheet(context,
        session: widget.repository.sessionEpoch, categories: data.categories,
        count: rebound.length, canCreate: data.canCreate, categoryChanged: categoryChanged,
        unavailableCategoryIds: {for (final c in data.categories)
          if (rebound.every((entry) => entry.categoryId == c.id)) c.id},
      );
      if (action == null) {
        await restoreView();
        return;
      }
      if (!mounted || session != widget.repository.sessionEpoch.value || _locked) return;
      if (action is MoveDestination) {
        final intended = action.category;
        final targets = _data!.categories.where((c) => intended.isDefault
            ? c.isDefault : !c.isDefault && c.label.trim() == intended.label.trim()).toList();
        if (targets.length != 1) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分类已变化，请刷新后重试')));
          return;
        }
        final target = targets.single;
        await _write((snapshot) => widget.repository.moveFavorites(snapshot, rebound, target.id),
          done: (n) => '已移动 $n 个到「${target.label}」', count: rebound.length);
        return;
      }
      ManageAction? manage;
      if (action is CreateMoveCategory) {
        manage = const CreateCategory();
      } else {
        manage = await showManageCategoriesSheet(context,
          session: widget.repository.sessionEpoch, data: _data!);
      }
      if (!mounted || session != widget.repository.sessionEpoch.value || _locked) return;
      if (manage != null) {
        final result = await _applyManageAction(manage, keepSelection: true);
        if (!mounted || session != widget.repository.sessionEpoch.value || _locked) return;
        categoryChanged = categoryChanged || result == FavoriteMutationStatus.confirmed;
      }
    }
  }

  Future<void> _manage() async {
    final data = _data;
    if (data == null || _locked) return;
    final epoch = _epoch;
    final action = await showManageCategoriesSheet(
      context,
      session: widget.repository.sessionEpoch,
      data: data,
    );
    if (action == null || !mounted || epoch != _epoch) return;
    await _applyManageAction(action);
  }

  Future<FavoriteMutationStatus?> _applyManageAction(ManageAction action, {bool keepSelection = false}) async {
    final data = _data;
    if (data == null || _locked) return null;
    final epoch = _epoch;
    switch (action) {
      case CreateCategory():
        final name = await showNewCategoryDialog(
          context,
          session: widget.repository.sessionEpoch,
          maxLength: data.nameMaxLength,
        );
        if (name == null ||
            name.trim().isEmpty ||
            !mounted ||
            epoch != _epoch) {
          return null;
        }
        return _write(
          (snapshot) =>
              widget.repository.createFavoriteCategory(snapshot, name.trim()),
          done: (_) => '已新建分类「${name.trim()}」',
          keepSelection: keepSelection,
        );
      case DeleteCategory(:final category):
        final ok = await showDeleteCategoryDialog(
          context,
          session: widget.repository.sessionEpoch,
          category: category,
        );
        if (!ok || !mounted || epoch != _epoch) return null;
        final targets = _data!.categories.where((c) => !c.isDefault && c.label.trim() == category.label.trim()).toList();
        if (targets.length != 1) {
          // Never fall back to the number: say why nothing was sent.
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('分类名称重复，请在原站整理后重试')));
          return null;
        }
        return _write(
          (snapshot) => widget.repository.deleteFavoriteCategory(snapshot, targets.single.id),
          done: (_) => '已删除分类「${category.label}」，其中的主题已移到默认分类',
          reloadAfter: true,
          keepSelection: keepSelection,
        );
    }
  }

  // Only rows that are on the screen can stay chosen; none left ends choosing.
  void _keepUnfinished(Set<String> unfinished, FavoriteCollections? fresh) {
    _selected.retainAll(unfinished);
    if (fresh != null) {
      _selected.retainAll({for (final e in fresh.items) e.id});
    }
    _selecting = _selected.isNotEmpty;
  }

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  void _startSelecting([String? id]) {
    if (_locked || (_data?.items.isEmpty ?? true)) return;
    setState(() {
      _selecting = true;
      if (id != null) _selected.add(id);
    });
  }

  void _stopSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isLoggedIn) {
      return SafeArea(
        bottom: false,
        child: LoginPrompt(
          icon: Icons.star_outline,
          title: '收藏',
          message: '登录后，在帖子里收藏的主题会集中在这里。',
          onLogin:
              widget.onLoginTap ?? () => openLogin(context, widget.repository),
        ),
      );
    }
    final data = _data;
    final items = data?.items ?? const <FavoriteCollectionEntry>[];
    final Widget body;
    if (_error != null) {
      // Whatever view was loaded before is not shown under this one's name.
      body = AsyncErrorView(
        title: '收藏加载失败',
        message: forumErrorText(_error),
        onRetry: () => _load(view: _view),
      );
    } else if (data == null || _loading) {
      body = const ThreadRowSkeleton(itemCount: 6);
    } else if (items.isEmpty) {
      // Only the whole list being on this page says there is nothing at all.
      final complete = _pageNote(data) == null;
      body = EmptyStateView(
        title: !complete
            ? '本页没有主题'
            : _view == null
                ? '还没有收藏'
                : '这个分类还没有主题',
        message: !complete
            ? '${_pageNote(data)}，下拉刷新再看看。'
            : _view == null
                ? '在帖子页点「收藏」，主题会出现在这里。'
                : null,
        icon: Icons.star_outline,
      );
    } else {
      body = DecoratedBox(
        decoration: appSurface(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, entry) in items.indexed) ...[
              if (i > 0) const Divider(indent: AppSpace.lg),
              _FavoriteRow(
                key: ValueKey('favorite-row:${entry.id}'),
                entry: entry,
                categoryLabel: _view == null && data.categories.length > 1
                    ? _labelOf(data, entry.categoryId)
                    : null,
                repository: widget.repository,
                selecting: _selecting,
                selected: _selected.contains(entry.id),
                enabled: !_locked,
                onToggle: () => _toggle(entry.id),
                onSelect: () => _startSelecting(entry.id),
                onRemove: () => _remove([entry]),
                onMove: () => _move([entry]),
                moveHint: _moveHint([entry]),
                onMoveCategories: _knownSources([entry]) ? () => _move([entry]) : null,
              ),
            ],
          ],
        ),
      );
    }
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _refresh,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side =
                        appGutter(constraints.maxWidth, AppWidths.list);
                    return ListView(
                      padding: EdgeInsets.fromLTRB(side, 8, side, 32),
                      children: [
                        _Header(
                          count: data == null || _loading || _error != null
                              ? null
                              : items.length,
                          page: data == null ? null : _pageNote(data),
                          selecting: _selecting,
                          selected: _selected.length,
                          allSelected: items.isNotEmpty &&
                              _selected.length == items.length,
                          canSelect:
                              data != null && items.isNotEmpty && !_locked,
                          onStart: _startSelecting,
                          onAll: () => setState(() {
                            if (_selected.length == items.length) {
                              _selected.clear();
                            } else {
                              _selected.addAll([for (final e in items) e.id]);
                            }
                          }),
                          onExit: _stopSelecting,
                        ),
                        if (_busy) const LinearProgressIndicator(minHeight: 2),
                        if (_unconfirmed case final text?)
                          _Notice(text: text, onRefresh: _refresh),
                        if (data != null && !_selecting) ...[
                          const SizedBox(height: 4),
                          _Views(
                            data: data,
                            view: _view,
                            enabled: !_switching,
                            canManage: !_locked,
                            onView: (id) => _load(view: id),
                            onManage: _manage,
                          ),
                        ],
                        const SizedBox(height: 8),
                        body,
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_selecting)
              _SelectionBar(
                count: _selected.length,
                busy: _locked,
                onMove: () => _move(_chosen),
                moveHint: _moveHint(_chosen),
                onManageMove: _knownSources(_chosen) ? () => _move(_chosen) : null,
                onRemove: () => _remove(_chosen),
              ),
          ],
        ),
      ),
    );
  }

  // Said only when the forum has more than the page shown, or when that is
  // not known.
  String? _pageNote(FavoriteCollections data) {
    final count = data.pageCount;
    if (count == null) return '页数未能确认';
    return count > 1 ? '第 ${data.page}/$count 页' : null;
  }

  String? _labelOf(FavoriteCollections? data, String? id) {
    if (data == null || id == null) return null;
    for (final c in data.categories) {
      if (c.id == id) return c.label;
    }
    return null;
  }
}

/// 收藏 and how many are shown; while choosing, how many are chosen.
class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.page,
    required this.selecting,
    required this.selected,
    required this.allSelected,
    required this.canSelect,
    required this.onStart,
    required this.onAll,
    required this.onExit,
  });

  final int? count;

  /// Set when the forum has more pages than the one shown.
  final String? page;
  final bool selecting;
  final int selected;
  final bool allSelected;
  final bool canSelect;
  final VoidCallback onStart;
  final VoidCallback onAll;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: selecting
          ? Row(
              children: [
                IconButton(
                  key: const ValueKey('favorite-select-exit'),
                  tooltip: '完成',
                  icon: const Icon(Icons.close),
                  onPressed: onExit,
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text('已选 $selected 个',
                        style: theme.textTheme.titleMedium),
                  ),
                ),
                TextButton(
                  key: const ValueKey('favorite-select-all'),
                  onPressed: onAll,
                  child: Text(allSelected ? '取消全选' : '全选已加载'),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('收藏', style: theme.textTheme.headlineSmall),
                if (count != null && (count! > 0 || page != null)) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        '已加载 $count 个主题${page == null ? '' : ' · $page'}',
                        style: theme.textTheme.bodySmall),
                  ),
                  if (count! > 0)
                    TextButton(
                      key: const ValueKey('favorite-select-start'),
                      onPressed: canSelect ? onStart : null,
                      child: const Text('选择'),
                    ),
                ],
              ],
            ),
    );
  }
}

/// 全部 and each category the forum has, then 管理.
class _Views extends StatelessWidget {
  const _Views({
    required this.data,
    required this.view,
    required this.enabled,
    required this.canManage,
    required this.onView,
    required this.onManage,
  });

  final FavoriteCollections data;
  final String? view;
  final bool enabled;
  final bool canManage;
  final ValueChanged<String?> onView;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    // The chosen view always reads as chosen, even while another loads; only
    // the others fade when the row is inert. An active tap does nothing.
    Widget chip(String key, String label, bool on, String? id) => ChoiceChip(
          key: ValueKey('favorite-folder:$key'),
          label: Text(label),
          selected: on,
          onSelected: enabled
              ? (_) {
                  if (!on) onView(id);
                }
              : null,
          showCheckmark: true,
          checkmarkColor: AppColors.brand,
          selectedColor: AppColors.brandSoft,
          backgroundColor: AppColors.surface,
          disabledColor: on ? AppColors.brandSoft : AppColors.surface,
          side: BorderSide(
            color: on
                ? AppColors.brand.withValues(alpha: 0.35)
                : AppColors.border,
          ),
          shape: const StadiumBorder(),
          labelStyle: TextStyle(
            color: on
                ? AppColors.brandDark
                : enabled
                    ? AppColors.text
                    : AppColors.textFaint,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('all', '全部', view == null, null),
          for (final c in data.categories) ...[
            const SizedBox(width: AppSpace.sm),
            chip(
              c.id,
              c.count == null ? c.label : '${c.label} ${c.count}',
              view == c.id,
              c.id,
            ),
          ],
          const SizedBox(width: AppSpace.sm),
          const SizedBox(height: 24, child: VerticalDivider(width: AppSpace.md)),
          ActionChip(
            key: const ValueKey('favorite-manage'),
            avatar: Icon(Icons.tune, size: 18, color: canManage ? AppColors.brand : AppColors.textFaint),
            label: const Text('管理'),
            shape: const StadiumBorder(),
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.border),
            labelStyle: TextStyle(color: canManage ? AppColors.text : AppColors.textFaint),
            onPressed: canManage ? onManage : null,
          ),
        ],
      ),
    );
  }
}

/// A line that stays until the list is read again.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.onRefresh});

  final String text;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Semantics(
        liveRegion: true,
        child: ListTile(
          key: const ValueKey('favorite-unconfirmed'),
          dense: true,
          tileColor: Theme.of(context).colorScheme.errorContainer,
          leading: const Icon(Icons.info_outline),
          title: Text(text),
          trailing: TextButton(
            key: const ValueKey('favorite-refresh'),
            onPressed: onRefresh,
            child: const Text('刷新'),
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onMove,
    required this.onRemove,
    this.moveHint,
    this.onManageMove,
  });

  final String? moveHint;
  final VoidCallback? onManageMove;
  final int count;
  final bool busy;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = count > 0 && !busy;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Why 移动到… is off, and the way out when it is for lack of
              // a destination.
              if (moveHint != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Row(children: [
                    Icon(Icons.info_outline,
                        size: 18, color: AppColors.textMuted),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                        child:
                            Text(moveHint!, style: theme.textTheme.bodySmall)),
                    if (moveHint == _noTarget && onManageMove != null)
                      TextButton(
                        key: const ValueKey('favorite-move-manage-selected'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.brand),
                        onPressed: enabled ? onManageMove : null,
                        child: const Text('新建或管理分类'),
                      ),
                  ]),
                ),
              Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('favorite-move'),
                onPressed: enabled && moveHint == null ? onMove : null,
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('移动到…'),
              ),
              FilledButton.icon(
                key: const ValueKey('favorite-remove-selected'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.star_outline),
                label: const Text('取消收藏'),
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

/// A favourite: opens the thread, or is chosen while choosing; long-press or
/// ⋯ offers 移动到… and 取消收藏.
class _FavoriteRow extends StatefulWidget {
  const _FavoriteRow({
    super.key,
    required this.entry,
    required this.categoryLabel,
    required this.repository,
    required this.selecting,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.onSelect,
    required this.onRemove,
    required this.onMove,
    this.moveHint,
    this.onMoveCategories,
  });

  final String? moveHint;
  final VoidCallback? onMoveCategories;
  final FavoriteCollectionEntry entry;
  final String? categoryLabel;
  final ForumRepository repository;
  final bool selecting;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  final VoidCallback onMove;

  @override
  State<_FavoriteRow> createState() => _FavoriteRowState();
}

class _FavoriteRowState extends State<_FavoriteRow> {
  final _menu = GlobalKey<PopupMenuButtonState<void>>();

  @override
  Widget build(BuildContext context) {
    final item = widget.entry.thread;
    return ForumThreadRow(
      title: item.title,
      meta: [
        if (widget.categoryLabel != null) widget.categoryLabel!,
        if (item.section != null) item.section!,
        if (item.author != null) item.author!,
        if (item.date != null) item.date!,
        if (item.replies != null) '${item.replies} 回复',
      ],
      onTap: widget.selecting
          ? widget.onToggle
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ThreadDetailScreen(
                    thread: ForumThread(
                      title: item.title,
                      url: item.url,
                      replies: item.replies ?? 0,
                      section: item.section ?? '收藏',
                      author: item.author,
                      authorUrl: item.authorUrl,
                      lastPost: item.date,
                    ),
                    repository: widget.repository,
                  ),
                ),
              ),
      onLongPress: !widget.enabled
          ? null
          : widget.selecting
              ? widget.onToggle
              : () => _menu.currentState?.showButtonMenu(),
      trailing: widget.selecting
          ? Semantics(
              label: '选择 ${item.title}',
              child: Checkbox(
                key: ValueKey('favorite-select:${widget.entry.id}'),
                value: widget.selected,
                onChanged: (_) => widget.onToggle(),
              ),
            )
          : PopupMenuButton<void>(
              key: _menu,
              enabled: widget.enabled,
              tooltip: '更多',
              icon: Icon(Icons.more_horiz, color: AppColors.textMuted),
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: widget.onSelect,
                  child: const Row(
                    children: [
                      Icon(Icons.checklist, size: 20),
                      SizedBox(width: AppSpace.md),
                      Text('多选'),
                    ],
                  ),
                ),
                // Genuinely disabled when there is nowhere to go; the hint
                // says why and the next item is the way out.
                PopupMenuItem(
                  key: ValueKey('favorite-row-move:${widget.entry.id}'),
                  enabled: widget.moveHint == null,
                  onTap: widget.moveHint == null ? widget.onMove : null,
                  child: Row(children: [
                    const Icon(Icons.drive_file_move_outline, size: 20),
                    const SizedBox(width: AppSpace.md),
                    Flexible(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('移动到…'),
                        if (widget.moveHint != null)
                          Text(widget.moveHint!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textFaint)),
                      ],
                    )),
                  ]),
                ),
                if (widget.moveHint == _noTarget &&
                    widget.onMoveCategories != null)
                  PopupMenuItem(
                    key: ValueKey(
                        'favorite-row-move-manage:${widget.entry.id}'),
                    onTap: widget.onMoveCategories,
                    child: const Row(children: [
                      Icon(Icons.create_new_folder_outlined, size: 20),
                      SizedBox(width: AppSpace.md),
                      Text('新建或管理分类…'),
                    ]),
                  ),
                PopupMenuItem(
                  onTap: widget.onRemove,
                  child: const Row(
                    children: [
                      Icon(Icons.star_outline, size: 20),
                      SizedBox(width: AppSpace.md),
                      Text('取消收藏'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
