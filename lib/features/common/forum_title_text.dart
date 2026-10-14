import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';

/// A thread title drawn with the site's highlight (color, bold, italic,
/// underline), its color kept readable on the current surface.
class ForumTitleText extends StatelessWidget {
  const ForumTitleText(
    this.title, {
    super.key,
    required this.titleStyle,
    required this.style,
    this.maxLines,
  });

  final String title;
  final ForumTitleStyle? titleStyle;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final highlight = titleStyle;
    final color = highlight?.colorValue;
    return Text(
      title,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: highlight == null
          ? style
          : style.copyWith(
              color: color == null
                  ? null
                  : readableTitleColor(Color(color), AppColors.surface),
              fontWeight: highlight.bold ? FontWeight.w800 : null,
              fontStyle: highlight.italic ? FontStyle.italic : null,
              decoration: highlight.underline ? TextDecoration.underline : null,
            ),
    );
  }
}

/// Moves [color]'s lightness away from [background] until the pair reaches
/// WCAG AA contrast (4.5:1), keeping the hue the site chose.
Color readableTitleColor(Color color, Color background) {
  final bg = background.computeLuminance();
  final towardLight = bg < 0.5;
  var hsl = HSLColor.fromColor(color);
  double contrast(Color c) {
    final l = c.computeLuminance();
    return (l > bg ? l + 0.05 : bg + 0.05) / (l > bg ? bg + 0.05 : l + 0.05);
  }

  while (contrast(hsl.toColor()) < 4.5) {
    final next = (hsl.lightness + (towardLight ? 0.04 : -0.04)).clamp(0.0, 1.0);
    if (next == hsl.lightness) break;
    hsl = hsl.withLightness(next);
  }
  return hsl.toColor();
}
