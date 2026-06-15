import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';

part 'user_profile_widgets.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userUrl,
    required this.repository,
  });

  final String userUrl;
  final ForumRepository repository;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<UserProfile> _overviewFuture;
  Future<UserProfile>? _detailsFuture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() {
    _detailsFuture = null;
    _overviewFuture = _fetchOverviewWithCache();
  }

  Future<UserProfile> _fetchOverviewWithCache() async {
    final cached = await widget.repository.cachedUserProfileOverview(
      widget.userUrl,
    );
    if (cached != null) {
      _detailsFuture = widget.repository.fetchUserProfileDetails(cached);
      _refreshOverviewAfterCache();
      return cached;
    }

    final overview = await widget.repository.fetchUserProfileOverview(
      widget.userUrl,
    );
    _detailsFuture = widget.repository.fetchUserProfileDetails(overview);
    return overview;
  }

  void _refreshOverviewAfterCache() {
    widget.repository.fetchUserProfileOverview(widget.userUrl).then((overview) {
      if (!mounted) return;
      setState(() {
        _overviewFuture = Future.value(overview);
        _detailsFuture = widget.repository.fetchUserProfileDetails(overview);
      });
    }).catchError((_) {});
  }

  Future<void> _refresh() async {
    setState(() {
      _loadProfile();
    });
    final overview = await _overviewFuture;
    await _detailsFuture ?? Future.value(overview);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<UserProfile>(
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
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(child: _ProfileHeader(profile: profile)),
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
                          builder: (context, details) => _ItemList(
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
                          builder: (context, details) => _ItemList(
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
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
