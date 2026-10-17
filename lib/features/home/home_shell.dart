import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_search_preferences.dart';
import '../../services/forum_trace_logger.dart';
import '../../services/home_reading_preferences.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../common/async_state_view.dart';
import '../common/brand_mark.dart';
import '../common/thread_row.dart';
import '../messages/messages_screen.dart';
import '../profile/account_screen.dart';
import '../profile/favorite_threads_page.dart';
import '../profile/forum_tasks_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';

part 'home_board_shortcuts.dart';
part 'home_widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, ForumRepository? repository})
      : repository = repository;

  final ForumRepository? repository;

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
    return ListenableBuilder(
      // A guest switching forum origin keeps the same (null) user, so the
      // session epoch is watched too and the key carries the storage scope.
      listenable:
          Listenable.merge([_repository.sessionUser, _repository.sessionEpoch]),
      builder: (context, _) {
        final owner = _repository.sessionUser.value;
        final scope = _repository.localPreferenceAccount;
        // A new owner or storage scope rebuilds every tab, so no account's
        // data lingers.
        Widget tab(int index, Widget Function() build) => _opened
                .contains(index)
            ? KeyedSubtree(key: ValueKey((index, owner, scope)), child: build())
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
                    ),
                  ),
                  tab(1, () => FavoriteThreadsPage(repository: _repository)),
                  tab(2, () => SearchScreen(repository: _repository)),
                  tab(
                    3,
                    () => _repository.isLoggedIn
                        ? MessagesScreen(repository: _repository)
                        : Scaffold(
                            appBar: AppBar(title: const Text('消息')),
                            body: LoginPrompt(
                              icon: Icons.mail_outline,
                              title: '消息',
                              message: '登录后可以查看短消息和回复提醒。',
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
              // Either kind of unread dots the 消息 destination.
              final unread = flags.unreadPm || flags.replyNotice;
              final pmIcon = Badge(
                isLabelVisible: unread,
                child: const Icon(Icons.mail_outline),
              );
              final pmSelectedIcon = Badge(
                isLabelVisible: unread,
                child: const Icon(Icons.mail),
              );
              final destinations = [
                (
                  const Icon(Icons.home_outlined),
                  const Icon(Icons.home),
                  '首页',
                ),
                (
                  const Icon(Icons.star_outline),
                  const Icon(Icons.star),
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
              return Scaffold(
                body: Row(
                  children: [
                    if (rail) ...[
                      SafeArea(
                        right: false,
                        child: NavigationRail(
                          selectedIndex: _index,
                          onDestinationSelected: _select,
                          minWidth: 80,
                          labelType: NavigationRailLabelType.all,
                          leading: const Padding(
                            padding: EdgeInsets.only(top: 4, bottom: 12),
                            child: BrandMark(size: 40),
                          ),
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
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysShow,
                        destinations: [
                          for (final (icon, selected, label) in destinations)
                            NavigationDestination(
                              icon: icon,
                              selectedIcon: selected,
                              label: label,
                              tooltip: identical(icon, pmIcon) && unread
                                  ? '消息，有未读'
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
  });

  final ForumRepository repository;

  /// Shows the signed-in user's 我的 tab.
  final VoidCallback? onAccountTap;

  @override
  State<ForumHomePage> createState() => _ForumHomePageState();
}

/// The directory's geometry as last loaded, for the placeholders: how many
/// hot boards, and per section each board's [_tileLines]. No names or ids.
/// The first load ever guesses.
typedef _HomeShape = ({int hot, List<List<int>> sections});

const _HomeShape _guessedShape = (
  hot: 6,
  sections: [
    [3, 3, 3, 3, 3, 3],
    [3, 3, 3, 3, 3, 3],
  ],
);

// Per account: what a directory holds can depend on who is signed in.
String _shapeKey(String? account) =>
    'home_layout_shape/${Uri.encodeComponent(account ?? '')}';

Future<_HomeShape> _loadShape(String? account) async {
  try {
    final raw =
        (await SharedPreferences.getInstance()).getString(_shapeKey(account));
    if (raw == null) return _guessedShape;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (
      hot: json['hot'] as int,
      sections: [
        for (final section in json['sections'] as List)
          [for (final lines in section as List) lines as int],
      ],
    );
  } catch (_) {
    return _guessedShape;
  }
}

Future<void> _saveShape(String? account, ForumHomeSnapshot data) async {
  try {
    await (await SharedPreferences.getInstance()).setString(
      _shapeKey(account),
      jsonEncode({
        'hot': data.hot.length,
        'sections': [
          for (final section in data.sections)
            [for (final board in section.items) _tileLines(board)],
        ],
      }),
    );
  } catch (_) {
    // Only the next placeholders lose their shape.
  }
}

class _ForumHomePageState extends State<ForumHomePage> {
  late Future<ForumHomeSnapshot> _future;
  _HomeShape _shape = _guessedShape;
  // The account is fixed per page: a new owner rebuilds the whole tab.
  late final String? _account = widget.repository.localPreferenceAccount;
  HomeReadingPreferences _prefs = const HomeReadingPreferences();
  int _prefsRun = 0;

  @override
  void initState() {
    super.initState();
    _future = _fetchHome();
    _loadShape(widget.repository.currentUsername).then((shape) {
      if (mounted) setState(() => _shape = shape);
    });
    _loadPrefs();
    // Visits, row count and folds change elsewhere too (a board route, the
    // search tab), so any write reloads them.
    HomeReadingPreferences.revision.addListener(_loadPrefs);
  }

  @override
  void dispose() {
    HomeReadingPreferences.revision.removeListener(_loadPrefs);
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final run = ++_prefsRun;
    try {
      final prefs = await HomeReadingPreferences.load(account: _account);
      if (mounted && run == _prefsRun) setState(() => _prefs = prefs);
    } catch (_) {
      // The defaults stay.
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleCollapsed(String id) async {
    final collapse = !_prefs.collapsedIds.contains(id);
    setState(() {
      _prefs = HomeReadingPreferences(
        quickRowCount: _prefs.quickRowCount,
        collapsedIds: {
          for (final other in _prefs.collapsedIds)
            if (other != id) other,
          if (collapse) id,
        },
        recentBoards: _prefs.recentBoards,
      );
    });
    try {
      await HomeReadingPreferences.setCollapsed(id, collapse,
          account: _account);
    } catch (_) {
      _showMessage('无法保存折叠状态');
      _loadPrefs();
    }
  }

  Future<void> _pickQuickRows() async {
    final rows = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (_) => _QuickRowsSheet(current: _prefs.quickRowCount),
    );
    if (rows == null || rows == _prefs.quickRowCount || !mounted) return;
    setState(() {
      _prefs = HomeReadingPreferences(
        quickRowCount: rows,
        collapsedIds: _prefs.collapsedIds,
        recentBoards: _prefs.recentBoards,
      );
    });
    try {
      await HomeReadingPreferences.saveQuickRowCount(rows, account: _account);
    } catch (_) {
      _showMessage('无法保存显示行数');
      _loadPrefs();
    }
  }

  Future<ForumHomeSnapshot> _fetchHome() {
    final account = widget.repository.currentUsername;
    return widget.repository.fetchHome().then((data) {
      unawaited(_saveShape(account, data));
      return data;
    });
  }

  Future<void> _refresh() async {
    final next = _fetchHome();
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

  // A foldable section; the fold is remembered under its title.
  List<Widget> _section(ForumHomeSnapshot? data, int i, double inner) {
    final section = data?.sections[i];
    final title = section?.title.trim() ?? '';
    final id = title.isEmpty ? null : 'section:$title';
    final collapsed = id != null && _prefs.collapsedIds.contains(id);
    return [
      const SizedBox(height: 32),
      _SectionHeader(
        section?.title,
        key: ValueKey('home-section-$i'),
        note: section == null ? null : '${section.items.length} 个版块',
        collapsed: collapsed,
        onToggle: id == null ? null : () => _toggleCollapsed(id),
      ),
      _Collapsible(
        collapsed: collapsed,
        child: _BoardGrid(
          key: ValueKey('home-grid-$i'),
          boards: section?.items ?? const [],
          bones: section == null ? _shape.sections[i] : null,
          columns: inner >= 960 ? 3 : (inner >= 600 ? 2 : 1),
          onOpen: _openBoard,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A centred column at most _homeMaxWidth wide; phones (< 600)
            // get a compact header and single-column lists.
            final width = constraints.maxWidth;
            final compact = width < 600;
            final gutter = math.max(
              compact ? 16.0 : 32.0,
              (width - _homeMaxWidth) / 2,
            );
            final inner = width - 2 * gutter;
            return RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _refresh,
              child: FutureBuilder<ForumHomeSnapshot>(
                future: _future,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  // Null data renders the same layout with placeholders.
                  final sectionCount =
                      data?.sections.length ?? _shape.sections.length;
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      compact ? 4 : 24,
                      gutter,
                      32,
                    ),
                    children: [
                      _HomeHeader(
                        repository: widget.repository,
                        onAccountTap: widget.onAccountTap,
                      ),
                      SizedBox(height: compact ? 16 : 32),
                      if (snapshot.hasError)
                        AsyncErrorView(
                          title: '主页加载失败',
                          message: '${snapshot.error}',
                          onRetry: _refresh,
                        )
                      else ...[
                        _SectionHeader(
                          '速览',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '显示行数',
                                onPressed: data == null ? null : _pickQuickRows,
                                icon: const Icon(Icons.tune, size: 20),
                              ),
                              data == null
                                  ? _taskButtonPlaceholder()
                                  : _TaskShortcut(
                                      repository: widget.repository),
                            ],
                          ),
                        ),
                        _QuickLists(
                          // Lazy lists reload with the snapshot they came from.
                          key: ObjectKey(data),
                          lists: data?.quickLists,
                          latest: data?.latest ?? const [],
                          // Large text gives up the side-by-side lists.
                          columns: inner >= 840 &&
                              MediaQuery.textScalerOf(context).scale(1) <= 1.3,
                          rows: _prefs.quickRowCount,
                          repository: widget.repository,
                        ),
                        _HotBoards(
                          hotBoards: data?.hot,
                          boneCount: _shape.hot,
                          onOpen: _openCategory,
                        ),
                        _MyBoards(
                          repository: widget.repository,
                          recent: _prefs.recentBoards,
                          hotBoards: data?.hot,
                          sections: data?.sections,
                          onOpen: _openCategory,
                        ),
                        for (var i = 0; i < sectionCount; i++)
                          ..._section(data, i, inner),
                      ],
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
