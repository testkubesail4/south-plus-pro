import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../theme/app_theme.dart';

/// What a purchase left inside a sale box. [canRetry] is false once the
/// purchase went through but the page could not be refreshed: buying again
/// would charge twice.
class ThreadSaleBoxNotice {
  const ThreadSaleBoxNotice(
    this.message, {
    required this.canRetry,
    this.unconfirmed = false,
  });

  final String message;
  final bool canRetry;

  /// The request failed with no answer, so the purchase may have gone through.
  /// The box never offers another purchase; leaving the page resets it.
  final bool unconfirmed;

  @override
  bool operator ==(Object other) =>
      other is ThreadSaleBoxNotice &&
      other.message == message &&
      other.canRetry == canRetry &&
      other.unconfirmed == unconfirmed;

  @override
  int get hashCode => Object.hash(message, canRetry, unconfirmed);
}

/// The purchase state of one post, for the sale boxes and revealed blocks
/// anywhere below it.
class ThreadPurchaseScope extends InheritedWidget {
  const ThreadPurchaseScope({
    super.key,
    required this.postKey,
    required this.revealPaths,
    required this.played,
    required this.notices,
    this.onRefreshBox,
    required super.child,
  });

  /// Names the post across refreshes, e.g. its stable floor id.
  final String postKey;

  /// Block index paths that replaced a sale box (purchaseRevealPaths).
  final Set<String> revealPaths;

  /// Reveals that already ran, shared by the screen: a block that scrolled
  /// away and back, or a refreshed page, never plays again.
  final Set<String> played;

  /// Sale box buy path to its notice.
  final Map<String, ThreadSaleBoxNotice> notices;

  /// Reads the page holding that box again: the one action left on a box
  /// that was paid for. Never buys.
  final Future<void> Function(String buyPath)? onRefreshBox;

  static ThreadPurchaseScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThreadPurchaseScope>();

  @override
  bool updateShouldNotify(ThreadPurchaseScope old) =>
      postKey != old.postKey ||
      !setEquals(revealPaths, old.revealPaths) ||
      !mapEquals(notices, old.notices);
}

/// Fades in content that a purchase unlocked. The block is laid out at its
/// final size from the first frame, so nothing around it moves; only its own
/// opacity changes. Plays once per [id]: not when animations are disabled,
/// nor when [played] already has it (a refresh, or scrolling away and back).
class ThreadPurchaseReveal extends StatefulWidget {
  const ThreadPurchaseReveal({
    super.key,
    required this.id,
    required this.played,
    required this.child,
  });

  final String id;
  final Set<String> played;
  final Widget child;

  @override
  State<ThreadPurchaseReveal> createState() => _ThreadPurchaseRevealState();
}

class _ThreadPurchaseRevealState extends State<ThreadPurchaseReveal>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: AppMotion.medium);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final instant = widget.played.contains(widget.id) ||
        MediaQuery.disableAnimationsOf(context);
    widget.played.add(widget.id);
    if (instant) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: AppMotion.enter)),
      child: widget.child,
    );
  }
}

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
    final purchase = ThreadPurchaseScope.maybeOf(context);
    final notice = purchase?.notices[saleBox.buyPath];
    final bought = notice != null && !notice.canRetry;
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
                    // The theme pads only sideways; a label at a large text
                    // scale needs its own room. 40 stays the minimum.
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(
                        horizontal: AppSpace.lg,
                        vertical: AppSpace.sm,
                      )),
                    ),
                    onPressed: isBuying
                        ? null
                        : bought
                            ? (purchase?.onRefreshBox == null
                                ? null
                                : () =>
                                    purchase!.onRefreshBox!(saleBox.buyPath))
                            : onBuy,
                    // The label keeps its room while busy, so the button does
                    // not change height when the spinner takes its place.
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Visibility(
                          visible: !isBuying,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(
                            bought ? '刷新页面' : (notice == null ? '购买查看' : '重试'),
                          ),
                        ),
                        if (isBuying)
                          SizedBox(
                            width: 18,
                            height: 18,
                            // The busy button has the disabled neutral fill.
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (notice != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    notice.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: bought ? AppColors.text : theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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
      // 32 is the least; the label's own height wins at a large text scale.
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
