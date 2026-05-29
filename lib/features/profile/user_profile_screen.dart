import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
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
  late Future<UserProfile> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchUserProfile(widget.userUrl);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repository.fetchUserProfile(widget.userUrl);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xfff7f7f8),
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<UserProfile>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _ProfileError(
                  message: '${snapshot.error}',
                  onRetry: _refresh,
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final profile = snapshot.data!;
              return NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverToBoxAdapter(child: _ProfileHeader(profile: profile)),
                  const SliverToBoxAdapter(child: _ProfileTabs()),
                ],
                body: TabBarView(
                  children: [
                    _RefreshTab(
                      onRefresh: _refresh,
                      child: _HomeTab(
                        profile: profile,
                        repository: widget.repository,
                      ),
                    ),
                    _RefreshTab(
                      onRefresh: _refresh,
                      child: _ProfileInfoTab(profile: profile),
                    ),
                    _RefreshTab(
                      onRefresh: _refresh,
                      child: _ItemList(
                        items: profile.topics,
                        emptyText: '没有主题',
                        repository: widget.repository,
                      ),
                    ),
                    _RefreshTab(
                      onRefresh: _refresh,
                      child: _ItemList(
                        items: profile.posts,
                        emptyText: '没有回复',
                        repository: widget.repository,
                      ),
                    ),
                    _RefreshTab(
                      onRefresh: _refresh,
                      child: _ItemList(
                        items: profile.favorites,
                        emptyText: '没有公开收藏',
                        repository: widget.repository,
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
