import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show SynchronousFuture, listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../services/forum_search_preferences.dart';
import '../../services/forum_trace_logger.dart';
import '../../services/home_reading_preferences.dart';
import '../../services/watch_notifications.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../common/app_switcher.dart';
import '../common/app_tab_header.dart';
import '../common/async_state_view.dart';
import '../common/brand_mark.dart';
import '../common/sub_tabs.dart';
import '../common/thread_row.dart';
import '../messages/live_notice_banner.dart';
import '../messages/messages_screen.dart';
import '../profile/account_screen.dart';
import '../profile/favorite_threads_page.dart';
import '../profile/favorite_collections_sheets.dart';
import '../profile/home_boards_settings_screen.dart';
import '../profile/forum_tasks_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';
import 'quick_list_settings_screen.dart';

part 'home_board_shortcuts.dart';
part 'home_widgets.dart';

/// The shell tab a forum link asked for, e.g. the forum homepage; every
/// request notifies, even for the tab asked for last time.
class _TabRequests extends ChangeNotifier {
  int tab = 0;

  void request(int value) {
    tab = value;
    notifyListeners();
  }
}

final _tabRequests = _TabRequests();

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, ForumRepository? repository})
      : repository = repository;

  final ForumRepository? repository;

  static const homeTab = 0;
  static const accountTab = 4;

  /// Returns to the shell and shows [tab], as a link to that page does.
  static void showTab(BuildContext context, int tab) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _tabRequests.request(tab);
  }

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

  void _onTabRequest() => _select(_tabRequests.tab);

  // A page asking 放弃修改 for a tapped notification.
  Route<dynamic>? _asking;

  void _onWatch() {
    final watch = _repository.watch;
    if (_asking != null ||
        (watch.pendingNoticeOpen == null && watch.pendingOpen == null)) {
      return;
    }
    _showMessages();
  }

  // A tapped notification closes what is open on top and shows 消息, which
  // turns to its tab. A page that asks before closing (an unsaved draft)
  // asks as Back does.
  void _showMessages() {
    final navigator = Navigator.of(context);
    Route<dynamic>? guarded;
    navigator.popUntil((route) {
      if (!route.isFirst &&
          route.popDisposition == RoutePopDisposition.doNotPop) {
        guarded = route;
      }
      return route.isFirst || guarded != null;
    });
    if (guarded case final page?) {
      _asking = page;
      unawaited(_askToLeave(navigator, page));
      return;
    }
    if (_index != 3) _select(3);
  }

  // 放弃 goes on to 消息; keeping the page, or a page still saving, drops the
  // tap.
  Future<void> _askToLeave(
      NavigatorState navigator, Route<dynamic> page) async {
    await navigator.maybePop();
    if (!mounted) return;
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    if (top case final question? when question != page) await question.popped;
    // The page closes itself right after its question does.
    await Future<void>.delayed(Duration.zero);
    _asking = null;
    if (!mounted) return;
    if (page.isActive) {
      _repository.watch
        ..takePendingOpen()
        ..takePendingNoticeOpen();
      MessagesScreen.cancelTabRequest();
    } else {
      _showMessages();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabRequests.addListener(_onTabRequest);
    // The repository owns the service; the shell only starts its checks.
    _repository.watch.addListener(_onWatch);
    unawaited(_repository.watch.start());
    _repository.liveSync.start();
    // Above every page, so a notice shows wherever the reader is.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).overlay!.insert(_banner);
      _bannerInserted = true;
    });
  }

  // Inserted is not yet mounted: the entry builds a frame later.
  var _bannerInserted = false;

  late final _banner = OverlayEntry(
    builder: (_) => LiveNoticeBanner(
      notices: _repository.liveSync.latestNotice,
      suppressed: (kind) => MessagesScreen.visibleKind == kind,
      onOpen: _openNotice,
    ),
  );

  // Like a tapped system notification, without reloading the list: the
  // sync that raised the notice has just refreshed it.
  void _openNotice(NoticeNotificationKind kind) {
    if (_asking != null) return;
    MessagesScreen.requestTab(kind);
    _showMessages();
  }

  @override
  void dispose() {
    _tabRequests.removeListener(_onTabRequest);
    _repository.watch.removeListener(_onWatch);
    _repository.watch.stop();
    _repository.liveSync.stop();
    if (_bannerInserted) _banner.remove();
    _banner.dispose();
    super.dispose();
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
        // A hidden tab keeps its state, not its tickers: work it runs can
        // tell it left the screen.
        Widget tab(int index, Widget Function() build) => _opened
                .contains(index)
            ? TickerMode(
                enabled: index == _index,
                child: KeyedSubtree(
                    key: ValueKey(
                        (index, owner, scope, _repository.sessionEpoch.value)),
                    child: build()))
            : const SizedBox.shrink();
        return PopScope(
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _select(0);
          },
          child: ListenableBuilder(
            listenable:
                Listenable.merge([_repository.noticeFlags, _repository.watch]),
            builder: (context, _) {
              final flags = _repository.noticeFlags.value;
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
                            body: Column(children: [
                              const AppTabHeader(title: '消息'),
                              Expanded(
                                child: LoginPrompt(
                                  icon: Icons.mail_outline,
                                  onLogin: () =>
                                      openLogin(context, _repository),
                                ),
                              ),
                            ]),
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
              // Any kind of unread dots the 消息 destination.
              final unread = flags.unreadPm ||
                  flags.replyNotice ||
                  _repository.watch.unreadCount > 0;
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
                    Expanded(
                      key: const ValueKey('pages'),
                      child: _TabReveal(index: _index, child: pages),
                    ),
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

/// Brings a newly selected tab in: it fades up from 65% (never through
/// blank) and rises 12px. The tab left is hidden at once, so only one is
/// ever visible or tappable; a new account or session swaps in place.
class _TabReveal extends StatefulWidget {
  const _TabReveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabReveal> createState() => _TabRevealState();
}

class _TabRevealState extends State<_TabReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final _curve =
      CurvedAnimation(parent: _controller, curve: AppMotion.enter);

  @override
  void didUpdateWidget(covariant _TabReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: 0.65 + 0.35 * _curve.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - _curve.value)),
          child: child,
        ),
      ),
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
  bool _prefsReady = false;
  bool _layoutBusy = false;
  Object? _prefsError;
  late final _epoch = widget.repository.sessionEpoch.value;

  bool get _current =>
      mounted &&
      _account == widget.repository.localPreferenceAccount &&
      _epoch == widget.repository.sessionEpoch.value;

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
    widget.repository.liveSync.homeRevision.addListener(_onHomeRevision);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden behind another tab or page; a revision missed meanwhile is
    // caught up on return.
    final shown = TickerMode.of(context);
    if (shown == _shown) return;
    _shown = shown;
    if (shown && _stale) _quietRefresh();
  }

  @override
  void dispose() {
    widget.repository.liveSync.homeRevision.removeListener(_onHomeRevision);
    HomeReadingPreferences.revision.removeListener(_loadPrefs);
    super.dispose();
  }

  bool _shown = true;
  bool _stale = false;
  // Numbers every home load, so a quiet one never lands over a newer one.
  int _homeLoads = 0;

  void _onHomeRevision() {
    _stale = true;
    if (_shown) _quietRefresh();
  }

  /// Reads the home again behind what is shown; it swaps in only once read,
  /// and a failure keeps the page as it is.
  Future<void> _quietRefresh() async {
    _stale = false;
    final load = ++_homeLoads;
    final ForumHomeSnapshot data;
    try {
      data = await _fetchHome();
    } catch (_) {
      return; // The next revision tries again.
    }
    if (!_current || load != _homeLoads) return;
    setState(() {
      _future = SynchronousFuture(data);
    });
  }

  Future<void> _loadPrefs() async {
    final run = ++_prefsRun;
    try {
      final prefs = await HomeReadingPreferences.load(account: _account);
      if (!_current || run != _prefsRun) return;
      // New sources need a new snapshot; rows, folds and visits do not.
      final sourcesChanged =
          _prefsReady && !listEquals(prefs.quickSources, _prefs.quickSources);
      setState(() {
        _prefs = prefs;
        _prefsReady = true;
        _prefsError = null;
      });
      if (sourcesChanged) _refresh();
    } catch (error) {
      if (_current && run == _prefsRun) setState(() => _prefsError = error);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Layout writes wait for the one in flight, and stop while the saved state
  // could not be read back (the screen may not show what is stored).
  bool get _layoutLocked => _layoutBusy || _prefsError != null;

  Future<void> _toggleCollapsed(String id, List<ForumSection> sections) async {
    if (!_current || _layoutLocked) return;
    final prefs = _prefs.reconcile(sections);
    final collapse = !prefs.collapsedIds.contains(id);
    setState(() {
      _layoutBusy = true;
      _prefs = prefs.copyWith(collapsedIds: {
        ...prefs.collapsedIds.where((other) => other != id),
        if (collapse) id,
      });
    });
    try {
      await HomeReadingPreferences.setCollapsed(id, collapse,
          account: _account, sections: sections);
    } catch (_) {
      // Back to what was acknowledged before reading again, so a failed read
      // cannot leave the unsaved fold on screen.
      if (_current) setState(() => _prefs = prefs);
      _showMessage('无法保存折叠状态');
      await _loadPrefs();
    } finally {
      if (_current) setState(() => _layoutBusy = false);
    }
  }

  // Like every layout write, waits while the saved state is unread.
  void _openQuickSettings() {
    if (!_current || _layoutLocked) return;
    final page = QuickListSettingsScreen(repository: widget.repository);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<ForumHomeSnapshot> _fetchHome() {
    final account = widget.repository.currentUsername;
    return widget.repository.fetchHome().then((data) {
      unawaited(_saveShape(account, data));
      return data;
    });
  }

  /// Reloads the home; a [pulled] refresh brings 消息 up to date with it.
  Future<void> _refresh({bool pulled = false}) async {
    final next = _fetchHome();
    _homeLoads++;
    setState(() {
      _future = next;
    });
    // After the home read starts, so the notice check can share its page.
    // Handled from the start: it may fail while the home still loads.
    final messages = pulled && widget.repository.isLoggedIn
        ? _awaitMessages(widget.repository.liveSync.syncMessages(user: true))
        : null;
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error state.
    }
    await messages;
  }

  Future<void> _awaitMessages(Future<void> messages) async {
    try {
      await messages;
    } catch (_) {
      if (!_current) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('消息同步失败'),
        action: SnackBarAction(
          label: '重试',
          onPressed: () => _awaitMessages(
              widget.repository.liveSync.syncMessages(user: true)),
        ),
      ));
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

  void _openHomeSettings() {
    if (!_current) return;
    final page = HomeBoardsSettingsScreen(repository: widget.repository);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  String? _boardFid(ForumBoard board) => widget.repository.searchBoardId(
      ForumCategory(name: board.name, slug: board.slug, url: board.url));

  Future<void> _homeActions(
      {String? sectionId,
      ForumBoard? board,
      required List<ForumSection> sections}) async {
    if (!_current || _layoutLocked) return;
    final fid = board == null ? null : _boardFid(board);
    if (sectionId == null && fid == null) return;
    final epoch = widget.repository.sessionEpoch.value;
    final account = widget.repository.localPreferenceAccount;
    final sectionTitle = board == null
        ? sections
            .where((s) =>
                _prefs.reconcile(sections).sectionId(s, sections) == sectionId)
            .firstOrNull
            ?.title
        : sections.where((s) => s.items.contains(board)).firstOrNull?.title;
    final caption = board == null
        ? null
        : [
            if (sectionTitle != null && sectionTitle.trim().isNotEmpty)
              sectionTitle.trim(),
            if (board.children.isNotEmpty) '含 ${board.children.length} 个子版块',
          ].join(' · ');
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
      builder: (sheetContext) => SessionBound(
        session: widget.repository.sessionEpoch,
        generation: epoch,
        child: SafeArea(
            child: SingleChildScrollView(
                child: _HomeActionsSheet(
          title: board?.name ?? sectionTitle ?? '',
          caption: caption,
          board: board != null,
          onPick: (action) => Navigator.pop(sheetContext, action),
        ))),
      ),
    );
    if (action == null || !_current || account != _account || epoch != _epoch)
      return;
    if (action == 'manage') {
      _openHomeSettings();
      return;
    }
    if (action == 'open' && board != null) {
      _openBoard(board);
      return;
    }
    setState(() => _layoutBusy = true);
    try {
      if (sectionId != null) {
        await HomeReadingPreferences.setSectionHidden(sectionId, true,
            account: account, sections: sections);
      } else {
        await HomeReadingPreferences.setParentHidden(fid!, true,
            account: account, sections: sections);
      }
      await _loadPrefs();
    } catch (_) {
      _showMessage('无法保存隐藏设置，请重试');
    } finally {
      if (_current) setState(() => _layoutBusy = false);
    }
  }

  static String _quickListsKey(ForumHomeSnapshot? data) => data == null
      ? 'loading'
      : [
          'lists',
          for (final list in data.quickLists)
            '${list.title}/${list.source.kind.name}/${list.source.fid}/'
                '${list.source.order.name}',
        ].join('|');

  static String _hiddenSummary(int sections, int boards) => '首页已隐藏 ${[
        if (sections > 0) '$sections 个分区',
        if (boards > 0) '$boards 个版块',
      ].join('、')}';

  List<Widget> _section(ForumSection section, List<ForumSection> sections,
      int i, double inner, HomeReadingPreferences prefs) {
    final id = prefs.sectionId(section, sections);
    final collapsed = id != null && prefs.collapsedIds.contains(id);
    final boards = section.items
        .where((board) => !prefs.hiddenParentFids.contains(_boardFid(board)))
        .toList();
    return [
      const SizedBox(height: 32),
      _SectionHeader(
        section.title,
        key: ValueKey('home-section-$i'),
        collapsed: collapsed,
        // Taps while a write is in flight are ignored inside; the header
        // keeps its look.
        onToggle: id == null ? null : () => _toggleCollapsed(id, sections),
        onLongPress: id == null
            ? null
            : () => _homeActions(sectionId: id, sections: sections),
      ),
      _Collapsible(
        collapsed: collapsed,
        child: _BoardGrid(
          key: ValueKey('home-grid-$i'),
          boards: boards,
          columns: inner >= 960 ? 3 : (inner >= 600 ? 2 : 1),
          onOpen: _openBoard,
          onLongPress: (board) =>
              _homeActions(board: board, sections: sections),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _HomeHeader(
            repository: widget.repository,
            onAccountTap: widget.onAccountTap,
          ),
          Expanded(child: LayoutBuilder(
            builder: (context, constraints) {
              // A centred column at most _homeMaxWidth wide; phones (< 600)
              // get single-column lists.
              final width = constraints.maxWidth;
              final compact = width < 600;
              final gutter = math.max(
                compact ? AppSpace.lg : AppSpace.xl,
                (width - _homeMaxWidth) / 2,
              );
              final inner = width - 2 * gutter;
              return RefreshIndicator(
                color: AppColors.brand,
                onRefresh: () => _refresh(pulled: true),
                child: FutureBuilder<ForumHomeSnapshot>(
                  future: _future,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    final sections = data?.sections ?? const <ForumSection>[];
                    final prefs = _prefs.reconcile(sections);
                    final hiddenSections = sections
                        .where((s) => prefs.hiddenSectionIds
                            .contains(prefs.sectionId(s, sections)))
                        .length;
                    final hiddenParents = {
                      for (final s in sections)
                        for (final b in s.items) _boardFid(b)
                    }.where((id) => prefs.hiddenParentFids.contains(id)).length;
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        compact ? AppSpace.sm : AppSpace.xl,
                        gutter,
                        32,
                      ),
                      children: [
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
                                  tooltip: '速览设置',
                                  onPressed: data == null || _layoutLocked
                                      ? null
                                      : _openQuickSettings,
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
                            // A new set of lists starts over; a fresher
                            // snapshot of the same ones swaps in place, so
                            // the open tab stays.
                            key: ValueKey(_quickListsKey(data)),
                            lists: data?.quickLists,
                            latest: data?.latest ?? const [],
                            // Large text gives up the side-by-side lists.
                            columns: inner >= 840 &&
                                MediaQuery.textScalerOf(context).scale(1) <=
                                    1.3,
                            rows: _prefs.quickRowCount,
                            repository: widget.repository,
                            onChangeSource: _openQuickSettings,
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
                          if (data == null || !_prefsReady)
                            if (_prefsError == null)
                              // One quiet block: order and hiding are not
                              // known yet, so no section takes its place.
                              const Padding(
                                key: ValueKey('home-directory-pending'),
                                padding: EdgeInsets.only(top: 32),
                                child: ThreadRowSkeleton(itemCount: 6),
                              )
                            else
                              _HomeFootnote(
                                key: const ValueKey('home-layout-retry'),
                                text: '首页设置未能读取',
                                action: '重试',
                                onAction: _loadPrefs,
                              )
                          else ...[
                            for (final section
                                in prefs.orderedSections(sections))
                              if (!prefs.hiddenSectionIds
                                  .contains(prefs.sectionId(section, sections)))
                                ..._section(section, sections,
                                    sections.indexOf(section), inner, prefs),
                            if (_prefsError != null)
                              _HomeFootnote(
                                key: const ValueKey('home-layout-retry'),
                                text: '首页设置未能读取',
                                action: '重试',
                                onAction: _loadPrefs,
                              )
                            else if (hiddenSections + hiddenParents > 0)
                              _HomeFootnote(
                                key: const ValueKey('home-hidden-summary'),
                                text: _hiddenSummary(
                                    hiddenSections, hiddenParents),
                                action: '管理',
                                onAction: _openHomeSettings,
                              ),
                          ],
                        ],
                      ],
                    );
                  },
                ),
              );
            },
          )),
        ]),
      ),
    );
  }
}
