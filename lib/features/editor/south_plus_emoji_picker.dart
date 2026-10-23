import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/forum_emojis.dart';
import '../../services/image_loading_settings.dart';
import '../../theme/app_theme.dart';
import '../common/cached_forum_image.dart';
import '../common/forum_emoji_assets.dart';

export '../../models/forum_emojis.dart' show SouthPlusEmoji;

/// The site editor's full face set, one tab per server category.
class SouthPlusEmojiPicker extends StatelessWidget {
  const SouthPlusEmojiPicker({
    super.key,
    required this.onSelected,
    this.baseUri,
  });

  final ValueChanged<SouthPlusEmoji> onSelected;
  final Uri? baseUri;

  String get _emojiBaseUrl =>
      (baseUri ?? Uri.https('south-plus.net', '/')).toString();

  static const _gap = 8.0;

  /// As many columns as fit tiles of at least a 48 px target, wider at
  /// large text so a scaled code label stays on one line.
  static int _columns(BuildContext context, double width) {
    final minTile = math.max(48.0, MediaQuery.textScalerOf(context).scale(40));
    return math.max(1, ((width + _gap) / (minTile + _gap)).floor());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: southPlusEmojiCategories.length,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '表情',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final category in southPlusEmojiCategories)
                    Tab(text: category.name),
                ],
              ),
              Expanded(
                child: ValueListenableBuilder<ImageLoadMode?>(
                  valueListenable: ImageLoadingSettings.notifier,
                  builder: (context, mode, _) => TabBarView(
                    children: [
                      for (final category in southPlusEmojiCategories)
                        LayoutBuilder(
                          builder: (context, constraints) => GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: _columns(
                                context,
                                constraints.maxWidth - 24,
                              ),
                              mainAxisSpacing: _gap,
                              crossAxisSpacing: _gap,
                            ),
                            itemCount: category.items.length,
                            itemBuilder: (context, index) => _EmojiTile(
                              emoji: category.items[index],
                              baseUrl: _emojiBaseUrl,
                              showImage: mode != null &&
                                  mode != ImageLoadMode.noImages,
                              onSelected: onSelected,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({
    required this.emoji,
    required this.baseUrl,
    required this.showImage,
    required this.onSelected,
  });

  final SouthPlusEmoji emoji;
  final String baseUrl;
  final bool showImage;
  final ValueChanged<SouthPlusEmoji> onSelected;

  @override
  Widget build(BuildContext context) {
    // Without images the code itself is the label, so every face stays usable.
    final codeLabel = Center(
      child: Text(
        emoji.id,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: AppColors.textMuted),
      ),
    );
    return Tooltip(
      message: '[s:${emoji.id}]',
      child: Semantics(
        button: true,
        label: '表情 ${emoji.id}',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => onSelected(emoji),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: showImage
                  ? CachedForumImage(
                      url: emoji.urlFromBase(baseUrl),
                      assetName: forumEmojiAssetNameFromPath(emoji.path),
                      fit: BoxFit.contain,
                      bypassLoadPolicy: true,
                      errorWidget: (context) => codeLabel,
                    )
                  : codeLabel,
            ),
          ),
        ),
      ),
    );
  }
}
