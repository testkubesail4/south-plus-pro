import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';

/// Closes a page when pages turn explicitly: the next page is one large
/// tap away; the page bar below the list does the rest of the paging.
class ThreadPageEndCard extends StatelessWidget {
  const ThreadPageEndCard({
    super.key,
    required this.pagination,
    required this.onPageSelected,
    required this.onRefresh,
  });

  final ThreadPagination pagination;

  /// Null while a page loads.
  final ValueChanged<int>? onPageSelected;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final current = pagination.currentPage;
    final select = onPageSelected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!pagination.hasNext) ...[
              Text(
                '已是最后一页',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (pagination.hasNext)
              FilledButton.icon(
                key: const ValueKey('thread-next-page'),
                onPressed: select == null ? null : () => select(current + 1),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text('下一页 · 第 ${current + 1} 页'),
              )
            else
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新本页，看看新回复'),
              ),
          ],
        ),
      ),
    );
  }
}
