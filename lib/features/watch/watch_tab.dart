import 'package:flutter/material.dart';

import '../../models/watch_models.dart';
import '../../services/forum_repository.dart';
import '../../services/watch_notifications.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/forum_link_opener.dart';
import '../common/grouped_list.dart';
import '../common/session_bound.dart';
import '../common/thread_row.dart';
import 'watch_rule_sheet.dart';

/// The 消息 › 关注 tab: what the local checks found (动态), and the rules
/// that look (规则).
class WatchTab extends StatefulWidget {
  const WatchTab({
    super.key,
    required this.repository,
    this.initialRules = false,
    this.opensNotifications = true,
  });

  final ForumRepository repository;

  /// Starts on 规则 instead of 动态.
  final bool initialRules;

  /// Opens the 动态 a tapped system notification asked for; only the
  /// 消息 tab's instance does.
  final bool opensNotifications;

  @override
  State<WatchTab> createState() => _WatchTabState();
}

/// 关注 on its own page, from a 管理 link.
class WatchScreen extends StatelessWidget {
  const WatchScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) => SessionBound(
        repository: repository,
        title: '关注',
        child: Scaffold(
          appBar: AppBar(title: const Text('关注')),
          body: WatchTab(
            repository: repository,
            initialRules: true,
            opensNotifications: false,
          ),
        ),
      );
}

class _WatchTabState extends State<WatchTab> {
  WatchService get _watch => widget.repository.watch;
  late var _showRules = widget.initialRules;
  // The account this list belongs to; a write after a switch is dropped.
  late final WatchSessionScope _scope;

  @override
  void initState() {
    super.initState();
    _scope = WatchSessionScope(widget.repository);
    _watch.addListener(_onWatch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onWatch());
  }

  @override
  void dispose() {
    _watch.removeListener(_onWatch);
    super.dispose();
  }

  // A tapped system notification lands here and opens its 动态.
  void _onWatch() {
    if (!mounted || !widget.opensNotifications || _watch.pendingOpen == null) {
      return;
    }
    final event = _watch.takePendingOpen();
    if (event != null) {
      setState(() => _showRules = false);
      _open(event);
    }
  }

