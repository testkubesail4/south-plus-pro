import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';
import 'thread_rich_content.dart';

class ThreadPostBody extends StatelessWidget {
  const ThreadPostBody({
    super.key,
    required this.content,
    required this.segments,
    required this.quote,
    required this.images,
    required this.links,
    required this.saleBoxes,
    required this.saleBoxesFirst,
    required this.buyingSaleBoxes,
    required this.onBuySaleBox,
  });

  final String content;
  final List<ThreadContentSegment> segments;
  final String? quote;
  final List<ThreadImage> images;
  final List<ThreadLink> links;
  final List<ThreadSaleBox> saleBoxes;
  final bool saleBoxesFirst;
  final Set<String> buyingSaleBoxes;
  final ValueChanged<ThreadSaleBox> onBuySaleBox;

  @override
  Widget build(BuildContext context) {
    final saleBoxWidgets = saleBoxes
        .map(
          (saleBox) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SaleBoxView(
              saleBox: saleBox,
              isBuying: buyingSaleBoxes.contains(saleBox.buyPath),
              onBuy: () => onBuySaleBox(saleBox),
            ),
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saleBoxesFirst) ...saleBoxWidgets,
        if (quote != null && segments.isEmpty) ...[
          _QuoteView(text: quote!),
          if (content.isNotEmpty) const SizedBox(height: 12),
        ],
        if (segments.isNotEmpty)
          ThreadRichContent(segments: segments)
        else if (content.isNotEmpty)
          Text(content, style: Theme.of(context).textTheme.bodyMedium),
        if (images.isNotEmpty) ...[
          if (content.isNotEmpty || quote != null) const SizedBox(height: 12),
          ...images.map(
            (image) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ThreadInlineImage(image: image),
            ),
          ),
        ],
        if (links.isNotEmpty) ...[
          if (content.isNotEmpty || quote != null || images.isNotEmpty)
            const SizedBox(height: 8),
          _ThreadLinkList(links: links),
        ],
        if (!saleBoxesFirst && saleBoxes.isNotEmpty) ...[
          if (content.isNotEmpty || images.isNotEmpty || links.isNotEmpty)
            const SizedBox(height: 12),
          ...saleBoxWidgets,
        ],
      ],
    );
  }
}

class _ThreadLinkList extends StatelessWidget {
  const _ThreadLinkList({required this.links});

  final List<ThreadLink> links;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth =
            constraints.maxWidth < 280 ? constraints.maxWidth : 280.0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: links
              .map(
                (link) => ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxChipWidth),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link.url));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('链接已复制')),
                      );
                    },
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(
                      link.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              )
              .toList(),
        );
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
      decoration: const BoxDecoration(
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

class _SaleBoxView extends StatelessWidget {
  const _SaleBoxView({
    required this.saleBox,
    required this.isBuying,
    required this.onBuy,
  });

  final ThreadSaleBox saleBox;
  final bool isBuying;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                saleBox.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.brandDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isBuying ? null : onBuy,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isBuying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('愿意购买,我买,我付钱'),
                ),
              ),
            ],
          ),
        ),
        if (saleBox.warning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.brand, width: 4),
              ),
              color: AppColors.surface,
            ),
            child: Text(
              saleBox.warning!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xff555555),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
