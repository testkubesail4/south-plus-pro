import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../models/user_content_query.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../common/thread_row.dart';
import '../common/user_note.dart';
import '../messages/pm_compose_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';

part 'user_profile_widgets.dart';

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
  // Counts pull-to-refresh restarts so filter tabs restart their queries.
  int _contentRefresh = 0;
  // Board ids belong to one session; a new session starts unfiltered.
  var _topicSelection = _ContentSelection();
  var _postSelection = _ContentSelection();
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
      _topicSelection = _ContentSelection();
      _postSelection = _ContentSelection();
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
    final saved = await showUserNoteEditor(
      context,
      repository: widget.repository,
      uid: profile.uid.trim(),
      name: profile.name,
      note: _notes.noteFor(profile.uid.trim()),
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备注已更新')),
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

  void _copyLoginName(String name) {
    Clipboard.setData(ClipboardData(text: name));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制登录名')),
    );
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

    final overview = await widget.repository.fetchUserProfileOverview(
      widget.userUrl,
    );
    if (epoch == _lookupEpoch) {
      _detailsFuture = widget.repository
          .fetchUserProfileDetails(overview, forceReload: forceReload);
    }
    return overview;
  }

  void _refreshOverviewAfterCache(String cachedUid) {
    final epoch = _lookupEpoch;
    widget.repository.fetchUserProfileOverview(widget.userUrl).then((overview) {
      if (!mounted || epoch != _lookupEpoch) return;
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
      _contentRefresh++;
      _loadProfile(forceReload: true);
    });
    final overview = await _overviewFuture;
    await _detailsFuture ?? Future.value(overview);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: UserProfileTab.values.length,
      initialIndex: widget.initialTab.index,
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
                            builder: (context, _) => _ProfileHeader(
                              profile: profile,
                              note: hasUid ? _notes.noteFor(uid) : null,
                              onEditNote:
                                  hasUid ? () => _editNote(profile) : null,
                              onMessage: switch (profile.messageUrl) {
                                final url? => () => Navigator.of(context).push(
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
                        const SliverToBoxAdapter(child: _ProfileTabs()),
                      ],
                      body: TabBarView(
                        children: [
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _DetailsTab(
                              future: detailsFuture,
                              builder: (context, details) => _HomeTab(
                                profile: details,
                                repository: widget.repository,
                              ),
                            ),
                          ),
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _ProfileInfoTab(profile: profile),
                          ),
                          _RefreshTab(
                            onRefresh: _refresh,
                            child: _DetailsTab(
                              future: detailsFuture,
                              builder: (context, details) => hasUid
                                  ? _ContentTab(
                                      uid: uid,
                                      tab: UserProfileTab.topics,
                                      defaultItems: details.topics,
                                      emptyText: '没有主题',
                                      repository: widget.repository,
                                      loadBoards: _loadBoards,
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
                              builder: (context, details) => hasUid
                                  ? _ContentTab(
                                      uid: uid,
                                      tab: UserProfileTab.posts,
                                      defaultItems: details.posts,
                                      emptyText: '没有回复',
                                      repository: widget.repository,
                                      loadBoards: _loadBoards,
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
                              builder: (context, details) => _ItemList(
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
