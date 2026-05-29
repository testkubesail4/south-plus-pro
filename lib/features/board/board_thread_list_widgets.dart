part of 'board_thread_list_screen.dart';

sealed class _BoardListItem {
  const _BoardListItem();

  static List<_BoardListItem> fromPage(ForumThreadPage page) {
    final threads = page.threads;
    return [
      ...page.ads.map(_BoardAdItem.new),
      ...threads.map(_BoardThreadItem.new),
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

class _BoardAdBanner extends StatelessWidget {
  const _BoardAdBanner({required this.ad});

  final ForumBoardAd ad;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ad.imageUrl;
    if (imageUrl != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 6, 28, 14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
            final height = math.max(width / 4.65, 56.0);

            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: AppColors.surface),
                child: SizedBox(
                  width: double.infinity,
                  height: height,
                  child: CachedForumImage(
                    url: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context) {
                      return Container(
                        alignment: Alignment.center,
                        color: AppColors.surfaceTint,
                        child: Text(
                          ad.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return _ListLine(
      minHeight: 76,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.link,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  ad.subtitle == null || ad.subtitle!.isEmpty
                      ? '广告'
                      : ad.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              '广告',
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListLine extends StatelessWidget {
  const _ListLine({
    required this.child,
    this.minHeight = 64,
  });

  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 10, 28, 9),
              child: child,
            ),
          ),
          const Divider(
            height: 1,
            thickness: 0.8,
            indent: 20,
            endIndent: 20,
            color: AppColors.border,
          ),
        ],
      ),
    );
  }
}

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
      return const SizedBox(height: 2);
    }
    final visiblePages = _visiblePages();

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PageTextButton(
            label: '«',
            enabled: page.hasPrevious,
            onPressed: () => onPageSelected(page.currentPage - 1),
          ),
          _PageNumberButton(
            label: '${visiblePages.first}',
            selected: visiblePages.first == page.currentPage,
            onPressed: () => onPageSelected(visiblePages.first),
          ),
          for (final pageNumber in visiblePages.skip(1))
            _PageNumberButton(
              label: '$pageNumber',
              selected: pageNumber == page.currentPage,
              onPressed: () => onPageSelected(pageNumber),
            ),
          _PageTextButton(
            label: '跳转',
            enabled: true,
            wide: true,
            onPressed: () => _showJumpDialog(context),
          ),
          _PageTextButton(
            label: '»',
            enabled: page.hasNext,
            onPressed: () => onPageSelected(page.currentPage + 1),
          ),
        ],
      ),
    );
  }

  List<int> _visiblePages() {
    const windowSize = 5;
    final total = page.totalPages < 1 ? 1 : page.totalPages;
    final current = page.currentPage.clamp(1, total);
    if (total <= windowSize) {
      return [for (var i = 1; i <= total; i++) i];
    }

    var start = current - 2;
    var end = current + 2;
    if (start < 1) {
      end += 1 - start;
      start = 1;
    }
    if (end > total) {
      start -= end - total;
      end = total;
    }
    if (start < 1) start = 1;
    return [for (var i = start; i <= end; i++) i];
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

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return _PageBox(
      label: label,
      onPressed: onPressed,
      background: selected ? AppColors.brand : AppColors.surface,
      foreground: selected ? Colors.white : AppColors.link,
    );
  }
}

class _PageTextButton extends StatelessWidget {
  const _PageTextButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.wide = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return _PageBox(
      label: label,
      onPressed: enabled ? onPressed : null,
      width: wide ? 52 : 34,
      background: AppColors.surface,
      foreground: enabled ? AppColors.link : AppColors.textFaint,
    );
  }
}

class _PageBox extends StatelessWidget {
  const _PageBox({
    required this.label,
    required this.background,
    required this.foreground,
    this.onPressed,
    this.width = 34,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 34,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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
      child: InkWell(
        onTap: onTap,
        child: _ListLine(
          minHeight: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: thread.isSticky
                            ? AppColors.brandDark
                            : AppColors.text,
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight:
                            thread.isSticky ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (thread.bodyPreview != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        thread.bodyPreview!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (thread.author != null)
                          InkWell(
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
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(
                                thread.author!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          )
                        else
                          const Text(
                            '匿名',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            thread.lastPost == null
                                ? ''
                                : ' - 发布于 ${thread.lastPost}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                constraints: const BoxConstraints(minWidth: 50),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.inkSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${thread.replies} 回',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
