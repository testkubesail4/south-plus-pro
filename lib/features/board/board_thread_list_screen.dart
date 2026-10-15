import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/perf_trace.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/forum_title_text.dart';
import '../common/cached_forum_image.dart';
import '../profile/user_profile_screen.dart';
import '../search/search_screen.dart';
import 'thread_preview_image_layout.dart';
import '../thread/thread_detail_screen.dart';
import '../thread/thread_compose_screen.dart';

part 'board_navigation_widgets.dart';
part 'board_thread_list_widgets.dart';

const _doujinContentBoardName = '同人志&CG';

/// One board: its sub-boards, then its topics as a list or a picture wall.
/// A sub-board opens as its own route; [parent] and [siblings] are the board
/// it was opened from and that board's sub-boards, for the switcher.
class BoardThreadListScreen extends StatefulWidget {
  const BoardThreadListScreen({
    super.key,
    required this.category,
    required this.repository,
    this.initialSubBoards = const [],
    this.parent,
    this.siblings = const [],
  });

  final ForumCategory category;
  final ForumRepository repository;
  final List<ForumBoard> initialSubBoards;
  final ForumCategory? parent;
  final List<ForumBoard> siblings;

  @override
  State<BoardThreadListScreen> createState() => _BoardThreadListScreenState();
}

class _BoardThreadListScreenState extends State<BoardThreadListScreen> {
  late Future<ForumThreadPage> _future;
  final ScrollController _scrollController = ScrollController();
  late ForumCategory _category = widget.category;
  late List<ForumBoard> _knownSubBoards = List.of(widget.initialSubBoards);
  // The last loaded page keeps sub-boards and filters on screen while the
  // next page loads, so only the topic area shows a skeleton.
  ForumThreadPage? _shown;
  int _page = 1;
  ForumThreadOrder _order = ForumThreadOrder.lastPost;
  ForumBoardFilter? _filter;
  bool _wall = false;

  @override
  void initState() {
    super.initState();
    _future = _fetchPage(_page);
  }

  Future<ForumThreadPage> _fetchPage(int page) async {
    final category = _category;
    final threadPage = await widget.repository.fetchBoardThreadPage(
      category,
      page: page,
      order: _order,
      filter: _filter,
    );
    _adoptBoardName(category, threadPage);
    _rememberSubBoards(threadPage);
    final defaultSubBoard = _defaultContentSubBoard(threadPage);
    if (defaultSubBoard != null) {
      final nextCategory = ForumCategory(
        name: defaultSubBoard.name,
        slug: defaultSubBoard.slug,
        url: defaultSubBoard.url,
      );
      void adopt() {
        _category = nextCategory;
        _knownSubBoards = List.of(defaultSubBoard.children);
        _page = 1;
        _order = ForumThreadOrder.lastPost;
        _filter = null;
      }

      if (mounted) {
        setState(adopt);
      } else {
        adopt();
      }
      final nextPage =
          await widget.repository.fetchBoardThreadPage(nextCategory, page: 1);
      _adoptBoardName(nextCategory, nextPage);
      _rememberSubBoards(nextPage);
      return nextPage;
    }
    return threadPage;
  }

  // The board page's breadcrumb names the board; link text does not. A page
  // without one keeps the known name, and a late page for a board the user
  // has left renames nothing.
  void _adoptBoardName(ForumCategory requested, ForumThreadPage page) {
    final name = page.boardName?.trim() ?? '';
    if (name.isEmpty || name == requested.name) return;
    if (!identical(_category, requested)) return;
    final named = ForumCategory(
      name: name,
      slug: requested.slug,
      url: requested.url,
    );
    if (mounted) {
      setState(() => _category = named);
    } else {
      _category = named;
    }
  }

  String get _title {
    if (_category.name.isNotEmpty) return _category.name;
    final fid = widget.repository.searchBoardId(_category);
    return fid == null ? '版块' : '版块 $fid';
  }

  void _rememberSubBoards(ForumThreadPage page) {
    if (mounted && page.subBoards.isNotEmpty) {
      _knownSubBoards = List.of(page.subBoards);
    }
  }

  ForumBoard? _defaultContentSubBoard(ForumThreadPage page) {
    if (page.threads.isNotEmpty || page.subBoards.isEmpty) return null;
    // Some parent event boards only render global notices/stickies in the
    // desktop table and keep the actual topics in a regular child board. The
    // similarly named wall-mode child can be empty, so choose only the exact
    // content board users would otherwise have to enter manually.
    for (final board in page.subBoards) {
      if (board.name == _doujinContentBoardName && board.url != _category.url) {
        return board;
      }
    }
    return null;
  }

