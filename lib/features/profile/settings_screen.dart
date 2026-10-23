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
import '../../services/loading_preferences.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import '../home/quick_list_settings_screen.dart';
import 'forum_preferences_screen.dart';
import 'home_boards_settings_screen.dart';
import 'local_user_annotations_screen.dart';
import 'network_options.dart';
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
    setState(() {
      _scopeGeneration++;
      _homeReading = _loadHomeReading();
    });
    scheduleMicrotask(_reloadHomeReading);
  }

  void _reloadHomeReading() {
    if (!mounted) return;
    setState(() {
      _homeReading = _loadHomeReading();
    });
  }

  void _openHomeBoards() {
    final page = HomeBoardsSettingsScreen(repository: widget.repository);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openLocalAnnotations() {
    final page = LocalUserAnnotationsScreen(repository: widget.repository);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
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
        SnackBar(content: Text('检查更新失败，$error')),
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
              Text('当前 v${result.currentVersion}'),
              const SizedBox(height: 4),
              Text('最新 ${release.tagName}'),
              if (release.publishedAt != null) ...[
                const SizedBox(height: 4),
                Text('发布于 ${_formatReleaseDate(release.publishedAt!)}'),
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
              child: Text(result.hasUpdate ? '稍后' : '关闭'),
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
                      builder: (context, mode, _) => _ChoiceRow<ThemeMode>(
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
                      builder: (context, size, _) => _ChoiceRow<ForumTextSize>(
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
                    AppRow(
                      icon: Icons.vertical_align_bottom_outlined,
                      title: const Text('加载与分页'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoadingSettingsScreen(),
                        ),
                      ),
                    ),
                    FutureBuilder<ImageLoadMode>(
                      future: _imageMode,
                      builder: (context, snapshot) {
                        return _ChoiceRow<ImageLoadMode>(
                          icon: Icons.image_outlined,
                          title: '图片加载',
                          value: snapshot.data ?? ImageLoadMode.automatic,
                          options: {
                            for (final mode in ImageLoadMode.values)
                              mode: mode.label,
                          },
                          onChanged: _setImageMode,
                        );
                      },
                    ),
                    FutureBuilder<HomeReadingPreferences>(
                      key: ValueKey((
                        _scopeGeneration,
                        widget.repository.localPreferenceAccount
                      )),
                      future: _homeReading,
                      builder: (context, snapshot) {
                        final rows = snapshot.data?.quickRowCount ?? 8;
                        return AppRow(
                          icon: Icons.view_list_outlined,
                          title: const Text('速览'),
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
                      onTap: _openHomeBoards,
                    ),
                    AppRow(
                      icon: Icons.label_outline,
                      title: const Text('备注与标签'),
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
                      subtitle:
                          Text('${networkModeLabel(networkConfig.mode)} · '
                              '${networkConfig.site.host}'),
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

/// 加载与分页: for each list that pages, whether the next page waits for a
/// tap or follows on by itself.
class LoadingSettingsScreen extends StatefulWidget {
  const LoadingSettingsScreen({super.key});

  @override
  State<LoadingSettingsScreen> createState() => _LoadingSettingsScreenState();
}

class _LoadingSettingsScreenState extends State<LoadingSettingsScreen> {
  late Future<void> _read = _load();

  static const _domains = {
    LoadingDomain.thread: ('帖子楼层', Icons.forum_outlined),
    LoadingDomain.board: ('版块主题列表', Icons.view_list_outlined),
    LoadingDomain.search: ('搜索结果', Icons.search),
    LoadingDomain.favorites: ('收藏夹', Icons.star_outline),
    LoadingDomain.userContent: ('用户主页', Icons.person_outline),
    LoadingDomain.pm: ('短消息与对话', Icons.mail_outline),
    LoadingDomain.friends: ('好友列表', Icons.people_outline),
    LoadingDomain.avatars: ('系统头像', Icons.face_outlined),
  };

  static Future<void> _load() async {
    if (!LoadingPreferences.isReady) await LoadingPreferences.load();
  }

  Future<void> _save(LoadingDomain domain, LoadingMode mode) async {
    try {
      await LoadingPreferences.save(domain, mode);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法保存加载设置')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加载与分页')),
      body: FutureBuilder<void>(
        future: _read,
        builder: (context, snapshot) {
          final failed = snapshot.hasError;
          // Unread choices are not shown or saved over: the lists behave
          // as 手动翻页 until a read succeeds.
          final ready =
              snapshot.connectionState == ConnectionState.done && !failed;
          return ValueListenableBuilder<Map<LoadingDomain, LoadingMode>>(
            valueListenable: LoadingPreferences.notifier,
            builder: (context, modes, _) => ListView(
              padding: EdgeInsets.symmetric(
                horizontal:
                    appGutter(MediaQuery.sizeOf(context).width, AppWidths.form),
                vertical: AppSpace.md,
              ),
              children: [
                if (failed)
                  AppGroup(children: [
                    AppRow(
                      icon: Icons.error_outline,
                      // An error to read, not a disabled row.
                      enabled: true,
                      title: const Text('加载设置读取失败'),
                      subtitle: const Text('读取成功前全部手动翻页'),
                      trailing: TextButton(
                        onPressed: () => setState(() {
                          _read = _load();
                        }),
                        child: const Text('重试'),
                      ),
                    ),
                  ]),
                if (failed) const SizedBox(height: AppSpace.xl),
                AppGroup(
                  label: '自动接续',
                  children: [
                    for (final MapEntry(key: domain, value: (title, icon))
                        in _domains.entries)
                      _LoadingRow(
                        key: ValueKey('loading-${domain.name}'),
                        icon: icon,
                        title: title,
                        continuous: modes[domain] == LoadingMode.continuous,
                        onChanged: ready
                            ? (on) => _save(
                                domain,
                                on
                                    ? LoadingMode.continuous
                                    : LoadingMode.manual)
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A setting with a few short choices: one row showing the current one,
/// opening a menu anchored to it with the current choice checked.
class _ChoiceRow<T> extends StatefulWidget {
  const _ChoiceRow({
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

  /// Saves the choice; throws when it was not saved.
  final Future<void> Function(T) onChanged;

  @override
  State<_ChoiceRow<T>> createState() => _ChoiceRowState<T>();
}

class _ChoiceRowState<T> extends State<_ChoiceRow<T>> {
  final _menu = MenuController();

  // Focus starts on the current option, so keys move from it and Escape
  // closes the menu.
  final _current = FocusNode();

  // The menu is an overlay, not a route: while it is open, back closes it
  // instead of leaving the page.
  var _open = false;

  @override
  void dispose() {
    _current.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_menu.isOpen) return _menu.close();
    _menu.open();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_menu.isOpen) _current.requestFocus();
    });
  }

  // The row keeps showing what is saved; picking again retries.
  Future<void> _choose(T choice) async {
    try {
      await widget.onChanged(choice);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _menu.close();
      },
      child: AppRow(
        icon: w.icon,
        title: Text(w.title),
        value: w.options[w.value],
        // The menu hangs from the trailing end, under the current value.
        trailing: MenuAnchor(
          controller: _menu,
          onOpen: () => setState(() => _open = true),
          onClose: () => setState(() => _open = false),
          menuChildren: [
            for (final MapEntry(:key, value: label) in w.options.entries)
              // Merged, so the option itself is announced as selected.
              MergeSemantics(
                child: Semantics(
                  selected: key == w.value,
                  child: MenuItemButton(
                    focusNode: key == w.value ? _current : null,
                    leadingIcon: Icon(Icons.check,
                        color: key == w.value
                            ? AppColors.brand
                            : Colors.transparent),
                    onPressed: () => _choose(key),
                    child: Text(label),
                  ),
                ),
              ),
          ],
          child: Icon(Icons.unfold_more, color: AppColors.textFaint),
        ),
        onTap: _toggle,
      ),
    );
  }
}

/// One list's paging: on follows on by itself, off waits for a tap.
class _LoadingRow extends StatelessWidget {
  const _LoadingRow({
    super.key,
    required this.icon,
    required this.title,
    required this.continuous,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool continuous;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    // One node for readers: the title, its on/off state and the row's tap.
    return MergeSemantics(
      child: Semantics(
        toggled: continuous,
        enabled: onChanged != null,
        child: AppRow(
          icon: icon,
          title: Text(title),
          enabled: onChanged != null,
          onTap: onChanged == null ? null : () => onChanged!(!continuous),
          trailing: ExcludeSemantics(
              child: Switch(value: continuous, onChanged: onChanged)),
        ),
      ),
    );
  }
}
