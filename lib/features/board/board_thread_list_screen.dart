import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../profile/user_profile_screen.dart';
import '../thread/thread_detail_screen.dart';
import '../thread/thread_compose_screen.dart';

class BoardThreadListScreen extends StatefulWidget {
  const BoardThreadListScreen({
    super.key,
    required this.category,
    required this.repository,
  });

  final ForumCategory category;
  final ForumRepository repository;

  @override
  State<BoardThreadListScreen> createState() => _BoardThreadListScreenState();
}

class _BoardThreadListScreenState extends State<BoardThreadListScreen> {
  late Future<List<ForumThread>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchBoardThreads(widget.category);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repository.fetchBoardThreads(widget.category);
    });
    await _future;
  }

  Future<void> _openComposer() async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ThreadComposeScreen(
          category: widget.category,
          repository: widget.repository,
        ),
      ),
    );
    if (posted == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _BoardHeader(
              title: widget.category.name,
              slug: widget.category.slug,
              onCompose: _openComposer,
            ),
            Expanded(
              child: FutureBuilder<List<ForumThread>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorState(
                        message: '${snapshot.error}', onRetry: _refresh);
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final threads = snapshot.data!;
                  return RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: threads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        return _ThreadRow(
                          thread: thread,
                          repository: widget.repository,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ThreadDetailScreen(
                                thread: thread,
                                repository: widget.repository,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.title,
    required this.slug,
    required this.onCompose,
  });

  final String title;
  final String slug;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          decoration: const BoxDecoration(
            color: AppColors.header,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chevron_left, size: 30),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: '发帖',
                onPressed: onCompose,
                icon: const Icon(Icons.edit_outlined, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              const Text(
                '南+ South Plus',
                style: TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textFaint),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.link,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                ' / $slug',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.repository,
    required this.onTap,
  });

  final ForumThread thread;
  final ForumRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (thread.author != null)
                    Expanded(
                      child: Text(
                        thread.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brand,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    const Expanded(
                      child: Text(
                        '匿名',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  Text(
                    '[${thread.replies}]',
                    style: const TextStyle(
                      color: AppColors.link,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                thread.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (thread.bodyPreview != null) ...[
                const SizedBox(height: 8),
                Text(
                  thread.bodyPreview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (thread.author != null && thread.authorUrl != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userUrl: thread.authorUrl!,
                            repository: repository,
                          ),
                        ),
                      ),
                      child: _MetaChip(
                        icon: Icons.person_outline,
                        text: '资料',
                        emphasized: true,
                      ),
                    ),
                  if (thread.author != null && thread.authorUrl != null)
                    const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      thread.lastPost == null
                          ? thread.section
                          : thread.lastPost!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MetaChip(
                    icon: Icons.chat_bubble_outline,
                    text: '${thread.replies}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  final IconData icon;
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.brandSoft : AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: emphasized ? AppColors.brand : AppColors.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: emphasized ? AppColors.brand : AppColors.textMuted,
              fontSize: 12,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
            const Text('板块加载失败', style: TextStyle(fontSize: 18)),
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
