import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Settings-like rows on one card surface (DESIGN.md §8): an optional
/// label and description above, rows divided by hairlines.
class AppGroup extends StatelessWidget {
  const AppGroup({
    super.key,
    this.label,
    this.description,
    required this.children,
    this.dividerIndent = 54,
  });

  final String? label;

  /// One short sentence under the label, for groups that need it.
  final String? description;
  final List<Widget> children;

  /// Where dividers start: the title's start in rows with a leading icon.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null || description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Semantics(
                    header: true,
                    child: Text(
                      label!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (description != null)
                  Text(description!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        Container(
          decoration: appSurface(context),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) Divider(indent: dividerIndent),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of an [AppGroup]: leading icon, title, optional subtitle and a
/// trailing value, control or chevron (DESIGN.md §8).
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.selected,
    this.unread = false,
    this.destructive = false,
    this.enabled,
  });

  final IconData? icon;
  final Widget title;
  final Widget? subtitle;

  /// Current value shown before the chevron, e.g. 「跟随系统」.
  final String? value;

  /// Replaces the default trailing (check or chevron), e.g. a [Switch].
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Non-null makes this a choice row; true shows the check.
  final bool? selected;
  final bool unread;
  final bool destructive;

  /// Whether the row looks usable; by default, whether it has [onTap].
  /// Static information rows pass true so they read at full contrast.
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = enabled ?? onTap != null;
    final error = theme.colorScheme.error;
    final iconColor = !active
        ? AppColors.textFaint
        : destructive
            ? error
            : AppColors.textMuted;
    final end = trailing ??
        switch (selected) {
          true => Icon(Icons.check, color: AppColors.brand),
          false => null,
          null when onTap != null && !destructive =>
            Icon(Icons.chevron_right, color: AppColors.textFaint),
          null => null,
        };
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: active ? onTap : null,
        child: Semantics(
          selected: selected,
          // The dot alone is invisible to screen readers.
          value: unread ? '有未读' : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: subtitle == null ? 56 : 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: iconColor),
                    const SizedBox(width: AppSpace.lg),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: DefaultTextStyle.merge(
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: !active
                                      ? AppColors.textFaint
                                      : destructive
                                          ? error
                                          : AppColors.text,
                                ),
                                child: title,
                              ),
                            ),
                            if (unread) const SizedBox(width: AppSpace.sm),
                            Badge(isLabelVisible: unread),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle.merge(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: active
                                  ? AppColors.textMuted
                                  : AppColors.textFaint,
                            ),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: AppSpace.md),
                    Flexible(
                      flex: 0,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          value!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ],
                  if (end != null) ...[
                    const SizedBox(width: AppSpace.sm),
                    end,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
