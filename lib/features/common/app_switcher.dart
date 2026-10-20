import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Swaps [child] for the next one of a different key with a cross-fade.
/// A [direction] of 1 or -1 also slides them along the row, as when moving
/// to the next or previous of sibling views (信箱, filters, pages); 0 only
/// fades, as between loading, content and error.
///
/// The fade is linear so the two together never thin out below the fainter
/// one. The leaving child keeps its state but cannot be tapped, focused,
/// typed into or read out, and a new [scope]
/// (e.g. the session epoch) drops it in the same frame: another account's
/// content never fades out.
class AppSwitcher extends StatelessWidget {
  const AppSwitcher({
    super.key,
    required this.child,
    this.id,
    this.direction = 0,
    this.scope,
  });

  /// A new [id] (or, without one, a new key on [child]) starts a transition.
  final Widget child;
  final Object? id;
  final int direction;
  final Object? scope;

  static const double _shift = 24;

  // The same widgets around the child whether it stays or leaves, so leaving
  // keeps its state (scroll offset, field text) and only switches them on.
  static Widget _layer(Widget child, {required bool leaving}) => KeyedSubtree(
        key: child.key,
        child: IgnorePointer(
          ignoring: leaving,
          child: ExcludeSemantics(
            excluding: leaving,
            child: ExcludeFocus(excluding: leaving, child: child),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final current =
        id == null ? child : KeyedSubtree(key: ValueKey(id), child: child);
    // A new scope is a new switcher, holding nothing of the old one.
    return KeyedSubtree(
        key: ValueKey(scope),
        child: AnimatedSwitcher(
          duration: AppMotion.of(context, AppMotion.medium),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.topCenter,
            children: [
              for (final old in previous) _layer(old, leaving: true),
              if (current != null) _layer(current, leaving: false),
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
        ));
  }
}

/// [AppSwitcher] for a sliver in a scroll view, where the old and new
/// content cannot overlap: when [id] changes the new content fades up from
/// 65%, never through blank. With [enter] it also fades up when it first
/// appears, in place of a spinner or an empty state.
class AppSliverReveal extends StatefulWidget {
  const AppSliverReveal({
    super.key,
    required this.id,
    required this.sliver,
    this.enter = false,
  });

  final Object? id;
  final Widget sliver;
  final bool enter;

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
  late final _opacity = Tween<double>(begin: 0.65, end: 1).animate(_curve);

  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered || !widget.enter) return;
    _entered = true;
    if (!MediaQuery.disableAnimationsOf(context)) _controller.forward(from: 0);
  }

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
