import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/tag_color_store.dart';
import '../../theme/app_theme.dart';

TextStyle? _tagStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .labelMedium
    ?.copyWith(color: AppColors.textMuted);

/// The account's tag colours (normalized label → colour id) for the
/// capsules below it; without one every capsule stays neutral.
class TagColorScope extends InheritedWidget {
  const TagColorScope({super.key, required this.colors, required super.child});

  final Map<String, String> colors;

  /// [tag]'s colour id under [context], if it has one.
  static String? idOf(BuildContext context, String tag) {
    final colors =
        context.dependOnInheritedWidgetOfExactType<TagColorScope>()?.colors;
    if (colors == null || colors.isEmpty) return null;
    try {
      return colors[TagColorStore.key(tag)];
    } on ArgumentError {
      return null;
    }
  }

  @override
  bool updateShouldNotify(TagColorScope oldWidget) =>
      !identical(colors, oldWidget.colors);
}

/// One local tag: neutral, or in the colour the reader gave its label. Brand
/// colour means "selected" in this app, so it is not in the palette.
class UserTagCapsule extends StatelessWidget {
  const UserTagCapsule({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context) {
    final colors = AppTagColors.of(TagColorScope.idOf(context, tag));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors?.$1 ?? AppColors.inkSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(tag,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _tagStyle(context)?.copyWith(color: colors?.$2)),
    );
  }
}

/// Picks the colour of [tag]'s label: a palette id, '' for none, or null
/// when dismissed.
Future<String?> showTagColorPicker(
  BuildContext context, {
  required String tag,
  required String? current,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: AppWidths.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      Widget swatch(String id, String name, Color? fill) {
        final selected = (current ?? '') == id;
        void pick() => Navigator.of(context).pop(id);
        // The label replaces the swatch's own node, so it carries the tap.
        return Semantics(
          button: true,
          selected: selected,
          label: '$name，标签颜色',
          onTap: pick,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('tag-color:${id.isEmpty ? 'none' : id}'),
            customBorder: const CircleBorder(),
            onTap: pick,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: fill ?? AppColors.inkSoft,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.text : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 18, color: AppColors.text)
                      : null,
                ),
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('「$tag」的颜色', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpace.xs),
              Text('仅本机保存；当前账号下所有带这个标签的用户一起变色',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  swatch('', '无颜色', null),
                  for (final id in TagColorStore.ids)
                    swatch(id, AppTagColors.names[id] ?? id,
                        AppTagColors.of(id)?.$1),
                ],
              ),
            ],
          ),
        ),
      );
    },
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
