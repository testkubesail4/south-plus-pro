part of 'board_thread_list_screen.dart';

// Board layout, in the home page's language: a centred column (AppWidths.list) of
// soft surfaces on the background, section titles 20/w600, hairline rows.

const _wallSpacing = 12.0;
const _siblingPanelWidth = 248.0;

// The list keeps AppWidths.list; the sibling panel adds its own width.
double _boardGutter(double width, {bool panel = false}) => appGutter(
    width, AppWidths.list + (panel ? _siblingPanelWidth + AppSpace.xl : 0));

int _subBoardColumns(double width) => width < 600
    ? 2
    : width < 900
        ? 3
        : 4;

int _wallColumns(double width) =>
    math.max(2, ((width + _wallSpacing) / (180 + _wallSpacing)).floor());

BoxDecoration _boardSurface(BuildContext context, {double radius = 16}) =>
    BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: Theme.of(context).brightness == Brightness.dark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
    );

/// 290511 → 29.1万; below ten thousand, digits with separators.
String _compactCount(int value) {
  if (value >= 10000) {
    final wan = (value / 10000).toStringAsFixed(1);
    return '${wan.endsWith('.0') ? wan.substring(0, wan.length - 2) : wan}万';
  }
  return value
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

/// "2026-10-15 13:25": today → 13:25, this year → 10-15, else the date.
String _shortTime(String time, {DateTime? now}) {
  final at = DateTime.tryParse(time.trim().replaceFirst(' ', 'T'));
  if (at == null) return time.trim();
  final today = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  if (at.year == today.year && at.month == today.month && at.day == today.day) {
    return '${two(at.hour)}:${two(at.minute)}';
  }
  if (at.year == today.year) return '${two(at.month)}-${two(at.day)}';
  return '${at.year}-${two(at.month)}-${two(at.day)}';
}

String _subBoardMeta(ForumBoard board) => [
      if (board.postCount != null) '${_compactCount(board.postCount!)} 帖',
      if (board.lastPostTime != null && board.lastPostTime!.isNotEmpty)
        _shortTime(board.lastPostTime!),
    ].join(' · ');

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: AppColors.border.withValues(alpha: 0.6),
      );
}

/// Back, the board title and search. A sub-board names its parent above the
/// title; the title opens the sibling switcher (or the parent when the
/// siblings are unknown).
class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.gutter,
    required this.title,
    this.parent,
    this.onParent,
    this.onSwitch,
    this.onSearch,
  });

  final double gutter;
  final String title;
  final ForumCategory? parent;
  final VoidCallback? onParent;
  final VoidCallback? onSwitch;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final onTitle = onSwitch ?? onParent;
    final parentName = parent?.name ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter - 12, 4, gutter - 8, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: onTitle != null,
                hint: onSwitch != null ? '切换版块' : null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTitle,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (parentName.isNotEmpty)
                            Text(
                              parentName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              if (onSwitch != null) ...[
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.expand_more,
                                  size: 20,
                                  color: AppColors.textFaint,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onSearch != null)
              IconButton(
                tooltip: '在本版搜索',
                onPressed: onSearch,
                icon: const Icon(Icons.search),
              ),
          ],
        ),
      ),
    );
  }
}

/// 子版块: one surface holding a grid of sub-board tiles.
class _SubBoardSection extends StatelessWidget {
  const _SubBoardSection({
    required this.boards,
    required this.width,
    required this.onOpen,
    this.collapsed = false,
    this.onToggle,
  });

  final List<ForumBoard> boards;
  final double width;
  final ValueChanged<ForumBoard> onOpen;
  final bool collapsed;

