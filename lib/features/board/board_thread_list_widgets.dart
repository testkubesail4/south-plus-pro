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
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
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
              style: TextStyle(
                color: AppColors.text,
                fontSize: 15.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 12,
                height: 1.3,
              ),
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
