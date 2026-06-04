import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../services/forum_repository.dart';
import '../../services/forum_network_setup_store.dart';
import '../../services/image_loading_settings.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../common/cached_forum_image.dart';
import 'network_setup_flow_screen.dart';
import 'network_settings_screen.dart';
import 'user_profile_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    required this.onLoggedOut,
  });

  final ForumRepository repository;
  final VoidCallback onLoggedOut;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<ImageLoadMode> _imageMode = ImageLoadingSettings.loadMode();
  bool _clearingCache = false;

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

  @override
  Widget build(BuildContext context) {
    final username = widget.repository.currentUsername;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _AccountHeader(
            title: username ?? '未登录',
            subtitle: widget.repository.isLoggedIn
                ? 'South Plus 账号已连接'
                : '登录后可查看个人内容和收藏',
          ),
          const SizedBox(height: 14),
          _AccountSection(
            title: '账号',
            children: [
              _AccountTile(
                icon: Icons.person_outline,
                title: widget.repository.isLoggedIn ? '个人中心' : '登录',
                subtitle: widget.repository.isLoggedIn
                    ? '资料、主题、回复、收藏'
                    : '登录 South Plus 账号',
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
              if (widget.repository.isLoggedIn)
                _AccountTile(
                  icon: Icons.logout,
                  title: '退出登录',
                  subtitle: '清除本地登录状态',
                  onTap: _logout,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _AccountSection(
            title: '网络',
            children: [
              _AccountTile(
                icon: Icons.public_outlined,
                title: '连接设置',
                subtitle:
                    '${widget.repository.networkConfig.site.host} · ${widget.repository.networkConfig.dohEnabled ? '加密解析' : '系统默认解析'}',
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
            title: '图片与流量',
            children: [
              FutureBuilder<ImageLoadMode>(
                future: _imageMode,
                builder: (context, snapshot) {
                  final mode = snapshot.data ?? ImageLoadMode.automatic;
                  return Column(
                    children: ImageLoadMode.values.map((item) {
                      final selected = item == mode;
                      return ListTile(
                        onTap: () => _setImageMode(item),
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.label),
                        subtitle: Text(item.description),
                        trailing: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color:
                              selected ? AppColors.brand : AppColors.textFaint,
                        ),
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
            children: [
              const _StaticInfoTile(
                icon: Icons.info_outline,
                title: 'South Plus Rewrite',
                subtitle: 'v0.1.3',
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

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      leading: Icon(icon, color: AppColors.brand),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
    return ListTile(
      leading: Icon(icon, color: AppColors.brand),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