  /// Null when the board has no id to remember a fold under.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            button: onToggle != null,
            expanded: onToggle == null ? null : !collapsed,
            hint: onToggle == null ? null : (collapsed ? '展开' : '折叠'),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '子版块',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              '${boards.length} 个',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onToggle != null)
                      AnimatedRotation(
                        turns: collapsed ? -0.25 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppMotion.short,
                        curve: AppMotion.enter,
                        child: Icon(
                          Icons.expand_more,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Only the fold animates; a grid that changes height follows at once.
        TweenAnimationBuilder<double>(
          tween: Tween(end: collapsed ? 0 : 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.short,
          curve: AppMotion.enter,
          child: ExcludeFocus(
            excluding: collapsed,
            child: ExcludeSemantics(
              excluding: collapsed,
              child: IgnorePointer(
                ignoring: collapsed,
                child: _subBoardGrid(context),
              ),
            ),
          ),
          builder: (context, open, child) => ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: open,
              child: child,
            ),
          ),
        ),
      ],
    );
  }

  Widget _subBoardGrid(BuildContext context) {
    final columns = _subBoardColumns(width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: _boardSurface(context),
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              for (var start = 0; start < boards.length; start += columns)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++)
                        Expanded(
                          child: start + c < boards.length
                              ? _SubBoardTile(
                                  board: boards[start + c],
                                  onOpen: onOpen,
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubBoardTile extends StatelessWidget {
  const _SubBoardTile({required this.board, required this.onOpen});

  final ForumBoard board;
  final ValueChanged<ForumBoard> onOpen;

  @override
  Widget build(BuildContext context) {
    final meta = _subBoardMeta(board);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(board),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              board.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Parent board on top, then its sub-boards; the open one is checked.
class _SiblingList extends StatelessWidget {
  const _SiblingList({
    required this.parent,
    required this.siblings,
    required this.currentUrl,
    required this.onParent,
    required this.onSelected,
  });

  final ForumCategory? parent;
  final List<ForumBoard> siblings;
  final String? currentUrl;
  final VoidCallback onParent;
  final ValueChanged<ForumBoard> onSelected;

  @override
  Widget build(BuildContext context) {
    final parent = this.parent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parent != null) ...[
          ListTile(
            minTileHeight: 56,
            leading: Icon(
              Icons.arrow_upward_outlined,
              color: AppColors.textMuted,
              size: 20,
            ),
            title: Text(
              parent.name,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '返回上级版块',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: onParent,
          ),
          const _RowDivider(),
        ],
        for (final board in siblings)
          ListTile(
            minTileHeight: 52,
            selected: board.url == currentUrl,
            title: Text(
              board.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: board.url == currentUrl
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
            ),
            subtitle: switch (_subBoardMeta(board)) {
              '' => null,
              final meta => Text(
                  meta,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            },
            trailing: board.url == currentUrl
                ? Icon(Icons.check, color: AppColors.brand, size: 20)
                : null,
            onTap: board.url == currentUrl ? null : () => onSelected(board),
          ),
      ],
    );
  }
}

Future<void> _showSiblingSheet(
  BuildContext context, {
  required ForumCategory? parent,
  required List<ForumBoard> siblings,
  required String? currentUrl,
  required ValueChanged<ForumBoard> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: _SiblingList(
          parent: parent,
          siblings: siblings,
          currentUrl: currentUrl,
          onParent: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).maybePop();
          },
          onSelected: (board) {
            Navigator.of(sheetContext).pop();
            onSelected(board);
          },
        ),
      ),
    ),
  );
}

/// Wide windows keep the switcher open beside the topics.
class _SiblingPanel extends StatelessWidget {
  const _SiblingPanel({required this.child});

  final _SiblingList child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          decoration: _boardSurface(context),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Filter tabs (全部 · 精华 · topic types | special types), then sort and the
/// list/picture-wall switch. [wall] is null when the board has no wall.
class _BoardToolbar extends StatelessWidget {
  const _BoardToolbar({
    required this.filters,
    required this.activeUrl,
    required this.onFilter,
    required this.order,
    required this.onOrder,
    required this.wall,
    required this.onWall,
  });

  final List<ForumBoardFilter> filters;
  final String? activeUrl;
  final ValueChanged<ForumBoardFilter> onFilter;
  final ForumThreadOrder order;
  final ValueChanged<ForumThreadOrder> onOrder;
  final bool? wall;
  final ValueChanged<bool> onWall;

  static double extentFor(BuildContext context) =>
      math.max(48, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 26) + 1;

  bool _selected(ForumBoardFilter filter) => activeUrl == null
      ? filter.kind == ForumBoardFilterKind.all
      : filter.url == activeUrl;

