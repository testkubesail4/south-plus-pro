import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart' show forumErrorText;

/// The forum's own marks on a post, under its body: the opening post's bounty
/// state, a floor's award, the rating record, and the author's award buttons.
class ThreadPostMarks extends StatelessWidget {
  const ThreadPostMarks({
    super.key,
    this.bounty,
    this.award,
    this.ratings = const [],
    this.rewardActions = const [],
    this.rewardLocked = false,
    this.onReward,
  });

  final ThreadBounty? bounty;
  final ThreadAward? award;
  final List<ThreadRating> ratings;
  final List<ThreadRewardAction> rewardActions;

  /// An award's outcome is unconfirmed: no further award from this screen.
  final bool rewardLocked;
  final ValueChanged<ThreadRewardAction>? onReward;

  bool get isEmpty =>
      bounty == null &&
      award == null &&
      ratings.isEmpty &&
      (rewardActions.isEmpty || onReward == null);

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final bounty = this.bounty;
    final award = this.award;
    final onReward = this.onReward;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bounty != null) ThreadBountyPanel(bounty: bounty),
          if (award != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _AwardPill(award: award),
            ),
          if (ratings.isNotEmpty) _RatingsRow(ratings: ratings),
          if (rewardActions.isNotEmpty && onReward != null)
            _RewardButtons(
              actions: rewardActions,
              locked: rewardLocked,
              onReward: onReward,
            ),
        ].expand((w) => [w, const SizedBox(height: AppSpace.sm)]).toList()
          ..removeLast(),
      ),
    );
  }
}

/// The headline of a bounty state; never claims an answer it cannot see.
String bountyHeadline(ForumBountyStatus status) => switch (status) {
      ForumBountyStatus.active => '悬赏中',
      ForumBountyStatus.expired => '悬赏已到期',
      ForumBountyStatus.ended => '悬赏已结束',
      ForumBountyStatus.unknown => '悬赏',
    };

/// A board row's bounty word: the native amount while it runs; otherwise
/// only that the thread is a bounty (no answer is claimed from a missing
/// amount).
String? boardBountyLabel(ForumBounty? bounty) => switch (bounty) {
      null => null,
      ForumBounty(status: ForumBountyStatus.active, :final amount?) =>
        '悬赏 $amount',
      ForumBounty(status: ForumBountyStatus.unknown) => '悬赏帖',
      ForumBounty(:final status) => bountyHeadline(status),
    };

/// The opening post's bounty, as the forum states it.
class ThreadBountyPanel extends StatelessWidget {
  const ThreadBountyPanel({super.key, required this.bounty});

  final ThreadBounty bounty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = bounty;
    final note = switch (b.status) {
      ForumBountyStatus.expired => '时限已过，楼主尚未选出最佳答案',
      ForumBountyStatus.ended => '楼主已选出最佳答案',
      _ => null,
    };
    final pills = [
      if (b.status == ForumBountyStatus.active && b.remainingHours != null)
        (Icons.schedule, '剩余 ${b.remainingHours} 小时'),
      if (b.bestAmount != null)
        (Icons.emoji_events_outlined, '最佳答案 ${b.bestAmount} ${b.currency}'),
      if (b.helpfulRemaining != null && b.status != ForumBountyStatus.ended)
        (
          Icons.volunteer_activism_outlined,
          '热心助人剩余 ${b.helpfulRemaining} ${b.currency}'
        ),
    ];
    return Container(
      key: const ValueKey('thread-bounty'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bountyHeadline(b.status),
            style: theme.textTheme.titleSmall?.copyWith(
              color: b.status == ForumBountyStatus.active
                  ? AppColors.brandDark
                  : AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(note, style: _onInkSoft(theme)),
          ],
          if (pills.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final (icon, label) in pills)
                  _Pill(icon: icon, label: label),
              ],
            ),
          ] else if (b.status == ForumBountyStatus.unknown &&
              b.text.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(b.text.trim(), style: _onInkSoft(theme)),
          ],
        ],
      ),
    );
  }

  // textMuted on inkSoft is under AA; body text keeps full contrast.
  static TextStyle? _onInkSoft(ThemeData theme) =>
      theme.textTheme.bodySmall?.copyWith(color: AppColors.text);
}

/// `最佳答案 +20 SP币` on the floor that won it.
String awardLabel(ThreadAward award) {
  final kind = award.kind == ThreadRewardKind.bestAnswer ? '最佳答案' : '热心助人';
  return '$kind +${award.amount} ${award.currency}';
}

/// `SP币 +109`, `HP -10`.
String ratingLabel(ThreadRating rating) =>
    '${rating.currency} ${rating.amount > 0 ? '+' : ''}${rating.amount}';

class _AwardPill extends StatelessWidget {
  const _AwardPill({required this.award});

  final ThreadAward award;

  @override
  Widget build(BuildContext context) {
    final best = award.kind == ThreadRewardKind.bestAnswer;
    return _Pill(
      icon: best ? Icons.emoji_events : Icons.volunteer_activism,
      label: awardLabel(award),
      color: AppColors.success,
      background: AppColors.successSoft,
    );
  }
}

class _RatingsRow extends StatelessWidget {
  const _RatingsRow({required this.ratings});

  final List<ThreadRating> ratings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: const ValueKey('post-ratings'),
      container: true,
      label: '最近评分 ${ratings.map(ratingLabel).join('，')}',
      excludeSemantics: true,
      child: Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('最近评分', style: theme.textTheme.bodySmall),
          for (final rating in ratings)
            _Pill(
              label: ratingLabel(rating),
              color: rating.amount < 0
                  ? theme.colorScheme.error
                  : AppColors.success,
              background: rating.amount < 0
                  ? theme.colorScheme.errorContainer
                  : AppColors.successSoft,
            ),
        ],
      ),
    );
  }
}

