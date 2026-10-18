import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

TextStyle? _tagStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelMedium
    ?.copyWith(color: AppColors.textMuted);

/// One local tag: a quiet neutral capsule. Brand colour means "selected" in
/// this app, so assigned tags never use it.
class UserTagCapsule extends StatelessWidget {
  const UserTagCapsule({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(tag,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _tagStyle(context)),
      );
}

/// At most two tags that fit the width, then +N. Tapping opens [onShowAll],
/// which shows every tag; screen readers hear every tag here.
class UserTagsInline extends StatelessWidget {
  const UserTagsInline({super.key, required this.tags, required this.onShowAll});
  final List<String> tags;
  final VoidCallback onShowAll;

  static const _gap = 6.0;
  // Capsule horizontal padding.
  static const _pad = 16.0;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final style = _tagStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text) {
      final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler)
        ..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(builder: (context, box) {
      final available = box.maxWidth.isFinite ? box.maxWidth : 320.0;
      var shown = math.min(2, tags.length);
      while (shown > 0) {
        final rest = tags.length - shown;
        final width = tags
                .take(shown)
                .fold<double>(0, (sum, tag) => sum + measure(tag) + _pad) +
            (shown - 1) * _gap +
            (rest > 0 ? _gap + measure('+$rest') + 8 : 0);
        if (width <= available) break;
        shown--;
      }
      final rest = tags.length - shown;
      return Semantics(
        button: true,
        label: '标签 ${tags.join('、')}',
        hint: '查看全部标签',
        onTap: onShowAll,
        excludeSemantics: true,
        child: InkWell(
          onTap: onShowAll,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < shown; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Flexible(child: UserTagCapsule(tag: tags[i])),
            ],
            if (rest > 0) ...[
              if (shown > 0) const SizedBox(width: _gap),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Text('+$rest', style: style, maxLines: 1),
              ),
            ],
          ]),
        ),
      );
    });
  }
}
