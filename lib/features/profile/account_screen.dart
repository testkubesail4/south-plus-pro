import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_network_setup_store.dart';
import '../../services/forum_text_size_settings.dart';
import '../../services/image_loading_settings.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/cached_forum_image.dart';
import '../history/browsing_history_screen.dart';
import '../messages/pm_box_screen.dart';
import '../messages/reply_notices_screen.dart';
import 'forum_tasks_screen.dart';
import 'network_setup_flow_screen.dart';
import 'network_settings_screen.dart';
import 'user_profile_screen.dart';

part 'settings_screen.dart';

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
            _AccountSection(
              title: '个人内容',
              children: [
                _AccountTile(
                  icon: Icons.badge_outlined,
                  title: '资料',
                  subtitle: '等级、积分和个人信息',
                  onTap: () => _openProfile(UserProfileTab.profile),
                ),
                _AccountTile(
                  icon: Icons.article_outlined,
                  title: '主题',
                  subtitle: '我发表的主题',
                  onTap: () => _openProfile(UserProfileTab.topics),
                ),
                _AccountTile(
                  icon: Icons.forum_outlined,
                  title: '回复',
                  subtitle: '我参与的回复',
                  onTap: () => _openProfile(UserProfileTab.posts),
                ),
                _AccountTile(
                  icon: Icons.star_outline,
                  title: '收藏',
                  subtitle: '我公开收藏的主题',
                  onTap: () => _openProfile(UserProfileTab.favorites),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _AccountSection(
            title: '账号',
            children: [
              if (loggedIn)
                ValueListenableBuilder<ForumNoticeFlags>(
                  valueListenable: widget.repository.noticeFlags,
                  builder: (context, flags, _) => _AccountTile(
                    icon: Icons.mail_outline,
                    title: '短消息',
                    subtitle: '收件箱、发件箱和消息跟踪',
                    unread: flags.unreadPm,
                    onTap: () =>
                        _push(PmBoxScreen(repository: widget.repository)),
                  ),
                ),
              if (loggedIn)
                ValueListenableBuilder<ForumNoticeFlags>(
                  valueListenable: widget.repository.noticeFlags,
                  builder: (context, flags, _) => _AccountTile(
                    icon: Icons.alternate_email,
                    title: '回复提醒',
                    subtitle: flags.replyNotice ? '有新的回复提醒' : '我的主题收到的回复',
                    unread: flags.replyNotice,
                    onTap: () => _push(
                        ReplyNoticesScreen(repository: widget.repository)),
                  ),
                ),
              _AccountTile(
                icon: Icons.fact_check_outlined,
                title: '论坛任务',
                subtitle: loggedIn ? '申请日常、周常并领取奖励' : '登录后领取 SP 币任务奖励',
                onTap: () =>
                    _push(ForumTasksScreen(repository: widget.repository)),
              ),
              _AccountTile(
                icon: Icons.history_outlined,
                title: '浏览历史',
                subtitle: '只保存在本机的阅读记录',
                onTap: () => _push(BrowsingHistoryScreen(
                  repository: widget.repository,
                  onBrowseHome: widget.onBrowseHome,
                )),
              ),
              _AccountTile(
                icon: Icons.settings_outlined,
                title: '设置',
                subtitle: '网络、外观、图片、字体和版本',
                onTap: _openSettings,
              ),
            ],
          ),
          if (loggedIn) ...[
            const SizedBox(height: 14),
            _AccountSection(
              title: '登录状态',
              children: [
                _AccountTile(
                  icon: Icons.logout,
                  title: '退出登录',
                  subtitle: '清除本机登录状态',
                  danger: true,
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

String _compactReleaseNotes(String body) {
  return body
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(6)
      .join('\n');
}

String _formatReleaseDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brandSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
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

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dividedChildren = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        dividedChildren.add(Divider(indent: 64, endIndent: 12));
      }
      dividedChildren.add(children[index]);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          ...dividedChildren,
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.unread = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool unread;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return _BaseAccountTile(
      icon: icon,
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
      unread: unread,
      danger: danger,
      trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
    );
  }
}

class _StaticInfoTile extends StatelessWidget {
  const _StaticInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _BaseAccountTile(
      icon: icon,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _SelectableAccountTile extends StatelessWidget {
  const _SelectableAccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Widget title;
  final Widget subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseAccountTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      selected: selected,
      trailing: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked_outlined,
        color: selected ? AppColors.brand : AppColors.textFaint,
      ),
    );
  }
}

class _BaseAccountTile extends StatelessWidget {
  const _BaseAccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.selected = false,
    this.unread = false,
    this.danger = false,
  });

  final IconData icon;
  final Widget title;
  final Widget subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected;
  final bool unread;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // Neutral icons; brand marks a chosen option, brandDark a destructive
    // one, and unread shows as a dot.
    final iconColor = danger
        ? AppColors.brandDark
        : selected
            ? AppColors.brand
            : AppColors.textMuted;
    final iconBackground =
        danger || selected ? AppColors.brandSoft : AppColors.inkSoft;
    final titleColor = danger ? AppColors.brandDark : AppColors.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        // The dot alone is invisible to screen readers.
        child: Semantics(
          value: unread ? '有未读' : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 74),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: unread,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: enabled ? iconBackground : AppColors.inkSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: enabled ? iconColor : AppColors.textFaint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DefaultTextStyle.merge(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: titleColor,
                                  ),
                          child: title,
                        ),
                        const SizedBox(height: 3),
                        DefaultTextStyle.merge(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: enabled
                                        ? AppColors.textMuted
                                        : AppColors.textFaint,
                                  ),
                          child: subtitle,
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusSummaryTile extends StatelessWidget {
  const _StatusSummaryTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
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

IconData _iconForImageMode(ImageLoadMode mode) {
  return switch (mode) {
    ImageLoadMode.automatic => Icons.image_outlined,
    ImageLoadMode.wifiOnly => Icons.wifi_outlined,
    ImageLoadMode.manual => Icons.touch_app_outlined,
    ImageLoadMode.noImages => Icons.hide_image_outlined,
  };
}

IconData _iconForThemeMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => Icons.settings_suggest_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };
}

String _labelForThemeMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '白天模式',
    ThemeMode.dark => '暗黑模式',
  };
}

String _descriptionForThemeMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '自动使用系统外观设置',
    ThemeMode.light => '始终使用浅色界面',
    ThemeMode.dark => '始终使用深色界面',
  };
}
