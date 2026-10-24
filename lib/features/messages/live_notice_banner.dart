import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/forum_live_sync.dart';
import '../../services/watch_notifications.dart';
import '../../theme/app_theme.dart';

/// A new short message or reply notice, dropped in from the top. It lives
/// in the root overlay, over whatever page is open, and passes every tap
/// outside the pill through. A tap opens its list; it leaves by itself, on
/// an upward swipe, or when a newer one replaces it. Nothing shows while
/// [suppressed] says that list is already on screen.
class LiveNoticeBanner extends StatefulWidget {
  const LiveNoticeBanner({
    super.key,
    required this.notices,
    required this.onOpen,
    required this.suppressed,
  });

  final ValueListenable<LiveNotice?> notices;
  final ValueChanged<NoticeNotificationKind> onOpen;
  final bool Function(NoticeNotificationKind kind) suppressed;

  static const shownFor = Duration(seconds: 4);

  @override
  State<LiveNoticeBanner> createState() => _LiveNoticeBannerState();
}

class _LiveNoticeBannerState extends State<LiveNoticeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  LiveNotice? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
      reverseDuration: AppMotion.short,
    );
    _slide = Tween(begin: const Offset(0, -1.2), end: Offset.zero).animate(
        CurvedAnimation(
            parent: _controller,
            curve: AppMotion.enter,
            reverseCurve: AppMotion.exit));
    widget.notices.addListener(_onNotice);
  }

  @override
  void didUpdateWidget(covariant LiveNoticeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notices != widget.notices) {
      oldWidget.notices.removeListener(_onNotice);
      widget.notices.addListener(_onNotice);
    }
  }

  @override
  void dispose() {
    widget.notices.removeListener(_onNotice);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onNotice() {
    final notice = widget.notices.value;
    // A cleared notice (a session change) takes the banner with it.
    if (notice == null) return _hide(at: _shown?.serial);
    if (widget.suppressed(notice.kind)) return;
    setState(() => _shown = notice);
    _controller.duration = AppMotion.of(context, AppMotion.medium);
    _controller.reverseDuration = AppMotion.of(context, AppMotion.short);
    _controller.forward();
    _timer?.cancel();
    _timer = Timer(LiveNoticeBanner.shownFor, () => _hide(at: notice.serial));
  }

  // Hides the banner while it still shows [at], so a stale timer never
  // takes down a newer notice.
  void _hide({int? at}) {
    if (!mounted || _shown == null || _shown!.serial != at) return;
    _timer?.cancel();
    _controller.reverse().whenComplete(() {
      if (mounted && _shown?.serial == at && _controller.isDismissed) {
        setState(() => _shown = null);
      }
    });
  }

  void _open() {
    final notice = _shown;
    if (notice == null) return;
    _hide(at: notice.serial);
    widget.onOpen(notice.kind);
  }

  @override
  Widget build(BuildContext context) {
    final notice = _shown;
    if (notice == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SlideTransition(
              position: _slide,
              child: _Pill(
                key: ValueKey(notice.serial),
                notice: notice,
                onTap: _open,
                onDismiss: () => _hide(at: notice.serial),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.notice,
    required this.onTap,
    required this.onDismiss,
  });

  final LiveNotice notice;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pm = notice.kind == NoticeNotificationKind.pm;
    final title = switch (notice.title?.trim()) {
      final title? when title.isNotEmpty => title,
      _ => pm ? '新短消息' : '新回复提醒',
    };
    final count = notice.count > 1 ? notice.count : null;
    return Semantics(
      liveRegion: true,
      button: true,
      label:
          [pm ? '短消息' : '回复提醒', title, if (count != null) '$count 条'].join('，'),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        // An upward swipe puts it away.
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < 0) onDismiss();
        },
        child: Material(
          color: AppColors.surface,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.sm, AppSpace.sm, AppSpace.lg, AppSpace.sm),
                child: Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.sm),
                        child: Icon(
                          pm ? Icons.mail_outline : Icons.mode_comment_outlined,
                          size: 18,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: AppSpace.sm),
                      Badge(
                        label: Text('$count'),
                        backgroundColor: AppColors.noticeDot,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
