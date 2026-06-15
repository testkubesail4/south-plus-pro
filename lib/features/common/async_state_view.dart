import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.padding = const EdgeInsets.all(24),
  });

  final String title;
  final String message;
  final FutureOr<void> Function() onRetry;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.padding = const EdgeInsets.all(28),
  });

  final String title;
  final String? message;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textFaint),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return const SkeletonCard(
          height: 86,
          lines: [0.92, 0.58, 0.36],
        );
      },
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

class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBlock(height: 58)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBlock(height: 58)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBlock(height: 58)),
            ],
          ),
          SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBlock(width: 120, height: 22),
          ),
          SizedBox(height: 12),
          SkeletonCard(height: 92, lines: [0.94, 0.62, 0.44]),
          SizedBox(height: 10),
          SkeletonCard(height: 92, lines: [0.88, 0.54, 0.38]),
          SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBlock(width: 100, height: 22),
          ),
          SizedBox(height: 12),
          SkeletonCard(height: 180, lines: [0.7, 0.78, 0.64, 0.72]),
        ],
      ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
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
