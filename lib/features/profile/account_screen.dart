import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/cached_forum_image.dart';
import '../common/grouped_list.dart';
import '../history/browsing_history_screen.dart';
import '../messages/pm_box_screen.dart';
import '../messages/reply_notices_screen.dart';
import 'forum_tasks_screen.dart';
import 'settings_screen.dart';
import 'user_profile_screen.dart';


class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    required this.onLoggedOut,
    this.onBrowseHome,
    this.updateChecker = const UpdateChecker(),
    this.packageInfoLoader = PackageInfo.fromPlatform,
  });

  final ForumRepository repository;
  final VoidCallback onLoggedOut;

  /// Lets the pushed history page send the user back to the home tab.
  final VoidCallback? onBrowseHome;
  final UpdateChecker updateChecker;
  final Future<PackageInfo> Function() packageInfoLoader;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

/// The 我的 tab: who is signed in and everything that belongs to them.
/// Device settings live one level deeper in [SettingsScreen].
class _AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    // The nickname is optional; the system name shows until it arrives.
    widget.repository.loadAccountNickname().ignore();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('将清除本机的登录状态，帖子、收藏和私信不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // The shell rebuilds this tab as soon as the session owner clears, so
    // everything needed afterwards is captured before awaiting.
    final messenger = ScaffoldMessenger.of(context);
    final onLoggedOut = widget.onLoggedOut;
    await widget.repository.clearSession();
    onLoggedOut();
    messenger.showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openProfile(UserProfileTab tab) => _push(UserProfileScreen(
        userUrl: 'u.php',
        repository: widget.repository,
        initialTab: tab,
      ));

  void _openSettings() => _push(SettingsScreen(
        repository: widget.repository,
        updateChecker: widget.updateChecker,
        packageInfoLoader: widget.packageInfoLoader,
      ));

  @override
  Widget build(BuildContext context) {
    final loggedIn = widget.repository.isLoggedIn;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: '设置',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<ForumAccountIdentity?>(
            valueListenable: widget.repository.accountIdentity,
            builder: (context, identity, _) {
              final name = accountDisplayName(identity);
              // A nickname is shown first; the system name stays visible below.
              final nicknameShown =
                  identity != null && name != identity.systemName;
              return _AccountHeader(
                title: !loggedIn
                    ? '未登录'
                    : name ?? widget.repository.currentUsername ?? '已登录',
                subtitle: !loggedIn
                    ? '登录后可查看个人内容、收藏和短消息'
                    : nicknameShown
                        ? identity.systemName
                        : '南+账号已连接',
                avatarUrl: loggedIn ? identity?.avatarUrl : null,
                loggedIn: loggedIn,
              );
            },
          ),
          if (!loggedIn) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => openLogin(context, widget.repository),
              icon: const Icon(Icons.login),
              label: const Text('登录南+账号'),
            ),
          ],
          if (loggedIn) ...[
            const SizedBox(height: 16),
            AppGroup(
              label: '个人内容',
              children: [
                AppRow(
                  icon: Icons.badge_outlined,
                  title: const Text('资料'),
                  subtitle: const Text('等级、积分和个人信息'),
                  onTap: () => _openProfile(UserProfileTab.profile),
                ),
                AppRow(
                  icon: Icons.article_outlined,
                  title: const Text('主题'),
                  subtitle: const Text('我发表的主题'),
                  onTap: () => _openProfile(UserProfileTab.topics),
                ),
                AppRow(
                  icon: Icons.forum_outlined,
                  title: const Text('回复'),
                  subtitle: const Text('我参与的回复'),
                  onTap: () => _openProfile(UserProfileTab.posts),
                ),
                AppRow(
                  icon: Icons.star_outline,
                  title: const Text('收藏'),
                  subtitle: const Text('我公开收藏的主题'),
                  onTap: () => _openProfile(UserProfileTab.favorites),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          AppGroup(
            label: '账号',
            children: [
              if (loggedIn)
                ValueListenableBuilder<ForumNoticeFlags>(
                  valueListenable: widget.repository.noticeFlags,
                  builder: (context, flags, _) => AppRow(
                    icon: Icons.mail_outline,
                    title: const Text('短消息'),
                    subtitle: const Text('收件箱、发件箱和消息跟踪'),
                    unread: flags.unreadPm,
                    onTap: () =>
                        _push(PmBoxScreen(repository: widget.repository)),
                  ),
                ),
              if (loggedIn)
                ValueListenableBuilder<ForumNoticeFlags>(
                  valueListenable: widget.repository.noticeFlags,
                  builder: (context, flags, _) => AppRow(
                    icon: Icons.alternate_email,
                    title: const Text('回复提醒'),
                    subtitle: Text(
                        flags.replyNotice ? '有新的回复提醒' : '我的主题收到的回复'),
                    unread: flags.replyNotice,
                    onTap: () => _push(
                        ReplyNoticesScreen(repository: widget.repository)),
                  ),
                ),
              AppRow(
                icon: Icons.fact_check_outlined,
                title: const Text('论坛任务'),
                subtitle: Text(
                    loggedIn ? '申请日常、周常并领取奖励' : '登录后领取 SP 币任务奖励'),
                onTap: () =>
                    _push(ForumTasksScreen(repository: widget.repository)),
              ),
              AppRow(
                icon: Icons.history_outlined,
                title: const Text('浏览历史'),
                subtitle: const Text('只保存在本机的阅读记录'),
                onTap: () => _push(BrowsingHistoryScreen(
                  repository: widget.repository,
                  onBrowseHome: widget.onBrowseHome,
                )),
              ),
              AppRow(
                icon: Icons.settings_outlined,
                title: const Text('设置'),
                subtitle: const Text('网络、外观、图片、字体和版本'),
                onTap: _openSettings,
              ),
            ],
          ),
          if (loggedIn) ...[
            const SizedBox(height: AppSpace.xl),
            AppGroup(
              label: '登录状态',
              children: [
                AppRow(
                  icon: Icons.logout,
                  title: const Text('退出登录'),
                  subtitle: const Text('清除本机登录状态'),
                  destructive: true,
                  onTap: _logout,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.title,
    required this.subtitle,
    required this.avatarUrl,
    required this.loggedIn,
  });

  final String title;
  final String subtitle;
  final String? avatarUrl;
  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: appSurface(context),
      child: Row(
        children: [
          AccountAvatar(avatarUrl: avatarUrl, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                _AccountBadge(
                  label: loggedIn ? '已连接' : '游客模式',
                  icon: loggedIn
                      ? Icons.verified_user_outlined
                      : Icons.person_off_outlined,
                  active: loggedIn,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The account's nickname when set, otherwise its system name.
String? accountDisplayName(ForumAccountIdentity? identity) {
  final nickname = identity?.nickname?.trim() ?? '';
  return nickname.isNotEmpty ? nickname : identity?.systemName;
}

/// The signed-in user's avatar in a circle, or a person icon without one.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.avatarUrl, required this.size});

  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    Widget icon(BuildContext context) => Icon(
          Icons.account_circle_outlined,
          color: AppColors.textMuted,
          size: size * 0.6,
        );
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.inkSoft,
      child: url == null
          ? icon(context)
          : ClipOval(
              child: CachedForumImage(
                url: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                bypassLoadPolicy: true,
                errorWidget: icon,
              ),
            ),
    );
  }
}

class _AccountBadge extends StatelessWidget {
  const _AccountBadge({
    required this.label,
    required this.icon,
    required this.active,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.successSoft : AppColors.inkSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: active ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: active ? AppColors.success : AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