  @override
  Widget build(BuildContext context) {
    // Large text keeps the width for the filter tabs.
    final compact = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final tabs = <Widget>[];
    for (final (i, filter) in filters.indexed) {
      if (i > 0 &&
          filter.kind == ForumBoardFilterKind.special &&
          filters[i - 1].kind != ForumBoardFilterKind.special) {
        tabs.add(Container(
          width: 1,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: AppColors.border,
        ));
      }
      tabs.add(_FilterTab(
        label: filter.label,
        selected: _selected(filter),
        onTap: () => onFilter(filter),
      ));
    }
    if (tabs.isEmpty) {
      tabs.add(const _FilterTab(label: '全部主题', selected: true));
    }
    return Row(
      children: [
        Expanded(
          // A trailing fade shows the tabs continue past the edge.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              colors: const [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 1 - 40 / rect.width, 1],
            ).createShader(rect),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 40),
              child: Row(children: tabs),
            ),
          ),
        ),
        PopupMenuButton<ForumThreadOrder>(
          key: const ValueKey('board-order-button'),
          tooltip: '排序',
          initialValue: order,
          onSelected: onOrder,
          itemBuilder: (context) => [
            for (final value in ForumThreadOrder.values)
              PopupMenuItem(value: value, child: Text(_orderLabel(value))),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 18, color: AppColors.textMuted),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text(
                      _orderLabel(order),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (wall != null)
          IconButton(
            tooltip: wall! ? '列表' : '图墙',
            onPressed: () => onWall(!wall!),
            icon: Icon(
              wall! ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
              size: 20,
              color: AppColors.textMuted,
            ),
          ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: selected && onTap != null
                      ? AppColors.text
                      : Colors.transparent,
                ),
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? AppColors.text : AppColors.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardToolbarDelegate extends SliverPersistentHeaderDelegate {
  _BoardToolbarDelegate({
    required this.gutter,
    required this.extent,
    required this.child,
  });

  final double gutter;
  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: extent,
      color: AppColors.background,
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
          ),
        ),
        // Tab text lines up with the row text below.
        child: Padding(padding: const EdgeInsets.only(left: 6), child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(_BoardToolbarDelegate oldDelegate) => true;
}

class _EmptyTopics extends StatelessWidget {
  const _EmptyTopics({required this.inSubBoards});

  final bool inSubBoards;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      alignment: Alignment.center,
      decoration: _boardSurface(context),
      child: Text(
        inSubBoards ? '这个板块的主题在子版块中' : '暂无主题',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

/// A picture-wall card: cover-cropped first image, title, author · replies.
class _WallCard extends StatelessWidget {
  const _WallCard({required this.thread, required this.onTap});

  final ForumThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = thread.previewImageUrl;
    final meta = [
      if (thread.author != null) thread.author!,
      '${thread.replies} 回复',
    ].join(' · ');
    return DecoratedBox(
      decoration: _boardSurface(context, radius: 12),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final placeholder = ColoredBox(
                      color: AppColors.inkSoft,
                      child: Center(
                        child: Icon(
                          url == null
                              ? Icons.article_outlined
                              : Icons.image_outlined,
                          size: 24,
                          color: AppColors.textFaint,
                        ),
                      ),
                    );
                    if (url == null) return placeholder;
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    return CachedForumImage(
                      url: url,
                      fit: BoxFit.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      // Cover needs the full card width; the height bound
                      // (three cards tall) keeps very long images small.
                      decodeToFit: true,
                      memCacheWidth: (constraints.maxWidth * dpr).ceil(),
                      memCacheHeight: (constraints.maxHeight * dpr * 3).ceil(),
                      placeholder: (_) => placeholder,
                      errorWidget: (_) => placeholder,
                    );
                  },
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(AppSpace.md, 8, AppSpace.md, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Two title lines are always reserved so a row of
                    // cards lines up.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            MediaQuery.textScalerOf(context).scale(15) * 2.9,
                      ),
                      child: ForumTitleText(
                        thread.title,
                        titleStyle: thread.titleStyle,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.titleSmall!,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
