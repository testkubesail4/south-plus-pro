import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../services/forum_network_probe.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({
    super.key,
    required this.repository,
  });

  final ForumRepository repository;

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen>
    with SingleTickerProviderStateMixin {
  late ForumNetworkConfig _config = widget.repository.networkConfig;
  final ForumNetworkProbe _probe = const ForumNetworkProbe();
  final Map<String, ForumSiteProbeResult> _siteResults = {};
  final Map<DohProvider, DohProbeResult> _dohResults = {};
  final Map<String, ForumAddressProbeResult> _addressResults = {};
  final Set<String> _testingSites = {};
  final Set<DohProvider> _testingDoh = {};
  final Set<String> _testingAddresses = {};
  List<InternetAddress> _cachedAddresses = const [];
  bool _loadingAddresses = true;
  bool _saving = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    unawaited(_loadCachedAddresses());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<InternetAddress> get _addressOptions {
    final options = <InternetAddress>[];
    final seen = <String>{};
    final fixedAddress = _config.fixedInternetAddress;
    if (fixedAddress != null && seen.add(fixedAddress.address)) {
      options.add(fixedAddress);
    }
    for (final address in _cachedAddresses) {
      if (seen.add(address.address)) options.add(address);
    }
    return options;
  }

  Future<void> _loadCachedAddresses({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loadingAddresses = true);
    }
    final addresses = await ForumResolvedAddressStore.load();
    if (!mounted) return;
    setState(() {
      _cachedAddresses = addresses;
      _loadingAddresses = false;
      final available =
          _addressOptions.map((address) => address.address).toSet();
      _addressResults.removeWhere((address, _) => !available.contains(address));
    });
  }

  Future<void> _save(ForumNetworkConfig config) async {
    setState(() {
      _saving = true;
      _config = config;
    });
    try {
      await widget.repository.updateNetworkConfig(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网络设置已保存')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _config = widget.repository.networkConfig);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSite(ForumSite site) async {
    if (_testingSites.contains(site.host)) return;
    setState(() => _testingSites.add(site.host));
    final result = await _probe.testSite(
      site,
      dohEnabled: _config.dohEnabled,
      dohProvider: _config.dohProvider,
      fixedAddress: _config.fixedAddress,
    );
    await _loadCachedAddresses(showLoading: false);
    if (!mounted) return;
    setState(() {
      _siteResults[site.host] = result;
      _testingSites.remove(site.host);
    });
  }

  Future<void> _testDohProvider(DohProvider provider) async {
    if (_testingDoh.contains(provider)) return;
    setState(() => _testingDoh.add(provider));
    final result = await _probe.testDoh(provider);
    if (result.addresses.isNotEmpty) {
      final cached =
          await ForumResolvedAddressStore.mergeAndSave(result.addresses);
      if (mounted) setState(() => _cachedAddresses = cached);
    }
    if (!mounted) return;
    setState(() {
      _dohResults[provider] = result;
      _testingDoh.remove(provider);
    });
  }

  Future<void> _testAddress(InternetAddress address) async {
    if (_testingAddresses.contains(address.address)) return;
    setState(() => _testingAddresses.add(address.address));
    final result = await _probe.testAddress(_config.site, address);
    if (!mounted) return;
    setState(() {
      _addressResults[address.address] = result;
      _testingAddresses.remove(address.address);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fixedAddress = _config.fixedInternetAddress?.address;
    final priorityTitle = fixedAddress != null
        ? '固定 IP'
        : _config.dohEnabled
            ? 'DoH'
            : '域名';
    final priorityValue = fixedAddress ??
        (_config.dohEnabled ? _config.dohProvider.label : _config.site.host);
    final priorityStatus = _priorityStatus;

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络连接'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _ConnectionOverviewCard(
            controller: _pulseController,
            title: '当前最优先',
            mode: priorityTitle,
            value: priorityValue,
            host: _config.site.host,
            status: priorityStatus,
            stable: priorityStatus?.success ?? true,
          ),
          const SizedBox(height: 14),
          _ConnectionEntryTile(
            icon: Icons.route_outlined,
            title: '固定 IP',
            subtitle: fixedAddress == null ? '未固定，自动选择连接线路' : fixedAddress,
            status: _fixedAddressStatus,
            active: fixedAddress != null,
            badgeLabel: fixedAddress == null ? '自动' : '已固定',
            onTap: () => _openFixedAddressPage(context),
          ),
          const SizedBox(height: 10),
          _ConnectionEntryTile(
            icon: Icons.language,
            title: '域名',
            subtitle: _config.site.host,
            status: _siteStatus,
            active: fixedAddress == null,
            badgeLabel: '已选',
            onTap: () => _openSitePage(context),
          ),
          const SizedBox(height: 10),
          _ConnectionEntryTile(
            icon: Icons.shield_outlined,
            title: 'DoH',
            subtitle: _config.dohEnabled ? _config.dohProvider.label : '已关闭',
            status: _dohStatus,
            active: fixedAddress == null && _config.dohEnabled,
            badgeLabel: _config.dohEnabled ? '已启用' : '已关闭',
            onTap: () => _openDohPage(context),
          ),
        ],
      ),
    );
  }

  _ProbeStatus? get _fixedAddressStatus {
    final address = _config.fixedInternetAddress?.address;
    return address == null ? null : _probeStatus(_addressResults[address]);
  }

  _ProbeStatus? get _siteStatus =>
      _probeStatus(_siteResults[_config.site.host]);

  _ProbeStatus? get _dohStatus =>
      _probeStatus(_dohResults[_config.dohProvider]);

  _ProbeStatus? get _priorityStatus {
    final fixedAddress = _config.fixedInternetAddress?.address;
    if (fixedAddress != null)
      return _probeStatus(_addressResults[fixedAddress]);
    if (_config.dohEnabled)
      return _probeStatus(_dohResults[_config.dohProvider]);
    return _probeStatus(_siteResults[_config.site.host]);
  }

  Future<void> _openFixedAddressPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SelectionPage(
          title: '固定 IP',
          subtitle: '选中后所有论坛域名都直连这个 IP',
          builder: (context, refresh) => _buildFixedAddressOptions(refresh),
        ),
      ),
    );
  }

  Future<void> _openSitePage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SelectionPage(
          title: '域名',
          subtitle: '选择当前论坛镜像',
          builder: (context, refresh) => _buildSiteOptions(refresh),
        ),
      ),
    );
  }

  Future<void> _openDohPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SelectionPage(
          title: 'DoH',
          subtitle: '当前选择优先，失败后自动尝试其它节点',
          builder: (context, refresh) => _buildDohOptions(refresh),
        ),
      ),
    );
  }

  List<Widget> _buildFixedAddressOptions(VoidCallback refresh) {
    final selectedFixedAddress = _config.fixedAddress ?? '';

    return [
      _Section(
        title: '固定 IP',
        subtitle: '选中后所有论坛域名都直连这个 IP',
        trailing: IconButton(
          tooltip: '刷新缓存',
          onPressed: _loadingAddresses
              ? null
              : () async {
                  await _loadCachedAddresses();
                  refresh();
                },
          icon: _loadingAddresses
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
        children: [
          _NetworkOptionTile(
            icon: Icons.route_outlined,
            title: '自动选择',
            subtitle: '按 DoH、系统 DNS 和备用缓存自动连接',
            selected: selectedFixedAddress.isEmpty,
            onTap: _saving
                ? null
                : () async {
                    await _save(_config.copyWith(clearFixedAddress: true));
                    refresh();
                  },
          ),
          if (_addressOptions.isEmpty)
            const _EmptyTile(
              icon: Icons.storage_outlined,
              title: '暂无缓存 IP',
              subtitle: '访问论坛或测试 DoH 后会自动记录解析结果',
            ),
          ..._addressOptions.map((address) {
            final result = _addressResults[address.address];
            return _NetworkOptionTile(
              icon: Icons.dns_outlined,
              title: address.address,
              subtitle: '用于 ${_config.site.host}',
              selected: selectedFixedAddress == address.address,
              status: _probeStatus(result),
              onTap: _saving
                  ? null
                  : () async {
                      await _save(
                        _config.copyWith(fixedAddress: address.address),
                      );
                      refresh();
                    },
              onTest: () async {
                await _testAddress(address);
                refresh();
              },
              testing: _testingAddresses.contains(address.address),
            );
          }),
        ],
      ),
    ];
  }

  List<Widget> _buildSiteOptions(VoidCallback refresh) {
    return [
      _Section(
        title: '域名',
        subtitle: '选择当前论坛镜像',
        children: ForumNetworkConfig.sites.map((site) {
          final result = _siteResults[site.host];
          return _NetworkOptionTile(
            icon: Icons.language,
            title: site.host,
            subtitle: site.baseUri.toString(),
            selected: _config.site == site,
            status: _probeStatus(result),
            onTap: _saving
                ? null
                : () async {
                    await _save(_config.copyWith(site: site));
                    refresh();
                  },
            onTest: () async {
              await _testSite(site);
              refresh();
            },
            testing: _testingSites.contains(site.host),
          );
        }).toList(),
      ),
    ];
  }

  List<Widget> _buildDohOptions(VoidCallback refresh) {
    return [
      _Section(
        title: '加密 DNS',
        subtitle: _config.dohEnabled
            ? '优先使用 DoH，失败后自动尝试其它可用节点'
            : '使用系统 DNS，仍可手动固定缓存 IP',
        children: [
          _SwitchTile(
            icon: Icons.enhanced_encryption_outlined,
            title: '启用 DoH',
            subtitle: _config.dohEnabled ? '当前已启用加密解析' : '当前使用系统 DNS',
            value: _config.dohEnabled,
            onChanged: _saving
                ? null
                : (value) async {
                    await _save(_config.copyWith(dohEnabled: value));
                    refresh();
                  },
          ),
        ],
      ),
      const SizedBox(height: 14),
      _Section(
        title: 'DoH 节点',
        subtitle: '当前选择优先，失败后自动尝试其它节点',
        children: DohProvider.values.map((provider) {
          final result = _dohResults[provider];
          final subtitle = result == null || result.addresses.isEmpty
              ? provider.uri
              : '${provider.uri}\n${result.addressesLabel}';
          return _NetworkOptionTile(
            icon: Icons.shield_outlined,
            title: provider.label,
            subtitle: subtitle,
            selected: _config.dohProvider == provider,
            enabled: _config.dohEnabled,
            status: _probeStatus(result),
            onTap: _saving || !_config.dohEnabled
                ? null
                : () async {
                    await _save(_config.copyWith(dohProvider: provider));
                    refresh();
                  },
            onTest: () async {
              await _testDohProvider(provider);
              refresh();
            },
            testing: _testingDoh.contains(provider),
          );
        }).toList(),
      ),
    ];
  }

  _ProbeStatus? _probeStatus(dynamic result) {
    if (result == null) return null;
    final success = result.success as bool;
    return _ProbeStatus(
      label: success ? result.latencyLabel as String : result.message as String,
      success: success,
    );
  }
}

