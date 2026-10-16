import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Horizontal padding that centres content at most [maxWidth] wide in an
/// area [width] wide, never less than the page gutter (DESIGN.md §4).
double appGutter(double width, double maxWidth) =>
    math.max(width < 600 ? AppSpace.lg : AppSpace.xl, (width - maxWidth) / 2);

/// Centres [child] at most [maxWidth] wide (e.g. [AppWidths.list]) with the
/// page gutter on both sides.
class AppContentWidth extends StatelessWidget {
  const AppContentWidth({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: appGutter(constraints.maxWidth, maxWidth),
        ),
        child: child,
      ),
    );
  }
}
