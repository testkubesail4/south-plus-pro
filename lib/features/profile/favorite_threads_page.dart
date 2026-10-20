import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/favorite_search.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../services/forum_url_resolver.dart';
import '../../services/full_scan.dart';
import '../../services/keyword_match.dart';
import '../../services/loading_preferences.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/app_switcher.dart';
import '../common/app_tab_header.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/leave_watch.dart';
import '../common/page_end.dart';
import '../common/search_scope_bar.dart';
import '../common/thread_row.dart';
import '../common/unresolved_group.dart';
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

class _FavoriteThreadsPageState extends State<FavoriteThreadsPage>
    with LeaveWatch<FavoriteThreadsPage> {
  FavoriteCollections? _data;
  Object? _error;
  bool _loading = false;

  /// The category asked for; null is every favourite.
  String? _view;
  // Which way the last category change moved along the chips.
  int _slide = 0;

  /// Moves on every load and every session change; a reply for an older
  /// value is dropped.
  int _epoch = 0;

  /// Native row ids, not addresses.
  final _selected = <String>{};
  bool _selecting = false;

  /// 自动接续: the pages read after [_data], in order. A row a page repeats
  /// is shown once; a write goes to the page its rows came from.
  final _more = <FavoriteCollections>[];
  bool _loadingMore = false;
  Object? _moreError;
  // Pages in a row that added no row; two pause 自动接续.
  int _emptyRun = 0;
  final _scroll = ScrollController();

  /// One write at a time.
  bool _busy = false;

  /// Set while the outcome of a write is not known: nothing is written until
  /// the list has been read again.
  String? _unconfirmed;

  /// 搜索收藏: the keyword filters the page on screen; a scan of every page
  /// runs only once asked, and its rows only open threads.
  bool _searchOpen = false;
  final _query = TextEditingController();
  FullScan<FavoriteSearchHit>? _scan;

  /// Moves with every keyword, view and scan; a scan confirmed under an
  /// older value never starts.
  int _searchGen = 0;
  bool _unresolvedOpen = false;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSession);
    _scroll.addListener(_maybeLoadMore);
    LoadingPreferences.notifier.addListener(_onLoadingModeChanged);
    if (!LoadingPreferences.isReady) LoadingPreferences.load().ignore();
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
    LoadingPreferences.notifier.removeListener(_onLoadingModeChanged);
    _dropScan();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 自动接续; otherwise (手动翻页, or the setting unread) pages turn by tap.
  bool get _continuous =>
      LoadingPreferences.modeFor(LoadingDomain.favorites) ==
      LoadingMode.continuous;

  // The footer follows the mode; a page already on its way still lands.
  void _onLoadingModeChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  void _clearMore() {
    _more.clear();
    _loadingMore = false;
    _moreError = null;
    _emptyRun = 0;
  }

  FavoriteCollections? get _lastPage => _more.isEmpty ? _data : _more.last;

  int? get _nextPage {
    final last = _lastPage;
    final count = last?.pageCount;
    return last == null || count == null || last.page >= count
        ? null
        : last.page + 1;
  }

  /// Each row once, in page order, with the page it was read on.
  Map<String, FavoriteCollections> get _pageOf {
    final pages = <String, FavoriteCollections>{};
    for (final page in [if (_data case final data?) data, ..._more]) {
      for (final entry in page.items) {
        pages.putIfAbsent(entry.id, () => page);
      }
    }
    return pages;
  }

  List<FavoriteCollectionEntry> get _items {
    final data = _data;
    if (data == null) return const [];
    if (_more.isEmpty) return data.items;
    final seen = <String>{};
    return [
      for (final page in [data, ..._more])
        for (final entry in page.items)
          if (seen.add(entry.id)) entry,
    ];
  }

  void _maybeLoadMore() {
    if (!mounted ||
        !_continuous ||
        _nextPage == null ||
        _loading ||
        _error != null ||
        _scan != null ||
        _loadingMore ||
        _moreError != null ||
        _emptyRun >= 2 ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    if (position.extentAfter < position.viewportDimension * 1.5) _loadMore();
  }

  /// Appends the page after the last one shown.
  Future<void> _loadMore() async {
    final next = _nextPage;
    final data = _data;
    if (next == null || data == null || _loadingMore) return;
    // Any load, write or session change moves this on: the answer is dropped.
    final epoch = _epoch;
    final view = _view;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await widget.repository
          .fetchFavoriteCollectionsPage(categoryId: view, page: next);
      if (!mounted || epoch != _epoch) return;
      // Category numbers can shift on the forum: under another name this is
      // another category's page, so the list is read again from the start.
      if (page.categoryId != view ||
          (view != null && _labelOf(page, view) != _labelOf(data, view))) {
        _load();
        return;
      }
      final seen = _pageOf;
      final added = page.items.any((entry) => !seen.containsKey(entry.id));
      setState(() {
        _loadingMore = false;
        _more.add(page);
        _emptyRun = added ? 0 : _emptyRun + 1;
      });
      // A page that shows nothing adds no height to scroll through.
      if (!added) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
      }
    } catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loadingMore = false;
        _moreError = error;
      });
    }
  }

  void _retryMore() {
    setState(() {
      _moreError = null;
      _emptyRun = 0;
    });
    _loadMore();
  }

  /// 手动翻页: the next page alone, from its top.
  void _turnTo(int page) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(view: _view, page: page);
  }

  // Rows written together come from one page's snapshot.
  bool _canJoin(String id) {
    if (_selected.isEmpty || _more.isEmpty) return true;
    final pages = _pageOf;
    return identical(pages[id], pages[_selected.first]);
  }

  void _onePageOnly() => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('一次只能选择同一页的收藏')));

  // Another account's categories and rows must not stay visible.
  void _forget() {
    _epoch++;
    _data = null;
    _error = null;
    _loading = false;
    _view = null;
    _clearMore();
    _selected.clear();
    _selecting = false;
    _busy = false;
    _unconfirmed = null;
    _dropScan();
    _searchOpen = false;
    _query.clear();
  }

  String get _keyword => _searchOpen ? _query.text.trim() : '';

  void _dropScan() {
    _searchGen++;
    _scan
      ?..removeListener(_onScan)
      ..dispose();
    _scan = null;
    _unresolvedOpen = false;
  }

  void _onScan() {
    if (mounted) setState(() {});
  }

  // Leaving the page (another page, another tab) stops the scan where it
  // is; its rows and 继续 stay.
  @override
  void onLeft() {
    final state = _scan?.progress.state;
    if (state == ScanState.running || state == ScanState.waiting) {
      _scan!.stop();
    }
  }

  // Rows chosen under another keyword may be out of sight: choosing ends.
  void _keywordChanged() => setState(() {
        _dropScan();
        _selected.clear();
        _selecting = false;
      });

  void _closeSearch() {
    _query.clear();
    setState(() {
      _searchOpen = false;
      _dropScan();
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _searchAll(FavoriteCollections data) async {
    final generation = _searchGen;
    final epoch = _epoch;
    final count = data.pageCount;
    final go = await confirmFullScan(context,
        subject: '收藏', remainingPages: count == null ? null : count - 1);
    // Asked for this keyword, view and session; any change cancels it.
    if (!go ||
        !mounted ||
        generation != _searchGen ||
        epoch != _epoch ||
        !identical(data, _data)) {
      return;
    }
    final scan = widget.repository
        .scanFavorites(categoryId: _view, keyword: _keyword, loaded: data);
    setState(() {
      _dropScan();
      _selected.clear();
      _selecting = false;
      _scan = scan..addListener(_onScan);
    });
    scan.start();
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
  Future<void> _load(
      {String? view, int page = 1, Set<String> keep = const {}}) async {
    // Category numbers can shift on the forum; the name tells which one this is.
    final asked = view == null ? null : _labelOf(_data, view);
    final epoch = ++_epoch;
    // 全部 comes first, then the categories in the forum's order.
    int place(String? id) =>
        id == null ? -1 : _data?.categories.indexWhere((c) => c.id == id) ?? -1;
    setState(() {
      _slide = (place(view) - place(_view)).sign;
      _loading = true;
      _error = null;
      _view = view;
      _clearMore();
      _selected.clear();
      _selecting = false;
      _dropScan();
    });
    try {
      final data = page == 1
          ? await widget.repository.fetchFavoriteCollections(categoryId: view)
          : await widget.repository
              .fetchFavoriteCollectionsPage(categoryId: view, page: page);
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
      // A list too short to scroll reads on by itself.
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
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
        for (final entry in _items)
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
    FavoriteCollections? source,
  }) async {
    // The page the rows were read on; categories are any page's.
    final snapshot = source ?? _data;
    if (snapshot == null || _locked) return null;
    final epoch = _epoch;
    final pageBefore = snapshot.page;
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
        // A write retires every page read before it.
        _clearMore();
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
      _load(view: _view, page: pageBefore);
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
        _load(view: named.single.id, page: pageBefore, keep: Set.of(_selected));
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
      source: _pageOf[entries.first.id],
    );
  }

  String? _tid(FavoriteCollectionEntry entry) =>
      entry.thread.threadId ??
      ForumUrlResolver(baseUri: widget.repository.networkConfig.baseUri)
          .tidFromUrl(entry.thread.url);

  bool _knownSources(List<FavoriteCollectionEntry> entries) =>
      entries.isNotEmpty &&
      entries.every((entry) =>
          _tid(entry) != null &&
          entry.categoryId != null &&
          _data!.categories.where((c) => c.id == entry.categoryId).length == 1);

  List<FavoriteCategory> _destinations(List<FavoriteCollectionEntry> entries) =>
      _data == null || !_knownSources(entries)
          ? []
          : [
              for (final category in _data!.categories)
                if (!entries.every((entry) => entry.categoryId == category.id))
                  category,
            ];

  String? _moveHint(List<FavoriteCollectionEntry> entries) {
    if (entries.isEmpty) return null;
    if (!_knownSources(entries)) return '分类信息未确认，请刷新';
    return _destinations(entries).isEmpty ? _noTarget : null;
  }

  Future<void> _move(List<FavoriteCollectionEntry> entries) async {
    if (entries.isEmpty || _data == null || _locked || !_knownSources(entries))
      return;
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
      if (!mounted ||
          session != widget.repository.sessionEpoch.value ||
          _locked) return;
      final named = [
        for (final c in _data!.categories)
          if (c.label == viewLabel) c,
      ];
      if (named.length != 1) return;
      await _load(
          view: named.single.id,
          keep: wasSelecting ? Set.of(_selected) : const {});
    }

    while (mounted &&
        session == widget.repository.sessionEpoch.value &&
        !_locked) {
      final data = _data!;
      final rebound = <FavoriteCollectionEntry>[];
      for (final request in pending.entries) {
        final matches = _items
            .where((entry) =>
                entry.id == request.key && _tid(entry) == request.value)
            .toList();
        if (matches.length == 1) rebound.add(matches.single);
      }
      if (rebound.length != pending.length) {
        // Said now, not queued behind the create/delete confirmation.
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('部分所选主题不在当前页，请重新选择')));
        pending.removeWhere((id, _) => !rebound.any((entry) => entry.id == id));
      }
      if (wasSelecting)
        setState(() {
          _selected
            ..clear()
            ..addAll(pending.keys);
          _selecting = _selected.isNotEmpty;
        });
      if (rebound.isEmpty || !_knownSources(rebound)) return;
      final action = await showMoveSheet(
        context,
        session: widget.repository.sessionEpoch,
        categories: data.categories,
        count: rebound.length,
        canCreate: data.canCreate,
        categoryChanged: categoryChanged,
        unavailableCategoryIds: {
          for (final c in data.categories)
            if (rebound.every((entry) => entry.categoryId == c.id)) c.id
        },
      );
      if (action == null) {
        await restoreView();
        return;
      }
      if (!mounted ||
          session != widget.repository.sessionEpoch.value ||
          _locked) return;
      if (action is MoveDestination) {
        final intended = action.category;
        final targets = _data!.categories
            .where((c) => intended.isDefault
                ? c.isDefault
                : !c.isDefault && c.label.trim() == intended.label.trim())
            .toList();
        if (targets.length != 1) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('分类已变化，请刷新后重试')));
          return;
        }
        final target = targets.single;
        await _write(
            (snapshot) =>
                widget.repository.moveFavorites(snapshot, rebound, target.id),
            done: (n) => '已移动 $n 个到「${target.label}」',
            count: rebound.length,
            source: _pageOf[rebound.first.id]);
        return;
      }
      ManageAction? manage;
      if (action is CreateMoveCategory) {
        manage = const CreateCategory();
      } else {
        manage = await showManageCategoriesSheet(context,
            session: widget.repository.sessionEpoch, data: _data!);
      }
      if (!mounted ||
          session != widget.repository.sessionEpoch.value ||
          _locked) return;
      if (manage != null) {
        final result = await _applyManageAction(manage, keepSelection: true);
        if (!mounted ||
            session != widget.repository.sessionEpoch.value ||
            _locked) return;
        categoryChanged =
            categoryChanged || result == FavoriteMutationStatus.confirmed;
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

  Future<FavoriteMutationStatus?> _applyManageAction(ManageAction action,
      {bool keepSelection = false}) async {
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
        final targets = _data!.categories
            .where(
                (c) => !c.isDefault && c.label.trim() == category.label.trim())
            .toList();
        if (targets.length != 1) {
          // Never fall back to the number: say why nothing was sent.
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('分类名称重复，请在原站整理后重试')));
          return null;
        }
        return _write(
          (snapshot) => widget.repository
              .deleteFavoriteCategory(snapshot, targets.single.id),
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

  void _toggle(String id) {
    if (!_selected.contains(id) && !_canJoin(id)) return _onePageOnly();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _startSelecting([String? id]) {
    if (_locked || _items.isEmpty) return;
    if (id != null && !_canJoin(id)) return _onePageOnly();
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
      return Column(children: [
        const AppTabHeader(title: '收藏'),
        Expanded(
          child: LoginPrompt(
            icon: Icons.star_outline,
            title: '收藏',
            message: '登录后，在帖子里收藏的主题会集中在这里。',
            onLogin: widget.onLoginTap ??
                () => openLogin(context, widget.repository),
          ),
        ),
      ]);
    }
    final data = _data;
    final items = _items;
    final pageOf = _pageOf;
    final keyword = _keyword;
    final scan = _scan;
    // A truncated title that misses the keyword may still hold it.
    final shown = keyword.isEmpty
        ? items
        : [
            for (final e in items)
              if (matchKeyword(keyword, [e.thread.title],
                      truncated: e.thread.titleTruncated) ==
                  true)
                e,
          ];
    final undecided = keyword.isEmpty
        ? const <FavoriteCollectionEntry>[]
        : [
            for (final e in items)
              if (matchKeyword(keyword, [e.thread.title],
                      truncated: e.thread.titleTruncated) ==
                  null)
                e,
          ];
    // 全选 takes the rows the search shows; chosen undecided rows are not
    // what it counts.
    // Rows written together come from one page: the chosen rows' page, or
    // the first shown.
    final anchor = _selected.isNotEmpty
        ? pageOf[_selected.first]
        : shown.isEmpty
            ? null
            : pageOf[shown.first.id];
    final shownIds = {
      for (final e in shown)
        if (identical(pageOf[e.id], anchor)) e.id,
    };
    final allChosen = shownIds.isNotEmpty && _selected.containsAll(shownIds);
    Widget rows(List<FavoriteCollectionEntry> entries) => DecoratedBox(
          decoration: appSurface(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, entry) in entries.indexed) ...[
                if (i > 0) const Divider(indent: AppSpace.lg),
                _FavoriteRow(
                  key: ValueKey('favorite-row:${entry.id}'),
                  entry: entry,
                  categoryLabel: _view == null && data!.categories.length > 1
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
                  onMoveCategories:
                      _knownSources([entry]) ? () => _move([entry]) : null,
                ),
              ],
            ],
          ),
        );
    // Appended pages each start under their 第 N 页 rule.
    Widget pagedRows(List<FavoriteCollectionEntry> entries) {
      if (_more.isEmpty) return rows(entries);
      final runs = <(FavoriteCollections, List<FavoriteCollectionEntry>)>[];
      for (final entry in entries) {
        final page = pageOf[entry.id]!;
        if (runs.isEmpty || !identical(runs.last.$1, page)) {
          runs.add((page, []));
        }
        runs.last.$2.add(entry);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (page, run) in runs) ...[
            if (!identical(page, data)) PageBoundary(page: page.page),
            rows(run),
          ],
        ],
      );
    }

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
    } else if (scan != null) {
      body = _scanBody(scan);
    } else if (items.isEmpty) {
      // Only the whole list being on this page says there is nothing at all.
      final complete = _wholeList;
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
      // Only the whole list on this page, all titles whole, makes a miss final.
      final complete = _wholeList && undecided.isEmpty;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shown.isNotEmpty)
            pagedRows(shown)
          else
            EmptyStateView(
              icon: Icons.manage_search_outlined,
              title: complete
                  ? '没有符合的收藏'
                  : _more.isEmpty
                      ? '本页没有符合的收藏'
                      : '已加载的页面没有符合的收藏',
            ),
          if (undecided.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            UnresolvedGroup(
              title: '标题不完整 (${undecided.length})',
              description: '这些收藏的标题被截断，可能符合条件；搜索全部页面会补全标题。',
              expanded: _unresolvedOpen,
              onToggle: () =>
                  setState(() => _unresolvedOpen = !_unresolvedOpen),
              child: rows(undecided),
            ),
          ],
        ],
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
            _Header(
              // Scan rows are no page's: no count, no 选择.
              count: data == null || _loading || _error != null || scan != null
                  ? null
                  : items.length,
              page: data == null ? null : _pageNote(data),
              selecting: _selecting,
              selected: _selected.length,
              allSelected: allChosen,
              // Scan rows only open threads.
              canSelect:
                  data != null && shown.isNotEmpty && !_locked && scan == null,
              filtered: keyword.isNotEmpty,
              onSearch: data == null || _searchOpen
                  ? null
                  : () => setState(() => _searchOpen = true),
              onStart: _startSelecting,
              // Only the rows the search shows.
              onAll: () => setState(() {
                if (allChosen) {
                  _selected.clear();
                } else {
                  _selected.addAll(shownIds);
                }
              }),
              onExit: _stopSelecting,
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _refresh,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side =
                        appGutter(constraints.maxWidth, AppWidths.list);
                    return ListView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(side, 0, side, 32),
                      children: [
                        if (_busy) const LinearProgressIndicator(minHeight: 2),
                        if (_unconfirmed case final text?)
                          _Notice(text: text, onRefresh: _refresh),
                        if (_searchOpen) ...[
                          const SizedBox(height: AppSpace.sm),
                          ListSearchField(
                            controller: _query,
                            hintText: '搜索收藏标题',
                            autofocus: true,
                            onChanged: (_) => _keywordChanged(),
                            onClose: _closeSearch,
                          ),
                        ],
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
                        if (keyword.isNotEmpty &&
                            data != null &&
                            !_loading &&
                            _error == null) ...[
                          const SizedBox(height: AppSpace.sm),
                          SearchScopeBar(
                            progress: scan?.progress ??
                                ScanProgress(
                                  scannedPages: 1 + _more.length,
                                  totalPages: data.pageCount,
                                  found: shown.length,
                                  unresolved: undecided.length,
                                ),
                            // One whole page with whole titles is all there is.
                            onSearchAll: data.pageCount == 1 &&
                                    !items.any((e) => e.thread.titleTruncated)
                                ? null
                                : () => _searchAll(data),
                            onStop: scan?.stop,
                            onResume: scan?.resume,
                            onBackToLoaded: () => setState(_dropScan),
                          ),
                        ],
                        const SizedBox(height: 8),
                        AppSwitcher(
                          id: _view,
                          direction: _slide,
                          child: AppSwitcher(
                            id: _error != null
                                ? 'error'
                                : data == null || _loading
                                    ? 'loading'
                                    : scan != null
                                        ? 'scan'
                                        : 'list',
                            child: body,
                          ),
                        ),
                        if (data != null &&
                            !_loading &&
                            _error == null &&
                            scan == null &&
                            (_nextPage != null ||
                                _more.isNotEmpty ||
                                data.page > 1))
                          PageEndFooter(
                            next: _nextPage,
                            manual: !_continuous,
                            loading: _loadingMore,
                            failed: _moreError != null,
                            error: _moreError,
                            paused: _emptyRun >= 2,
                            // 手动翻页 turns to the next page alone; 自动接续
                            // appends.
                            onNext: _nextPage == null || _locked
                                ? null
                                : !_continuous
                                    ? () => _turnTo(_nextPage!)
                                    : _retryMore,
                          ),
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
                onManageMove:
                    _knownSources(_chosen) ? () => _move(_chosen) : null,
                onRemove: () => _remove(_chosen),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scanBody(FullScan<FavoriteSearchHit> scan) {
    final hits = scan.hits;
    final unresolved = scan.unresolved;
    Widget rows(List<FavoriteSearchHit> found) => DecoratedBox(
          decoration: appSurface(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, hit) in found.indexed) ...[
                if (i > 0) const Divider(indent: AppSpace.lg),
                ForumThreadRow(
                  key: ValueKey('favorite-hit:${hit.page}:${hit.thread.url}'),
                  title: hit.thread.title,
                  meta: [
                    '第 ${hit.page} 页',
                    if (hit.thread.section case final section?) section,
                    if (hit.thread.author case final author?) author,
                  ],
                  onTap: () =>
                      _openFavorite(context, widget.repository, hit.thread),
                ),
              ],
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text('全部页面的结果只能打开；移动或取消收藏请在所在页面操作',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        if (hits.isNotEmpty)
          rows(hits)
        // Undecided rows may still match: only none at all is final.
        else if (scan.progress.state == ScanState.done && unresolved.isEmpty)
          const EmptyStateView(
            icon: Icons.manage_search_outlined,
            title: '没有符合的收藏',
          )
        else if (scan.progress.state == ScanState.done)
          const EmptyStateView(
            icon: Icons.manage_search_outlined,
            title: '没有确认符合的收藏',
            message: '下方标题不完整的收藏仍可能符合。',
          )
        else
          const EmptyStateView(
            icon: Icons.manage_search_outlined,
            title: '暂未找到',
            message: '搜索未完成，结果可能不全。',
          ),
        if (unresolved.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          UnresolvedGroup(
            title: '标题不完整 (${unresolved.length})',
            description: '这些收藏的标题被截断且无法补全，可能符合条件。',
            expanded: _unresolvedOpen,
            onToggle: () => setState(() => _unresolvedOpen = !_unresolvedOpen),
            child: rows(unresolved),
          ),
        ],
      ],
    );
  }

  // Said only when the forum has more than the page shown, or when that is
  // not known.
  String? _pageNote(FavoriteCollections data) {
    final last = _lastPage ?? data;
    final count = last.pageCount;
    if (count == null) return '页数未能确认';
    if (count <= 1) return null;
    return last.page == data.page
        ? '第 ${data.page}/$count 页'
        : '第 ${data.page}–${last.page}/$count 页';
  }

  /// Every page is on screen, from the first.
  bool get _wholeList =>
      _data?.page == 1 && _lastPage?.pageCount != null && _nextPage == null;

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
    required this.filtered,
    required this.onSearch,
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

  /// A keyword narrows the rows: 全选 takes only those.
  final bool filtered;

  /// Opens 搜索收藏; null while it is open or nothing is loaded.
  final VoidCallback? onSearch;
  final VoidCallback onStart;
  final VoidCallback onAll;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    if (selecting) {
      return AppTabHeader(
        title: '已选 $selected 个',
        liveRegion: true,
        leading: IconButton(
          key: const ValueKey('favorite-select-exit'),
          tooltip: '完成',
          icon: const Icon(Icons.close),
          onPressed: onExit,
        ),
        actions: [
          TextButton(
            key: const ValueKey('favorite-select-all'),
            onPressed: onAll,
            child: Text(allSelected
                ? '取消全选'
                : filtered
                    ? '全选结果'
                    : '全选已加载'),
          ),
        ],
      );
    }
    final shown = count != null && (count! > 0 || page != null);
    return AppTabHeader(
      title: '收藏',
      subtitle:
          shown ? '已加载 $count 个主题${page == null ? '' : ' · $page'}' : null,
      actions: [
        if (shown && onSearch != null)
          IconButton(
            key: const ValueKey('favorite-search'),
            tooltip: '搜索收藏',
            onPressed: onSearch,
            icon: const Icon(Icons.search),
          ),
        if (shown && count! > 0)
          TextButton(
            key: const ValueKey('favorite-select-start'),
            onPressed: canSelect ? onStart : null,
            child: const Text('选择'),
          ),
      ],
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
            color:
                on ? AppColors.brand.withValues(alpha: 0.35) : AppColors.border,
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
          const SizedBox(
              height: 24, child: VerticalDivider(width: AppSpace.md)),
          ActionChip(
            key: const ValueKey('favorite-manage'),
            avatar: Icon(Icons.tune,
                size: 18,
                color: canManage ? AppColors.brand : AppColors.textFaint),
            label: const Text('管理'),
            shape: const StadiumBorder(),
            backgroundColor: AppColors.surface,
            side: BorderSide(color: AppColors.border),
            labelStyle: TextStyle(
                color: canManage ? AppColors.text : AppColors.textFaint),
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
          : () => _openFavorite(context, widget.repository, item),
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
                    Flexible(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('移动到…'),
                        if (widget.moveHint != null)
                          Text(widget.moveHint!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textFaint)),
                      ],
                    )),
                  ]),
                ),
                if (widget.moveHint == _noTarget &&
                    widget.onMoveCategories != null)
                  PopupMenuItem(
                    key:
                        ValueKey('favorite-row-move-manage:${widget.entry.id}'),
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

void _openFavorite(
    BuildContext context, ForumRepository repository, UserListItem item) {
  Navigator.of(context).push(
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
        repository: repository,
      ),
    ),
  );
}
