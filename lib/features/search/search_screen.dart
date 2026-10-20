import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_blocking_settings.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../services/forum_search_preferences.dart';
import '../../services/loading_preferences.dart';
import '../../services/search_board_hierarchy.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/app_tab_header.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/forum_pager.dart';
import '../common/page_end.dart';
import '../common/thread_row.dart';
import '../thread/thread_detail_screen.dart';

const _allBoards = ForumSearchBoard(id: 'all', name: '全部版块');

typedef _KeywordOwner = ({ForumRepository repository, (String?, int) session});

const _matchLabels = {
  ForumSearchMatch.partial: '部分匹配',
  ForumSearchMatch.exact: '完全匹配',
};

const _timeLabels = {
  ForumSearchTime.all: '全部时间',
  ForumSearchTime.newTopics: '最新主题',
  ForumSearchTime.day: '一天内',
  ForumSearchTime.twoDays: '两天内',
  ForumSearchTime.week: '一周内',
  ForumSearchTime.month: '一个月内',
  ForumSearchTime.twoMonths: '两个月内',
  ForumSearchTime.threeMonths: '三个月内',
  ForumSearchTime.halfYear: '半年内',
  ForumSearchTime.year: '一年内',
};

const _orderLabels = {
  ForumThreadOrder.postedAt: '发表时间',
  ForumThreadOrder.lastPost: '最后发表',
  ForumThreadOrder.replies: '回复',
  ForumThreadOrder.hits: '人气',
};

