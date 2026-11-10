import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/app_tab_header.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../history/browsing_history_screen.dart';
import '../home/home_shell.dart';
import 'account_profile_edit_screen.dart';
import 'blocking_settings_screen.dart';
import 'forum_preferences_screen.dart';
import 'forum_tasks_screen.dart';
import 'friends_screen.dart';
import 'account_switcher_binding.dart';
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
  bool _confirmingLogout = false;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    // The nickname is optional; the system name shows until it arrives.
    widget.repository.loadAccountNickname().ignore();
  }

  Future<void> _logoutCurrent() async {
    if (!mounted || _confirmingLogout || _loggingOut) return;
    _confirmingLogout = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('退出当前账号？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出当前账号'),
            ),
          ],
        ),
      );
    } finally {
      _confirmingLogout = false;
    }
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repository = widget.repository;
    final onLoggedOut = widget.onLoggedOut;
    setState(() => _loggingOut = true);
    try {
      await repository.logoutCurrent();
      onLoggedOut();
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('已退出当前账号')),
        );
      }
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(
          content: const Text('退出失败，请重试'),
          action: mounted
              ? SnackBarAction(label: '重试', onPressed: _logoutCurrent)
              : null,
        ));
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _openSwitcher() =>
      openAccountSwitcher(context, widget.repository);

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
    return Column(children: [
      AppTabHeader(
        title: '我的',
        maxWidth: AppWidths.form,
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      Expanded(
          child: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.symmetric(
              horizontal: appGutter(constraints.maxWidth, AppWidths.form),
            ).copyWith(top: AppSpace.sm, bottom: AppSpace.xxl),
            children: [
              ValueListenableBuilder<ForumAccountIdentity?>(
                valueListenable: widget.repository.accountIdentity,
                builder: (context, identity, _) {
                  final name = accountDisplayName(identity);
                  // A nickname is shown first; the system name stays below it.
                  final nicknameShown =
                      identity != null && name != identity.systemName;
                  return _AccountHeader(
                    title: !loggedIn
                        ? '未登录'
                        : name ?? widget.repository.currentUsername ?? '已登录',
                    subtitle:
                        loggedIn && nicknameShown ? identity.systemName : null,
                    avatarUrl: loggedIn ? identity?.avatarUrl : null,
                    onTap: loggedIn
                        ? () => _openProfile(UserProfileTab.home)
                        : null,
                    onSwitchAccounts: _openSwitcher,
                    action: loggedIn
                        ? null
                        : FilledButton.icon(
                            onPressed: () =>
                                openLogin(context, widget.repository),
                            icon: const Icon(Icons.login),
                            label: const Text('登录南+账号'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                  );
                },
              ),
              ValueListenableBuilder(
                valueListenable: widget.repository.accounts,
                builder: (context, _, __) {
                  final showSwitcher = loggedIn ||
                      accountsForCurrentSite(widget.repository).isNotEmpty;
                  if (!showSwitcher && !loggedIn) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpace.xl),
                      AppGroup(
                        children: [
                          if (showSwitcher)
                            AppRow(
                              icon: Icons.swap_horiz,
                              title: const Text('切换账号'),
                              onTap: _openSwitcher,
                            ),
                          if (loggedIn) ...[
                            AppRow(
                              icon: Icons.edit_outlined,
                              title: const Text('编辑资料'),
                              onTap: () => _push(AccountProfileEditScreen(
                                  repository: widget.repository)),
                            ),
                            AppRow(
                              icon: Icons.tune_outlined,
                              title: const Text('论坛偏好'),
                              onTap: () => _push(ForumPreferencesScreen(
                                  repository: widget.repository)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpace.xl),
              AppGroup(
                children: [
                  if (loggedIn) ...[
                    AppRow(
                      icon: Icons.article_outlined,
                      title: const Text('我的主题'),
                      onTap: () => _openProfile(UserProfileTab.topics),
                    ),
                    AppRow(
                      icon: Icons.forum_outlined,
                      title: const Text('我的回复'),
                      onTap: () => _openProfile(UserProfileTab.posts),
                    ),
                    AppRow(
                      icon: Icons.star_outline,
                      title: const Text('我的收藏'),
                      onTap: () =>
                          HomeShell.showTab(context, HomeShell.favoritesTab),
                    ),
                    AppRow(
                      icon: Icons.people_outline,
                      title: const Text('好友'),
                      onTap: () =>
                          _push(FriendsScreen(repository: widget.repository)),
                    ),
                  ],
                  AppRow(
                    icon: Icons.history_outlined,
                    title: const Text('浏览历史'),
                    onTap: () => _push(BrowsingHistoryScreen(
                      repository: widget.repository,
                      onBrowseHome: widget.onBrowseHome,
                    )),
                  ),
                ],
              ),
              if (loggedIn) ...[
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  children: [
                    AppRow(
                      icon: Icons.fact_check_outlined,
                      title: const Text('论坛任务'),
                      onTap: () => _push(
                          ForumTasksScreen(repository: widget.repository)),
                    ),
                    AppRow(
                      icon: Icons.block_outlined,
                      title: const Text('屏蔽配置'),
                      onTap: () => _push(BlockingSettingsScreen(
                          repository: widget.repository)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  children: [
                    AppRow(
                      icon: Icons.logout,
                      title: const Text('退出当前账号'),
                      destructive: true,
                      enabled: !_loggingOut,
                      onTap: _loggingOut ? null : _logoutCurrent,
                      trailing: _loggingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: '正在退出',
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      )),
    ]);
  }
}

/// Who is signed in: avatar, name and, for guests, the login action.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.title,
    required this.subtitle,
    required this.avatarUrl,
    this.onTap,
    this.onSwitchAccounts,
    this.action,
  });

  final String title;
  final String? subtitle;
  final String? avatarUrl;

  /// Opens the own profile.
  final VoidCallback? onTap;

  /// Opens the multi-account sheet without leaving the profile affordance.
  final VoidCallback? onSwitchAccounts;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: appSurface(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AccountAvatar(avatarUrl: avatarUrl, size: 56),
                    const SizedBox(width: AppSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(subtitle!, style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    if (onSwitchAccounts != null)
                      IconButton(
                        tooltip: '切换账号',
                        onPressed: onSwitchAccounts,
                        icon: const Icon(Icons.swap_horiz),
                      ),
                    if (onTap != null)
                      Icon(Icons.chevron_right, color: AppColors.textFaint),
                  ],
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpace.lg),
                  action!,
                ],
              ],
            ),
          ),
        ),
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
