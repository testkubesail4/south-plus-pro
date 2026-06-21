import 'package:flutter/material.dart';

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

    return SelectionArea(
      child: Column(
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
          if (!saleBoxesFirst && saleBoxes.isNotEmpty) ...[
            if (content.isNotEmpty || images.isNotEmpty)
              const SizedBox(height: 12),
            ...saleBoxWidgets,
          ],
        ],
      ),
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
    final hasMeta = saleBox.price != null || saleBox.buyers != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: AppColors.brandDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '付费内容',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppColors.brandDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          saleBox.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasMeta) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (saleBox.price != null)
                      _SaleMetaPill(
                        icon: Icons.paid_outlined,
                        label: '${saleBox.price} SP币',
                      ),
                    if (saleBox.buyers != null)
                      _SaleMetaPill(
                        icon: Icons.group_outlined,
                        label: '${saleBox.buyers} 人购买',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SelectionContainer.disabled(
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
                        : const Text('购买查看'),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (saleBox.warning != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
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

class _SaleMetaPill extends StatelessWidget {
  const _SaleMetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.link),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
