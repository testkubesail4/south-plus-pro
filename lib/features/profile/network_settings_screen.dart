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

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
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

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedAddresses());
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
    final selectedFixedAddress = _config.fixedAddress ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络连接'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _Section(
            title: '当前连接',
            subtitle: '${_config.site.host} · '
                '${_config.fixedAddress == null ? _config.dohProvider.label : '固定 IP'}',
            children: [
              _SwitchTile(
                icon: Icons.enhanced_encryption_outlined,
                title: '加密 DNS',
                subtitle: _config.dohEnabled
                    ? '优先使用 DoH，失败后自动尝试其它可用节点'
                    : '使用系统 DNS，仍可手动固定缓存 IP',
                value: _config.dohEnabled,
                onChanged: _saving
                    ? null
                    : (value) => _save(_config.copyWith(dohEnabled: value)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: '固定 IP',
            subtitle: '选中后所有论坛域名都直连这个 IP',
            trailing: IconButton(
              tooltip: '刷新缓存',
              onPressed:
                  _loadingAddresses ? null : () => _loadCachedAddresses(),
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
                    : () => _save(_config.copyWith(clearFixedAddress: true)),
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
                      : () => _save(
                            _config.copyWith(fixedAddress: address.address),
                          ),
                  onTest: () => _testAddress(address),
                  testing: _testingAddresses.contains(address.address),
                );
              }),
            ],
          ),
          const SizedBox(height: 14),
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
                onTap:
                    _saving ? null : () => _save(_config.copyWith(site: site)),
                onTest: () => _testSite(site),
                testing: _testingSites.contains(site.host),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'DoH',
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
                    : () => _save(_config.copyWith(dohProvider: provider)),
                onTest: () => _testDohProvider(provider),
                testing: _testingDoh.contains(provider),
              );
            }).toList(),
          ),
        ],
      ),
    );
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
