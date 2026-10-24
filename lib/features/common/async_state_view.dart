import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/forum_request_exception.dart';
import '../../theme/app_theme.dart';

/// Short user-facing text for a classified forum request failure.
String forumRequestErrorText(ForumRequestKind kind) => switch (kind) {
      ForumRequestKind.rateLimited => '请求过于频繁',
      ForumRequestKind.loginRequired => '登录失效',
      ForumRequestKind.forbidden => '没有权限',
      ForumRequestKind.invalidInput => '用户不存在，请检查实际登录名称',
      ForumRequestKind.network => '网络失败',
      ForumRequestKind.server => '服务器失败',
    };

/// Short text for any error shown to the user.
String forumErrorText(Object? error) => switch (error) {
      ForumRequestException(:final kind) => forumRequestErrorText(kind),
      _ => '$error',
    };

class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.title,
    this.message,
    required this.onRetry,
    this.padding = const EdgeInsets.all(24),
  });

  final String title;
  final String? message;
  final FutureOr<void> Function() onRetry;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.cloud_off_outlined,
      iconColor: AppColors.textMuted,
      title: title,
      message: message,
      padding: padding,
      action: FilledButton.tonalIcon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.iconColor,
    this.padding = const EdgeInsets.all(28),
    this.action,
  });

  final String? title;
  final String? message;
  final IconData icon;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Upper third: the eye lands there first, and it stays clear of the FAB.
    return Align(
      alignment: const Alignment(0, -1 / 3),
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.inkSoft,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Icon(icon,
                      size: 28, color: iconColor ?? AppColors.textFaint),
                ),
              ),
              if (title case final title?) ...[
                const SizedBox(height: AppSpace.lg),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ],
              if (message != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpace.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: SizedBox(width: width, height: height),
    );
  }
}

class ThreadListSkeleton extends StatelessWidget {
  const ThreadListSkeleton({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: [ThreadRowSkeleton(itemCount: itemCount)],
    );
  }
}

/// Thread rows still loading: title and meta bones in one surface, shaped
/// like [ForumThreadRow]s (DESIGN.md §10).
class ThreadRowSkeleton extends StatelessWidget {
  const ThreadRowSkeleton({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return DecoratedBox(
      decoration: appSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0) const Divider(indent: AppSpace.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: i.isEven ? 0.86 : 0.64,
                    child: SkeletonBlock(
                        height: scale.scale(15), borderRadius: 999),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  FractionallySizedBox(
                    widthFactor: 0.42,
                    child: SkeletonBlock(
                        height: scale.scale(11), borderRadius: 999),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ThreadDetailSkeleton extends StatelessWidget {
  const ThreadDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return SkeletonCard(
          height: index == 0 ? 132 : 112,
          lines: const [0.72, 1, 0.86, 0.42],
        );
      },
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    required this.height,
    this.lines = const [0.8, 0.56],
  });

  final double height;
  final List<double> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: appSurface(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (lines.isEmpty) return const SizedBox.shrink();

          final lineCount = lines.length;
          final maxHeight =
              constraints.maxHeight.isFinite ? constraints.maxHeight : height;
          final desiredGap = lineCount > 1 ? 8.0 : 0.0;
          final desiredLineHeight = 13.0;
          final desiredContentHeight =
              desiredLineHeight * lineCount + desiredGap * (lineCount - 1);
          final scale = desiredContentHeight > 0
              ? math.min(1.0, maxHeight / desiredContentHeight)
              : 1.0;
          final lineHeight = desiredLineHeight * scale;
          final gap = lineCount > 1 ? desiredGap * scale : 0.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < lines.length; index++) ...[
                FractionallySizedBox(
                  widthFactor: lines[index],
                  child: SkeletonBlock(
                    height: lineHeight,
                    borderRadius: 999,
                  ),
                ),
                if (index != lines.length - 1) SizedBox(height: gap),
              ],
            ],
          );
        },
      ),
    );
  }
}
