import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/async_state_view.dart';

class ForumTasksScreen extends StatefulWidget {
  const ForumTasksScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<ForumTasksScreen> createState() => _ForumTasksScreenState();
}

class _ForumTasksScreenState extends State<ForumTasksScreen> {
  ForumTaskStatus _status = ForumTaskStatus.inProgress;
  late Future<List<ForumTask>> _future = _load();
  final Set<String> _runningIds = {};
  var _quickClaiming = false;

  Future<List<ForumTask>> _load() {
    return widget.repository.fetchForumTasks(_status);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _setStatus(ForumTaskStatus status) async {
    if (status == _status) return;
    setState(() {
      _status = status;
      _future = _load();
    });
  }

  Future<void> _runTask(ForumTask task) async {
    final id = task.id;
    if (id == null) return;
    setState(() => _runningIds.add(id));
    final result = await widget.repository.runForumTask(task);
    if (!mounted) return;
    setState(() => _runningIds.remove(id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    if (!result.success) return;
    setState(() {
      _status = task.status == ForumTaskStatus.inProgress
          ? ForumTaskStatus.completed
          : ForumTaskStatus.inProgress;
      _future = _load();
    });
  }

  Future<void> _quickClaimRewards() async {
    setState(() => _quickClaiming = true);
    try {
      final result = await widget.repository.claimForumTaskRewards();
      if (!mounted) return;
      showForumTaskClaimSnackBar(context, result);
      setState(() {
        _status = result.hasClaims ? ForumTaskStatus.completed : _status;
        _future = _load();
      });
    } catch (error) {
      if (!mounted) return;
      showForumTaskClaimErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _quickClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('论坛任务')),
        body: _TasksLoginPrompt(repository: widget.repository),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('论坛任务')),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _TaskHeader(
                status: _status,
                onStatusChanged: _setStatus,
                quickClaiming: _quickClaiming,
                onQuickClaim: _quickClaimRewards,
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ForumTask>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return AsyncErrorView(
                      title: '任务加载失败',
                      message: '${snapshot.error}',
                      onRetry: _refresh,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const ThreadListSkeleton(itemCount: 4);
                  }

                  final tasks = snapshot.data!;
                  return RefreshIndicator(
                    color: AppColors.brand,
                    onRefresh: _refresh,
                    child: tasks.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
                            children: [
                              EmptyStateView(
                                title: _emptyTitle(_status),
                                message: _emptyMessage(_status),
                                icon: Icons.task_alt_outlined,
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            itemCount: tasks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              return _TaskCard(
                                task: task,
                                running: task.id != null &&
                                    _runningIds.contains(task.id),
                                onRun:
                                    task.canRun ? () => _runTask(task) : null,
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskHeader extends StatelessWidget {
  const _TaskHeader({
    required this.status,
    required this.onStatusChanged,
    required this.quickClaiming,
    required this.onQuickClaim,
  });

  final ForumTaskStatus status;
  final ValueChanged<ForumTaskStatus> onStatusChanged;
  final bool quickClaiming;
  final VoidCallback onQuickClaim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brandSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.fact_check_outlined, color: AppColors.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('社区论坛任务',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      '申请任务后在进行中领取奖励，完成记录会回到已完成任务。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: quickClaiming ? null : onQuickClaim,
              icon: quickClaiming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.redeem_outlined),
              label: Text(quickClaiming ? '领取中...' : '一键领取任务奖励'),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<ForumTaskStatus>(
            segments: const [
              ButtonSegment(
                value: ForumTaskStatus.available,
                icon: Icon(Icons.add_task_outlined),
                label: Text('新任务'),
              ),
              ButtonSegment(
                value: ForumTaskStatus.inProgress,
                icon: Icon(Icons.pending_actions_outlined),
                label: Text('进行中'),
              ),
              ButtonSegment(
                value: ForumTaskStatus.completed,
                icon: Icon(Icons.verified_outlined),
                label: Text('已完成'),
              ),
            ],
            selected: {status},
            onSelectionChanged: (values) => onStatusChanged(values.single),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.running,
    required this.onRun,
  });

  final ForumTask task;
  final bool running;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final progress = task.progressPercent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _statusSoftColor(task.status),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _statusIcon(task.status),
                  color: _statusColor(task.status),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      task.description ?? _statusLabel(task.status),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (task.reward != null)
                _TaskPill(icon: Icons.toll_outlined, label: task.reward!),
              if (task.endsAt != null)
                _TaskPill(
                    icon: Icons.event_outlined, label: '至 ${task.endsAt}'),
              if (progress != null)
                _TaskPill(
                  icon: Icons.percent_outlined,
                  label: '已完成 $progress%',
                ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: (progress.clamp(0, 100)) / 100,
                backgroundColor: AppColors.inkSoft,
                color: AppColors.success,
              ),
            ),
          ],
          if (task.completedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '完成时间 ${task.completedAt}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (onRun != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: running ? null : onRun,
                icon: running
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_actionIcon(task.status)),
                label: Text(running ? '处理中...' : _actionLabel(task)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(ForumTaskStatus status) {
    return switch (status) {
      ForumTaskStatus.available => AppColors.link,
      ForumTaskStatus.inProgress => AppColors.brand,
      ForumTaskStatus.completed => AppColors.success,
      ForumTaskStatus.failed => ThemeData().colorScheme.error,
    };
  }

  Color _statusSoftColor(ForumTaskStatus status) {
    return switch (status) {
      ForumTaskStatus.available => AppColors.inkSoft,
      ForumTaskStatus.inProgress => AppColors.brandSoft,
      ForumTaskStatus.completed => AppColors.successSoft,
      ForumTaskStatus.failed => AppColors.brandSoft,
    };
  }
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TasksLoginPrompt extends StatelessWidget {
  const _TasksLoginPrompt({required this.repository});

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.fact_check_outlined, color: AppColors.brand, size: 34),
              const SizedBox(height: 14),
              Text('论坛任务', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '登录后可以申请日常、周常任务，并领取 SP 币奖励。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LoginScreen(repository: repository),
                  ),
                ),
                icon: Icon(Icons.login),
                label: const Text('去登录'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void showForumTaskClaimSnackBar(
  BuildContext context,
  ForumTaskQuickClaimResult result,
) {
  final lines = <String>[
    for (final reward in result.claimedRewards) reward.completionMessage,
    if (!result.hasClaims && result.appliedCount > 0)
      '已申请 ${result.appliedCount} 个任务，完成后可领取奖励',
    if (result.alreadyHandled) '本周期任务奖励已领取',
    if (!result.hasClaims && result.inProgress.isNotEmpty)
      '${result.inProgress.join('、')}任务进行中，完成后可领取奖励',
    if (!result.hasClaims &&
        result.appliedCount == 0 &&
        !result.hasFailures &&
        result.skipped.isEmpty &&
        result.inProgress.isEmpty &&
        !result.alreadyHandled)
      '暂无可领取任务奖励',
    if (result.skipped.isNotEmpty) result.skipped.first,
    if (result.hasFailures) '部分任务失败：${result.failures.first}',
  ];

  final title = result.hasClaims
      ? '任务奖励领取完成'
      : result.hasFailures
          ? '任务奖励领取异常'
          : result.alreadyHandled
              ? '任务奖励已领取'
              : '任务奖励暂无更新';

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      forumTaskSnackBar(
        context: context,
        title: title,
        lines: lines,
        success: result.hasClaims && !result.hasFailures,
      ),
    );
}

void showForumTaskClaimErrorSnackBar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      forumTaskSnackBar(
        context: context,
        title: '任务奖励领取失败',
        lines: ['请稍后重试：$error'],
        success: false,
      ),
    );
}

SnackBar forumTaskSnackBar({
  required BuildContext context,
  required String title,
  required List<String> lines,
  required bool success,
}) {
  final color = success ? AppColors.success : AppColors.brand;
  final softColor = success ? AppColors.successSoft : AppColors.brandSoft;
  final borderColor = success ? AppColors.successBorder : AppColors.brandSoft;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 4),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
    padding: EdgeInsets.zero,
    elevation: 8,
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: borderColor),
    ),
    content: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              success ? Icons.check_circle_outline : Icons.info_outline_rounded,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            height: 1.35,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _actionLabel(ForumTask task) {
  if (task.status == ForumTaskStatus.inProgress) return '领取奖励';
  if (task.status == ForumTaskStatus.available) return '申请任务';
  return task.actionLabel ?? '处理任务';
}

String _statusLabel(ForumTaskStatus status) {
  return switch (status) {
    ForumTaskStatus.available => '可申请任务',
    ForumTaskStatus.inProgress => '任务已完成时可以领取奖励',
    ForumTaskStatus.completed => '奖励已经领取完成',
    ForumTaskStatus.failed => '任务已失败',
  };
}

IconData _statusIcon(ForumTaskStatus status) {
  return switch (status) {
    ForumTaskStatus.available => Icons.add_task_outlined,
    ForumTaskStatus.inProgress => Icons.pending_actions_outlined,
    ForumTaskStatus.completed => Icons.verified_outlined,
    ForumTaskStatus.failed => Icons.error_outline,
  };
}

IconData _actionIcon(ForumTaskStatus status) {
  return switch (status) {
    ForumTaskStatus.available => Icons.playlist_add_check_outlined,
    ForumTaskStatus.inProgress => Icons.redeem_outlined,
    ForumTaskStatus.completed => Icons.verified_outlined,
    ForumTaskStatus.failed => Icons.refresh_outlined,
  };
}

String _emptyTitle(ForumTaskStatus status) {
  return switch (status) {
    ForumTaskStatus.available => '没有可申请任务',
    ForumTaskStatus.inProgress => '没有进行中任务',
    ForumTaskStatus.completed => '还没有已完成任务',
    ForumTaskStatus.failed => '没有失败任务',
  };
}

String _emptyMessage(ForumTaskStatus status) {
  return switch (status) {
    ForumTaskStatus.available => '源站当前没有新的社区任务。',
    ForumTaskStatus.inProgress => '申请日常或周常后，会在这里领取奖励。',
    ForumTaskStatus.completed => '领取奖励后会显示完成时间。',
    ForumTaskStatus.failed => '未按期限完成的任务会显示在这里。',
  };
}
