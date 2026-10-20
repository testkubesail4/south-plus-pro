import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Swaps [child] for the next one of a different key with a cross-fade.
/// A [direction] of 1 or -1 also slides them along the row, as when moving
/// to the next or previous of sibling views (信箱, filters, pages); 0 only
/// fades, as between loading, content and error.
///
/// The fade is linear so the two together never thin out below the fainter
/// one. The leaving child cannot be tapped or read out.
class AppSwitcher extends StatelessWidget {
  const AppSwitcher({
    super.key,
    required this.child,
    this.id,
    this.direction = 0,
  });

  /// A new [id] (or, without one, a new key on [child]) starts a transition.
  final Widget child;
  final Object? id;
  final int direction;

  static const double _shift = 24;

  @override
  Widget build(BuildContext context) {
    final current =
        id == null ? child : KeyedSubtree(key: ValueKey(id), child: child);
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.medium),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [
          for (final old in previous)
            IgnorePointer(child: ExcludeSemantics(child: old)),
          if (current != null) current,
        ],
      ),
      transitionBuilder: (child, animation) {
        // The entering child comes from the side it lies on; the leaving
        // one goes the other way. Runs again for the leaving child on every
        // swap, so its key tells which it is now.
        final sign = child.key == current.key ? direction : -direction;
        return FadeTransition(
          opacity: animation,
          child: sign == 0
              ? child
              : AnimatedBuilder(
                  animation: animation,
                  child: child,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      sign *
                          _shift *
                          (1 - AppMotion.enter.transform(animation.value)),
                      0,
                    ),
                    child: child,
                  ),
                ),
        );
      },
      child: current,
    );
  }
}

/// [AppSwitcher] for a sliver in a scroll view, where the old and new
/// content cannot overlap: when [id] changes the new content fades up from
/// 40%, never through blank.
class AppSliverReveal extends StatefulWidget {
  const AppSliverReveal({super.key, required this.id, required this.sliver});

  final Object? id;
  final Widget sliver;

  @override
  State<AppSliverReveal> createState() => _AppSliverRevealState();
}

class _AppSliverRevealState extends State<AppSliverReveal>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
    value: 1,
  );
  late final _curve =
      CurvedAnimation(parent: _controller, curve: AppMotion.enter);
  late final _opacity = Tween<double>(begin: 0.4, end: 1).animate(_curve);

  @override
  void didUpdateWidget(covariant AppSliverReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
}
