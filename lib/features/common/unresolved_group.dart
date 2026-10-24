import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Rows a search could not decide on, shown in full on demand under their
/// own heading; never folded into the matches and never dropped.
class UnresolvedGroup extends StatelessWidget {
  const UnresolvedGroup({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  /// The heading with its count, e.g. 标题不完整 (2).
  final String title;

  final bool expanded;
  final VoidCallback onToggle;

  /// The rows themselves.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = expanded ? child : const SizedBox(width: double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Reduced motion shows the content directly: a zero-duration
        // AnimatedSize finishes its controller inside its own layout and
        // dirties itself there.
        if (MediaQuery.disableAnimationsOf(context))
          body
        else
          AnimatedSize(
            duration: AppMotion.short,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: body,
          ),
      ],
    );
  }
}
