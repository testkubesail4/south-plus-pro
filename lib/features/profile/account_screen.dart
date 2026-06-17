import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_network_setup_store.dart';
import '../../services/image_loading_settings.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/cached_forum_image.dart';
import 'forum_tasks_screen.dart';
import 'network_setup_flow_screen.dart';
import 'network_settings_screen.dart';
import 'user_profile_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    required this.onLoggedOut,
    this.updateChecker = const UpdateChecker(),
    this.packageInfoLoader = PackageInfo.fromPlatform,
  });

  final ForumRepository repository;
  final VoidCallback onLoggedOut;
  final UpdateChecker updateChecker;
  final Future<PackageInfo> Function() packageInfoLoader;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<ImageLoadMode> _imageMode = ImageLoadingSettings.loadMode();
  late Future<PackageInfo> _packageInfo = widget.packageInfoLoader();
  bool _clearingCache = false;
  bool _checkingUpdate = false;

  Future<void> _setImageMode(ImageLoadMode mode) async {
    await ImageLoadingSettings.saveMode(mode);
    if (!mounted) return;
    setState(() {
      _imageMode = Future<ImageLoadMode>.value(mode);
    });
  }

  Future<void> _clearImageCache() async {
    setState(() => _clearingCache = true);
    await ForumImageCache.manager.emptyCache();
    if (!mounted) return;
    setState(() => _clearingCache = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片缓存已清理')),
    );
  }

  Future<void> _logout() async {
    await widget.repository.clearSession();
    if (!mounted) return;
    widget.onLoggedOut();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  Future<void> _openNetworkSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NetworkSetupFlowScreen(
          repository: widget.repository,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _resetNetworkSetupAndOpen() async {
    await ForumNetworkSetupStore.reset();
    if (!mounted) return;
    await _openNetworkSetup();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final packageInfo = await _packageInfo;
      final result = await widget.updateChecker.check(
        currentVersion: packageInfo.version,
      );
      if (!mounted) return;
      await _showUpdateResult(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败：$error')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _showUpdateResult(UpdateCheckResult result) {
    final release = result.release;
    final downloadUrl = release.downloadUrlForPlatform();
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(result.hasUpdate ? '发现新版本' : '已是最新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本：v${result.currentVersion}'),
              const SizedBox(height: 4),
              Text('最新版本：${release.tagName}'),
              if (release.publishedAt != null) ...[
                const SizedBox(height: 4),
                Text('发布时间：${_formatReleaseDate(release.publishedAt!)}'),
              ],
              if (release.body.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  _compactReleaseNotes(release.body),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(result.hasUpdate ? '稍后' : '知道了'),
            ),
            TextButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _openReleaseLink(release.htmlUrl);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('版本详情'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _openReleaseLink(downloadUrl);
              },
              icon: Icon(
                result.hasUpdate ? Icons.download_outlined : Icons.open_in_new,
              ),
              label: Text(result.hasUpdate ? '下载新版' : '打开下载页'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openReleaseLink(String url) async {
    try {
      await ExternalLinkLauncher.open(url);
    } on ExternalLinkLaunchException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.repository.currentUsername;
    final networkConfig = widget.repository.networkConfig;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _AccountHeader(
            title: username ?? '未登录',
            subtitle:
                widget.repository.isLoggedIn ? '南+账号已连接' : '登录后可查看个人内容和收藏',
            loggedIn: widget.repository.isLoggedIn,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatusSummaryTile(
                  icon: Icons.public_outlined,
                  label: '访问入口',
                  value: networkConfig.site.host,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatusSummaryTile(
                  icon: networkConfig.dohEnabled
                      ? Icons.enhanced_encryption_outlined
                      : Icons.dns_outlined,
                  label: '解析方式',
                  value: networkConfig.dohEnabled ? '加密解析' : '系统默认',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AccountSection(
            title: '账号',
            subtitle: '管理登录状态和个人内容入口',
            children: [
              _AccountTile(
                icon: Icons.person_outline,
                title: widget.repository.isLoggedIn ? '个人中心' : '登录',
                subtitle:
                    widget.repository.isLoggedIn ? '资料、主题、回复、收藏' : '登录南+账号',
                accent: widget.repository.isLoggedIn,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => widget.repository.isLoggedIn
                        ? UserProfileScreen(
                            userUrl: 'u.php',
                            repository: widget.repository,
                          )
                        : LoginScreen(
                            repository: widget.repository,
                          ),
                  ),
                ),
              ),
              _AccountTile(
                icon: Icons.fact_check_outlined,
                title: '论坛任务',
                subtitle: widget.repository.isLoggedIn
                    ? '申请日常、周常并领取奖励'
                    : '登录后领取 SP 币任务奖励',
                accent: widget.repository.isLoggedIn,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ForumTasksScreen(
                      repository: widget.repository,
                    ),
                  ),
                ),
              ),
              if (widget.repository.isLoggedIn)
                _AccountTile(
                  icon: Icons.logout,
                  title: '退出登录',
                  subtitle: '清除本地登录状态',
                  danger: true,
                  onTap: _logout,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _AccountSection(
            title: '网络',
            subtitle: '调整访问入口、解析方式和连接探测',
            children: [
              _AccountTile(
                icon: Icons.public_outlined,
                title: '连接设置',
                subtitle:
                    '${networkConfig.site.host} · ${networkConfig.dohEnabled ? '加密解析' : '系统默认解析'}',
                accent: true,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NetworkSettingsScreen(
                        repository: widget.repository,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  setState(() {});
                },
              ),
              _AccountTile(
                icon: Icons.auto_fix_high_outlined,
                title: '连接引导',
                subtitle: '重新探测解析线路、访问入口和直连线路',
                onTap: _openNetworkSetup,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AccountSection(
            title: '界面设置',
            subtitle: '选择应用配色偏好',
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppThemeController.notifier,
                builder: (context, themeMode, _) {
                  return Column(
                    children: ThemeMode.values.map((mode) {
                      return _SelectableAccountTile(
                        icon: _iconForThemeMode(mode),
                        onTap: () => AppThemeController.setMode(mode),
                        title: Text(_labelForThemeMode(mode)),
                        subtitle: Text(_descriptionForThemeMode(mode)),
                        selected: themeMode == mode,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AccountSection(
            title: '图片与流量',
            subtitle: '控制帖子图片的加载策略和本地缓存',
            children: [
              FutureBuilder<ImageLoadMode>(
                future: _imageMode,
                builder: (context, snapshot) {
                  final mode = snapshot.data ?? ImageLoadMode.automatic;
                  return Column(
                    children: ImageLoadMode.values.map((item) {
                      final selected = item == mode;
                      return _SelectableAccountTile(
                        icon: _iconForImageMode(item),
                        onTap: () => _setImageMode(item),
                        title: Text(item.label),
                        subtitle: Text(item.description),
                        selected: selected,
                      );
                    }).toList(),
                  );
                },
              ),
              _AccountTile(
                icon: Icons.cleaning_services_outlined,
                title: '清理图片缓存',
                subtitle: _clearingCache ? '正在清理...' : '释放本地图片缓存空间',
                onTap: _clearingCache ? null : _clearImageCache,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _AccountSection(
            title: '应用',
            subtitle: '版本信息和开发调试入口',
            children: [
              FutureBuilder<PackageInfo>(
                future: _packageInfo,
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  return _StaticInfoTile(
                    icon: Icons.info_outline,
                    title: '南+',
                    subtitle: info == null
                        ? '正在读取版本信息'
                        : 'v${info.version}+${info.buildNumber}',
                  );
                },
              ),
              _AccountTile(
                icon: Icons.system_update_alt_outlined,
                title: '检查更新',
                subtitle:
                    _checkingUpdate ? '正在检查 GitHub Releases' : '查看是否有新版本可下载',
                accent: true,
                onTap: _checkingUpdate ? null : _checkForUpdate,
              ),
              if (kDebugMode)
                _AccountTile(
                  icon: Icons.bug_report_outlined,
                  title: '重置网络引导',
                  subtitle: '调试首次启动引导流程',
                  onTap: _resetNetworkSetupAndOpen,
                ),
            ],
          ),
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
    required this.loggedIn,
  });

  final String title;
  final String subtitle;
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFD6DB)),
            ),
            child: Icon(
              Icons.account_circle_outlined,
              color: AppColors.brand,
              size: 30,
            ),
          ),
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
    this.accent = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool accent;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return _BaseAccountTile(
      icon: icon,
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
      accent: accent,
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
      accent: selected,
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
    this.accent = false,
    this.danger = false,
  });

  final IconData icon;
  final Widget title;
  final Widget subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool accent;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconColor = danger
        ? AppColors.brandDark
        : accent
            ? AppColors.brand
            : AppColors.link;
    final iconBackground = danger
        ? AppColors.brandSoft
        : accent
            ? AppColors.brandSoft
            : AppColors.inkSoft;
    final titleColor = danger ? AppColors.brandDark : AppColors.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 74),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: enabled ? iconBackground : AppColors.inkSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: enabled ? iconColor : AppColors.textFaint,
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: titleColor,
                            ),
                        child: title,
                      ),
                      const SizedBox(height: 3),
                      DefaultTextStyle.merge(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
              Icon(icon, size: 17, color: AppColors.link),
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
