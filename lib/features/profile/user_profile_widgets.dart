part of 'user_profile_screen.dart';

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeeeeef))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chevron_left, size: 30),
              ),
              const Text(
                '用户中心',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfffffbfb),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffffe3e8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: const Color(0xfff2d8dd),
                      backgroundImage: profile.avatarUrl == null
                          ? null
                          : NetworkImage(profile.avatarUrl!),
                      child: profile.avatarUrl == null
                          ? Text(
                              profile.name.characters.firstOrNull ?? '?',
                              style: const TextStyle(
                                color: _ProfileTheme.accent,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: -1,
                      bottom: 2,
                      child: _OnlineDot(isOnline: profile.isOnline),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _OnlinePill(
                            isOnline: profile.isOnline,
                            text: profile.statusText,
                          ),
                        ],
                      ),
                      if (profile.tagline != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          profile.tagline!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff666666),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile.messageUrl != null)
                const _ActionChip(
                  icon: Icons.mail_outline,
                  label: '可发短消息',
                ),
              _MetricChip(label: 'UID', value: profile.uid),
              if (profile.level != null && profile.level!.isNotEmpty)
                _MetricChip(label: '等级', value: profile.level!),
              ...profile.stats.take(3).map(
                    (field) => _MetricChip(
                      label: field.label,
                      value: field.value,
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.isOnline});

  final bool? isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline == null
        ? const Color(0xffb9b9b9)
        : isOnline!
            ? const Color(0xff24b26b)
            : const Color(0xff9b9b9b);
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.isOnline, required this.text});

  final bool? isOnline;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final online = isOnline == true;
    final color = isOnline == null
        ? const Color(0xff777777)
        : online
            ? const Color(0xff167a49)
            : const Color(0xff666666);
    final background = isOnline == null
        ? const Color(0xfff1f1f2)
        : online
            ? const Color(0xffe8f8ef)
            : const Color(0xfff1f1f2);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.circle : Icons.circle_outlined,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            text ?? '未知',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _ProfileTheme.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: const TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: _ProfileTheme.accent,
        unselectedLabelColor: Color(0xff777777),
        indicatorColor: _ProfileTheme.accent,
        tabs: [
          Tab(text: '首页'),
          Tab(text: '资料'),
          Tab(text: '主题'),
          Tab(text: '回复'),
          Tab(text: '收藏'),
        ],
      ),
    );
  }
}

class _LoadingProfileFrame extends StatelessWidget {
  const _LoadingProfileFrame({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, _) => const [
        SliverToBoxAdapter(child: _ProfileLoadingHeader()),
        SliverToBoxAdapter(child: _ProfileTabs()),
      ],
      body: TabBarView(
        children: [
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
          _RefreshTab(
              onRefresh: onRefresh, child: const _ProfileInfoLoadingTab()),
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
          _RefreshTab(onRefresh: onRefresh, child: const _TabLoadingSkeleton()),
        ],
      ),
    );
  }
}

class _ProfileLoadingHeader extends StatelessWidget {
  const _ProfileLoadingHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeeeeef))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chevron_left, size: 30),
              ),
              const Text(
                '用户中心',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfffffbfb),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffffe3e8)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(0xfff2d8dd),
                      child: _SkeletonBox(width: 32, height: 32, radius: 16),
                    ),
                    Positioned(
                      right: -1,
                      bottom: 2,
                      child: _OnlineDot(isOnline: null),
                    ),
                  ],
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _SkeletonBox(
                              width: 132,
                              height: 26,
                              radius: 7,
                            ),
                          ),
                          SizedBox(width: 8),
                          _SkeletonBox(width: 58, height: 28, radius: 14),
                        ],
                      ),
                      SizedBox(height: 9),
                      _SkeletonBox(width: 180, height: 14, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SkeletonBox(width: 92, height: 32, radius: 16),
              _SkeletonBox(width: 88, height: 32, radius: 16),
              _SkeletonBox(width: 118, height: 32, radius: 16),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.profile, required this.repository});

  final UserProfile profile;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _ActivitySection(
          title: '个人动态',
          items: profile.homeActivities,
          repository: repository,
        ),
        const SizedBox(height: 14),
        _ActivitySection(
          title: '最新回复',
          items: profile.homeReplies,
          repository: repository,
        ),
      ],
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.future,
    required this.builder,
  });

  final Future<UserProfile>? future;
  final Widget Function(BuildContext context, UserProfile profile) builder;

  @override
  Widget build(BuildContext context) {
    final detailsFuture = future;
    if (detailsFuture == null) {
      return const _TabLoadingSkeleton();
    }
    return FutureBuilder<UserProfile>(
      future: detailsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TextPanel(
                title: '内容加载失败',
                text: '${snapshot.error}',
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const _TabLoadingSkeleton();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(snapshot.data!.uid),
            child: builder(context, snapshot.data!),
          ),
        );
      },
    );
  }
}

class _ProfileInfoTab extends StatelessWidget {
  const _ProfileInfoTab({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _FieldSection(title: '个人信息', fields: profile.info),
        const SizedBox(height: 14),
        _FieldSection(title: '论坛资历', fields: profile.stats),
        if (profile.signature != null && profile.signature!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TextPanel(title: '帖间签名', text: profile.signature!),
        ],
      ],
    );
  }
}

