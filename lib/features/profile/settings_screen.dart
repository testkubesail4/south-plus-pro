part of 'account_screen.dart';

/// Device-only preferences: network, appearance, images, text size, app.
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
  bool _clearingCache = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    ThreadPagingSettings.load().ignore();
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
    final networkConfig = widget.repository.networkConfig;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
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
              title: '阅读',
              subtitle: '帖子的翻页方式',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ThreadPagingSettings.notifier,
                  builder: (context, autoLoad, _) => MergeSemantics(
                    child: _BaseAccountTile(
                      icon: Icons.vertical_align_bottom_outlined,
                      title: const Text('自动加载下一页'),
                      subtitle: const Text('滑到页尾时自动接上下一页；关闭时用页尾的「下一页」翻页'),
                      onTap: () => _setAutoLoad(!autoLoad),
                      trailing:
                          Switch(value: autoLoad, onChanged: _setAutoLoad),
                    ),
                  ),
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
              title: '字体大小',
              subtitle: '在系统字号基础上调整应用文字',
              children: [
                ValueListenableBuilder<ForumTextSize>(
                  valueListenable: ForumTextSizeSettings.notifier,
                  builder: (context, current, _) {
                    return Column(
                      children: ForumTextSize.values.map((size) {
                        return _SelectableAccountTile(
                          icon: switch (size) {
                            ForumTextSize.small => Icons.text_decrease,
                            ForumTextSize.normal => Icons.text_fields,
                            ForumTextSize.large => Icons.text_increase,
                          },
                          onTap: () => ForumTextSizeSettings.save(size),
                          title: Text(switch (size) {
                            ForumTextSize.small => '小',
                            ForumTextSize.normal => '标准',
                            ForumTextSize.large => '大',
                          }),
                          subtitle:
                              Text('系统字号的 ${(size.scale * 100).round()}%'),
                          selected: current == size,
                        );
                      }).toList(),
                    );
                  },
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
      ),
    );
  }
}
