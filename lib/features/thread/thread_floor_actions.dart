import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum ThreadFloorAction {
  edit,
  showAuthorPosts,
  editNote,
  blockContent,
  blockUser,
  blockAvatar,
  manageBlocking,
  watchUser,
  watchInThread,
  manageWatch,
}

/// The rule state a floor's menu reflects, and which rules may change.
class ThreadFloorBlockState {
  const ThreadFloorBlockState({
    this.userBlocked = false,
    this.avatarBlocked = false,
    this.contentBlocked = false,
    this.canBlockUser = false,
    this.canBlockContent = false,
    this.userBlockUnavailableReason,
    this.contentBlockUnavailableReason,
  });

  final bool userBlocked;
  final bool avatarBlocked;
  final bool contentBlocked;

  /// Native 屏蔽此人 / 屏蔽头像 need a signed-in account and the author's uid.
  final bool canBlockUser;

  /// 屏蔽内容 needs text to match on.
  final bool canBlockContent;
  final String? userBlockUnavailableReason;
  final String? contentBlockUnavailableReason;
}

/// Footer of a floor: quiet actions at the trailing edge, the everyday two
/// then ⋯ for the rest. Labels show from 600 px wide; phones get icons.
class ThreadFloorFooter extends StatelessWidget {
  const ThreadFloorFooter({
    super.key,
    required this.moreKey,
    required this.onReply,
    required this.onQuote,
    required this.onMore,
    this.quoteLoading = false,
  });

  final Key moreKey;
  final VoidCallback? onReply;
  final VoidCallback? onQuote;
  final VoidCallback? onMore;
  final bool quoteLoading;

  @override
  Widget build(BuildContext context) {
    final labels = MediaQuery.sizeOf(context).width >= 600;
    Widget action(
      String label,
      Widget icon,
      VoidCallback? onPressed,
    ) =>
        labels
            ? TextButton.icon(
                onPressed: onPressed,
                icon: icon,
                label: Text(label),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                ),
              )
            : IconButton(
                tooltip: label,
                onPressed: onPressed,
                color: AppColors.textMuted,
                icon: icon,
              );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (onReply != null)
          action('回复', const Icon(Icons.reply_outlined, size: 18), onReply),
        if (onQuote != null)
          action(
            quoteLoading ? '引用中…' : '引用',
            quoteLoading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.format_quote_outlined, size: 18),
            quoteLoading ? null : onQuote,
          ),
        if (onMore != null)
          IconButton(
            key: moreKey,
            tooltip: '更多操作',
            onPressed: onMore,
            color: AppColors.textMuted,
            icon: const Icon(Icons.more_horiz, size: 18),
          ),
      ],
    );
  }
}

/// The floor's secondary actions, headed by whose floor it is.
Future<ThreadFloorAction?> showThreadFloorActions(
  BuildContext context, {
  required String author,
  required String? floor,
  required Widget avatar,
  required bool canShowAuthorPosts,

  /// The floor carries the forum's own edit link.
  bool canEdit = false,

  /// The local note on the author; editing needs the author's uid.
  bool canEditNote = false,
  bool hasNote = false,

  /// Null hides the 屏蔽 group, e.g. while the rules are unavailable.
  required ThreadFloorBlockState? block,

  /// Shows the 关注 group: signed in and the author's uid known.
  bool canWatch = false,

  /// The floor is the reader's own: no 关注 TA, and the thread item reads
  /// 本帖中回复我的.
  bool ownFloor = false,
}) {
  return showModalBottomSheet<ThreadFloorAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget item(
        ThreadFloorAction action,
        IconData icon,
        String title,
        String subtitle, {
        bool enabled = true,
      }) =>
          ListTile(
            enabled: enabled,
            leading: Icon(icon, size: 20, color: AppColors.textMuted),
            title: Text(title),
            subtitle: Text(subtitle),
            minVerticalPadding: 10,
            onTap: () => Navigator.of(context).pop(action),
          );
      final nativeNote = block == null || block.canBlockUser
          ? null
          : block.userBlockUnavailableReason;
      Widget divider() => Divider(
            height: 17,
            indent: 16,
            endIndent: 16,
            color: AppColors.border.withValues(alpha: 0.6),
          );
      // A small group label with its 管理 link, as 屏蔽 and 关注 use.
      Widget groupHeader(String label, ThreadFloorAction manage) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => Navigator.of(context).pop(manage),
                  child: const Text('管理'),
                ),
              ],
            ),
          );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: avatar,
                title: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: floor == null || floor.isEmpty ? null : Text(floor),
              ),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.border.withValues(alpha: 0.6),
              ),
              if (canEdit)
                item(
                  ThreadFloorAction.edit,
                  Icons.edit_outlined,
                  '编辑',
                  '修改这层的标题和正文，保存到论坛',
                ),
              if (canShowAuthorPosts)
                item(
                  ThreadFloorAction.showAuthorPosts,
                  Icons.person_search_outlined,
                  '只看该作者',
                  '只显示 TA 在本帖的楼层',
                ),
              if (canEditNote)
                item(
                  ThreadFloorAction.editNote,
                  Icons.edit_note_outlined,
                  hasNote ? '修改备注' : '添加备注',
                  '仅本机',
                ),
              if (canWatch) ...[
                if (canShowAuthorPosts || canEditNote || canEdit) divider(),
                groupHeader('关注', ThreadFloorAction.manageWatch),
                if (!ownFloor)
                  item(
                    ThreadFloorAction.watchUser,
                    Icons.notifications_none_outlined,
                    '关注 TA',
                    '新主题、回复或可见收藏',
                  ),
                item(
                  ThreadFloorAction.watchInThread,
                  Icons.forum_outlined,
                  ownFloor ? '本帖中回复我的' : '本帖中涉及 TA 的回复',
                  ownFloor ? '回复或引用我的新楼层' : '回复或引用 TA 的新楼层',
                ),
              ],
              if (block != null) ...[
                if (canShowAuthorPosts || canWatch) divider(),
                groupHeader('屏蔽', ThreadFloorAction.manageBlocking),
                item(
                  ThreadFloorAction.blockContent,
                  Icons.comments_disabled_outlined,
                  block.contentBlocked ? '取消屏蔽内容' : '屏蔽内容',
                  block.canBlockContent
                      ? '仅本机 · 隐藏内容相同的楼层'
                      : block.contentBlockUnavailableReason ?? '此楼没有可匹配的文字',
                  enabled: block.canBlockContent,
                ),
                item(
                  ThreadFloorAction.blockUser,
                  Icons.person_off_outlined,
                  block.userBlocked ? '取消屏蔽此人' : '屏蔽此人',
                  nativeNote ?? '同步南+屏蔽配置 · 隐藏 TA 的主题与回复',
                  enabled: block.canBlockUser,
                ),
                item(
                  ThreadFloorAction.blockAvatar,
                  Icons.hide_image_outlined,
                  block.avatarBlocked ? '取消屏蔽头像' : '屏蔽头像',
                  nativeNote ?? '同步南+屏蔽配置 · 只隐藏 TA 的头像',
                  enabled: block.canBlockUser,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// A hidden floor keeps its place as one slim row the reader can open.
class ThreadBlockedFloor extends StatelessWidget {
  const ThreadBlockedFloor({
    super.key,
    required this.label,
    required this.onReveal,
  });

  final String label;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inkSoft,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
        child: Row(
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 16,
              color: AppColors.textFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: onReveal,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.link,
                minimumSize: const Size(48, 44),
              ),
              child: const Text('显示'),
            ),
          ],
        ),
      ),
    );
  }
}
