import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/thread_image_preview_strip.dart';
import '../profile/user_profile_screen.dart';
import '../thread/thread_detail_screen.dart';
import '../thread/thread_compose_screen.dart';

part 'board_thread_list_widgets.dart';

class BoardThreadListScreen extends StatefulWidget {
  const BoardThreadListScreen({
    super.key,
    required this.category,
    required this.repository,
    this.initialSubBoards = const [],
  });

  final ForumCategory category;
  final ForumRepository repository;
  final List<ForumBoard> initialSubBoards;

  @override
  State<BoardThreadListScreen> createState() => _BoardThreadListScreenState();
}

class _BoardThreadListScreenState extends State<BoardThreadListScreen> {
  late Future<ForumThreadPage> _future;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _warmedPreviewPageKeys = <String>{};
  late ForumCategory _category = widget.category;
  late List<ForumBoard> _knownSubBoards = List.of(widget.initialSubBoards);
  int _page = 1;
  int _fetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _future = _fetchPage(_page);
  }

  Future<ForumThreadPage> _fetchPage(int page) async {
    final generation = ++_fetchGeneration;
    final category = _category;
    final threadPage = await widget.repository.fetchBoardThreadPage(
      category,
      page: page,
    );
    if (!mounted || generation != _fetchGeneration || category != _category) {
      return threadPage;
    }
    if (threadPage.subBoards.isNotEmpty) {
      _knownSubBoards = List.of(threadPage.subBoards);
    }
    _warmThreadImagePreviews(category, threadPage);
    return threadPage;
  }

  void _warmThreadImagePreviews(
    ForumCategory category,
    ForumThreadPage threadPage,
  ) {
    final threadKeys = threadPage.threads
        .take(6)
        .map((thread) => thread.url)
        .join('|');
    final cacheKey = '${category.url}#${threadPage.currentPage}#$threadKeys';
    if (!_warmedPreviewPageKeys.add(cacheKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || category != _category) return;
      unawaited(_delayedPreviewWarmup(threadPage.threads.take(6)));
    });
  }

  Future<void> _delayedPreviewWarmup(Iterable<ForumThread> threads) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await _fetchPreviewWarmup(threads);
  }

  Future<void> _fetchPreviewWarmup(Iterable<ForumThread> threads) async {
    for (final thread in threads) {
      try {
        await widget.repository.fetchThreadImagePreview(thread);
      } catch (_) {
        // Preview warmup is best-effort; visible rows still handle failures.
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _fetchPage(_page);
    });
    await _future;
  }

  Future<void> _goToPage(int page) async {
    if (page == _page || page < 1) return;
    setState(() {
      _page = page;
      _future = _fetchPage(page);
    });
    await _future;
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
          category: _category,
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    if (posted == true) {
      await _refresh();
    }
  }

  Future<void> _openSubBoard(ForumBoard board) async {
    setState(() {
      _category = ForumCategory(
        name: board.name,
        slug: board.slug,
        url: board.url,
      );
      _knownSubBoards = List.of(board.children);
      _page = 1;
      _future = _fetchPage(_page);
    });
    await _future;
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _BoardHeader(
              title: _category.name,
              slug: _category.slug,
              onCompose: _openComposer,
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.surface,
                child: FutureBuilder<ForumThreadPage>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return AsyncErrorView(
                        title: '板块加载失败',
                        message: '${snapshot.error}',
                        onRetry: _refresh,
                      );
                    }
                    if (!snapshot.hasData) {
                      return const _BoardThreadListSkeleton();
                    }
                    final page = snapshot.data!;
                    final subBoards = page.subBoards.isNotEmpty
                        ? page.subBoards
                        : _knownSubBoards;
                    final items = _BoardListItem.fromPage(page);
                    if (_page != page.currentPage) {
                      _page = page.currentPage;
                    }
                    final hasSubBoards = subBoards.isNotEmpty;
                    final listItemCount =
                        items.length + 1 + (hasSubBoards ? 1 : 0);
                    return RefreshIndicator(
                      color: AppColors.brand,
                      onRefresh: _refresh,
                      child: ListView.separated(
                        controller: _scrollController,
                        cacheExtent: 500,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
                        itemCount: listItemCount,
                        separatorBuilder: (_, __) => const SizedBox.shrink(),
                        itemBuilder: (context, index) {
                          if (hasSubBoards && index == 0) {
                            return _SubBoardPanel(
                              boards: subBoards,
                              onBoardTap: _openSubBoard,
                            );
                          }

                          final itemIndex = index - (hasSubBoards ? 1 : 0);
                          if (itemIndex == items.length) {
                            return _PaginationBar(
                              page: page,
                              onPageSelected: _goToPage,
                            );
                          }
                          final item = items[itemIndex];
                          return switch (item) {
                            _BoardAdItem(:final ad) => _BoardAdBanner(ad: ad),
                            _BoardThreadItem(:final thread) => _ThreadRow(
                                thread: thread,
                                repository: widget.repository,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ThreadDetailScreen(
                                      thread: thread,
                                      repository: widget.repository,
                                    ),
                                  ),
                                ),
                              ),
                          };
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
