import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/perf_trace.dart';
import '../../theme/app_theme.dart';
import 'thread_rich_content.dart';
import 'thread_render_models.dart';
import 'thread_sale_box_view.dart';

class ThreadPostBody extends StatelessWidget {
  ThreadPostBody({
    super.key,
    required this.content,
    required this.quote,
    required this.images,
    required this.links,
    required this.saleBoxes,
    required this.saleBoxesFirst,
    required this.buyingSaleBoxes,
    required this.onBuySaleBox,
    List<ThreadContentSegment> segments = const [],
    ThreadPostRenderModel? renderModel,
  })  : segments = segments,
        renderModel =
            renderModel ?? ThreadPostRenderModel.fromSegments(segments);

  final String content;
  final List<ThreadContentSegment> segments;
  final ThreadPostRenderModel renderModel;
  final String? quote;
  final List<ThreadImage> images;
  final List<ThreadLink> links;
  final List<ThreadSaleBox> saleBoxes;
  final bool saleBoxesFirst;
  final Set<String> buyingSaleBoxes;
  final ValueChanged<ThreadSaleBox> onBuySaleBox;

  @override
  Widget build(BuildContext context) {
    return PerfTrace.span(
      'ThreadPostBody.build',
      () {
        final renderModelHasSaleBoxes = renderModel.hasSaleBoxes;
        final saleBoxWidgets = saleBoxes
            .map(
              (saleBox) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ThreadSaleBoxView(
                  saleBox: saleBox,
                  isBuying: buyingSaleBoxes.contains(saleBox.buyPath),
                  onBuy: () => onBuySaleBox(saleBox),
                ),
              ),
            )
            .toList();

        return SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (saleBoxesFirst && !renderModelHasSaleBoxes) ...saleBoxWidgets,
              if (quote != null && segments.isEmpty) ...[
                _QuoteView(text: quote!),
                if (content.isNotEmpty) const SizedBox(height: 12),
              ],
              if (!renderModel.isEmpty)
                ThreadRichContent.renderModel(
                  renderModel: renderModel,
                  buyingSaleBoxes: buyingSaleBoxes,
                  onBuySaleBox: onBuySaleBox,
                )
              else if (content.isNotEmpty)
                Text(content, style: Theme.of(context).textTheme.bodyMedium),
              if (images.isNotEmpty) ...[
                if (content.isNotEmpty || quote != null)
                  const SizedBox(height: 12),
                ...images.map(
                  (image) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ThreadInlineImage(image: image),
                  ),
                ),
              ],
              if (!saleBoxesFirst &&
                  saleBoxes.isNotEmpty &&
                  !renderModelHasSaleBoxes) ...[
                if (content.isNotEmpty || images.isNotEmpty)
                  const SizedBox(height: 12),
                ...saleBoxWidgets,
              ],
            ],
          ),
        );
      },
      arguments: {
        'segments': renderModel.blocks.length,
        'images': images.length,
        'saleBoxes': saleBoxes.length,
      },
    );
  }
}

class _QuoteView extends StatelessWidget {
  const _QuoteView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.brand, width: 4),
        ),
        color: AppColors.surfaceTint,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