class _ProbeStatus {
  const _ProbeStatus({
    required this.label,
    required this.success,
  });

  final String label;
  final bool success;
}

class _SelectionPage extends StatefulWidget {
  const _SelectionPage({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final List<Widget> Function(BuildContext context, VoidCallback refresh)
      builder;

  @override
  State<_SelectionPage> createState() => _SelectionPageState();
}

class _SelectionPageState extends State<_SelectionPage> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: Text(
              widget.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ...widget.builder(context, _refresh),
        ],
      ),
    );
  }
}

class _ConnectionOverviewCard extends StatelessWidget {
  const _ConnectionOverviewCard({
    required this.controller,
    required this.title,
    required this.mode,
    required this.value,
    required this.host,
    required this.stable,
    this.status,
  });

  final AnimationController controller;
  final String title;
  final String mode;
  final String value;
  final String host;
  final bool stable;
  final _ProbeStatus? status;

  @override
  Widget build(BuildContext context) {
    final statusText = status == null
        ? '连接稳定'
        : status!.success
            ? '连接稳定 · ${status!.label}'
            : status!.label;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SignalLight(controller: controller, stable: stable),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      mode,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              _StatusPill(
                status: _ProbeStatus(label: statusText, success: stable),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '当前域名 $host',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ConnectionEntryTile extends StatelessWidget {
  const _ConnectionEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
    this.badgeLabel,
    this.status,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;
  final String? badgeLabel;
  final _ProbeStatus? status;

  @override
  Widget build(BuildContext context) {
    final statusLabel =
        status == null ? badgeLabel ?? (active ? '已应用' : '可配置') : status!.label;
    final statusSuccess = status?.success ?? true;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.brand : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              _LeadingIcon(icon: icon, active: active),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        _StatusPill(
                          status: _ProbeStatus(
                            label: statusLabel,
                            success: statusSuccess,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalLight extends StatelessWidget {
  const _SignalLight({
    required this.controller,
    required this.stable,
  });

  final AnimationController controller;
  final bool stable;

  @override
  Widget build(BuildContext context) {
    final color = stable ? const Color(0xFF16A34A) : const Color(0xFFB93445);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final pulse = stable ? controller.value : 0.0;
        return SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 0.75 + pulse * 0.45,
                child: Opacity(
                  opacity: stable ? 0.24 * (1 - pulse) : 0.16,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.38),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dividedChildren = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        dividedChildren.add(const Divider(indent: 58, endIndent: 12));
      }
      dividedChildren.add(children[index]);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          ...dividedChildren,
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Row(
        children: [
          _LeadingIcon(icon: icon, active: value),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _NetworkOptionTile extends StatelessWidget {
  const _NetworkOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.enabled = true,
    this.status,
    this.onTap,
    this.onTest,
    this.testing = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final _ProbeStatus? status;
  final VoidCallback? onTap;
  final VoidCallback? onTest;
  final bool testing;

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                _LeadingIcon(icon: icon, active: selected, enabled: enabled),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: enabled
                                        ? AppColors.text
                                        : AppColors.textFaint,
                                  ),
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(width: 8),
                            _StatusPill(status: status!),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: enabled
                                  ? AppColors.textMuted
                                  : AppColors.textFaint,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked_outlined,
                  size: 22,
                  color: selected ? AppColors.brand : AppColors.textFaint,
                ),
                if (onTest != null) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: '测速',
                    onPressed: testing ? null : onTest,
                    icon: testing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.speed_outlined),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          _LeadingIcon(icon: icon, active: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
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

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.icon,
    required this.active,
    this.enabled = true,
  });

  final IconData icon;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textFaint
        : active
            ? AppColors.brand
            : AppColors.link;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: active ? AppColors.brandSoft : AppColors.inkSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
  });

  final _ProbeStatus status;

  @override
  Widget build(BuildContext context) {
    final color =
        status.success ? const Color(0xFF168A46) : AppColors.brandDark;
    final background =
        status.success ? const Color(0xFFEAF7EF) : AppColors.brandSoft;
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
