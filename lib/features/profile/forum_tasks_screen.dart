import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/app_switcher.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';

class ForumTasksScreen extends StatefulWidget {
  const ForumTasksScreen({
    super.key,
    required this.repository,
    this.initialStatus = ForumTaskStatus.inProgress,
  });

  final ForumTaskStatus initialStatus;

  final ForumRepository repository;

  @override
  State<ForumTasksScreen> createState() => _ForumTasksScreenState();
}

class _ForumTasksScreenState extends State<ForumTasksScreen> {
  late ForumTaskStatus _status = widget.initialStatus;
  // Which way the last status change moved along the segments.
  int _slide = 0;
  late Future<List<ForumTask>> _future = _load();
  final Set<String> _runningIds = {};
  var _quickClaiming = false;
  Map<String, ForumTaskState> _states = const {};

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSessionChanged);
    if (widget.repository.isLoggedIn) _loadStates();
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// Another account or network: nothing remembered applies, ask again.
  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _states = const {};
      _runningIds.clear();
      _future = _load();
    });
    if (widget.repository.isLoggedIn) _loadStates();
  }

  /// The remembered snapshot shows at once as a placeholder; the forum's own
  /// answer replaces it on every entry.
  Future<void> _loadStates() async {
    final repository = widget.repository;
    try {
      final cached = await repository.loadCachedForumTaskSnapshot();
      if (mounted && cached != null) {
        setState(() => _states = {for (final s in cached.tasks) s.name: s});
      }
      final fresh = await repository.refreshForumTaskSnapshot();
      if (mounted) {
        setState(() => _states = {for (final s in fresh.tasks) s.name: s});
      }
    } catch (_) {
      // Without a state a card says so instead of guessing.
    }
  }

  /// Claimed: the forum shows the cooldown, or it offers no action on a new
  /// task and the remembered state says the reward was taken. A task the
  /// forum offers now is never overridden by the memory.
  ForumTaskState? _claimedState(ForumTask task) {
    final state = _states[task.name];
    if (task.isCoolingDown) return state;
    return _status == ForumTaskStatus.available &&
            !task.canRun &&
            state != null &&
            state.isDoneToday
        ? state
        : null;
  }

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
      _slide = (status.index - _status.index).sign;
      _status = status;
      _future = _load();
    });
  }

  Future<void> _runTask(ForumTask task) async {
    final id = task.id;
    if (id == null) return;
    setState(() => _runningIds.add(id));
    final result = await widget.repository.runForumTask(
      task,
      claimReward: task.status == ForumTaskStatus.inProgress,
    );
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
        body: LoginPrompt(
          icon: Icons.fact_check_outlined,
          title: '论坛任务',
          onLogin: () async {
            if (!await openLogin(context, widget.repository)) return;
            if (!mounted) return;
            setState(() {
              _future = _load();
            });
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('论坛任务')),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, constraints) {
          final gutter = appGutter(constraints.maxWidth, AppWidths.form);
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 12),
                child: _TaskHeader(
                  status: _status,
                  onStatusChanged: _setStatus,
                  quickClaiming: _quickClaiming,
                  onQuickClaim: _quickClaimRewards,
                ),
              ),
              Expanded(
                  child: AppSwitcher(
                direction: _slide,
                // Another account's tasks never fade out under this one.
                scope: widget.repository.sessionEpoch.value,
                child: FutureBuilder<List<ForumTask>>(
                  key: ValueKey(_status),
                  future: _future,
                  builder: (context, snapshot) => AppSwitcher(
                      id: snapshot.hasError
                          ? 'error'
                          : snapshot.hasData
                              ? 'list'
                              : 'loading',
                      child: Builder(builder: (context) {
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
                                  padding: EdgeInsets.fromLTRB(
                                      gutter, 24, gutter, 28),
                                  children: [
                                    EmptyStateView(
                                      title: _emptyTitle(_status),
                                      message: _emptyMessage(_status),
                                      icon: Icons.task_alt_outlined,
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: EdgeInsets.fromLTRB(
                                      gutter, 0, gutter, 28),
                                  itemCount: tasks.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final task = tasks[index];
                                    final state = _claimedState(task);
                                    final claimed =
                                        task.isCoolingDown || state != null;
                                    final hours = (task.cooldownThreshold ??
                                            state?.cooldownThreshold)
                                        ?.inHours;
                                    return _TaskCard(
                                      task: task,
                                      running: task.id != null &&
                                          _runningIds.contains(task.id),
                                      onRun: task.canRun && !claimed
                                          ? () => _runTask(task)
                                          : null,
                                      claimed: claimed,
                                      thresholdHours: hours,
                                      stateUnknown: _status ==
                                              ForumTaskStatus.available &&
                                          !claimed &&
                                          !task.canRun,
                                      onRefreshState: _refresh,
                                    );
                                  },
                                ),
                        );
                      })),
                ),
              )),
            ],
          );
        }),
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
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: appSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.inkSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.fact_check_outlined,
                  size: 20,
                  color: AppColors.textMuted,
                ),
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
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ForumTaskStatus.available,
                label: Text('新任务'),
              ),
              ButtonSegment(
                value: ForumTaskStatus.inProgress,
                label: Text('进行中'),
              ),
              ButtonSegment(
                value: ForumTaskStatus.completed,
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
    this.claimed = false,
    this.thresholdHours,
    this.stateUnknown = false,
    this.onRefreshState,
  });

  final ForumTask task;
  final bool running;
  final VoidCallback? onRun;

  /// The reward was taken this cycle; the forum only states the cooldown
  /// threshold, so no countdown is shown.
  final bool claimed;
  final int? thresholdHours;
  final bool stateUnknown;
  final VoidCallback? onRefreshState;

  @override
  Widget build(BuildContext context) {
    final progress = task.progressPercent;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: appSurface(context),
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
                  color: AppColors.inkSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  claimed ? Icons.verified_outlined : _statusIcon(task.status),
                  color:
                      claimed ? AppColors.success : _statusColor(task.status),
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
              if (claimed)
                const _TaskPill(
                    icon: Icons.check_circle_outline,
                    label: '已领取',
                    success: true),
              if (stateUnknown)
                const _TaskPill(icon: Icons.help_outline, label: '状态未知'),
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
          if (claimed && thresholdHours != null) ...[
            const SizedBox(height: 10),
            Text(
              '上次领取未超过 $thresholdHours 小时',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (stateUnknown)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRefreshState,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新状态'),
              ),
            ),
          if (task.completedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '完成时间 ${task.completedAt}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (claimed && task.canRun) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check),
                label: const Text('已领取'),
              ),
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
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({
    required this.icon,
    required this.label,
    this.success = false,
  });

  final IconData icon;
  final String label;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: success ? AppColors.successSoft : AppColors.inkSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: success ? AppColors.success : AppColors.textMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              // The icon carries the colour; the text keeps AA contrast.
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: success ? AppColors.text : AppColors.textMuted),
            ),
          ),
        ],
      ),
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
        title: title,
        lines: lines,
      ),
    );
}

void showForumTaskAutoClaimSnackBar(
  BuildContext context,
  ForumTaskQuickClaimResult result,
) {
  final lines = <String>[
    for (final reward in result.claimedRewards) reward.completionMessage,
  ];
  if (lines.isEmpty) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      forumTaskSnackBar(
        title: '自动签到完成',
        lines: lines,
      ),
    );
}

void showForumTaskClaimErrorSnackBar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      forumTaskSnackBar(
        title: '任务奖励领取失败',
        lines: ['请稍后重试：$error'],
      ),
    );
}

/// A task result in the standard snackbar (DESIGN.md §9): the title in bold,
/// then one line per claimed reward or problem.
SnackBar forumTaskSnackBar({
  required String title,
  required List<String> lines,
}) {
  return SnackBar(
    duration: const Duration(seconds: 4),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final line in lines) Text(line),
      ],
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