class _RewardButtons extends StatelessWidget {
  const _RewardButtons({
    required this.actions,
    required this.locked,
    required this.onReward,
  });

  final List<ThreadRewardAction> actions;
  final bool locked;
  final ValueChanged<ThreadRewardAction> onReward;

  @override
  Widget build(BuildContext context) {
    // Helpful first, as the forum asks: best answer ends the bounty.
    final ordered = [
      ...actions.where((a) => a.kind == ThreadRewardKind.helpful),
      ...actions.where((a) => a.kind == ThreadRewardKind.bestAnswer),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          children: [
            for (final action in ordered)
              OutlinedButton.icon(
                key: ValueKey(
                  action.kind == ThreadRewardKind.bestAnswer
                      ? 'reward-best-${action.pid}'
                      : 'reward-helpful-${action.pid}',
                ),
                onPressed: locked ? null : () => onReward(action),
                icon: Icon(
                  action.kind == ThreadRewardKind.bestAnswer
                      ? Icons.emoji_events_outlined
                      : Icons.volunteer_activism_outlined,
                  size: 18,
                ),
                label: Text(
                  action.kind == ThreadRewardKind.bestAnswer
                      ? '选为最佳答案'
                      : '给热心助人',
                ),
              ),
          ],
        ),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              '上次评选结果未确认，请刷新或在网页端核对后再操作',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    this.icon,
    this.color,
    this.background,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.text;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: ShapeDecoration(
        color: background ?? AppColors.surface,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the author must know before an award, which cannot be undone.
List<String> rewardConsequences(
  ThreadRewardKind kind, {
  ThreadBounty? bounty,
}) {
  final currency = bounty?.currency ?? 'SP币';
  final remaining = bounty?.helpfulRemaining;
  if (kind == ThreadRewardKind.helpful) {
    return [
      '奖励额由论坛决定，提交后无法撤销。',
      '此楼获得热心助人后，不能再被选为最佳答案。',
      '想给多位回复者热心助人，请在选出最佳答案之前完成。',
    ];
  }
  return [
    '选出最佳答案即结束悬赏，无法撤销或改选。',
    if (remaining == null)
      '尚未发出的热心助人分，将按发帖顺序每楼 1 分自动发放，直至用完。'
    else if (remaining > 0)
      '尚未发出的热心助人分（剩余 $remaining $currency）将按发帖顺序每楼 1 分自动发放，直至用完。',
    '想指定热心助人，请先给热心助人，再选最佳答案。',
  ];
}

/// Asks for confirmation, then awards once. Returns null when the author
/// backs out before anything was sent.
Future<ThreadRewardResult?> showThreadRewardDialog(
  BuildContext context, {
  required ForumRepository repository,
  required ThreadRewardAction action,
  required String floor,
  ThreadBounty? bounty,
}) {
  return showDialog<ThreadRewardResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ThreadRewardDialog(
      repository: repository,
      action: action,
      floor: floor,
      bounty: bounty,
    ),
  );
}

class _ThreadRewardDialog extends StatefulWidget {
  const _ThreadRewardDialog({
    required this.repository,
    required this.action,
    required this.floor,
    required this.bounty,
  });

  final ForumRepository repository;
  final ThreadRewardAction action;
  final String floor;
  final ThreadBounty? bounty;

  @override
  State<_ThreadRewardDialog> createState() => _ThreadRewardDialogState();
}

class _ThreadRewardDialogState extends State<_ThreadRewardDialog> {
  ThreadRewardDraft? _draft;
  String? _loadError;
  bool _notify = true;
  bool _sending = false;

  bool get _best => widget.action.kind == ThreadRewardKind.bestAnswer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final draft = await widget.repository.fetchRewardDraft(widget.action);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _notify = draft.notifyDefault;
      });
    } catch (error) {
      if (mounted)
        setState(() => _loadError = '无法打开评选表单：${forumErrorText(error)}');
    }
  }

  Future<void> _send() async {
    final draft = _draft;
    if (draft == null || _sending) return;
    setState(() => _sending = true);
    ThreadRewardResult result;
    try {
      result = await widget.repository.submitReward(
        draft: draft,
        notify: _notify,
      );
    } catch (error) {
      // The request may have reached the forum: treat it as sent.
      result = ThreadRewardResult(
        outcome: ThreadRewardOutcome.unknown,
        message: forumErrorText(error),
      );
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft;
    final rules = draft?.nativeRules?.trim();
    final Widget body;
    if (_loadError != null) {
      body =
          Text(_loadError!, style: TextStyle(color: theme.colorScheme.error));
    } else if (draft == null) {
      body = const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in rewardConsequences(
            widget.action.kind,
            bounty: widget.bounty,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text('· $line'),
            ),
          SwitchListTile(
            value: _notify,
            onChanged: _sending ? null : (v) => setState(() => _notify = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('短消息通知对方'),
          ),
          if (rules != null && rules.isNotEmpty)
            Text(
              '论坛说明：$rules',
              style: theme.textTheme.bodySmall,
            ),
        ],
      );
    }
    return PopScope(
      canPop: !_sending,
      child: AlertDialog(
        title: Text(
          _best ? '选 ${widget.floor} 为最佳答案？' : '给 ${widget.floor} 热心助人？',
        ),
        content: SingleChildScrollView(child: body),
        actions: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          if (_loadError == null)
            FilledButton(
              key: const ValueKey('reward-confirm'),
              onPressed: draft == null || _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认，不可撤销'),
            ),
        ],
      ),
    );
  }
}
