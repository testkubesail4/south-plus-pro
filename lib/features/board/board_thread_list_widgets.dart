part of 'board_thread_list_screen.dart';

sealed class _BoardListItem {
  const _BoardListItem();

  static List<_BoardListItem> fromPage(
    ForumThreadPage page,
    BlockingRules rules,
  ) {
    return [
      ...page.ads.map(_BoardAdItem.new),
      for (final thread in page.threads)
        if (!rules.isThreadBlocked(thread)) _BoardThreadItem(thread),
    ];
  }
}

class _BoardThreadItem extends _BoardListItem {
  const _BoardThreadItem(this.thread);

  final ForumThread thread;
}

class _BoardAdItem extends _BoardListItem {
  const _BoardAdItem(this.ad);

  final ForumBoardAd ad;
}

/// Marks where an appended page starts.
class _BoardPageItem extends _BoardListItem {
  const _BoardPageItem(this.page);

  final int page;
}

const _rowPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);

/// Placeholder rows on the same surface and paddings as loaded rows.
class _BoardThreadListSkeleton extends StatelessWidget {
  const _BoardThreadListSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: SkeletonBlock(height: height, borderRadius: 6),
        );
    return Semantics(
      label: '加载中',
      child: Container(
        decoration: _boardSurface(context),
        child: Column(
          children: [
            for (var index = 0; index < 8; index++) ...[
              if (index > 0) const _RowDivider(),
              Padding(
                padding: _rowPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(index.isEven ? 0.86 : 0.7, 14),
                    const SizedBox(height: 10),
                    bar(index % 3 == 0 ? 0.5 : 0.4, 11),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A thin rule labelled with the page that starts below it.
class _PageBoundary extends StatelessWidget {
  const _PageBoundary({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    final rule = Expanded(
      child: Divider(
        height: 1,
        color: AppColors.border.withValues(alpha: 0.6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child:
                Text('第 $page 页', style: Theme.of(context).textTheme.bodySmall),
          ),
          rule,
        ],
      ),
    );
  }
}

/// Below the topics: one placeholder row while the next page loads, an
/// inline retry when it failed, and a closing line after the last page.
class _BoardMoreFooter extends StatelessWidget {
  const _BoardMoreFooter({
    required this.loading,
    required this.failed,
    required this.atEnd,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final bool atEnd;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (failed) {
      child = Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('加载下一页失败', style: Theme.of(context).textTheme.bodySmall),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (loading) {
      Widget bar(double widthFactor, double height) => FractionallySizedBox(
            widthFactor: widthFactor,
            child: SkeletonBlock(height: height, borderRadius: 6),
          );
      child = Semantics(
        label: '加载中',
        child: Container(
          decoration: _boardSurface(context),
          padding: _rowPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(0.8, 14),
              const SizedBox(height: 10),
              bar(0.4, 11),
            ],
          ),
        ),
      );
    } else if (atEnd) {
      child = Center(
        child: Text('已到最后一页', style: Theme.of(context).textTheme.bodySmall),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.only(top: 12), child: child);
  }
}

class _BoardAdBanner extends StatelessWidget {
  const _BoardAdBanner({
    required this.ad,
    required this.onTap,
  });

  final ForumBoardAd ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ad.imageUrl;
    if (imageUrl != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
            final height = math.max(width / 4.65, 56.0);

            return Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: SizedBox(
                    width: double.infinity,
                    height: height,
                    child: CachedForumImage(
                      url: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: width.ceil(),
                      memCacheHeight: height.ceil(),
                      errorWidget: (context) {
                        return Container(
                          alignment: Alignment.center,
                          color: AppColors.surfaceTint,
                          child: Text(
                            ad.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final subtitle = ad.subtitle == null || ad.subtitle!.isEmpty
        ? '广告'
        : '广告 · ${ad.subtitle}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: _rowPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ad.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _orderLabel(ForumThreadOrder order) => switch (order) {
      ForumThreadOrder.lastPost => '最后发表',
      ForumThreadOrder.postedAt => '发表时间',
      ForumThreadOrder.hits => '人气',
      ForumThreadOrder.replies => '回复',
    };

/// Title (site colours kept), optional preview, then one faint meta line:
/// 置顶 · author · time · replies.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.onTap});

  final ForumThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previewImageUrl = thread.previewImageUrl;
    final thumbnailDecode = ForumImageDecodeSpec.forDisplay(
      logicalSize: const Size.square(56),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      memoryScale: 3,
      diskScale: 3,
    );
    return PerfTrace.span(
      'BoardThreadRow.build',
      () => ForumThreadRow(
        title: thread.title,
        titleStyle: thread.titleStyle,
        tag: thread.isSticky ? '置顶' : null,
        emphasized: thread.isSticky,
        meta: [
          thread.author ?? '匿名',
          if (thread.lastPost case final last? when last.isNotEmpty) last,
          '${thread.replies} 回复',
        ],
        // The image-load setting applies: CachedForumImage keeps the policy.
        thumbnail: previewImageUrl == null
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: CachedForumImage(
                  url: previewImageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  // Fit within three tiles a side: cover keeps a sharp short
                  // side up to 3:1, and a long strip still decodes small.
                  decodeToFit: true,
                  memCacheWidth: thumbnailDecode.memCacheWidth,
                  memCacheHeight: thumbnailDecode.memCacheHeight,
                  maxWidthDiskCache: thumbnailDecode.maxWidthDiskCache,
                  maxHeightDiskCache: thumbnailDecode.maxHeightDiskCache,
                  placeholder: (_) => ColoredBox(color: AppColors.inkSoft),
                  errorWidget: (_) => ColoredBox(color: AppColors.inkSoft),
                ),
              ),
        onTap: onTap,
      ),
      arguments: {'hasPreview': previewImageUrl != null},
    );
  }
}
