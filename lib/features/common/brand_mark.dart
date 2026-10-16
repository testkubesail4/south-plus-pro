import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The S+ app mark: a brand-filled rounded square, [size] wide, its
/// letters in the theme's on-brand colour.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Text(
          'S+',
          // A fixed-size mark: its letters must not outgrow the tile.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
