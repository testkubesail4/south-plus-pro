import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'content_width.dart';

/// The title row of a top-level tab (首页, 收藏, 搜索, 消息, 我的): one title
/// style, height and inset on every tab, on the gutter of the tab's content
/// [maxWidth]. It grows with large text; only the title truncates.
class AppTabHeader extends StatelessWidget {
  const AppTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTitleTap,
    this.actions = const [],
    this.maxWidth = AppWidths.list,
    this.liveRegion = false,
  });

  final String title;

  /// A note after the title, e.g. how many rows are loaded; wraps below it
  /// when the row runs out of room.
  final String? subtitle;

  /// Before the title, e.g. the account avatar.
  final Widget? leading;

  /// Makes [leading] and the title one tap target.
  final VoidCallback? onTitleTap;
  final List<Widget> actions;
  final double maxWidth;

  /// Announces title changes, e.g. a selection count.
  final bool liveRegion;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Semantics(
      header: true,
      liveRegion: liveRegion,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleLarge,
      ),
    );
    Widget heading = leading == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading!,
              const SizedBox(width: AppSpace.md),
              Flexible(child: text),
            ],
          );
    if (onTitleTap != null) {
      heading = InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onTitleTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: heading,
        ),
      );
    }
    final note = subtitle;
    return SafeArea(
      bottom: false,
      child: AppContentWidth(
        maxWidth: maxWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Row(
            children: [
              if (note == null)
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: heading),
                )
              else ...[
                heading,
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text(note, style: theme.textTheme.bodySmall)),
              ],
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
