import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_request_exception.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../thread/thread_detail_screen.dart';

const _allBoards = ForumSearchBoard(id: 'all', name: '全部版块');

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

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _keyword = TextEditingController();
  final _username = TextEditingController();
  ForumSearchMatch _match = ForumSearchMatch.partial;
  String _boardId = _allBoards.id;
  ForumSearchTime _time = ForumSearchTime.year;
  ForumThreadOrder _order = ForumThreadOrder.postedAt;
  bool _ascending = false;
  List<ForumSearchBoard> _boards = const [_allBoards];
  bool _boardsRequested = false;

  Future<ForumSearchPage>? _future;
  Future<ForumSearchPage> Function()? _lastRequest;
  ForumSearchQuery? _query;
  String? _error;
  bool _searching = false;

  @override
  void dispose() {
    _keyword.dispose();
    _username.dispose();
    super.dispose();
  }

  // Board options cost a search.php request, so load them only when needed.
  Future<void> _loadBoards() async {
    if (_boardsRequested) return;
    _boardsRequested = true;
    try {
      final boards = await widget.repository.fetchSearchBoards();
      if (!mounted || boards.isEmpty) return;
      setState(() {
        _boards = boards.any((board) => board.id == _allBoards.id)
            ? boards
            : [_allBoards, ...boards];
      });
    } catch (_) {
      // Keep "全部版块" and allow another attempt on the next expand.
      _boardsRequested = false;
    }
  }

  void _search() {
    if (_searching) return;
    final query = ForumSearchQuery(
      keyword: _keyword.text.trim(),
      username: _username.text.trim(),
      match: _match,
      boardId: _boardId,
      time: _time,
      order: _order,
      ascending: _ascending,
    );
    if (query.keyword.isEmpty && query.username.isEmpty) {
      setState(() {
        _error = '请输入关键词或用户名';
        _future = null;
      });
      return;
    }
    _query = query;
    _run(() => widget.repository.searchForum(query));
  }

  void _nextPage(String pagePath) {
    final query = _query;
    if (_searching || query == null) return;
    _run(() => widget.repository.searchForumPage(query, pagePath));
  }

  void _run(Future<ForumSearchPage> Function() request) {
    if (_searching) return;
    final future = request();
    setState(() {
      _searching = true;
      _error = null;
      _lastRequest = request;
      _future = future;
    });
    future.whenComplete(() {
      // Only the latest search may release the button.
      if (mounted && identical(_future, future)) {
        setState(() => _searching = false);
      }
    }).ignore();
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
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                        prefixIcon: Icon(Icons.search),
                        suffixIcon: _keyword.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空',
                                onPressed: () {
                                  _keyword.clear();
                                  setState(() {});
                                },
                                icon: Icon(Icons.close),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _username,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        labelText: '用户名',
                        hintText: '只看该用户的主题',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: const Text('高级选项'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        onExpansionChanged: (expanded) {
                          if (expanded) _loadBoards();
                        },
                        children: [
                          _SearchOption<ForumSearchMatch>(
                            label: '匹配方式',
                            value: _match,
                            labels: const {
                              ForumSearchMatch.partial: '部分符合',
                              ForumSearchMatch.exact: '完全符合',
                            },
                            onChanged: (value) =>
                                setState(() => _match = value),
                          ),
                          _SearchOption<String>(
                            // Rebuild when the loaded options replace the default.
                            key: ValueKey(_boards.length),
                            label: '版块',
                            value: _boardId,
                            labels: {
                              for (final board in _boards) board.id: board.name,
                            },
                            onChanged: (value) =>
                                setState(() => _boardId = value),
                          ),
                          _SearchOption<ForumSearchTime>(
                            label: '时间',
                            value: _time,
                            labels: _timeLabels,
                            onChanged: (value) => setState(() => _time = value),
                          ),
                          _SearchOption<ForumThreadOrder>(
                            label: '排序',
                            value: _order,
                            labels: _orderLabels,
                            onChanged: (value) =>
                                setState(() => _order = value),
                          ),
                          _SearchOption<bool>(
                            label: '顺序',
                            value: _ascending,
                            labels: const {false: '降序', true: '升序'},
                            onChanged: (value) =>
                                setState(() => _ascending = value),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _searching ? null : _search,
                  icon: Icon(Icons.search),
                  label: Text(_searching ? '搜索中...' : '搜索'),
                ),
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: future == null
                  ? const _SearchIntro()
                  : FutureBuilder<ForumSearchPage>(
                      future: future,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return AsyncErrorView(
                            title: '搜索失败',
                            message: switch (snapshot.error) {
                              ForumRequestException(:final kind) =>
                                forumRequestErrorText(kind),
                              final error => '$error',
                            },
                            onRetry: () => _run(_lastRequest!),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const ThreadListSkeleton(itemCount: 5);
                        }
                        final page = snapshot.data!;
                        final results = page.threads;
                        if (results.isEmpty) {
                          return _EmptySearchResult(query: _query!);
                        }
                        final nextPagePath = page.nextPagePath;
                        final total = page.total;
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          children: [
                            if (total != null) ...[
                              Text(
                                '共 $total 条结果',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                              const SizedBox(height: 10),
                            ],
                            for (final thread in results) ...[
                              _SearchResultTile(
                                thread: thread,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ThreadDetailScreen(
                                      thread: thread,
                                      repository: widget.repository,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (nextPagePath != null)
                              OutlinedButton(
                                onPressed: _searching
                                    ? null
                                    : () => _nextPage(nextPagePath),
                                child: const Text('下一页'),
                              ),
                          ],
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

class _SearchOption<T> extends StatelessWidget {
  const _SearchOption({
    super.key,
    required this.label,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final entry in labels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
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
                style: TextStyle(
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
            style: TextStyle(
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
      message: '输入关键词或用户名后搜索主题。',
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.query});

  final ForumSearchQuery query;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.manage_search_outlined,
      title: '没有找到相关主题',
      message: [
        if (query.keyword.isNotEmpty) '关键词：“${query.keyword}”',
        if (query.username.isNotEmpty) '用户名：“${query.username}”',
      ].join('\n'),
    );
  }
}
