import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../models/user_content_query.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../../services/full_scan.dart';
import '../../services/keyword_match.dart';
import '../../services/user_content_sort.dart';
import '../../services/user_display_name_store.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/board_picker_sheet.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../common/leave_watch.dart';
import '../common/search_scope_bar.dart';
import '../common/thread_row.dart';
import '../common/unresolved_group.dart';
import '../common/user_note.dart';
import '../common/user_tags_inline.dart';
import '../messages/pm_compose_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';
import '../thread/thread_image_viewer.dart';
import '../thread/thread_render_models.dart';

part 'user_profile_widgets.dart';

/// The visible tab of [tab]: 首页 and 资料 both open 概览.
int _tabIndex(UserProfileTab tab) => switch (tab) {
      UserProfileTab.home || UserProfileTab.profile => 0,
      UserProfileTab.topics => 1,
      UserProfileTab.posts => 2,
      UserProfileTab.favorites => 3,
    };

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userUrl,
    required this.repository,
    this.initialTab = UserProfileTab.home,
  });

  final String userUrl;
  final ForumRepository repository;

  /// Tabs follow [UserProfileTab] order.
  final UserProfileTab initialTab;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<UserProfile> _overviewFuture;
  late UserNoteController _notes = UserNoteController(widget.repository);
  // Board options for the 主题/回复 filters; loaded on first use per session.
  Future<List<ForumSearchBoard>>? _boards;
  Future<List<ForumSection>>? _sections;
  // Counts pull-to-refresh restarts so filter tabs restart their queries.
  int _contentRefresh = 0;
  // Board ids belong to one session; a new session starts unfiltered.
  var _topicSelection = _ContentSelection();
  var _postSelection = _ContentSelection();
  var _favoriteSelection = _ContentSelection();
  Future<UserProfile>? _detailsFuture;

  // Login name from the explicit lookup; lives only as long as this screen
  // and this session.
  String? _loginName;
  bool _lookingUp = false;
  // Bumped whenever loaded data stops belonging to what is shown, so late
  // results are dropped.
  int _lookupEpoch = 0;
  // The session changed under this screen: what it loaded may be another
  // account's, so it stays hidden until the user reloads.
  bool _sessionChanged = false;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSessionChanged);
    _loadProfile();
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository == widget.repository) return;
    _notes.dispose();
    _notes = UserNoteController(widget.repository);
    oldWidget.repository.sessionEpoch.removeListener(_onSessionChanged);
    widget.repository.sessionEpoch.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_onSessionChanged);
    _notes.dispose();
    super.dispose();
  }

  void _forgetLoginName() {
    _lookupEpoch++;
    _loginName = null;
    _lookingUp = false;
  }

  // No automatic reload: the session may still be switching, and a request
  // now could carry the old account's cookies.
  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _forgetLoginName();
      _sessionChanged = true;
      _detailsFuture = null;
      _boards = null;
      _sections = null;
      _topicSelection = _ContentSelection();
      _postSelection = _ContentSelection();
      _favoriteSelection = _ContentSelection();
    });
  }

  /// Returns the login name, looking it up once per explicit tap; null when
  /// the lookup failed, was superseded, or another one is running.
  Future<String?> _lookupLoginName(String uid) async {
    if (_loginName case final name?) return name;
    if (_lookingUp) return null;
    final epoch = _lookupEpoch;
    setState(() => _lookingUp = true);
    try {
      final name = await widget.repository.fetchLoginUsername(uid);
      if (!mounted || epoch != _lookupEpoch) return null;
      setState(() {
        _loginName = name;
        _lookingUp = false;
      });
      return name;
    } catch (error) {
      if (!mounted || epoch != _lookupEpoch) return null;
      setState(() => _lookingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('查询登录名失败：${forumErrorText(error)}')),
      );
      return null;
    }
  }

  Future<void> _searchByUser(String uid) async {
    final epoch = _lookupEpoch;
    final name = await _lookupLoginName(uid);
    if (name == null || !mounted || epoch != _lookupEpoch) return;
    // Prefills the search; the user still submits it.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          repository: widget.repository,
          initialUsername: name,
        ),
      ),
    );
  }

  Future<void> _editNote(UserProfile profile) async {
    if (_notes.isLoading ||
        _notes.noteLoadError != null ||
        _notes.tagLoadError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标记加载失败，请重试')));
      _notes.reload();
      return;
    }
    final saved = await showUserNoteEditor(
      context,
      repository: widget.repository,
      uid: profile.uid.trim(),
      // Only a name the forum showed (or one learned before); a generated
      // `用户 n` fallback is no name, and the header then shows the UID once.
      name: profile.nickname ??
          profile.nativeHashName ??
          _notes.namesFor(profile.uid.trim())?.displayName,
      note: _notes.noteFor(profile.uid.trim()),
      tags: _notes.tagsFor(profile.uid.trim()),
      // Only names this screen read from the forum itself, never a cached or
      // generated fallback.
      learnNickname: identical(profile, _fresh) ? profile.nickname : null,
      learnHashName: identical(profile, _fresh) ? profile.nativeHashName : null,
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备注与标签已更新')),
      );
    }
  }

  Future<List<ForumSearchBoard>> _loadBoards() =>
      _boards ??= widget.repository.fetchSearchBoards().catchError(
        (Object error) {
          // A failed load must not stay cached; the sheet's retry asks again.
          _boards = null;
          throw error;
        },
      );

  /// The tab's page count as the profile page states it; null when unsaid.
  int? _totalPages(UserProfile details, UserProfileTab tab) =>
      details.contentPagination[tab]?.totalPages;

  // Only says which board sits under which; a failed read is not cached.
  Future<List<ForumSection>> _loadSections() =>
      _sections ??= widget.repository.fetchForumSections().catchError(
        (Object error) {
          _sections = null;
          throw error;
        },
      );

  void _copyLoginName(String name) {
    Clipboard.setData(ClipboardData(text: name));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制登录名')),
    );
  }

  // The overview this screen fetched from the forum (not the cache).
  UserProfile? _fresh;

  (String?, int) _scope() => (
        widget.repository.localPreferenceAccount,
        widget.repository.sessionEpoch.value
      );

  /// Remembers the forum's names for an annotated user once a fetched profile
  /// is on screen, in the scope the fetch started in. Unannotated users and
  /// cached or generated names are never recorded; a failure is silent.
  void _learnNames(UserProfile overview, (String?, int) scope) {
    _fresh = overview;
    final (account, epoch) = scope;
    if (account != widget.repository.localPreferenceAccount ||
        epoch != widget.repository.sessionEpoch.value) {
      return;
    }
    final uid = overview.uid.trim();
    final annotated =
        _notes.noteFor(uid) != null || _notes.tagsFor(uid).isNotEmpty;
    final nickname = overview.nickname;
    final hashName = overview.nativeHashName;
    if (!annotated || (nickname == null && hashName == null)) return;
    UserDisplayNameStore.save(uid,
            nickname: nickname, hashName: hashName, account: account)
        .then((_) {}, onError: (Object _) {});
  }

  void _loadProfile({bool forceReload = false}) {
    _detailsFuture = null;
    _overviewFuture = _fetchOverviewWithCache(forceReload: forceReload);
  }

  Future<UserProfile> _fetchOverviewWithCache(
      {bool forceReload = false}) async {
    final epoch = _lookupEpoch;
    final cached = await widget.repository.cachedUserProfileOverview(
      widget.userUrl,
    );
    if (cached != null) {
      if (epoch == _lookupEpoch) {
        _detailsFuture = widget.repository
            .fetchUserProfileDetails(cached, forceReload: forceReload);
        _refreshOverviewAfterCache(cached.uid);
      }
      return cached;
    }

    final scope = _scope();
    final overview = await widget.repository.fetchUserProfileOverview(
      widget.userUrl,
    );
    if (epoch == _lookupEpoch) {
      _detailsFuture = widget.repository
          .fetchUserProfileDetails(overview, forceReload: forceReload);
      _learnNames(overview, scope);
    }
    return overview;
  }

  void _refreshOverviewAfterCache(String cachedUid) {
    final epoch = _lookupEpoch;
    final scope = _scope();
    widget.repository.fetchUserProfileOverview(widget.userUrl).then((overview) {
      if (!mounted || epoch != _lookupEpoch) return;
      _learnNames(overview, scope);
      setState(() {
        _overviewFuture = Future.value(overview);
        // Details are per user; the cached user's request already covers it.
        if (overview.uid != cachedUid) {
          _detailsFuture = widget.repository.fetchUserProfileDetails(overview);
          // A login name looked up for the cached user is not this user's.
          _forgetLoginName();
        }
      });
    }).catchError((_) {});
  }

  Future<void> _refresh() async {
    setState(() {
      _forgetLoginName();
      _sessionChanged = false;
      _boards = null;
      _sections = null;
      _contentRefresh++;
      _loadProfile(forceReload: true);
    });
    final overview = await _overviewFuture;
    await _detailsFuture ?? Future.value(overview);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: _tabIndex(widget.initialTab),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: _sessionChanged
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.chevron_left, size: 30),
                    ),
                    Expanded(
                      child: AsyncErrorView(
                        title: '登录状态已变化',
                        message: '之前加载的资料已隐藏，重试将按当前账号重新加载。',
                        onRetry: _refresh,
                      ),
                    ),
                  ],
                )
              : FutureBuilder<UserProfile>(
                  future: _overviewFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return AsyncErrorView(
                        title: '用户中心加载失败',
                        message: '${snapshot.error}',
                        onRetry: _refresh,
                      );
                    }
                    if (!snapshot.hasData) {
                      return _LoadingProfileFrame(onRefresh: _refresh);
                    }
                    final profile = snapshot.data!;
                    final detailsFuture = _detailsFuture;
                    final uid = profile.uid.trim();
                    final hasUid = RegExp(r'^[1-9]\d*$').hasMatch(uid);
                    // No entry fade: content, cached or fresh, shows at once.
                    return NestedScrollView(
                      headerSliverBuilder: (context, _) => [
                        SliverToBoxAdapter(
                          child: ListenableBuilder(
                            listenable: _notes,
                            builder: (context, _) => TagColorScope(
                              colors: _notes.tagColors,
                              child: _ProfileHeader(
                                profile: profile,
                                note: hasUid ? _notes.noteFor(uid) : null,
                                tags: hasUid ? _notes.tagsFor(uid) : const [],
                                onEditNote:
                                    hasUid ? () => _editNote(profile) : null,
                                onMessage: switch (profile.messageUrl) {
                                  final url? => () =>
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PmComposeScreen(
                                            repository: widget.repository,
                                            path: url,
                                          ),
                                        ),
                                      ),
                                  null => null,
                                },
                                loginName: _loginName,
                                lookingUp: _lookingUp,
                                onShowLoginName:
                                    hasUid ? () => _lookupLoginName(uid) : null,
                                onCopyLoginName: _copyLoginName,
                                onSearchByUser:
                                    hasUid ? () => _searchByUser(uid) : null,
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: _ProfileTabs()),
                      ],
                      body: TabBarView(
                        children: [
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _OverviewTab(
                              profile: profile,
                              details: detailsFuture,
                              repository: widget.repository,
                            ),
                          ),
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _DetailsTab(
                              future: detailsFuture,
                              tab: UserProfileTab.topics,
                              onRetry: _refresh,
                              builder: (context, details) => hasUid
                                  ? _ContentTab(
                                      uid: uid,
                                      tab: UserProfileTab.topics,
                                      defaultItems: details.topics,
                                      defaultTotalPages: _totalPages(
                                          details, UserProfileTab.topics),
                                      emptyText: '没有主题',
                                      repository: widget.repository,
                                      loadBoards: _loadBoards,
                                      loadSections: _loadSections,
                                      selection: _topicSelection,
                                      refreshGeneration: _contentRefresh,
                                    )
                                  : _ItemList(
                                      items: details.topics,
                                      emptyText: '没有主题',
                                      repository: widget.repository,
                                    ),
                            ),
                          ),
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _DetailsTab(
                              future: detailsFuture,
                              tab: UserProfileTab.posts,
                              onRetry: _refresh,
                              builder: (context, details) => hasUid
                                  ? _ContentTab(
                                      uid: uid,
                                      tab: UserProfileTab.posts,
                                      defaultItems: details.posts,
                                      defaultTotalPages: _totalPages(
                                          details, UserProfileTab.posts),
                                      emptyText: '没有回复',
                                      repository: widget.repository,
                                      loadBoards: _loadBoards,
                                      loadSections: _loadSections,
                                      selection: _postSelection,
                                      refreshGeneration: _contentRefresh,
                                    )
                                  : _ItemList(
                                      items: details.posts,
                                      emptyText: '没有回复',
                                      repository: widget.repository,
                                    ),
                            ),
                          ),
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _DetailsTab(
                              future: detailsFuture,
                              tab: UserProfileTab.favorites,
                              onRetry: _refresh,
                              builder: (context, details) => hasUid
                                  ? _ContentTab(
                                      uid: uid,
                                      tab: UserProfileTab.favorites,
                                      defaultItems: details.favorites,
                                      defaultTotalPages: _totalPages(
                                          details, UserProfileTab.favorites),
                                      emptyText: '没有公开收藏',
                                      repository: widget.repository,
                                      loadBoards: _loadBoards,
                                      loadSections: _loadSections,
                                      selection: _favoriteSelection,
                                      refreshGeneration: _contentRefresh,
                                    )
                                  : _ItemList(
                                      items: details.favorites,
                                      emptyText: '没有公开收藏',
                                      repository: widget.repository,
                                      showAuthor: true,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
