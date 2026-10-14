import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_search_preferences.dart';
import '../../services/forum_trace_logger.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../common/async_state_view.dart';
import '../common/forum_title_text.dart';
import '../messages/pm_box_screen.dart';
import '../messages/reply_notices_screen.dart';
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
          child: ValueListenableBuilder<ForumNoticeFlags>(
            valueListenable: _repository.noticeFlags,
            builder: (context, flags, _) {
              final width = MediaQuery.sizeOf(context).width;
              final pages = IndexedStack(
                index: _index,
                children: [
                  tab(
                    0,
                    () => ForumHomePage(
                      repository: _repository,
                      onAccountTap: () => _select(4),
                      onMessagesTap: () => _select(3),
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
              );
              final pmIcon = Badge(
                isLabelVisible: flags.unreadPm,
                child: const Icon(Icons.mail_outline),
              );
              final pmSelectedIcon = Badge(
                isLabelVisible: flags.unreadPm,
                child: const Icon(Icons.mail),
              );
              final destinations = [
                (
                  const Icon(Icons.home_outlined),
                  const Icon(Icons.home),
                  '首页',
                ),
                (
                  const Icon(Icons.star_border_rounded),
                  const Icon(Icons.star_rounded),
                  '收藏',
                ),
                (const Icon(Icons.search), const Icon(Icons.search), '搜索'),
                (pmIcon, pmSelectedIcon, '消息'),
                (
                  const Icon(Icons.person_outline),
                  const Icon(Icons.person),
                  '我的',
                ),
              ];
              // Rail on tablets and desktop windows; bottom bar on phones.
              final rail = width >= 600;
              final extended = width > 840;
              return Scaffold(
                body: Row(
                  children: [
                    if (rail) ...[
                      SafeArea(
                        right: false,
                        child: NavigationRail(
                          extended: extended,
                          selectedIndex: _index,
                          onDestinationSelected: _select,
                          labelType: extended
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          destinations: [
                            for (final (icon, selected, label) in destinations)
                              NavigationRailDestination(
                                icon: icon,
                                selectedIcon: selected,
                                label: Text(label),
                              ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 1, color: AppColors.border),
                    ],
                    // Keyed so resizing across breakpoints keeps every tab.
                    Expanded(key: const ValueKey('pages'), child: pages),
                  ],
                ),
                bottomNavigationBar: rail
                    ? null
                    : NavigationBar(
                        selectedIndex: _index,
                        onDestinationSelected: _select,
                        labelBehavior: compactLabels
                            ? NavigationDestinationLabelBehavior
                                .onlyShowSelected
                            : NavigationDestinationLabelBehavior.alwaysShow,
                        destinations: [
                          for (final (icon, selected, label) in destinations)
                            NavigationDestination(
                              icon: icon,
                              selectedIcon: selected,
                              label: label,
                              tooltip: identical(icon, pmIcon) && flags.unreadPm
                                  ? '消息，有未读短消息'
                                  : null,
                            ),
                        ],
                      ),
              );
            },
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
    this.onMessagesTap,
    this.onToggleTheme,
  });

  final ForumRepository repository;

  /// Shows the signed-in user's 我的 tab.
  final VoidCallback? onAccountTap;

  /// Shows the 消息 (short messages) tab.
  final VoidCallback? onMessagesTap;
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

  void _openCategory(ForumCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardThreadListScreen(
          category: category,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Window breakpoints: compact < 600 <= medium <= 840 < expanded. The
    // side panel needs room beside the extended rail, so it starts at 1100.
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final expanded = width > 840;
    final sidePanel = width >= 1100;
    final loggedIn = widget.repository.isLoggedIn;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<ForumHomeSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final hot = [
              for (final category in data?.hot ?? const <ForumCategory>[])
                _ForumLink(
                  title: category.name,
                  subtitle: category.slug,
                  onTap: () => _openCategory(category),
                ),
            ];
            // Columns follow the feed's own width so cards never get cramped.
            final feed = LayoutBuilder(
              builder: (context, constraints) => RefreshIndicator(
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
                    if (loggedIn && !sidePanel)
                      _NoticeChips(
                        repository: widget.repository,
                        onMessagesTap: widget.onMessagesTap,
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
                      _QuickLists(
                        // Lazy lists reload with the snapshot they came from.
                        key: ObjectKey(data),
                        lists: data.quickLists,
                        latest: data.latest,
                        columns: compact
                            ? 1
                            : (constraints.maxWidth / 240).floor().clamp(2, 4),
                        repository: widget.repository,
                      ),
                      const SizedBox(height: 14),
                      if (!sidePanel && hot.isNotEmpty)
                        _ForumGroup(
                          title: '热门版块',
                          icon: Icons.local_fire_department_outlined,
                          children: hot,
                        ),
                      for (final section in data.sections)
                        _ForumGroup(
                          title: section.title,
                          initiallyExpanded: !compact,
                          children: [
                            _BoardGrid(
                              boards: section.items,
                              columns: compact
                                  ? 1
                                  : (constraints.maxWidth / 300)
                                      .floor()
                                      .clamp(2, 4),
                              showCounts: expanded,
                              onOpen: _openBoard,
                            ),
                          ],
                        ),
                      const _DesktopLink(),
                    ],
                  ],
                ),
              ),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sidePanel) ...[
                  SizedBox(
                    width: 300,
                    child: _SidePanel(
                      repository: widget.repository,
                      onAccountTap: widget.onAccountTap,
                      onMessagesTap: widget.onMessagesTap,
                      onOpenBoard: _openCategory,
                      hotBoards: data?.hot ?? const [],
                    ),
                  ),
                  VerticalDivider(width: 1, color: AppColors.border),
                ],
                // Keyed so crossing a breakpoint keeps scroll and lazy lists.
                Expanded(key: const ValueKey('feed'), child: feed),
              ],
            );
          },
        ),
      ),
    );
  }
}
