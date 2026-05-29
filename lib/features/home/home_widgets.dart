part of 'home_shell.dart';

class _TopBar extends StatelessWidget {
  const _TopBar({required this.repository});

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: const BoxDecoration(
        color: AppColors.header,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '菜单',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.search),
                        title: const Text('搜索'),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SearchScreen(repository: repository),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(repository.isLoggedIn ? '个人中心' : '登录'),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => repository.isLoggedIn
                                  ? UserProfileScreen(
                                      userUrl: 'u.php',
                                      repository: repository,
                                    )
                                  : LoginScreen(repository: repository),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.menu, color: AppColors.text, size: 30),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'southplus',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SearchScreen(repository: repository),
              ),
            ),
            icon: const Icon(Icons.search, color: AppColors.text),
          ),
          if (repository.isLoggedIn)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    userUrl: 'u.php',
                    repository: repository,
                  ),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.account_circle_outlined,
                      color: AppColors.brand,
                      size: 18,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      repository.currentUsername ?? '已登录',
                      style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(repository: repository),
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brand,
                minimumSize: const Size(56, 44),
              ),
              child: const Text(
                'dlkd',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _ForumCrumbs extends StatelessWidget {
  const _ForumCrumbs({required this.items, required this.current});

  final List<String> items;
  final String current;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final item in items) ...[
            Text(
              item,
              style: const TextStyle(
                color: AppColors.brand,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textFaint),
          ],
          Text(
            current,
            style: const TextStyle(
              color: AppColors.link,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardOverview extends StatelessWidget {
  const _BoardOverview({
    required this.sections,
    required this.hot,
    required this.latest,
  });

  final int sections;
  final int hot;
  final int latest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Row(
        children: [
          Expanded(child: _OverviewStat(label: '新帖', value: '$latest')),
          const SizedBox(width: 8),
          Expanded(child: _OverviewStat(label: '热门', value: '$hot')),
          const SizedBox(width: 8),
          Expanded(child: _OverviewStat(label: '分区', value: '$sections')),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LatestThreads extends StatelessWidget {
  const _LatestThreads({
    required this.threads,
    required this.repository,
  });

  final List<ForumThread> threads;
  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return _SimpleSection(
      title: '最新讨论',
      icon: Icons.subject_outlined,
      child: Column(
        children: threads.take(8).map((thread) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ThreadDetailScreen(
                    thread: thread,
                    repository: repository,
                  ),
                ),
              ),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 92),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (thread.bodyPreview != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        thread.bodyPreview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.forum_outlined,
                          color: AppColors.textMuted,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            thread.section,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '[${thread.replies}]',
                          style: const TextStyle(
                            color: AppColors.link,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ForumGroup extends StatelessWidget {
  const _ForumGroup({
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            collapsedIconColor: AppColors.brand,
            iconColor: AppColors.brand,
            leading: icon == null
                ? null
                : Icon(icon, color: AppColors.brand, size: 20),
            title: Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _ForumLink extends StatelessWidget {
  const _ForumLink({required this.title, required this.subtitle, this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.tag_outlined, color: AppColors.brand, size: 18),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

class _SimpleSection extends StatelessWidget {
  const _SimpleSection({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: AppColors.brand, size: 20),
                  const SizedBox(width: 7),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DesktopLink extends StatelessWidget {
  const _DesktopLink();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 14, bottom: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.desktop_windows_outlined,
                  size: 17, color: AppColors.brand),
              SizedBox(width: 6),
              Text(
                '桌面版',
                style: TextStyle(color: AppColors.brand, fontSize: 14),
              ),
            ],
          ),
          SizedBox(height: 18),
          Text(
            'Powered by SP Project v1.0',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