  // Opening is not reading: the thread clears the 动态 once its post shows.
  void _open(WatchEvent event) =>
      openForumLink(context, widget.repository, event.url, label: event.title);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _watch,
      builder: (context, _) {
        final rules = _watch.rules;
        return ListView(
          padding: const EdgeInsets.only(top: AppSpace.md, bottom: 88),
          children: [
            AppContentWidth(
              maxWidth: AppWidths.list,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, label: Text('动态')),
                    ButtonSegment(
                      value: true,
                      label: Text(
                        '规则 ${_watch.activeCount}/${WatchService.maxActiveRules}',
                      ),
                    ),
                  ],
                  showSelectedIcon: false,
                  selected: {_showRules},
                  onSelectionChanged: (values) =>
                      setState(() => _showRules = values.single),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            AppContentWidth(
              maxWidth: AppWidths.list,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _showRules
                    ? _rules(context, rules)
                    : _events(context, rules),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _events(BuildContext context, List<WatchRule> rules) {
    final events = _watch.events;
    final labels = {for (final rule in rules) rule.id: rule.label};
    return [
      _StatusStrip(watch: _watch),
      const SizedBox(height: AppSpace.md),
      if (rules.isEmpty)
        const _NoRules()
      else if (events.isEmpty)
        const EmptyStateView(
          icon: Icons.notifications_none_outlined,
          title: '还没有新动态',
          message: '打开 App 或回到前台时补查；后台或关闭期间不保证即时通知',
        )
      else
        AppGroup(
          dividerIndent: AppSpace.lg,
          children: [
            for (final event in events)
              _EventRow(
                event: event,
                ruleLabel: labels[event.ruleId],
                onOpen: () => _open(event),
                onMarkRead: () => _markRead(event),
              ),
          ],
        ),
    ];
  }

  List<Widget> _rules(BuildContext context, List<WatchRule> rules) {
    final theme = Theme.of(context);
    return [
      if (rules.isEmpty)
        const _NoRules()
      else
        AppGroup(
          label: '已启用 ${_watch.activeCount}/${WatchService.maxActiveRules}',
          children: [
            for (final rule in rules)
              _RuleRow(
                rule: rule,
                summary: watchRuleSummary(
                  rule,
                  watchSelfUid(widget.repository),
                ),
                status: watchStatusText(_watch, rule),
                failed: !rule.paused &&
                    _watch.statuses[rule.id]?.phase == WatchPhase.unavailable,
                onEdit: () => showWatchSheet(
                  context,
                  repository: widget.repository,
                  target: WatchTarget(
                    scope: rule.scope,
                    subjectId: rule.subjectId,
                    label: rule.label,
                  ),
                  edit: rule,
                ),
                onOpen: () => _openTarget(rule),
                onPause: () => _setPaused(rule, !rule.paused),
                onDelete: () => _delete(rule),
              ),
          ],
        ),
      if (_watch.notificationPermission == WatchNotificationPermission.denied)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.sm,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '系统通知未开启 · 动态只在这里显示',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _watch.requestNotifications,
                child: const Text('开启'),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.lg,
          0,
        ),
        child: Text(
          '检查只在本机进行：打开 App 或回到前台时补查，使用期间约每 15 分钟一次，'
          '每 5 分钟最多 ${WatchService.maxSends} 次请求。'
          'App 在后台或被关闭时不检查，不保证即时通知。'
          '私密收藏、已删除的楼层和图片中的文字无法识别。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ),
    ];
  }

  // The watched thread, user or board itself, events or not.
  void _openTarget(WatchRule rule) {
    final id = rule.subjectId;
    final url = switch (rule.scope) {
      WatchScope.thread => 'read.php?tid-$id.html',
      WatchScope.user => widget.repository.userProfileUrl(id),
      WatchScope.board => 'thread.php?fid-$id.html',
    };
    if (url != null) {
      openForumLink(context, widget.repository, url, label: rule.label);
    }
  }

  Future<void> _markRead(WatchEvent event) async {
    if (!_scope.current) return;
    try {
      await _watch.markRead(event.id);
    } catch (_) {
      // A failure for an account no longer shown is not this reader's.
      if (!mounted || !_scope.current) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  Future<void> _setPaused(WatchRule rule, bool paused) async {
    if (!_scope.current) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _watch.setPaused(rule.id, paused);
    } on WatchLimitException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
    }
  }

  Future<void> _delete(WatchRule rule) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条关注？'),
        content: const Text('它找到的动态也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    // The dialog may outlive the account it was asked under.
    if (confirmed != true || !_scope.current) return;
    try {
      await _watch.removeRule(rule.id);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }
}

String _when(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// When the checks last ran and will run, with 立即检查.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.watch});

  final WatchService watch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final pending = watch.pendingUntil;
    final waiting = pending != null && pending.isAfter(now);
    final last = [
      for (final status in watch.statuses.values)
        if (status.checkedAt case final at?) at,
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    String clock(DateTime at) {
      final local = at.toLocal();
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }

    final text = watch.running
        ? (watch.progressTotal > 0
            ? '正在检查 ${watch.progressDone}/${watch.progressTotal}'
            : '正在检查')
        : waiting
            ? '已达请求上限，约 ${clock(pending)} 继续'
            : [
                last == null ? '尚未检查' : '${clock(last)} 已检查',
                if (watch.nextCheckAt case final next?) '下次约 ${clock(next)}',
              ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.sm, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(text, style: theme.textTheme.bodySmall),
                ),
              ),
              TextButton(
                onPressed: watch.running ||
                        waiting ||
                        watch.rules.every((rule) => rule.paused)
                    ? null
                    : () => watch.checkNow().catchError((_) {}),
                child: const Text('立即检查'),
              ),
            ],
          ),
          if (watch.running)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: LinearProgressIndicator(
                value: watch.progressTotal == 0
                    ? null
                    : (watch.progressDone / watch.progressTotal)
                        .clamp(0, 1)
                        .toDouble(),
                minHeight: 3,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoRules extends StatelessWidget {
  const _NoRules();

  @override
  Widget build(BuildContext context) => const EmptyStateView(
        icon: Icons.notifications_none_outlined,
        title: '还没有关注',
        message: '在帖子右上角 ⋮、楼层作者菜单、用户中心或版块里添加',
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.ruleLabel,
    required this.onOpen,
    required this.onMarkRead,
  });

  final WatchEvent event;
  final String? ruleLabel;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = switch (event.kind) {
      WatchContentKind.topics => '新主题',
      WatchContentKind.replies => '新回复',
      WatchContentKind.favorites => '新可见收藏',
    };
    final meta = Text(
      [
        kind,
        // When a check found it, not when it was posted or favorited.
        '${_when(event.detectedAt)} 发现',
        if (ruleLabel != null) ruleLabel!,
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );
    final uncertain = event.confidence != WatchConfidence.certain;
    return ForumThreadRow(
      title: event.title,
      emphasized: event.unread,
      metaLine: !uncertain
          ? meta
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                meta,
                const SizedBox(height: AppSpace.xs),
                _Confidence(event: event),
              ],
            ),
      trailing: event.unread
          ? Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Icon(
                Icons.circle,
                size: 8,
                color: AppColors.noticeDot,
                semanticLabel: '未读',
              ),
            )
          : null,
      onTap: onOpen,
      onLongPress: !event.unread
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (sheet) => SafeArea(
                  child: ListTile(
                    leading: const Icon(Icons.done_all),
                    title: const Text('标为已读'),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      onMarkRead();
                    },
                  ),
                ),
              ),
    );
  }
}

