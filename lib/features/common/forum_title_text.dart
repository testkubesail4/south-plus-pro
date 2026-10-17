import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';

/// A thread title with the site's highlight: bold and italic on the text, the
/// site colour on a short bar hanging in the left margin beside the first line
/// (kept readable on the surface). The title is never inset, so a wrapped line
/// starts at the same x as the first. The text stays in the body colour and is
/// never underlined, so a highlighted title does not read as a raw link. The
/// parent leaves at least [markGutter] of padding at the start.
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

  /// The bar sits this far left of the text (its own 4 px included).
  static const markGutter = 8.0;

  @override
  Widget build(BuildContext context) {
    final highlight = titleStyle;
    final color = highlight?.colorValue;
    final text = Text(
      title,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: highlight == null
          ? style
          : style.copyWith(
              fontWeight: highlight.bold ? FontWeight.w700 : null,
              fontStyle: highlight.italic ? FontStyle.italic : null,
            ),
    );
    if (color == null) return text;
    // The bar is centred on the first line at any text scale.
    final fontSize =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14);
    final line = fontSize * (style.height ?? 1.3);
    final bar = fontSize * 0.9;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        text,
        PositionedDirectional(
          start: -markGutter,
          top: (line - bar) / 2,
          width: 4,
          height: bar,
          child: Semantics(
            label: '高亮标题',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: readableTitleColor(Color(color), AppColors.surface),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
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
