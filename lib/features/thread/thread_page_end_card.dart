import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';
import '../common/forum_pager.dart';

/// Closes a page when pages turn explicitly: the next page is one large
/// tap away, previous page and the page picker sit beside it.
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
    final total = pagination.totalPages;
    final select = onPageSelected;
    final muted = TextStyle(color: AppColors.textMuted, fontSize: 13);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pagination.hasNext ? '第 $current 页 · 共 $total 页' : '已是最后一页',
              textAlign: TextAlign.center,
              style: pagination.hasNext
                  ? muted
                  : TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 4),
            if (total > 1)
              // Wraps onto two lines when narrow or at large text sizes.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: pagination.hasPrevious && select != null
                        ? () => select(current - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left, size: 18),
                    label: const Text('上一页'),
                    style: _quiet,
                  ),
                  TextButton.icon(
                    onPressed: select == null
                        ? null
                        : () async {
                            final page = await showForumPagePicker(
                              context,
                              current: current,
                              total: total,
                            );
                            if (page != null && page != current) select(page);
                          },
                    icon: const Icon(Icons.apps, size: 18),
                    label: Text('第 $current / $total 页'),
                    style: _quiet,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // A getter: AppColors follows the live theme mode.
  static ButtonStyle get _quiet => TextButton.styleFrom(
    foregroundColor: AppColors.textMuted,
    minimumSize: const Size(48, 44),
  );
}
