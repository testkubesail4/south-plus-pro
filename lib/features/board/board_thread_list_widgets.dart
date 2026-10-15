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

/// ‹ 第 3 / 12 页 › — the centre opens a page-number dialog.
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.onPageSelected,
  });

  final ForumThreadPage page;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    if (page.totalPages <= 1) {
      return const SizedBox(height: 16);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: _boardSurface(context, radius: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: page.hasPrevious
                    ? () => onPageSelected(page.currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showJumpDialog(context),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '第 ${page.currentPage} / ${page.totalPages} 页',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 18,
                          color: AppColors.textFaint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: page.hasNext
                    ? () => onPageSelected(page.currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showJumpDialog(BuildContext context) async {
    final controller = TextEditingController(text: '${page.currentPage}');
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('跳转页码'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '页码',
              helperText: '1 - ${page.totalPages}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final input = int.tryParse(controller.text.trim());
                if (input == null) return;
                Navigator.of(context).pop(input.clamp(1, page.totalPages));
              },
              child: const Text('跳转'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (selected != null) onPageSelected(selected);
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
    final previewImageUrl = thread.previewImageUrl;
    final metaStyle = TextStyle(
      color: AppColors.textFaint,
      fontSize: 12,
      height: 1.3,
    );
    final author = thread.author ?? '匿名';
    final rest = [
      if (thread.lastPost != null && thread.lastPost!.isNotEmpty)
        thread.lastPost!,
      '${thread.replies} 回复',
    ];
    return PerfTrace.span(
      'BoardThreadRow.build',
      () {
        return InkWell(
          onTap: onTap,
          child: Padding(
            padding: _rowPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ForumTitleText(
                  thread.title,
                  titleStyle: thread.titleStyle,
                  maxLines: 2,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15.5,
                    height: 1.4,
                    fontWeight:
                        thread.isSticky ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (thread.bodyPreview != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    thread.bodyPreview!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
                if (previewImageUrl != null) ...[
                  const SizedBox(height: 10),
                  _ThreadPreviewImage(url: previewImageUrl),
                ],
                const SizedBox(height: 6),
                // Wraps rather than truncating at large text sizes.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (thread.isSticky) ...[
                      Icon(
                        Icons.push_pin_outlined,
                        size: 14,
                        color: AppColors.textFaint,
                      ),
                      const SizedBox(width: 2),
                      Text('置顶 · ', style: metaStyle),
                    ],
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: InkWell(
                        onTap: thread.authorUrl == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                      userUrl: thread.authorUrl!,
                                      repository: repository,
                                    ),
                                  ),
                                ),
                        child: Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                    ),
                    Text(' · ${rest.join(' · ')}', style: metaStyle),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      arguments: {'hasPreview': previewImageUrl != null},
    );
  }
}

class _ThreadPreviewImage extends StatefulWidget {
  const _ThreadPreviewImage({required this.url});

  final String url;

  @override
  State<_ThreadPreviewImage> createState() => _ThreadPreviewImageState();
}

class _ThreadPreviewImageState extends State<_ThreadPreviewImage> {
  Size? _imageSize;
  String? _metadataRequestUrl;

  @override
  void initState() {
    super.initState();
    _imageSize = ForumImageMetadataCache.instance.peek(widget.url);
  }

  @override
  void didUpdateWidget(covariant _ThreadPreviewImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _imageSize = ForumImageMetadataCache.instance.peek(widget.url);
    _metadataRequestUrl = null;
  }

  void _ensureMetadata(ImageProvider provider) {
    if (_imageSize != null || _metadataRequestUrl == widget.url) return;
    final url = widget.url;
    _metadataRequestUrl = url;
    ForumImageMetadataCache.instance.get(url, provider).then((size) {
      if (!mounted || widget.url != url) return;
      if (size == null) {
        _metadataRequestUrl = null;
        return;
      }
      if (size == _imageSize) {
        return;
      }
      setState(() {
        _imageSize = size;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _imageSize == null
            ? ThreadPreviewImageLayout.fallback(constraints.maxWidth)
            : ThreadPreviewImageLayout.resolve(
                imageSize: _imageSize!,
                maxWidth: constraints.maxWidth,
              );
        final spec = ForumImageDecodeSpec.forDisplay(
          logicalSize: layout.size,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          maxLongEdge: 960,
        );

        return RepaintBoundary(
          child: CachedForumImage(
            url: widget.url,
            width: layout.size.width,
            height: layout.size.height,
            fit: layout.fit,
            memCacheWidth: spec.memCacheWidth,
            memCacheHeight: spec.memCacheHeight,
            maxWidthDiskCache: spec.maxWidthDiskCache,
            maxHeightDiskCache: spec.maxHeightDiskCache,
            placeholder: (context) => _ThreadPreviewPlaceholder(
              layout: layout,
            ),
            imageBuilder: (context, provider) {
              _ensureMetadata(provider);
              return PerfTrace.span(
                'BoardThreadPreviewImage.build',
                () {
                  return _ThreadPreviewFrame(
                    layout: layout,
                    child: Image(
                      image: provider,
                      width: layout.size.width,
                      height: layout.size.height,
                      fit: layout.fit,
                    ),
                  );
                },
                arguments: {'resolved': _imageSize != null},
              );
            },
            errorWidget: (context) => _ThreadPreviewError(
              width: layout.size.width,
              height: layout.size.height,
            ),
          ),
        );
      },
    );
  }
}

class _ThreadPreviewFrame extends StatelessWidget {
  const _ThreadPreviewFrame({
    required this.layout,
    required this.child,
  });

  final ThreadPreviewImageLayout layout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.surfaceTint),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ThreadPreviewPlaceholder extends StatelessWidget {
  const _ThreadPreviewPlaceholder({required this.layout});

  final ThreadPreviewImageLayout layout;

  @override
  Widget build(BuildContext context) {
    return _ThreadPreviewFrame(
      layout: layout,
      child: const SizedBox.expand(),
    );
  }
}

class _ThreadPreviewError extends StatelessWidget {
  const _ThreadPreviewError({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        color: AppColors.surfaceTint,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 20,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