/// Advanced thread search: one scrolling page whose form folds into a
/// summary once results arrive. Initial values let other screens open it
/// pre-filled (a board, a user, a title).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    this.initialKeyword = '',
    this.initialUsername = '',
    this.initialBoard,
  });

  final ForumRepository repository;
  final String initialKeyword;
  final String initialUsername;
  final ForumSearchBoard? initialBoard;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _keyword = TextEditingController(text: widget.initialKeyword);
  late final _username = TextEditingController(text: widget.initialUsername);
  final _scroll = ScrollController();
  // Field hints show only while their field is being edited.
  final _keywordFocus = FocusNode();
  final _usernameFocus = FocusNode();

  ForumSearchPreferences _prefs = const ForumSearchPreferences();
  String? _prefsAccount;
  // Recent keywords of [_prefsAccount], newest first.
  List<String> _recent = const [];
  ForumSearchMatch _match = ForumSearchMatch.partial;
  late ForumSearchBoard _board = widget.initialBoard ?? _allBoards;
  ForumSearchTime _time = ForumSearchTime.year;
  ForumThreadOrder _order = ForumThreadOrder.postedAt;
  bool _ascending = false;
  bool _digest = false;
  // Saved defaults apply only until the user picks something.
  bool _matchTouched = false;
  bool _timeTouched = false;

  List<ForumSearchBoard>? _boards;
  // Per owner and session: board visibility differs between accounts, and a
  // re-login or site switch may change it under the same name.
  final _boardLoads = <(String?, int), Future<List<ForumSearchBoard>>>{};
  final _sectionLoads = <(String?, int), Future<List<ForumSection>>>{};

  bool _filtersOpen = false;
  bool _editing = true;
  String? _formError;

  ForumSearchQuery? _query;
  ForumSearchPage? _page;
  // Pages appended below [_page] by 自动接续, in order.
  final _more = <ForumSearchPage>[];
  bool _loadingMore = false;
  Object? _moreError;
  // Appended pages in a row that added no result: after two, following on
  // waits for a tap.
  int _emptyRun = 0;
  Future<ForumSearchPage> Function()? _lastRequest;
  // The keyword the last request remembers once answered; empty for pages.
  String _lastKeyword = '';
  Object? _error;
  bool _searching = false;
  int _requestId = 0;
  bool _resultsDropped = false;
  // Ticks whenever earlier results stop belonging to this screen; an open
  // board picker listens to it.
  final _scopeChanges = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_dropResults);
    _scroll.addListener(_maybeLoadMore);
    LoadingPreferences.notifier.addListener(_onLoadingModeChanged);
    if (!LoadingPreferences.isReady) LoadingPreferences.load().ignore();
    for (final focus in [_keywordFocus, _usernameFocus]) {
      focus.addListener(_refreshFocus);
    }
    _loadPrefs();
    // A board known only by id (e.g. from a link) gets its name from the list.
    if (_board.name.isEmpty) _loadBoards().ignore();
  }

  // Results, pages and retries belong to the session that fetched them; a
  // request still running is dropped by the new id.
  void _dropResults() {
    if (!mounted) return;
    _scopeChanges.value++;
    setState(() {
      _clearResults();
      _recent = const [];
    });
    // The new owner's keywords show at once.
    _loadPrefs();
  }

  void _clearResults() {
    _resultsDropped = _query != null;
    _requestId++;
    _searching = false;
    _query = null;
    _page = null;
    _clearMore();
    _error = null;
    _lastRequest = null;
    _editing = true;
  }

  void _clearMore() {
    _more.clear();
    _loadingMore = false;
    _moreError = null;
    _emptyRun = 0;
  }

  /// 自动接续; otherwise (手动翻页, or the setting unread) pages turn by tap.
  bool get _continuous =>
      LoadingPreferences.modeFor(LoadingDomain.search) ==
      LoadingMode.continuous;

  // The footer follows the mode; a page already on its way still lands.
  void _onLoadingModeChanged() {
    if (mounted) setState(() {});
  }

  ForumSearchPage? get _lastPage => _more.isEmpty ? _page : _more.last;

  static String _threadKey(ForumThread thread) =>
      RegExp(r'(?:tid[=-]|/t)(\d+)').firstMatch(thread.url)?.group(1) ??
      thread.url;

  void _maybeLoadMore() {
    final next = _lastPage?.nextPagePath;
    if (!mounted ||
        !_continuous ||
        next == null ||
        _searching ||
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
    final query = _query;
    final next = _lastPage?.nextPagePath;
    if (query == null || next == null || _loadingMore) return;
    // A new search, page or session moves these on: the answer is dropped.
    final id = _requestId;
    final repository = widget.repository;
    final session = _session;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await repository.searchForumPage(query, next);
      if (!mounted || id != _requestId || session != _session) return;
      final seen = {
        for (final shown in [_page!, ..._more])
          for (final thread in shown.threads) _threadKey(thread),
      };
      final fresh = [
        for (final thread in page.threads)
          if (seen.add(_threadKey(thread))) thread,
      ];
      final rules = repository.blocking.notifier.value;
      final added = fresh.any((thread) => !rules.isThreadBlocked(thread));
      setState(() {
        _loadingMore = false;
        _more.add(ForumSearchPage(
          threads: fresh,
          total: page.total,
          nextPagePath: page.nextPagePath,
          previousPagePath: page.previousPagePath,
          currentPage: page.currentPage,
          pageLinks: page.pageLinks,
          totalPages: page.totalPages,
        ));
        _emptyRun = added ? 0 : _emptyRun + 1;
      });
      // A page that shows nothing adds no height to scroll through.
      if (!added) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
      }
    } catch (error) {
      if (!mounted || id != _requestId || session != _session) return;
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

  String get _boardLabel =>
      _board.name.isEmpty ? '版块 ${_board.id}' : _board.name;

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.repository, widget.repository)) return;
    oldWidget.repository.sessionEpoch.removeListener(_dropResults);
    widget.repository.sessionEpoch.addListener(_dropResults);
    // Another repository's lists and results are not this one's.
    _boardLoads.clear();
    _sectionLoads.clear();
    _boards = null;
    // A rebuild follows; an open picker is told after this frame, since
    // it may not rebuild during this one.
    _clearResults();
    _recent = const [];
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeChanges.value++;
    });
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_dropResults);
    LoadingPreferences.notifier.removeListener(_onLoadingModeChanged);
    _keyword.dispose();
    _username.dispose();
    _scroll.dispose();
    _keywordFocus.dispose();
    _usernameFocus.dispose();
    _scopeChanges.dispose();
    super.dispose();
  }

  void _refreshFocus() {
    if (!mounted) return;
    setState(() {});
    // A login without a new session still brings its own keywords.
    if (_keywordFocus.hasFocus && _prefsAccount != _account) _loadPrefs();
  }

  // Preferences belong to the signed-in account (anonymous otherwise).
  String? get _account => widget.repository.localPreferenceAccount;

  (String?, int) get _session =>
      (_account, widget.repository.sessionEpoch.value);

  Future<void> _loadPrefs() async {
    final account = _account;
    final ForumSearchPreferences prefs;
    try {
      prefs = await ForumSearchPreferences.load(account: account);
    } catch (_) {
      // Search works with the last acknowledged defaults; the board picker
      // reports its own pins and offers a retry.
      return;
    }
    // A login switch during the read must not apply the old owner's prefs.
    if (!mounted || account != _account) return;
    setState(() {
      _prefsAccount = account;
      _prefs = prefs;
      _recent = prefs.recentKeywords;
      if (!_matchTouched) _match = prefs.defaultMatch;
      if (!_timeTouched) _time = prefs.defaultTime;
    });
  }

  // Board options cost a search.php request, so load them only when needed.
  Future<List<ForumSearchBoard>> _loadBoards() {
    final session = _session;
    return _boardLoads[session] ??= widget.repository.fetchSearchBoards().then(
      (boards) {
        final list = boards.any((board) => board.id == _allBoards.id)
            ? boards
            : [_allBoards, ...boards];
        if (mounted && session == _session) {
          setState(() {
            _boards = list;
            if (_board.name.isEmpty) {
              _board = list
                      .where((b) => b.selectable && b.id == _board.id)
                      .firstOrNull ??
                  _board;
            }
          });
        }
        return list;
      },
      onError: (Object error) {
        // A failed load may be retried.
        _boardLoads.remove(session);
        throw error;
      },
    );
  }

  // Homepage sections only group the search scopes; the picker works without.
  Future<List<ForumSection>> _loadSections() {
    final session = _session;
    return _sectionLoads[session] ??=
        widget.repository.fetchForumSections().then(
      (sections) {
        // An empty result may be transient; a retry must ask again.
        if (sections.isEmpty) _sectionLoads.remove(session);
        return sections;
      },
      onError: (Object error) {
        _sectionLoads.remove(session);
        throw error;
      },
    );
  }

  bool get _filtersAtDefault =>
      _match == _prefs.defaultMatch &&
      _board.id == _allBoards.id &&
      _time == _prefs.defaultTime &&
      _order == ForumThreadOrder.postedAt &&
      !_ascending &&
      !_digest;

  void _resetFilters() {
    setState(() {
      _match = _prefs.defaultMatch;
      _board = _allBoards;
      _time = _prefs.defaultTime;
      _order = ForumThreadOrder.postedAt;
      _ascending = false;
      _digest = false;
    });
  }

  Future<void> _search() async {
    if (_searching) return;
    if (_prefsAccount != _account) {
      // Another login since the defaults were read: apply its defaults.
      setState(() => _searching = true);
      await _loadPrefs();
      if (!mounted) return;
      _searching = false;
    }
    final query = ForumSearchQuery(
      keyword: _keyword.text.trim(),
      username: _username.text.trim(),
      match: _match,
      boardId: _board.id,
      time: _time,
      order: _order,
      ascending: _ascending,
      digest: _digest,
    );
    if (query.keyword.isEmpty && query.username.isEmpty) {
      setState(() => _formError = '请输入关键词或用户名');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _resultsDropped = false;
      _query = query;
      _page = null;
    });
    _run(() => widget.repository.searchForum(query), keyword: query.keyword);
  }

  void _openPage(String pagePath) {
    // Pages follow the submitted query, never the form being edited.
    final query = _query;
    if (_searching || query == null) return;
    FocusScope.of(context).unfocus();
    _run(() => widget.repository.searchForumPage(query, pagePath));
  }

  Future<void> _run(
    Future<ForumSearchPage> Function() request, {
    String keyword = '',
  }) async {
    final id = ++_requestId;
    final repository = widget.repository;
    final session = _session;
    // A result counts only for the repository and session it started in;
    // a login may change the account before notifying.
    bool current() =>
        identical(repository, widget.repository) && session == _session;
    setState(() {
      _searching = true;
      _error = null;
      _lastRequest = request;
      _lastKeyword = keyword;
    });
    try {
      final page = await request();
      if (!mounted || id != _requestId) return;
      if (!current()) {
        _dropResults();
        return;
      }
      setState(() {
        _page = page;
        _clearMore();
        _searching = false;
        if (page.threads.isNotEmpty) _editing = false;
      });
      // An answered search counts, even with no results.
      if (keyword.isNotEmpty) {
        _editRecent(
          (repository: repository, session: session),
          (account) =>
              ForumSearchPreferences.recordKeyword(keyword, account: account),
          failure: '搜索记录保存失败',
        );
      }
      // Each new result page starts at its summary and first result.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
    } catch (error) {
      if (!mounted || id != _requestId) return;
      if (!current()) {
        _dropResults();
        return;
      }
      setState(() {
        _error = error;
        _searching = false;
      });
    }
  }

  void _retry() {
    final request = _lastRequest;
    if (request != null && !_searching) _run(request, keyword: _lastKeyword);
  }

  _KeywordOwner get _owner =>
      (repository: widget.repository, session: _session);

  bool _owns(_KeywordOwner owner) =>
      mounted &&
      identical(owner.repository, widget.repository) &&
      owner.session == _session;

  // A keyword write belongs to whoever was signed in when the user acted:
  // a confirmation or a retry that outlives that login writes nothing.
  Future<void> _editRecent(
    _KeywordOwner owner,
    Future<List<String>> Function(String? account) edit, {
    required String failure,
  }) async {
    if (!_owns(owner)) return;
    try {
      final recent = await edit(owner.session.$1);
      if (_owns(owner)) setState(() => _recent = recent);
    } catch (_) {
      if (!_owns(owner)) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(failure),
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _editRecent(owner, edit, failure: failure),
          ),
        ));
    }
  }

  Future<void> _clearRecent() async {
    final owner = _owner;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空搜索记录？'),
        content: const Text('只清除本机的关键词记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _editRecent(
      owner,
      (account) => ForumSearchPreferences.clearKeywords(account: account),
      failure: '清空失败',
    );
  }

  /// Recent keywords containing what is typed, while the field is edited;
  /// none once the field holds the only match.
  List<String> get _recentMatches {
    if (!_keywordFocus.hasFocus || _prefsAccount != _account) return const [];
    final typed = _keyword.text.trim().toLowerCase();
    final hits = _recent
        .where((keyword) => keyword.toLowerCase().contains(typed))
        .take(10)
        .toList();
    return hits.length == 1 && hits.single == _keyword.text.trim()
        ? const []
        : hits;
  }

  Future<void> _pickTime() async {
    final value = await _showChoiceSheet<ForumSearchTime>(
      context,
      title: '时间范围',
      selected: _time,
      options: _timeLabels,
    );
    if (value == null || !mounted) return;
    setState(() {
      _time = value;
      _timeTouched = true;
    });
  }

  Future<void> _pickBoard() async {
    final account = _account;
    final repository = widget.repository;
    final session = _session;
    bool inSession() =>
        mounted &&
        identical(repository, widget.repository) &&
        session == _session;
    final picked = await showModalBottomSheet<ForumSearchBoard>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BoardPickerSheet(
        sessionChanges: _scopeChanges,
        inSession: inSession,
        selectedId: _board.id,
        loadBoards: _loadBoards,
        loadSections: _loadSections,
        baseUri: repository.networkConfig.baseUri,
        loadPinned: () async =>
            (await ForumSearchPreferences.load(account: account)).pinnedBoards,
        savePinned: (boards) =>
            ForumSearchPreferences.savePinnedBoards(boards, account: account),
      ),
    );
    if (picked == null || !inSession()) return;
    setState(() => _board = picked);
    // Pins may have changed inside the sheet.
    _loadPrefs();
  }

  // The choice is read when the button is tapped, not when a retry runs.
  Future<void> _saveDefaultMatch() {
    final value = _match;
    return _saveDefault(
      (account) =>
          ForumSearchPreferences.saveDefaultMatch(value, account: account),
    );
  }

  Future<void> _saveDefaultTime() {
    final value = _time;
    return _saveDefault(
      (account) =>
          ForumSearchPreferences.saveDefaultTime(value, account: account),
    );
  }

  Future<void> _saveDefault(Future<void> Function(String? account) save) =>
      _runSave(widget.repository, _session, save);

  // A rejected write leaves the stored defaults, and so the buttons, as they
  // were; the user may retry. A retry belongs to the repository and session
  // it was made in and does nothing once either has moved on.
  Future<void> _runSave(
    ForumRepository repository,
    (String?, int) session,
    Future<void> Function(String? account) save,
  ) async {
    bool current() =>
        mounted &&
        identical(repository, widget.repository) &&
        session == _session;
    if (!current()) return;
    try {
      await save(session.$1);
    } catch (error) {
      if (!current()) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('保存失败：$error'),
            action: SnackBarAction(
              label: '重试',
              onPressed: () => _runSave(repository, session, save),
            ),
          ),
        );
      return;
    }
    if (current()) await _loadPrefs();
  }

  List<String> _filterSummary(ForumSearchQuery? query) {
    final match = query?.match ?? _match;
    final time = query?.time ?? _time;
    final order = query?.order ?? _order;
    final ascending = query?.ascending ?? _ascending;
    final digest = query?.digest ?? _digest;
    final boardName = query == null || query.boardId == _board.id
        ? _boardLabel
        : _boards
                ?.where((board) => board.id == query.boardId)
                .firstOrNull
                ?.name ??
            '版块 ${query.boardId}';
    return [
      boardName,
      _timeLabels[time]!,
      _matchLabels[match]!,
      '${_orderLabels[order]} ${ascending ? '↑' : '↓'}',
      if (digest) '精华帖',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    // A tab of the shell, or a page opened from a board, thread or link.
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: pushed ? AppBar(title: const Text('搜索')) : null,
      body: SafeArea(
        top: false,
        child: Column(children: [
          if (!pushed) const AppTabHeader(title: '搜索'),
          Expanded(child: LayoutBuilder(
            builder: (context, constraints) {
              final gutter = appGutter(constraints.maxWidth, AppWidths.list);
              final form = _editing || _query == null;
              // The form is a form (720); the summary lines up with results.
              final top = form
                  ? appGutter(constraints.maxWidth, AppWidths.form)
                  : gutter;
              return CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(top, 12, top, 8),
                    sliver: SliverToBoxAdapter(
                      child: form
                          ? _buildForm(context)
                          : _SearchSummary(
                              query: _query!,
                              filters: _filterSummary(_query),
                              onEdit: () => setState(() => _editing = true),
                            ),
                    ),
                  ),
                  if (page != null && page.threads.isNotEmpty) ...[
                    // A result list fades in, over the one it replaces or the
                    // spinner. Blocked authors' results disappear as soon as
                    // a rule changes.
                    AppSliverReveal(
                        id: page,
                        enter: true,
                        sliver: ValueListenableBuilder<BlockingRules>(
                          valueListenable: widget.repository.blocking.notifier,
                          builder: (context, rules, _) {
                            List<ForumThread> shown(ForumSearchPage page) => [
                                  for (final thread in page.threads)
                                    if (!rules.isThreadBlocked(thread)) thread,
                                ];
                            return SliverPadding(
                              // A fresh list per page, so old row offsets can't shift it.
                              key: ObjectKey(page),
                              padding:
                                  EdgeInsets.fromLTRB(gutter, 4, gutter, 16),
                              sliver: SliverMainAxisGroup(
                                slivers: [
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(4, 0, 4, 8),
                                      child: Text(
                                        [
                                          if (page.total != null)
                                            '共 ${page.total} 条结果',
                                          '第 ${page.currentPage} 页',
                                        ].join(' · '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ),
                                  _resultRows(shown(page)),
                                  for (final more in _more) ...[
                                    SliverToBoxAdapter(
                                      child:
                                          PageBoundary(page: more.currentPage),
                                    ),
                                    _resultRows(shown(more)),
                                  ],
                                ],
                              ),
                            );
                          },
                        )),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                      sliver: SliverToBoxAdapter(child: _buildPager()),
                    ),
                  ] else
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildStatus(),
                    ),
                ],
              );
            },
          )),
        ]),
      ),
    );
  }

  Widget _buildStatus() {
    final error = _error;
    // The site rejected the username itself; retrying cannot help.
    if (error case ForumRequestException(kind: ForumRequestKind.invalidInput)) {
      return EmptyStateView(
        icon: Icons.person_off_outlined,
        title: '用户不存在',
        message: [
          if (_query?.username case final name? when name.isNotEmpty)
            '用户名：“$name”',
          '搜索需填写登录名，可能与显示昵称不同。',
          '可在该用户的用户中心点“查看登录名”或“按人查找”。',
        ].join('\n'),
      );
    }
    if (error != null) {
      return AsyncErrorView(
        title: '搜索失败',
        message: _errorText(error),
        onRetry: _retry,
      );
    }
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final query = _query;
    if (_page != null && query != null) {
      return EmptyStateView(
        icon: Icons.manage_search_outlined,
        title: '没有找到相关主题',
        message: [
          if (query.keyword.isNotEmpty) '关键词：“${query.keyword}”',
          if (query.username.isNotEmpty) '用户名：“${query.username}”',
          '可尝试部分匹配、放宽时间范围或更换版块。',
        ].join('\n'),
      );
    }
    if (_resultsDropped) {
      return const EmptyStateView(
        icon: Icons.manage_accounts_outlined,
        title: '登录状态已变化',
        message: '旧结果已隐藏，请重新搜索。',
      );
    }
    return const EmptyStateView(
      icon: Icons.search,
      title: '搜索主题',
      message: '输入关键词或用户名后搜索主题。',
    );
  }

  Widget _resultRows(List<ForumThread> shown) => DecoratedSliver(
        decoration: appSurface(context),
        sliver: SliverList.separated(
          itemCount: shown.length,
          separatorBuilder: (_, __) => const Divider(indent: AppSpace.lg),
          itemBuilder: (context, index) => ForumThreadRow(
            title: shown[index].title,
            titleStyle: shown[index].titleStyle,
            // Board first: results span boards.
            meta: [
              if (shown[index].section.isNotEmpty) shown[index].section,
              if (shown[index].author case final author?) author,
              if (shown[index].lastPost case final last?) last,
              '${shown[index].replies} 回复',
            ],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ThreadDetailScreen(
                  thread: shown[index],
                  repository: widget.repository,
                ),
              ),
            ),
          ),
        ),
      );

  /// Under the last page shown: its end (the next page, by tap or by
  /// following on), then the pager for any page.
  Widget _buildPager() {
    final page = _lastPage!;
    final previous = page.previousPagePath;
    final next = page.nextPagePath;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageEndFooter(
          next: next == null ? null : page.currentPage + 1,
          manual: !_continuous,
          loading: _loadingMore,
          failed: _moreError != null,
          error: _moreError,
          paused: _emptyRun >= 2,
          // 手动翻页 turns to the next page alone; 自动接续 appends.
          onNext: _searching || next == null
              ? null
              : !_continuous
                  ? () => _openPage(next)
                  : _retryMore,
        ),
        if (error != null) ...[
          Text(
            '加载失败：${_errorText(error)}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _searching ? null : _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
          const SizedBox(height: 8),
        ],
        if (_searching) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
        if (previous != null || next != null || page.pageLinks.isNotEmpty)
          Builder(
            builder: (context) {
              final current = page.currentPage;
              final int total = page.totalPages ??
                  page.pageLinks.fold<int>(
                    next == null ? current : current + 1,
                    (last, link) => math.max(last, link.page),
                  );
              return ForumPager(
                current: current,
                total: total,
                onSelected: _searching
                    ? null
                    : (number) {
                        final path = switch (number - current) {
                              1 => next,
                              -1 => previous,
                              _ => null,
                            } ??
                            page.pathForPage(number);
                        if (path != null) _openPage(path);
                      },
              );
            },
          ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _keyword,
          focusNode: _keywordFocus,
          autofocus:
              widget.initialKeyword.isEmpty && widget.initialUsername.isEmpty,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '关键词',
            hintText: '搜索主题标题',
            helperText: _keywordFocus.hasFocus ? '多个关键词用空格或 | 分隔' : null,
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _keyword.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空',
                    onPressed: () => setState(_keyword.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        if (_recentMatches case final recent when recent.isNotEmpty)
          _RecentKeywords(
            keywords: recent,
            // Fills the field only; searching stays an explicit submit.
            onPick: (keyword) => setState(() {
              _keyword.value = TextEditingValue(
                text: keyword,
                selection: TextSelection.collapsed(offset: keyword.length),
              );
            }),
            onRemove: (keyword) => _editRecent(
              _owner,
              (account) => ForumSearchPreferences.removeKeyword(keyword,
                  account: account),
              failure: '删除失败',
            ),
            onClear: _clearRecent,
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          focusNode: _usernameFocus,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: '用户名',
            hintText: '只看该用户的主题',
            helperText:
                _usernameFocus.hasFocus ? '填写登录名（非显示昵称），可用 * 通配，例如 abc*' : null,
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 8),
        _FiltersHeader(
          open: _filtersOpen,
          summary: _filterSummary(null),
          onReset: _filtersAtDefault ? null : _resetFilters,
          onToggle: () {
            setState(() => _filtersOpen = !_filtersOpen);
            if (_filtersOpen) {
              _loadBoards().ignore();
              // This tab outlives logins; refresh prefs for a new owner.
              if (_prefsAccount != _account) _loadPrefs();
            }
          },
        ),
        AnimatedSize(
          duration: AppMotion.of(context, AppMotion.medium),
          curve: AppMotion.move,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_filtersOpen) ...[
                _SectionLabel(
                  '匹配方式',
                  action: _match == _prefs.defaultMatch
                      ? null
                      : _SetDefaultButton(onPressed: _saveDefaultMatch),
                ),
                _ChoiceWrap<ForumSearchMatch>(
                  labels: _matchLabels,
                  selected: _match,
                  onSelected: (value) => setState(() {
                    _match = value;
                    _matchTouched = true;
                  }),
                ),
                const SizedBox(height: 12),
                _PickerTile(
                  label: '版块',
                  value: _boardLabel,
                  icon: Icons.dashboard_outlined,
                  onTap: _pickBoard,
                ),
                const SizedBox(height: 8),
                _PickerTile(
                  label: '时间范围',
                  value: _timeLabels[_time]!,
                  icon: Icons.schedule_outlined,
                  onTap: _pickTime,
                  trailing: _time == _prefs.defaultTime
                      ? null
                      : _SetDefaultButton(onPressed: _saveDefaultTime),
                ),
                const SizedBox(height: 12),
                const _SectionLabel('排序'),
                _ChoiceWrap<ForumThreadOrder>(
                  labels: _orderLabels,
                  selected: _order,
                  onSelected: (value) => setState(() => _order = value),
                ),
                const SizedBox(height: 8),
                _ChoiceWrap<bool>(
                  labels: const {false: '降序', true: '升序'},
                  selected: _ascending,
                  onSelected: (value) => setState(() => _ascending = value),
                ),
                CheckboxListTile(
                  value: _digest,
                  onChanged: (value) =>
                      setState(() => _digest = value ?? false),
                  title: const Text('只搜精华帖'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 4),
          Text(_formError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        // The page's one primary action, full width.
        FilledButton.icon(
          key: const ValueKey('search-submit'),
          onPressed: _searching ? null : _search,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.search),
          label: Text(_searching ? '搜索中...' : '搜索'),
        ),
      ],
    );
  }
}

String _errorText(Object error) => switch (error) {
      ForumRequestException(:final kind) => forumRequestErrorText(kind),
      ForumRepositoryException(:final message) => message,
      _ => '$error',
    };

Future<T?> _showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required T? selected,
  required Map<T, String> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final MapEntry(:key, :value) in options.entries)
                    ListTile(
                      title: Text(value),
                      selected: key == selected,
                      trailing:
                          key == selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(context).pop(key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Recent keywords under the keyword field. Taps here keep the field
/// focused, so the list stays put while it is used.
class _RecentKeywords extends StatelessWidget {
  const _RecentKeywords({
    required this.keywords,
    required this.onPick,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> keywords;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFieldTapRegion(
      child: Container(
        margin: const EdgeInsets.only(top: AppSpace.sm),
        decoration: appSurface(context),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        '最近搜索',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  TextButton(onPressed: onClear, child: const Text('清空')),
                ],
              ),
            ),
            for (final keyword in keywords)
              Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => onPick(keyword),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.lg, vertical: AppSpace.sm),
                            child: Row(
                              children: [
                                Icon(Icons.history,
                                    size: 20, color: AppColors.textMuted),
                                const SizedBox(width: AppSpace.md),
                                Expanded(
                                  child: Text(
                                    keyword,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '删除“$keyword”',
                      onPressed: () => onRemove(keyword),
                      icon: Icon(Icons.close,
                          size: 18, color: AppColors.textFaint),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FiltersHeader extends StatelessWidget {
  const _FiltersHeader({
    required this.open,
    required this.summary,
    required this.onToggle,
    this.onReset,
  });

  final bool open;
  final List<String> summary;
  final VoidCallback onToggle;

  /// Shown while any filter differs from its default.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final reset = onReset;
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('筛选条件', style: theme.textTheme.titleSmall),
                  if (!open)
                    Text(
                      summary.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (reset != null)
              TextButton(onPressed: reset, child: const Text('重置筛选')),
            Icon(open ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(text, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _SetDefaultButton extends StatelessWidget {
  const _SetDefaultButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.push_pin_outlined, size: 16),
      label: const Text('设为默认'),
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final Map<T, String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final MapEntry(:key, :value) in labels.entries)
          ChoiceChip(
            label: Text(value),
            selected: key == selected,
            onSelected: (_) => onSelected(key),
          ),
      ],
    );
  }
}

/// A full-width field whose label sits above a freely wrapping value.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(value, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({
    required this.query,
    required this.filters,
    required this.onEdit,
  });

  final ForumSearchQuery query;
  final List<String> filters;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The submitted query reads like the search field it came from.
    return Container(
      decoration: appSurface(context),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(Icons.search, color: AppColors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (query.keyword.isNotEmpty)
                        Text(query.keyword, style: theme.textTheme.titleSmall),
                      if (query.username.isNotEmpty)
                        Text(
                          '用户：${query.username}',
                          style: theme.textTheme.titleSmall,
                        ),
                      const SizedBox(height: 2),
                      Text(
                        filters.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onEdit, child: const Text('修改')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardPickerSheet extends StatefulWidget {
  const _BoardPickerSheet({
    required this.sessionChanges,
    required this.inSession,
    required this.selectedId,
    required this.loadBoards,
    required this.loadSections,
    required this.baseUri,
    required this.loadPinned,
    required this.savePinned,
  });

  final Listenable sessionChanges;
  final bool Function() inSession;
  final String selectedId;
  final Future<List<ForumSearchBoard>> Function() loadBoards;
  final Future<List<ForumSection>> Function() loadSections;
  final Uri baseUri;
  final Future<List<ForumSearchPinnedBoard>> Function() loadPinned;
  final Future<void> Function(List<ForumSearchPinnedBoard>) savePinned;

  @override
  State<_BoardPickerSheet> createState() => _BoardPickerSheetState();
}

class _BoardPickerSheetState extends State<_BoardPickerSheet> {
  final _filter = TextEditingController();
  late Future<List<ForumSearchBoard>> _boards = widget.loadBoards();
  List<ForumSearchPinnedBoard> _pinned = const [];
  // The last pin read or write that failed, with the action that repeats it.
  // The sheet covers any SnackBar, so it reports inline.
  ({String message, VoidCallback retry})? _pinNotice;
  // A pin write is in flight; further pin edits wait for it.
  bool _saving = false;
  // Options, pins and choices belong to the session the sheet opened in.
  bool _stale = false;
  List<ForumSection>? _sections;
  Object? _sectionsError;
  final _expanded = <String>{};
  // The lists the selection's ancestors were last expanded for.
  Object? _expandedFor;

  @override
  void initState() {
    super.initState();
    widget.sessionChanges.addListener(_checkSession);
    _loadPins();
    _loadSections();
  }

  Future<void> _loadPins() async {
    _checkSession();
    if (!mounted || _stale) return;
    try {
      final pinned = await widget.loadPinned();
      _checkSession();
      if (!mounted || _stale) return;
      setState(() {
        _pinned = pinned;
        _pinNotice = null;
      });
    } catch (_) {
      _checkSession();
      if (!mounted || _stale) return;
      setState(
        () => _pinNotice = (message: '常用版块加载失败', retry: _loadPins),
      );
    }
  }

  void _checkSession() {
    if (mounted && !_stale && !widget.inSession()) {
      setState(() => _stale = true);
    }
  }

  Future<void> _loadSections() async {
    try {
      final sections = await widget.loadSections();
      if (mounted) setState(() => _sections = sections);
    } catch (error) {
      if (mounted) setState(() => _sectionsError = error);
    }
  }

  void _retrySections() {
    setState(() {
      _sections = null;
      _sectionsError = null;
    });
    _loadSections();
  }

  // The search form's options stay the only source of scopes; homepage
  // sections only nest them.
  List<_BoardNode> _tree(List<ForumSearchBoard> boards) {
    final sections = _sections;
    final roots = _BoardNode.build(
      sections == null || sections.isEmpty
          ? boards
          : mergeSearchBoardHierarchy(boards, sections,
              baseUri: widget.baseUri),
    );
    final source = (boards, sections);
    if (_expandedFor != source) {
      _expandedFor = source;
      for (final node in _BoardNode.flatten(roots)) {
        if (node.board.id == widget.selectedId) {
          for (var parent = node.parent;
              parent != null;
              parent = parent.parent) {
            _expanded.add(parent.key);
          }
        }
      }
    }
    return roots;
  }

  @override
  void dispose() {
    widget.sessionChanges.removeListener(_checkSession);
    _filter.dispose();
    super.dispose();
  }

  Future<void> _togglePin(ForumSearchBoard board) async {
    _checkSession();
    if (_saving || _stale) return;
    if (_pinned.any((pin) => pin.id == board.id)) {
      await _savePins(_without(board.id));
      return;
    }
    final label = await _askLabel(board.name.trim());
    _checkSession();
    if (!mounted || _stale) return;
    if (label == null || label.trim().isEmpty) return;
    final pin = ForumSearchPinnedBoard(id: board.id, label: label.trim());
    await _savePins(
      (current) => [
        for (final other in current)
          if (other.id != pin.id) other,
        pin,
      ],
    );
  }

  List<ForumSearchPinnedBoard> Function(List<ForumSearchPinnedBoard>) _without(
    String id,
  ) =>
      (current) => [
            for (final pin in current)
              if (pin.id != id) pin,
          ];

  // The list on screen changes only once the write is acknowledged, and only
  // one write runs at a time. An edit is applied to the acknowledged list when
  // it runs, so a retry never reapplies an old whole list over newer saves.
  Future<void> _savePins(
    List<ForumSearchPinnedBoard> Function(List<ForumSearchPinnedBoard>) edit,
  ) async {
    // A retry arrives here directly, so the scope is checked again.
    _checkSession();
    if (_saving || !mounted || _stale) return;
    final next = edit(_pinned);
    setState(() => _saving = true);
    try {
      try {
        await widget.savePinned(next);
      } catch (error) {
        _checkSession();
        if (!mounted || _stale) return;
        setState(
          () => _pinNotice = (
            message: '保存失败：$error',
            retry: () => _savePins(edit),
          ),
        );
        return;
      }
      List<ForumSearchPinnedBoard> saved;
      try {
        saved = await widget.loadPinned();
      } catch (_) {
        // The write itself went through.
        saved = next;
      }
      _checkSession();
      if (!mounted || _stale) return;
      setState(() {
        _pinned = saved;
        _pinNotice = null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askLabel(String initial) => showDialog<String>(
        context: context,
        builder: (_) => _PinLabelDialog(initial: initial),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_stale) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: const EmptyStateView(
            icon: Icons.manage_accounts_outlined,
            title: '登录状态已变化',
            message: '请关闭后重新选择版块。',
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '查找版块',
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<ForumSearchBoard>>(
                  future: _boards,
                  builder: (context, snapshot) {
                    final boards = snapshot.data;
                    final roots = boards == null ? null : _tree(boards);
                    final filter = _filter.text.trim().toLowerCase();
                    final known = {
                      for (final board in boards ?? const <ForumSearchBoard>[])
                        if (board.selectable) board.id,
                    };
                    return ListView(
                      children: [
                        if (_saving)
                          const LinearProgressIndicator(minHeight: 2),
                        if (_pinNotice case final notice?)
                          ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(notice.message),
                            trailing: TextButton(
                              onPressed: _saving ? null : notice.retry,
                              child: const Text('重试'),
                            ),
                          ),
                        if (_pinned.isNotEmpty) ...[
                          _SheetHeader('版块捷径'),
                          for (final pin in _pinned)
                            if (filter.isEmpty ||
                                pin.label.toLowerCase().contains(filter))
                              _pinTile(
                                pin,
                                // Unknown until the server list is in.
                                boards == null ? null : known.contains(pin.id),
                              ),
                          const Divider(),
                        ],
                        _SheetHeader('全部版块'),
                        if (snapshot.hasError)
                          ListTile(
                            leading: Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                            ),
                            title: const Text('版块列表加载失败'),
                            trailing: TextButton(
                              onPressed: () => setState(() {
                                _boards = widget.loadBoards();
                              }),
                              child: const Text('重试'),
                            ),
                          )
                        else if (roots == null)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else ...[
                          _hierarchyStatus(),
                          if (filter.isEmpty)
                            ..._treeRows(roots)
                          else
                            for (final node in _BoardNode.flatten(roots))
                              if ((node.children.isEmpty ||
                                      node.board.selectable) &&
                                  node.name.toLowerCase().contains(filter))
                                _boardTile(node, level: 0, showPath: true),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinTile(ForumSearchPinnedBoard pin, bool? exists) {
    return ListTile(
      leading: Icon(
        switch (exists) {
          true => Icons.bookmark,
          false => Icons.warning_amber_outlined,
          null => Icons.bookmark_border,
        },
        color: exists == false
            ? Theme.of(context).colorScheme.error
            : AppColors.brand,
      ),
      title: Text(pin.label),
      subtitle: switch (exists) {
        true => null,
        false => const Text('此版块已不存在，无法搜索'),
        null => const Text('版块列表加载后可选'),
      },
      selected: pin.id == widget.selectedId,
      enabled: exists == true,
      onTap: () => Navigator.of(
        context,
      ).pop(ForumSearchBoard(id: pin.id, name: pin.label)),
      trailing: IconButton(
        tooltip: '删除捷径',
        icon: const Icon(Icons.close),
        onPressed: _saving
            ? null
            : () => _togglePin(ForumSearchBoard(id: pin.id, name: pin.label)),
      ),
    );
  }

  Widget _hierarchyStatus() {
    final sections = _sections;
    if (_sectionsError == null && sections == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '正在加载版块层级…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    if (sections != null && sections.isNotEmpty) return const SizedBox.shrink();
    return ListTile(
      dense: true,
      leading: const Icon(Icons.info_outline),
      title: const Text('未能加载版块层级，按平铺列表显示'),
      trailing: TextButton(onPressed: _retrySections, child: const Text('重试')),
    );
  }

  List<Widget> _treeRows(List<_BoardNode> nodes) => [
        for (final node in nodes)
          if (node.children.isEmpty)
            _boardTile(node, level: node.level)
          else ...[
            _groupTile(node),
            if (_expanded.contains(node.key)) ...[
              // Opening a group never selects it; searching all of it is
              // its own row.
              if (node.board.selectable)
                _boardTile(node,
                    level: node.level + 1, label: '搜索整个${node.name}'),
              ..._treeRows(node.children),
            ],
          ],
      ];

  double _indent(int level) => 16.0 + 16.0 * level.clamp(0, 4);

  Widget _groupTile(_BoardNode node) {
    final open = _expanded.contains(node.key);
    return Semantics(
      expanded: open,
      child: ListTile(
        contentPadding: EdgeInsets.only(left: _indent(node.level), right: 16),
        title: Text(
          node.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
        onTap: () => setState(() {
          if (!_expanded.remove(node.key)) _expanded.add(node.key);
        }),
      ),
    );
  }

  Widget _boardTile(
    _BoardNode node, {
    required int level,
    String? label,
    bool showPath = false,
  }) {
    final board = node.board;
    final subtitle = [
      if (showPath && node.parent != null) node.parent!.path,
      if (!board.selectable) '不可搜索',
    ].join(' · ');
    if (!board.selectable) {
      return ListTile(
        enabled: false,
        contentPadding: EdgeInsets.only(left: _indent(level), right: 16),
        title: Text(label ?? node.name),
        subtitle: Text(subtitle),
      );
    }
    final picked = ForumSearchBoard(
      id: board.id,
      name: node.name,
      depth: board.depth,
    );
    final pinned = _pinned.any((pin) => pin.id == board.id);
    final canPin = board.id != _allBoards.id;
    return ListTile(
      contentPadding: EdgeInsets.only(left: _indent(level), right: 4),
      title: Text(label ?? node.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      selected: board.id == widget.selectedId,
      onTap: () => Navigator.of(context).pop(picked),
      trailing: canPin
          ? IconButton(
              tooltip: pinned ? '删除捷径' : '存为捷径',
              icon: Icon(pinned ? Icons.bookmark : Icons.bookmark_add_outlined),
              onPressed: _saving ? null : () => _togglePin(picked),
            )
          : null,
    );
  }
}

/// One search scope placed under its parent by the preorder depth.
class _BoardNode {
  _BoardNode(this.board, this.parent)
      : level = parent == null ? 0 : parent.level + 1;

  final ForumSearchBoard board;
  final _BoardNode? parent;
  final int level;
  final children = <_BoardNode>[];

  // Form options carry the site's '>>' and '|-' tree markers.
  String get name =>
      board.name.replaceFirst(RegExp(r'^\s*(?:(?:>>|\|-)\s*)+'), '').trim();

  String get key => board.id.isEmpty ? 'heading:${board.name}' : board.id;

  String get path => [if (parent != null) parent!.path, name].join(' › ');

  static List<_BoardNode> build(List<ForumSearchBoard> boards) {
    final roots = <_BoardNode>[];
    final open = <_BoardNode>[];
    for (final board in boards) {
      while (open.isNotEmpty && open.last.board.depth >= board.depth) {
        open.removeLast();
      }
      final node = _BoardNode(board, open.lastOrNull);
      (node.parent?.children ?? roots).add(node);
      open.add(node);
    }
    return roots;
  }

  static Iterable<_BoardNode> flatten(List<_BoardNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* flatten(node.children);
    }
  }
}

// Owns its controller so the closing animation never sees it disposed.
class _PinLabelDialog extends StatefulWidget {
  const _PinLabelDialog({required this.initial});

  final String initial;

  @override
  State<_PinLabelDialog> createState() => _PinLabelDialogState();
}

class _PinLabelDialogState extends State<_PinLabelDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('存为捷径'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '显示名称'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
