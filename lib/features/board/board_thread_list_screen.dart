import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../profile/user_profile_screen.dart';
import 'thread_preview_image_layout.dart';
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
  late ForumCategory _category = widget.category;
  late List<ForumBoard> _knownSubBoards = List.of(widget.initialSubBoards);
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _fetchPage(_page);
  }

  Future<ForumThreadPage> _fetchPage(int page) async {
    final threadPage = await widget.repository.fetchBoardThreadPage(
      _category,
      page: page,
    );
    if (mounted && threadPage.subBoards.isNotEmpty) {
      _knownSubBoards = List.of(threadPage.subBoards);
    }
    return threadPage;
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
                            _BoardAdItem(:final ad) => _BoardAdBanner(
                                ad: ad,
                                onTap: () => _openAd(ad),
                              ),
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
