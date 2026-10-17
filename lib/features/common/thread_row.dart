import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';
import 'forum_title_text.dart';

/// A thread in any list (DESIGN.md §8): title, then one meta line.
/// Sits in an [AppGroup]-like surface with dividers; no card of its own.
class ForumThreadRow extends StatelessWidget {
  const ForumThreadRow({
    super.key,
    required this.title,
    this.titleStyle,
    this.meta = const [],
    this.tag,
    this.thumbnail,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.emphasized = false,
  })  : dense = false,
        count = null;

  /// One line, title and a trailing count only (home 速览).
  const ForumThreadRow.dense({
    super.key,
    required this.title,
    this.titleStyle,
    this.count,
    this.onTap,
    this.onLongPress,
  })  : dense = true,
        meta = const [],
        tag = null,
        thumbnail = null,
        trailing = null,
        emphasized = false;

  final String title;
  final ForumTitleStyle? titleStyle;

  /// Shown joined by ` · ` in one line: board, author, time, `N 回复`.
  final List<String> meta;

  /// A short leading tag such as 置顶 or 精华.
  final String? tag;

  /// A 56 px preview image, already clipped by the caller.
  final Widget? thumbnail;

  /// E.g. a `⋯` [IconButton] for the long-press actions.
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Unread or sticky: the title uses weight 600.
  final bool emphasized;
  final bool dense;

  /// Reply count of a dense row.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleText = ForumTitleText(
      title,
      titleStyle: titleStyle,
      maxLines: dense ? 1 : 2,
      style: theme.textTheme.titleSmall!.copyWith(
        fontWeight: emphasized ? FontWeight.w600 : null,
      ),
    );
    final Widget body;
    if (dense) {
      body = Row(
        children: [
          Expanded(child: titleText),
          if (count != null) ...[
            const SizedBox(width: AppSpace.md),
            Semantics(
              label: '$count 回复',
              excludeSemantics: true,
              child: Text(
                '$count',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ],
      );
    } else {
      body = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText,
                if (meta.isNotEmpty || tag != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  _MetaLine(tag: tag, meta: meta.join(' · ')),
                ],
              ],
            ),
          ),
          if (thumbnail != null) ...[
            const SizedBox(width: AppSpace.md),
            SizedBox.square(dimension: 56, child: thumbnail),
          ],
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.xs),
            trailing!,
          ],
        ],
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.lg,
              dense ? AppSpace.sm : AppSpace.md,
              trailing == null ? AppSpace.lg : AppSpace.xs,
              dense ? AppSpace.sm : AppSpace.md,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The meta line. A tag such as 置顶 leads it as an accent word that never
/// ellipsizes; only the joined meta does.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.tag, required this.meta});

  final String? tag;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final metaText = Text(
      meta,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final tag = this.tag;
    if (tag == null) return metaText;
    return Row(
      children: [
        Text(
          tag,
          maxLines: 1,
          style: style?.copyWith(
            color: AppColors.brandDark,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (meta.isNotEmpty) ...[
          Text(' · ', style: style),
          Flexible(child: metaText),
        ],
      ],
    );
  }
}

/// A small pill label (DESIGN.md §8): neutral, or accent for 楼主 / 置顶.
class AppTag extends StatelessWidget {
  const AppTag(this.label, {super.key, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
      decoration: ShapeDecoration(
        color: accent ? AppColors.brandSoft : AppColors.inkSoft,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: accent ? AppColors.brandDark : AppColors.textMuted,
            ),
      ),
    );
  }
}
