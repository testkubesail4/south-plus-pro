import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../services/external_link_launcher.dart';
import '../../services/forum_network_setup_store.dart';
import '../../services/forum_repository.dart';
import '../../services/forum_text_size_settings.dart';
import '../../services/home_reading_preferences.dart';
import '../../services/image_loading_settings.dart';
import '../../services/thread_paging_settings.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../home/quick_list_settings_screen.dart';
import 'forum_preferences_screen.dart';
import 'home_boards_settings_screen.dart';
import 'local_user_annotations_screen.dart';
import 'network_settings_screen.dart';
import 'network_setup_flow_screen.dart';

/// Device preferences, by how often they change: 外观 (theme, text size),
/// 阅读 (paging, images), 网络 and 关于.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    this.updateChecker = const UpdateChecker(),
    this.packageInfoLoader = PackageInfo.fromPlatform,
  });

  final ForumRepository repository;
  final UpdateChecker updateChecker;
  final Future<PackageInfo> Function() packageInfoLoader;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<ImageLoadMode> _imageMode = ImageLoadingSettings.loadMode();
  late Future<PackageInfo> _packageInfo = widget.packageInfoLoader();
  late Future<HomeReadingPreferences> _homeReading = _loadHomeReading();
  bool _clearingCache = false;
  bool _checkingUpdate = false;
  int _scopeGeneration = 0;

  @override
  void initState() {
    super.initState();
    ThreadPagingSettings.load().ignore();
    HomeReadingPreferences.revision.addListener(_reloadHomeReading);
    widget.repository.sessionEpoch.addListener(_scopeChanged);
    widget.repository.sessionUser.addListener(_scopeChanged);
  }

  @override
  void dispose() {
    HomeReadingPreferences.revision.removeListener(_reloadHomeReading);
    widget.repository.sessionEpoch.removeListener(_scopeChanged);
    widget.repository.sessionUser.removeListener(_scopeChanged);
    super.dispose();
  }

  void _scopeChanged() {
    if (!mounted) return;
    setState(() { _scopeGeneration++; _homeReading = _loadHomeReading(); });
    scheduleMicrotask(_reloadHomeReading);
  }

  void _reloadHomeReading() {
    if (mounted) setState(() => _homeReading = _loadHomeReading());
  }

  void _openHomeBoards() {
    final page = HomeBoardsSettingsScreen(repository: widget.repository);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openLocalAnnotations() {
    final page = LocalUserAnnotationsScreen(repository: widget.repository);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _setAutoLoad(bool enabled) async {
    try {
      await ThreadPagingSettings.save(enabled);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<HomeReadingPreferences> _loadHomeReading() =>
      HomeReadingPreferences.load(
          account: widget.repository.localPreferenceAccount);

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
                const SizedBox(height: AppSpace.xl),
                Text(
                  _compactReleaseNotes(release.body),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // The third option is a link in the body (DESIGN.md §9).
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.brand,
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _openReleaseLink(release.htmlUrl);
                  },
                  child: const Text('查看版本详情'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(result.hasUpdate ? '稍后' : '知道了'),
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

  Future<void> _chooseImageMode(ImageLoadMode current) async {
    final chosen = await showModalBottomSheet<ImageLoadMode>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg, 0, AppSpace.lg, AppSpace.sm),
                child: Text('图片加载',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final mode in ImageLoadMode.values)
                AppRow(
                  icon: _iconForImageMode(mode),
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                  selected: mode == current,
                  onTap: () => Navigator.of(context).pop(mode),
                ),
              const SizedBox(height: AppSpace.sm),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && chosen != current) await _setImageMode(chosen);
  }

  Future<void> _openNetworkSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NetworkSettingsScreen(repository: widget.repository),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final networkConfig = widget.repository.networkConfig;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = appGutter(constraints.maxWidth, AppWidths.form);
            return ListView(
              padding: EdgeInsets.fromLTRB(
                  gutter, AppSpace.sm, gutter, AppSpace.xxl),
              children: [
                AppGroup(
                  label: '外观',
                  children: [
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: AppThemeController.notifier,
                      builder: (context, mode, _) => _SegmentRow<ThemeMode>(
                        icon: Icons.contrast,
                        title: '主题',
                        value: mode,
                        options: const {
                          ThemeMode.system: '系统',
                          ThemeMode.light: '浅色',
                          ThemeMode.dark: '深色',
                        },
                        onChanged: AppThemeController.setMode,
                      ),
                    ),
                    ValueListenableBuilder<ForumTextSize>(
                      valueListenable: ForumTextSizeSettings.notifier,
                      builder: (context, size, _) => _SegmentRow<ForumTextSize>(
                        icon: Icons.format_size,
                        title: '字体大小',
                        value: size,
                        options: const {
                          ForumTextSize.small: '小',
                          ForumTextSize.normal: '标准',
                          ForumTextSize.large: '大',
                        },
                        onChanged: ForumTextSizeSettings.save,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  label: '阅读',
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: ThreadPagingSettings.notifier,
                      builder: (context, autoLoad, _) => MergeSemantics(
                        child: AppRow(
                          icon: Icons.vertical_align_bottom_outlined,
                          title: const Text('自动加载下一页'),
                          subtitle: const Text('滑到页尾时接上下一页'),
                          onTap: () => _setAutoLoad(!autoLoad),
                          trailing:
                              Switch(value: autoLoad, onChanged: _setAutoLoad),
                        ),
                      ),
                    ),
                    FutureBuilder<ImageLoadMode>(
                      future: _imageMode,
                      builder: (context, snapshot) {
                        final mode = snapshot.data ?? ImageLoadMode.automatic;
                        return AppRow(
                          icon: Icons.image_outlined,
                          title: const Text('图片加载'),
                          value: mode.label,
                          onTap: () => _chooseImageMode(mode),
                        );
                      },
                    ),
                    FutureBuilder<HomeReadingPreferences>(
                      key: ValueKey((_scopeGeneration, widget.repository.localPreferenceAccount)),
                      future: _homeReading,
                      builder: (context, snapshot) {
                        final rows = snapshot.data?.quickRowCount ?? 8;
                        return AppRow(
                          icon: Icons.view_list_outlined,
                          title: const Text('速览'),
                          subtitle: const Text('显示行数与栏目来源'),
                          value: '$rows 行',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => QuickListSettingsScreen(
                                  repository: widget.repository),
                            ),
                          ),
                        );
                      },
                    ),
                    AppRow(
                      icon: Icons.cleaning_services_outlined,
                      title: const Text('清理图片缓存'),
                      value: _clearingCache ? '正在清理…' : null,
                      trailing: const SizedBox.shrink(),
                      onTap: _clearingCache ? null : _clearImageCache,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  label: '个性化',
                  children: [
                    AppRow(
                      icon: Icons.dashboard_outlined,
                      title: const Text('首页版块'),
                      subtitle: const Text('分区顺序与显示、版块隐藏'),
                      onTap: _openHomeBoards,
                    ),
                    AppRow(
                      icon: Icons.label_outline,
                      title: const Text('备注与标签'),
                      subtitle: const Text('仅本机保存，按当前账号区分'),
                      onTap: _openLocalAnnotations,
                    ),
                  ],
                ),
                if (widget.repository.isLoggedIn) ...[
                  const SizedBox(height: AppSpace.xl),
                  AppGroup(
                    label: '账号',
                    children: [
                      AppRow(
                        icon: Icons.tune_outlined,
                        title: const Text('论坛偏好'),
                        subtitle: const Text('短消息黑名单、好友和个人设置'),
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ForumPreferencesScreen(
                              repository: widget.repository),
                        )),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  label: '网络',
                  children: [
                    AppRow(
                      icon: Icons.public_outlined,
                      title: const Text('连接设置'),
                      subtitle: Text('${networkConfig.site.host} · '
                          '${networkConfig.dohEnabled ? '加密解析' : '系统解析'}'),
                      onTap: _openNetworkSettings,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                AppGroup(
                  label: '关于',
                  children: [
                    FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snapshot) {
                        final info = snapshot.data;
                        return AppRow(
                          icon: Icons.info_outline,
                          title: const Text('版本'),
                          // Static information, not a disabled control.
                          enabled: true,
                          value: info == null
                              ? '…'
                              : 'v${info.version}+${info.buildNumber}',
                        );
                      },
                    ),
                    AppRow(
                      icon: Icons.system_update_alt_outlined,
                      title: const Text('检查更新'),
                      value: _checkingUpdate ? '正在检查…' : null,
                      onTap: _checkingUpdate ? null : _checkForUpdate,
                    ),
                    if (kDebugMode)
                      AppRow(
                        icon: Icons.bug_report_outlined,
                        title: const Text('重置网络引导'),
                        onTap: _resetNetworkSetupAndOpen,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
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

/// A setting with a few short choices: the title row, then a full-width
/// segmented control (DESIGN.md §7).
class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textMuted),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(:key, value: label) in options.entries)
                ButtonSegment(value: key, label: Text(label)),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.single),
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
