import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_trace_logger.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../common/async_state_view.dart';
import '../common/forum_title_text.dart';
import '../messages/pm_box_screen.dart';
import '../profile/account_screen.dart';
import '../profile/favorite_threads_page.dart';
import '../profile/forum_tasks_screen.dart';
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
  // Tabs are built on first visit, so startup only loads the home page.
  final Set<int> _opened = {0};

  void _select(int index) {
    setState(() {
      _index = index;
      _opened.add(index);
    });
  }

  void _showHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _select(0);
  }

  @override
  Widget build(BuildContext context) {
    final compactLabels = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return ValueListenableBuilder<String?>(
      valueListenable: _repository.sessionUser,
      builder: (context, owner, _) {
        // A new owner rebuilds every tab, so no account's data lingers.
        Widget tab(int index, Widget Function() build) =>
            _opened.contains(index)
                ? KeyedSubtree(key: ValueKey((index, owner)), child: build())
                : const SizedBox.shrink();
        return PopScope(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _select(0);
          },
          child: Scaffold(
            body: IndexedStack(
              index: _index,
              children: [
                tab(
                  0,
                  () => ForumHomePage(
                    repository: _repository,
                    onAccountTap: () => _select(4),
                    onToggleTheme: widget.onToggleTheme,
                  ),
                ),
                tab(1, () => FavoriteThreadsPage(repository: _repository)),
                tab(2, () => SearchScreen(repository: _repository)),
                tab(
                  3,
                  () => _repository.isLoggedIn
                      ? PmBoxScreen(repository: _repository)
                      : Scaffold(
                          appBar: AppBar(title: const Text('短消息')),
                          body: LoginPrompt(
                            icon: Icons.mail_outline,
                            title: '短消息',
                            message: '登录后可以查看收件箱、发件箱和消息跟踪。',
                            onLogin: () => openLogin(context, _repository),
                          ),
                        ),
                ),
                tab(
                  4,
                  () => AccountScreen(
                    repository: _repository,
                    onLoggedOut: _showHome,
                    onBrowseHome: _showHome,
                  ),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelBehavior: compactLabels
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
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
                  icon: Icon(Icons.search),
                  label: '搜索',
                ),
                NavigationDestination(
                  icon: Icon(Icons.mail_outline),
                  selectedIcon: Icon(Icons.mail),
                  label: '消息',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ForumHomePage extends StatefulWidget {
  const ForumHomePage({
    super.key,
    required this.repository,
    this.onAccountTap,
    this.onToggleTheme,
  });

  final ForumRepository repository;

  /// Shows the signed-in user's 我的 tab.
  final VoidCallback? onAccountTap;
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
                    onAccountTap: widget.onAccountTap,
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
