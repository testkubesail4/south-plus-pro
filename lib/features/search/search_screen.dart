import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _keyword = TextEditingController();
  Future<List<ForumThread>>? _future;
  String? _error;
  String _lastQuery = '';

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  void _search() {
    final query = _keyword.text.trim();
    if (query.isEmpty) {
      setState(() {
        _error = '请输入关键词';
        _future = null;
      });
      return;
    }

    setState(() {
      _error = null;
      _lastQuery = query;
      _future = widget.repository.searchThreads(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final future = _future;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _keyword,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      labelText: '关键词',
                      hintText: '搜索主题标题',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _keyword.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空',
                              onPressed: () {
                                _keyword.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _search,
                    icon: const Icon(Icons.search),
                    label: const Text('搜索'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: future == null
                  ? const _SearchIntro()
                  : FutureBuilder<List<ForumThread>>(
                      future: future,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return AsyncErrorView(
                            title: '搜索失败',
                            message: '${snapshot.error}',
                            onRetry: _search,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const ThreadListSkeleton(itemCount: 5);
                        }
                        final results = snapshot.data!;
                        if (results.isEmpty) {
                          return _EmptySearchResult(query: _lastQuery);
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final thread = results[index];
                            return _SearchResultTile(
                              thread: thread,
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

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.thread, required this.onTap});

  final ForumThread thread;
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
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SearchMetaChip(
                    icon: Icons.tag_outlined,
                    text: thread.section,
                  ),
                  if (thread.author != null)
                    _SearchMetaChip(
                      icon: Icons.person_outline,
                      text: thread.author!,
                    ),
                  if (thread.lastPost != null)
                    _SearchMetaChip(
                      icon: Icons.schedule_outlined,
                      text: thread.lastPost!,
                    ),
                  _SearchMetaChip(
                    icon: Icons.chat_bubble_outline,
                    text: '${thread.replies} 回复',
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

class _SearchMetaChip extends StatelessWidget {
  const _SearchMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchIntro extends StatelessWidget {
  const _SearchIntro();

  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.search,
      title: '搜索主题',
      message: '输入关键词后搜索主题标题。',
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.manage_search_outlined,
      title: '没有找到相关主题',
      message: '关键词：“$query”',
    );
  }
}