/// 可能 for a probable match; 待确认 for anything less; with the reason.
class _Confidence extends StatelessWidget {
  const _Confidence({required this.event});

  final WatchEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final probable = event.confidence == WatchConfidence.probable;
    final (background, foreground) = probable
        ? AppTagColors.of('amber')!
        : (AppColors.inkSoft, AppColors.textMuted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.sm,
            vertical: 1,
          ),
          decoration: ShapeDecoration(
            color: background,
            shape: const StadiumBorder(),
          ),
          child: Text(
            probable ? '可能' : '待确认',
            style: theme.textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ),
        if (event.reason.isNotEmpty) ...[
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              event.reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

enum _RuleAction { open, pause, delete }

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.summary,
    required this.status,
    required this.failed,
    required this.onEdit,
    required this.onOpen,
    required this.onPause,
    required this.onDelete,
  });

  final WatchRule rule;
  final String summary;
  final String status;
  final bool failed;
  final VoidCallback onEdit;
  final VoidCallback onOpen;
  final VoidCallback onPause;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = rule.paused;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.xs,
            AppSpace.md,
          ),
          child: Row(
            children: [
              Opacity(
                opacity: muted ? 0.5 : 1,
                child: WatchScopeTile(scope: rule.scope),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: muted ? AppColors.textMuted : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: failed ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_RuleAction>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert),
                onSelected: (action) => switch (action) {
                  _RuleAction.open => onOpen(),
                  _RuleAction.pause => onPause(),
                  _RuleAction.delete => onDelete(),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _RuleAction.open,
                    child: Text(switch (rule.scope) {
                      WatchScope.thread => '打开帖子',
                      WatchScope.user => '打开用户中心',
                      WatchScope.board => '打开版块',
                    }),
                  ),
                  PopupMenuItem(
                    value: _RuleAction.pause,
                    child: Text(rule.paused ? '恢复' : '暂停'),
                  ),
                  const PopupMenuItem(
                    value: _RuleAction.delete,
                    child: Text('删除'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
