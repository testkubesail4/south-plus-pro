import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';

class ThreadSaleBoxView extends StatelessWidget {
  const ThreadSaleBoxView({
    super.key,
    required this.saleBox,
    required this.isBuying,
    required this.onBuy,
  });

  final ThreadSaleBox saleBox;
  final bool isBuying;
  final VoidCallback? onBuy;

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
            color: AppColors.inkSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
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
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: AppColors.textMuted,
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
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          saleBox.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.text,
                            // textMuted on inkSoft is 4.47:1, under AA.
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
                    child: isBuying
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            // The busy button has the disabled neutral fill.
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textMuted,
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
                color: AppColors.textMuted,
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppColors.text),
          ),
        ],
      ),
    );
  }
}
