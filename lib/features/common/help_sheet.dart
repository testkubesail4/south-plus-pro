import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Opens on-demand notes: a title over short icon-led lines.
Future<void> showHelpSheet(
  BuildContext context, {
  required String title,
  required List<(IconData, String)> lines,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: AppSpace.lg),
                for (final (icon, line) in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: AppColors.textMuted),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Text(line, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

/// The "?" that opens [showHelpSheet].
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.title, required this.lines});

  final String title;
  final List<(IconData, String)> lines;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: '说明',
        icon: const Icon(Icons.help_outline),
        onPressed: () => showHelpSheet(context, title: title, lines: lines),
      );
}
