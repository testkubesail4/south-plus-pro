import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_trace_logger.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../common/async_state_view.dart';
import '../history/browsing_history_screen.dart';
import '../profile/account_screen.dart';
import '../profile/favorite_threads_page.dart';
import '../profile/forum_tasks_screen.dart';
import '../profile/user_profile_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';

part 'home_widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    ForumRepository? repository,
    this.onToggleTheme,
  }) : repository = repository;

  final ForumRepository? repository;
  final VoidCallback? onToggleTheme;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final ForumRepository _repository =
      widget.repository ?? ForumRepository();
  int _index = 0;

  void _showHome() {
    setState(() => _index = 0);
  }

  void _showHistory() {
    setState(() => _index = 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          ForumHomePage(
            repository: _repository,
            onHistoryTap: _showHistory,
            onToggleTheme: widget.onToggleTheme,
          ),
          FavoriteThreadsPage(
            repository: _repository,
            onLoginTap: () => setState(() => _index = 4),
          ),
          _index == 2
              ? BrowsingHistoryScreen(
                  repository: _repository,
                  onBrowseHome: _showHome,
                )
              : const SizedBox.shrink(),
          SearchScreen(repository: _repository),
          AccountScreen(repository: _repository, onLoggedOut: _showHome),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border_rounded),
            selectedIcon: Icon(Icons.star_rounded),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class ForumHomePage extends StatefulWidget {
  const ForumHomePage({
    super.key,
    required this.repository,
    this.onHistoryTap,
    this.onToggleTheme,
  });

  final ForumRepository repository;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onToggleTheme;

  @override
  State<ForumHomePage> createState() => _ForumHomePageState();
}

class _ForumHomePageState extends State<ForumHomePage> {
  late Future<ForumHomeSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchHome();
  }

  Future<void> _refresh() async {
    final next = widget.repository.fetchHome();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error state.
    }
  }

  void _openBoard(ForumBoard board) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardThreadListScreen(
          category: _categoryFromBoard(board),
          repository: widget.repository,
          initialSubBoards: board.children,
        ),
      ),
    );
  }

  ForumCategory _categoryFromBoard(ForumBoard board) {
    return ForumCategory(
      name: board.name,
      slug: board.slug,
      url: board.url,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<ForumHomeSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  _TopBar(
                    repository: widget.repository,
                    onHistoryTap: widget.onHistoryTap,
                    onToggleTheme: widget.onToggleTheme,
                  ),
                  if (snapshot.hasError)
                    AsyncErrorView(
                      title: '主页加载失败',
                      message: '${snapshot.error}',
                      onRetry: _refresh,
                    )
                  else if (data == null)
                    const HomeSkeleton()
                  else ...[
                    const SizedBox(height: 18),
                    _LatestThreads(
                      threads: data.latest,
                      repository: widget.repository,
                    ),
                    const SizedBox(height: 14),
                    _ForumGroup(
                      title: '热门版块',
                      icon: Icons.local_fire_department_outlined,
                      children: data.hot
                          .map(
                            (category) => _ForumLink(
                              title: category.name,
                              subtitle: category.slug,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BoardThreadListScreen(
                                    category: category,
                                    repository: widget.repository,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    ...data.sections.map(
                      (section) => _ForumGroup(
                        title: section.title,
                        initiallyExpanded: false,
                        children: section.items
                            .map(
                              (board) => _ForumBoardLink(
                                board: board,
                                onTap: () => _openBoard(board),
                                onChildTap: _openBoard,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const _DesktopLink(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class BoardDirectoryPage extends StatefulWidget {
  const BoardDirectoryPage({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<BoardDirectoryPage> createState() => _BoardDirectoryPageState();
}

class _BoardDirectoryPageState extends State<BoardDirectoryPage> {
  late Future<ForumHomeSnapshot> _future = widget.repository.fetchHome();

  Future<void> _refresh() async {
    final next = widget.repository.fetchHome();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error state.
    }
  }

  void _openBoard(ForumBoard board) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardThreadListScreen(
          category: ForumCategory(
            name: board.name,
            slug: board.slug,
            url: board.url,
          ),
          repository: widget.repository,
          initialSubBoards: board.children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<ForumHomeSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AsyncErrorView(
              title: '版块加载失败',
              message: '${snapshot.error}',
              onRetry: _refresh,
            );
          }
          final data = snapshot.data;
          if (data == null) return const HomeSkeleton();

          return RefreshIndicator(
            color: AppColors.brand,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text('版块', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  '按源站分区组织，常用版块放在顶部。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                _ForumGroup(
                  title: '热门版块',
                  icon: Icons.local_fire_department_outlined,
                  children: data.hot
                      .map(
                        (category) => _ForumLink(
                          title: category.name,
                          subtitle: category.slug,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BoardThreadListScreen(
                                category: category,
                                repository: widget.repository,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                ...data.sections.map(
                  (section) => _ForumGroup(
                    title: section.title,
                    initiallyExpanded: false,
                    children: section.items
                        .map(
                          (board) => _ForumBoardLink(
                            board: board,
                            onTap: () => _openBoard(board),
                            onChildTap: _openBoard,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