  Future<void> _reload({int? page}) async {
    setState(() {
      if (page != null) _page = page;
      _future = _fetchPage(_page);
    });
    await _future;
  }

  Future<void> _refresh() => _reload();

  Future<void> _goToPage(int page) async {
    if (page == _page || page < 1) return;
    await _reload(page: page);
    await _scrollToTop();
  }

  Future<void> _changeOrder(ForumThreadOrder order) async {
    if (order == _order) return;
    _order = order;
    await _reload(page: 1);
    await _scrollToTop();
  }

  // Filters are passed explicitly, 全部 included: a null filter keeps the
  // one a deep link's url carries.
  Future<void> _changeFilter(ForumBoardFilter filter) async {
    if (filter.url == _activeFilterUrl) return;
    _filter = filter;
    await _reload(page: 1);
    await _scrollToTop();
  }

  String? get _activeFilterUrl => _filter?.url ?? _shown?.activeFilter?.url;

  Future<void> _scrollToTop() async {
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openComposer() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ThreadComposeScreen(
          category: ForumCategory(
            name: _title,
            slug: _category.slug,
            url: _category.url,
          ),
          repository: widget.repository,
        ),
      ),
    );
    if (posted == true) {
      await _refresh();
    }
  }

  ForumCategory _categoryOf(ForumBoard board) =>
      ForumCategory(name: board.name, slug: board.slug, url: board.url);

  void _openSubBoard(ForumBoard board, List<ForumBoard> siblings) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BoardThreadListScreen(
        category: _categoryOf(board),
        repository: widget.repository,
        initialSubBoards: board.children,
        parent: _category,
        siblings: siblings,
      ),
    ));
  }

  // A sibling replaces this route, so back still returns to the parent.
  void _openSibling(ForumBoard board) {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => BoardThreadListScreen(
        category: _categoryOf(board),
        repository: widget.repository,
        initialSubBoards: board.children,
        parent: widget.parent,
        siblings: widget.siblings,
      ),
    ));
  }

  void _openParent(ForumCategory parent) {
    if (widget.parent != null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BoardThreadListScreen(
        category: parent,
        repository: widget.repository,
      ),
    ));
  }

  Future<void> _openAd(ForumBoardAd ad) async {
    try {
      await ExternalLinkLauncher.open(ad.url);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  void _openThread(ForumThread thread) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadDetailScreen(
          thread: thread,
          repository: widget.repository,
        ),
      ),
    );
  }

  VoidCallback? get _search =>
      switch (widget.repository.searchBoardId(_category)) {
        final fid? => () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SearchScreen(
                  repository: widget.repository,
                  initialBoard: ForumSearchBoard(id: fid, name: _category.name),
                ),
              ),
            ),
        null => null,
      };

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    PerfTrace.markScreen('BoardThreadListScreen');
    return PerfTrace.span(
      'BoardThreadListScreen.build',
      () {
        return FutureBuilder<ForumThreadPage>(
          future: _future,
          builder: (context, snapshot) {
            final done = snapshot.connectionState == ConnectionState.done;
            final loaded = done && snapshot.hasData;
            if (loaded) {
              _shown = snapshot.data;
              _page = snapshot.data!.currentPage;
            }
            final page = loaded ? snapshot.data : null;
            final shown = _shown;
            final parent = widget.parent ??
                (shown == null || shown.parents.isEmpty
                    ? null
                    : shown.parents.last);
            return Scaffold(
              backgroundColor: AppColors.background,
              floatingActionButton: FloatingActionButton(
                tooltip: '发帖',
                onPressed: _openComposer,
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                child: const Icon(Icons.edit_outlined),
              ),
              body: SafeArea(
                bottom: false,
                child: LayoutBuilder(builder: (context, constraints) {
                  final gutter = _boardGutter(constraints.maxWidth);
                  final siblings = widget.siblings.length > 1;
                  final panel = siblings && constraints.maxWidth >= 1200;
                  final body = done && snapshot.hasError
                      ? AsyncErrorView(
                          title: '板块加载失败',
                          message: '${snapshot.error}',
                          onRetry: _refresh,
                        )
                      : _buildBody(
                          context,
                          page,
                          shown,
                          gutter: panel ? 0 : gutter,
                          content: constraints.maxWidth -
                              gutter * 2 -
                              (panel ? _siblingPanelWidth + 24 : 0),
                        );
                  final list = _SiblingList(
                    parent: widget.parent,
                    siblings: widget.siblings,
                    currentUrl: widget.category.url,
                    onParent: () => Navigator.of(context).maybePop(),
                    onSelected: _openSibling,
                  );
                  return Column(
                    children: [
                      _BoardHeader(
                        gutter: gutter,
                        title: _title,
                        parent: parent,
                        // The panel has its own parent row.
                        onParent: parent == null || panel
                            ? null
                            : () => _openParent(parent),
                        onSwitch: !siblings || panel
                            ? null
                            : () => _showSiblingSheet(
                                  context,
                                  parent: widget.parent,
                                  siblings: widget.siblings,
                                  currentUrl: widget.category.url,
                                  onSelected: _openSibling,
                                ),
                        onSearch: _search,
                      ),
                      Expanded(
                        child: !panel
                            ? body
                            : Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: gutter),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: _siblingPanelWidth,
                                      child: _SiblingPanel(child: list),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(child: body),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  );
                }),
              ),
            );
          },
        );
      },
      arguments: {'page': _page, 'board': _category.slug},
    );
  }

  Widget _buildBody(
    BuildContext context,
    ForumThreadPage? page,
    ForumThreadPage? shown, {
    required double gutter,
    required double content,
  }) {
    final subBoards = shown == null || shown.subBoards.isEmpty
        ? _knownSubBoards
        : shown.subBoards;
    final items = page == null ? null : _BoardListItem.fromPage(page);
    final filters = shown?.filters ?? const <ForumBoardFilter>[];
    final wallAvailable = shown?.hasPictureWall ?? false;
    final wall = _wall && wallAvailable;
    Widget padded(Widget sliver) => SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            sliver: sliver,
          );
      return RefreshIndicator(
        color: AppColors.brand,
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (subBoards.isNotEmpty)
              padded(SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: _SubBoardSection(
                    boards: subBoards,
                    width: content,
                    onOpen: (board) => _openSubBoard(board, subBoards),
                  ),
                ),
              )),
            SliverPersistentHeader(
              pinned: true,
              delegate: _BoardToolbarDelegate(
                gutter: gutter,
                extent: _BoardToolbar.extentFor(context),
                child: _BoardToolbar(
                  filters: filters,
                  activeUrl: _activeFilterUrl,
                  onFilter: _changeFilter,
                  order: _order,
                  onOrder: _changeOrder,
                  wall: wallAvailable ? wall : null,
                  onWall: (value) => setState(() => _wall = value),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (items == null)
              padded(const SliverToBoxAdapter(child: _BoardThreadListSkeleton()))
            else if (items.isEmpty)
              padded(SliverToBoxAdapter(
                child: _EmptyTopics(inSubBoards: subBoards.isNotEmpty),
              ))
            else if (wall)
              ..._wallSlivers(items, content).map(padded)
            else
              padded(_listSliver(items)),
            if (page != null)
              padded(SliverToBoxAdapter(
                child: _PaginationBar(page: page, onPageSelected: _goToPage),
              )),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      );
  }

  Widget _itemWidget(_BoardListItem item) => switch (item) {
        _BoardAdItem(:final ad) => _BoardAdBanner(
            ad: ad,
            onTap: () => _openAd(ad),
          ),
        _BoardThreadItem(:final thread) => _ThreadRow(
            thread: thread,
            repository: widget.repository,
            onTap: () => _openThread(thread),
          ),
      };

  Widget _listSliver(List<_BoardListItem> items) => DecoratedSliver(
        decoration: _boardSurface(context),
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const _RowDivider(),
          itemBuilder: (context, index) => _itemWidget(items[index]),
        ),
      );

  // Pinned topics and ads stay a compact list above the wall.
  List<Widget> _wallSlivers(List<_BoardListItem> items, double width) {
    final listed = [
      for (final item in items)
        if (item is _BoardAdItem ||
            (item is _BoardThreadItem && item.thread.isSticky))
          item,
    ];
    final tiles = [
      for (final item in items)
        if (item is _BoardThreadItem && !item.thread.isSticky) item.thread,
    ];
    final columns = _wallColumns(width);
    final rows = (tiles.length / columns).ceil();
    return [
      if (listed.isNotEmpty) ...[
        _listSliver(listed),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
      SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, row) => Padding(
          padding: EdgeInsets.only(top: row == 0 ? 0 : _wallSpacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: _wallSpacing),
                Expanded(
                  child: row * columns + c < tiles.length
                      ? _WallCard(
                          thread: tiles[row * columns + c],
                          onTap: () => _openThread(tiles[row * columns + c]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }
}