class _ProfileInfoLoadingTab extends StatelessWidget {
  const _ProfileInfoLoadingTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: const [
        _SkeletonPanel(),
        SizedBox(height: 14),
        _SkeletonPanel(),
      ],
    );
  }
}

class _ItemList extends StatelessWidget {
  const _ItemList({
    required this.items,
    required this.emptyText,
    required this.repository,
  });

  final List<UserListItem> items;
  final String emptyText;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyList(text: emptyText);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _ThreadLikeTile(
          item: item,
          repository: repository,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadDetailScreen(
                thread: ForumThread(
                  title: item.title,
                  url: item.url,
                  replies: item.replies ?? 0,
                  section: item.section ?? '用户中心',
                  author: item.author,
                  authorUrl: item.authorUrl,
                  lastPost: item.date,
                ),
                repository: repository,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.title,
    required this.items,
    required this.repository,
  });

  final String title;
  final List<UserActivityItem> items;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _TextPanel(title: title, text: '暂无内容');
    return _Panel(
      title: title,
      child: Column(
        children: items
            .map(
              (item) => _ActivityTile(
                item: item,
                repository: repository,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.item, required this.repository});

  final UserActivityItem item;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ThreadDetailScreen(
            thread: ForumThread(
              title: item.title,
              url: item.url,
              replies: 0,
              section: '用户动态',
              author: item.author,
              lastPost: item.date,
            ),
            repository: repository,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.bolt_outlined,
              size: 18,
              color: _ProfileTheme.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.action ?? '动态',
                    style: const TextStyle(
                      color: Color(0xff777777),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                  if (item.date != null)
                    Text(
                      item.date!,
                      style: const TextStyle(
                        color: Color(0xff999999),
                        fontSize: 12,
                      ),
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

class _ThreadLikeTile extends StatelessWidget {
  const _ThreadLikeTile({
    required this.item,
    required this.repository,
    required this.onTap,
  });

  final UserListItem item;
  final ForumRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (item.section != null) item.section!,
      if (item.date != null) item.date!,
    ].join(' · ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff777777),
                    fontSize: 12,
                  ),
                ),
              ],
              if (item.author != null) ...[
                const SizedBox(height: 8),
                _AuthorLink(
                  name: item.author!,
                  url: item.authorUrl,
                  repository: repository,
                ),
              ],
              if (item.replies != null || item.views != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (item.replies != null)
                      _TinyStat(
                          icon: Icons.forum_outlined, text: '${item.replies}'),
                    if (item.views != null)
                      _TinyStat(
                        icon: Icons.visibility_outlined,
                        text: '${item.views}',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorLink extends StatelessWidget {
  const _AuthorLink({
    required this.name,
    required this.url,
    required this.repository,
  });

  final String name;
  final String? url;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: url == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    userUrl: url!,
                    repository: repository,
                  ),
                ),
              ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xfffff1f3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_outline,
              size: 14,
              color: _ProfileTheme.accent,
            ),
            const SizedBox(width: 4),
            Text(
              name,
              style: const TextStyle(
                color: _ProfileTheme.accent,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection({required this.title, required this.fields});

  final String title;
  final List<UserProfileField> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return _TextPanel(title: title, text: '暂无内容');
    return _Panel(
      title: title,
      child: Column(
        children: fields
            .map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(
                        field.label,
                        style: const TextStyle(
                          color: Color(0xff777777),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        field.value,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: Text(text, style: const TextStyle(color: Color(0xff777777))),
    );
  }
}

class _RefreshTab extends StatelessWidget {
  const _RefreshTab({required this.child, required this.onRefresh});

  final Widget child;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _ProfileTheme.accent,
      onRefresh: onRefresh,
      child: child,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xfffff1f3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(color: _ProfileTheme.accent, fontSize: 12),
      ),
    );
  }
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xff999999)),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Color(0xff777777), fontSize: 12),
        ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Center(
          child: Text(text, style: const TextStyle(color: Color(0xff777777))),
        ),
      ],
    );
  }
}

class _SkeletonPanel extends StatelessWidget {
  const _SkeletonPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 90, height: 18, radius: 6),
          SizedBox(height: 14),
          _SkeletonBox(width: double.infinity, height: 14, radius: 5),
          SizedBox(height: 10),
          _SkeletonBox(width: double.infinity, height: 14, radius: 5),
          SizedBox(height: 10),
          _SkeletonBox(width: 210, height: 14, radius: 5),
        ],
      ),
    );
  }
}

class _TabLoadingSkeleton extends StatelessWidget {
  const _TabLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: const [
        _SkeletonPanel(),
        SizedBox(height: 12),
        _SkeletonPanel(),
        SizedBox(height: 12),
        _SkeletonPanel(),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .45, end: .9),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOut,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xffe7e7ea),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        );
      },
      onEnd: () {},
    );
  }
}

class _ProfileTheme {
  static const accent = Color(0xFFD97786);
}
