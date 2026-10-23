import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A page's second level of navigation: compact chips on one line, start
/// aligned, with room for a trailing control.
class SubTabs<T> extends StatelessWidget {
  const SubTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    this.trailing,
    this.padding,
  });

  final List<(T, String)> tabs;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? trailing;

  /// Defaults to the page gutter; zero inside an already padded parent.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ??
          EdgeInsets.only(
            left: AppSpace.lg,
            right: trailing == null ? AppSpace.lg : AppSpace.xs,
          ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, (value, label)) in tabs.indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpace.sm),
                    // One node per tab, announced as one of a group.
                    MergeSemantics(
                      child: Semantics(
                        inMutuallyExclusiveGroup: true,
                        child: ChoiceChip(
                          label: Text(label),
                          selected: value == selected,
                          showCheckmark: false,
                          // 48px to touch on every platform, desktop too.
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          visualDensity: VisualDensity.standard,
                          labelStyle: theme.textTheme.labelLarge?.copyWith(
                            color: value == selected
                                ? AppColors.brandDark
                                : AppColors.textMuted,
                          ),
                          onSelected: (_) => onSelected(value),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing case final trailing?) trailing,
        ],
      ),
    );
  }
}
