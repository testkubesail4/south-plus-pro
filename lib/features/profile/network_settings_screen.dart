import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../services/forum_network_probe.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import 'network_options.dart';
import 'network_setup_flow_screen.dart';
import 'proxy_form.dart';

/// Network settings: the connection mode, the entrance, and the details of
/// the active mode. Every change saves at once.
class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({
    super.key,
    required this.repository,
    this.probe = const ForumNetworkProbe(),
  });

  final ForumRepository repository;
  final ForumNetworkProbe probe;

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  ForumNetworkConfig get _config => widget.repository.networkConfig;

  /// One save at a time, app-wide for this screen and the pages it opens.
  final _saving = ValueNotifier(false);

  /// The status card's test of the config in effect.
  final _check = SingleCheck();

  @override
  void initState() {
    super.initState();
    _saving.addListener(_changed);
    _check.addListener(_changed);
    _runCheck();
  }

  @override
  void dispose() {
    _saving.dispose();
    _check.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _runCheck() {
    final config = _config;
    _check.run((cancellation) async => ProbeReading.site(
        await widget.probe.testConfig(config, cancellation: cancellation)));
  }

  /// The only path to the repository. Throws on failure, with the old
  /// config still in place; a test result of the old config is dropped.
  Future<void> _apply(ForumNetworkConfig config) async {
    if (_saving.value) throw StateError('A save is already running');
    if (config == _config) return;
    _saving.value = true;
    try {
      await widget.repository.updateNetworkConfig(config);
      // A test of the previous settings no longer says anything.
      _check.reset();
    } finally {
      if (mounted) _saving.value = false;
    }
  }

  /// [_apply] for rows: reports failures instead of throwing.
  Future<void> _save(ForumNetworkConfig config) async {
    if (_saving.value) return;
    try {
      await _apply(config);
    } on FormatException catch (error) {
      _snack('无法保存：${error.message}');
    } catch (_) {
      // Raw errors may carry proxy credentials.
      _snack('保存失败，设置未更改');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectMode(ForumNetworkMode mode) async {
    final config = _config;
    if (mode == config.mode) return;
    if (mode == ForumNetworkMode.proxy && config.proxy == null) {
      await _openProxy(thenUseProxy: true);
      return;
    }
    if (config.mode == ForumNetworkMode.proxy &&
        !await confirmDisableProxy(context)) {
      return;
    }
    await _save(config.copyWith(mode: mode));
  }

  Future<void> _openProxy({bool thenUseProxy = false}) async {
    final config = _config;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProxyPage(
        initial: config.proxy,
        // ProxyForm shows its own generic error when these throw.
        onSubmit: (proxy) => _apply(_config.copyWith(
          proxy: proxy,
          // Explicit: editing a saved, unused proxy must not switch to it.
          mode: thenUseProxy ? ForumNetworkMode.proxy : _config.mode,
        )),
        onDelete: config.mode == ForumNetworkMode.proxy
            ? null
            : () => _apply(_config.copyWith(clearProxy: true)),
      ),
    ));
  }

  /// A page whose rows follow the current config and lock while saving.
  Future<void> _openPage(String title,
      Widget Function(ForumNetworkConfig config, bool saving) body) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: _saving,
        builder: (context, saving, _) =>
            NetworkPage(title: title, children: [body(_config, saving)]),
      ),
    ));
  }

  Future<void> _openSites() => _openPage(
        '访问入口',
        (config, saving) => SiteChoiceList(
          config: config,
          probe: widget.probe,
          onSelected:
              saving ? null : (site) => _save(config.copyWith(site: site)),
        ),
      );

  Future<void> _openDoh() => _openPage(
        '加密 DNS',
        (config, saving) => DohChoiceList(
          config: config,
          probe: widget.probe,
          onChanged: saving ? null : _save,
        ),
      );

  Future<void> _openHostAddresses() async {
    final updated =
        await HostAddressesPage.open(context, _config, probe: widget.probe);
    if (updated != null && mounted) await _save(updated);
  }

  Future<void> _openGuide() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NetworkSetupFlowScreen(
        repository: widget.repository,
        probe: widget.probe,
      ),
    ));
    if (!mounted) return;
    _runCheck();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final proxy = config.proxy;
    final gutter = appGutter(MediaQuery.sizeOf(context).width, AppWidths.form);
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络连接'),
        actions: [
          TextButton(
            onPressed: _saving.value ? null : _openGuide,
            child: const Text('重新引导'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xxl),
        children: [
          _StatusCard(
            config: config,
            check: _check,
            onTest: _check.testing ? null : _runCheck,
          ),
          const SizedBox(height: AppSpace.xl),
          AppGroup(
            label: '连接方式',
            description: '三种方式互斥，同一时间只使用一种。',
            children: [
              for (final mode in ForumNetworkMode.values)
                AppRow(
                  icon: networkModeIcon(mode),
                  title: Text(networkModeLabel(mode)),
                  subtitle: Text(mode == ForumNetworkMode.proxy &&
                          proxy != null &&
                          config.mode != mode
                      ? '已保存 ${proxyLabel(proxy)}'
                      : networkModeDescription(mode)),
                  selected: config.mode == mode,
                  onTap: _saving.value ? null : () => _selectMode(mode),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          AppGroup(
            label: '访问入口',
            children: [
              AppRow(
                icon: Icons.language,
                title: Text(config.site.host),
                subtitle: const Text('要访问的论坛域名，与连接方式各自独立'),
                onTap: _saving.value ? null : _openSites,
              ),
            ],
          ),
          if (config.mode == ForumNetworkMode.optimized) ...[
            const SizedBox(height: AppSpace.xl),
            AppGroup(
              label: '网络优化',
              children: [
                AppRow(
                  icon: Icons.shield_outlined,
                  title: const Text('加密 DNS'),
                  value: dohLabel(config),
                  onTap: _saving.value ? null : _openDoh,
                ),
                Ipv6Row(
                  value: config.ipv6Enabled,
                  onChanged: _saving.value
                      ? null
                      : (value) => _save(config.copyWith(ipv6Enabled: value)),
                ),
                AppRow(
                  icon: Icons.pin_drop_outlined,
                  title: const Text('目标地址'),
                  subtitle: Text('为 ${config.site.host} 指定优先尝试的 IP'),
                  value: hostAddressesLabel(config),
                  onTap: _saving.value ? null : _openHostAddresses,
                ),
              ],
            ),
          ],
          if (config.mode == ForumNetworkMode.proxy && proxy != null) ...[
            const SizedBox(height: AppSpace.xl),
            AppGroup(
              label: '代理',
              children: [
                AppRow(
                  icon: Icons.dns_outlined,
                  title: const Text('代理服务器'),
                  value: proxyLabel(proxy),
                  onTap: _saving.value ? null : _openProxy,
                ),
              ],
            ),
          ] else if (proxy != null) ...[
            const SizedBox(height: AppSpace.xl),
            AppGroup(
              label: '已保存的代理',
              children: [
                AppRow(
                  icon: Icons.dns_outlined,
                  title: Text(proxyLabel(proxy)),
                  subtitle: const Text('未使用。可编辑或删除'),
                  onTap: _saving.value ? null : _openProxy,
                ),
              ],
            ),
          ],
          const NetworkNote(externalTrafficNote),
        ],
      ),
    );
  }
}

/// What is configured, and what the last test from this screen showed.
/// Without a test it claims nothing about the connection.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.config,
    required this.check,
    required this.onTest,
  });

  final ForumNetworkConfig config;
  final SingleCheck check;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = check.reading;
    final (Color dot, String status) = check.testing
        ? (AppColors.textFaint, '正在测试…')
        : reading == null
            ? (AppColors.textFaint, '尚未测试当前设置')
            : reading.success
                ? (AppColors.success, '刚才的测试成功 · ${reading.label}')
                : (theme.colorScheme.error, '刚才的测试失败：${reading.label}');
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: appSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(networkModeIcon(config.mode), color: AppColors.brand),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(networkModeLabel(config.mode),
                        style: theme.textTheme.titleLarge),
                    Text(config.site.host, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onTest,
                child: Text(check.testing ? '测试中' : '测试连接'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: dot),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
