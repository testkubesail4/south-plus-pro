import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/watch_models.dart';
import '../../services/forum_repository.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/content_width.dart';
import '../common/forum_link_opener.dart';
import '../common/grouped_list.dart';
import '../common/help_sheet.dart';
import '../common/session_bound.dart';
import '../common/sub_tabs.dart';
import '../common/thread_row.dart';
import '../messages/notification_permission_row.dart';
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
          body: Column(
            children: [
              AppContentWidth(
                maxWidth: AppWidths.list,
                child: NotificationPermissionRow(watch: repository.watch),
              ),
              Expanded(
                child: WatchTab(
                  repository: repository,
                  initialRules: true,
                  opensNotifications: false,
                ),
              ),
            ],
          ),
        ),
      );
}

class _WatchTabState extends State<WatchTab> {
  WatchService get _watch => widget.repository.watch;
  late var _showRules = widget.initialRules;
  // The account this list belongs to; a write after a switch is dropped.
  late final WatchSessionScope _scope;
  var _shown = false;

  @override
  void initState() {
    super.initState();
    _scope = WatchSessionScope(widget.repository);
    _watch.addListener(_onWatch);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.of(context);
    if (shown == _shown) return;
    _shown = shown;
    if (shown) WidgetsBinding.instance.addPostFrameCallback((_) => _onWatch());
  }

  @override
  void dispose() {
    _watch.removeListener(_onWatch);
    super.dispose();
  }

  // A tapped system notification lands on 动态; its rows open their floors.
  // Under another page it waits until that page is gone.
  void _onWatch() {
    if (!mounted ||
        !_shown ||
        !widget.opensNotifications ||
        _watch.pendingOpen == null) {
      return;
    }
    if (_watch.takePendingOpen() != null) setState(() => _showRules = false);
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
        // Unread local state is not an empty list; 重试 reads it again.
        final unreadable = _watch.statuses.containsKey('storage');
        // Pulling waits for the check; at the request limit it just returns.
        return RefreshIndicator(
          color: AppColors.brand,
          onRefresh: () => _watch.checkNow().catchError((_) {}),
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppSpace.sm, bottom: 88),
          children: [
            AppContentWidth(
              maxWidth: AppWidths.list,
              child: SubTabs<bool>(
                tabs: [
                  (false, '动态'),
                  (
                    true,
                    unreadable
                        ? '规则'
                        : '规则 ${_watch.activeCount}/${WatchService.maxActiveRules}'
                  ),
                ],
                selected: _showRules,
                onSelected: (value) => setState(() => _showRules = value),
                trailing: HelpButton(title: '关注', lines: watchHelpLines),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            AppContentWidth(
              maxWidth: AppWidths.list,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: unreadable
                    ? [
                        EmptyStateView(
                          icon: Icons.error_outline,
                          iconColor: AppColors.textMuted,
                          title: '关注数据无法读取',
                          action: FilledButton.tonalIcon(
                            onPressed: _watch.running
                                ? null
                                : () => _watch.checkNow().catchError((_) {}),
                            icon: const Icon(Icons.refresh),
                            label: const Text('重试'),
                          ),
                        ),
                      ]
                    : _showRules
                        ? _rules(context, rules)
                        : _events(context, rules),
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  List<Widget> _events(BuildContext context, List<WatchRule> rules) {
    final events = _watch.events;
    final labels = {for (final rule in rules) rule.id: rule.label};
    if (rules.isEmpty) return const [_NoRules()];
    return [
      if (_watch.running)
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
          child: LinearProgressIndicator(
            value: _watch.progressTotal == 0
                ? null
                : (_watch.progressDone / _watch.progressTotal)
                    .clamp(0, 1)
                    .toDouble(),
            minHeight: 2,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      if (events.isEmpty)
        const EmptyStateView(
          icon: Icons.notifications_none_outlined,
          title: '还没有新动态',
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
    bool failed(WatchRule rule) =>
        !rule.paused &&
        _watch.statuses[rule.id]?.phase == WatchPhase.unavailable;
    return [
      if (rules.isEmpty)
        const _NoRules()
      else
        AppGroup(
          children: [
            for (final rule in rules)
              _RuleRow(
                rule: rule,
                summary: watchRuleSummary(
                  rule,
                  watchSelfUid(widget.repository),
                ),
                // Rows only speak up when something is off.
                status: rule.paused || failed(rule)
                    ? watchStatusText(_watch, rule)
                    : null,
                failed: failed(rule),
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

class _NoRules extends StatelessWidget {
  const _NoRules();

  @override
  Widget build(BuildContext context) => const EmptyStateView(
        icon: Icons.notifications_none_outlined,
        title: '还没有关注',
      );
}

/// What 关注 checks, where it is added, and what it cannot see. Only
/// Android keeps checking in the background, and only for rules that notify.
List<(IconData, String)> get watchHelpLines => [
      (Icons.add_alert_outlined, '在帖子右上角菜单、楼层作者菜单、用户中心或版块里添加'),
      (Icons.schedule_outlined, '使用 App 时约每 15 分钟检查一次'),
      if (defaultTargetPlatform == TargetPlatform.android) ...[
        (Icons.notifications_active_outlined, '开启通知的关注在后台也检查，系统可能延迟或停止'),
        (Icons.phonelink_erase_outlined, '关闭 App 后不检查'),
      ] else
        (Icons.phonelink_erase_outlined, '后台或关闭时不检查'),
      (Icons.visibility_off_outlined, '私密收藏、已删除的楼层和图片中的文字无法识别'),
    ];

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
  final String? status;
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
                    if (status case final status?)
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
