part of 'user_profile_screen.dart';

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 34,
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
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (profile.tagline != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        profile.tagline!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff777777),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'UID', value: profile.uid),
              if (profile.level != null)
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

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('用户中心加载失败', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTheme {
  static const accent = Color(0xFFD97786);
}
