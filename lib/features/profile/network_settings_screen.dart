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
  List<InternetAddress> _cachedAddresses = const [];
  bool _loadingAddresses = true;
  bool _testingAddresses = false;
  bool _testingSites = false;
  bool _testingDoh = false;
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

  Future<void> _testSites() async {
    if (_testingSites) return;
    setState(() {
      _testingSites = true;
      _siteResults.clear();
    });
    for (final site in ForumNetworkConfig.sites) {
      final result = await _probe.testSite(
        site,
        dohEnabled: _config.dohEnabled,
        dohProvider: _config.dohProvider,
        fixedAddress: _config.fixedAddress,
      );
      if (!mounted) return;
      setState(() => _siteResults[site.host] = result);
    }
    await _loadCachedAddresses(showLoading: false);
    if (!mounted) return;
    setState(() => _testingSites = false);
  }

  Future<void> _testDoh() async {
    if (_testingDoh) return;
    setState(() {
      _testingDoh = true;
      _dohResults.clear();
    });
    for (final provider in DohProvider.values) {
      final result = await _probe.testDoh(provider);
      if (result.addresses.isNotEmpty) {
        final cached =
            await ForumResolvedAddressStore.mergeAndSave(result.addresses);
        if (mounted) {
          setState(() => _cachedAddresses = cached);
        }
      }
      if (!mounted) return;
      setState(() => _dohResults[provider] = result);
    }
    await _loadCachedAddresses(showLoading: false);
    if (!mounted) return;
    setState(() => _testingDoh = false);
  }

  Future<void> _testAddresses() async {
    if (_testingAddresses) return;
    final addresses = _addressOptions;
    if (addresses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可测速的缓存 IP')),
      );
      return;
    }

    setState(() {
      _testingAddresses = true;
      _addressResults.clear();
    });
    for (final address in addresses) {
      final result = await _probe.testAddress(_config.site, address);
      if (!mounted) return;
      setState(() => _addressResults[address.address] = result);
    }
    if (!mounted) return;
    setState(() => _testingAddresses = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络连接'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _Section(
            title: '当前连接',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用加密 DNS'),
                subtitle: Text(
                  _config.dohEnabled ? '论坛请求会先通过 DoH 解析域名' : '使用系统 DNS 解析域名',
                ),
                value: _config.dohEnabled,
                onChanged: _saving
                    ? null
                    : (value) => _save(_config.copyWith(dohEnabled: value)),
              ),
              RadioGroup<DohProvider>(
                groupValue: _config.dohProvider,
                onChanged: (value) {
                  if (_saving || !_config.dohEnabled || value == null) return;
                  _save(_config.copyWith(dohProvider: value));
                },
                child: Column(
                  children: DohProvider.values
                      .map(
                        (provider) => RadioListTile<DohProvider>(
                          contentPadding: EdgeInsets.zero,
                          value: provider,
                          title: Text(provider.label),
                          subtitle: Text(provider.uri),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: '固定 IP',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '刷新缓存',
                  onPressed:
                      _loadingAddresses ? null : () => _loadCachedAddresses(),
                  icon: _loadingAddresses
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                TextButton.icon(
                  onPressed: _testingAddresses ? null : _testAddresses,
                  icon: _testingAddresses
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed_outlined),
                  label: const Text('测速'),
                ),
              ],
            ),
            children: [
              RadioGroup<String>(
                groupValue: _config.fixedAddress ?? '',
                onChanged: (value) {
                  if (_saving || value == null) return;
                  _save(
                    _config.copyWith(
                      fixedAddress: value,
                      clearFixedAddress: value.isEmpty,
                    ),
                  );
                },
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: '',
                      title: const Text('不固定 IP'),
                      subtitle: const Text('按 DoH、系统 DNS 和备用缓存自动连接'),
                    ),
                    if (_addressOptions.isEmpty)
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.storage_outlined),
                        title: Text('暂无缓存 IP'),
                        subtitle: Text('测试 DoH 或成功访问论坛后会自动记录解析结果'),
                      ),
                    ..._addressOptions.map((address) {
                      final result = _addressResults[address.address];
                      final selected = _config.fixedAddress == address.address;
                      return RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: address.address,
                        title: Text(address.address),
                        subtitle: Text(
                          result == null
                              ? '未测速'
                              : '${result.message} · ${result.latencyLabel}',
                        ),
                        secondary: Icon(
                          selected
                              ? Icons.push_pin
                              : result?.success == false
                                  ? Icons.error_outline
                                  : Icons.dns_outlined,
                          color: selected
                              ? AppColors.brand
                              : result?.success == false
                                  ? Colors.redAccent
                                  : AppColors.textMuted,
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: '域名选择',
            trailing: TextButton.icon(
              onPressed: _testingSites ? null : _testSites,
              icon: _testingSites
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed_outlined),
              label: const Text('测速'),
            ),
            children: [
              RadioGroup<ForumSite>(
                groupValue: _config.site,
                onChanged: (value) {
                  if (_saving || value == null) return;
                  _save(_config.copyWith(site: value));
                },
                child: Column(
                  children: ForumNetworkConfig.sites.map((site) {
                    final result = _siteResults[site.host];
                    final selected = _config.site.host == site.host;
                    return RadioListTile<ForumSite>(
                      contentPadding: EdgeInsets.zero,
                      value: site,
                      title: Text(site.host),
                      subtitle: Text(
                        result == null
                            ? '未测速'
                            : '${result.message} · ${result.latencyLabel}',
                      ),
                      secondary: Icon(
                        selected
                            ? Icons.check_circle
                            : result?.success == false
                                ? Icons.error_outline
                                : Icons.language,
                        color: selected
                            ? AppColors.brand
                            : result?.success == false
                                ? Colors.redAccent
                                : AppColors.textMuted,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'DoH 测试',
            trailing: TextButton.icon(
              onPressed: _testingDoh ? null : _testDoh,
              icon: _testingDoh
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.dns_outlined),
              label: const Text('测试'),
            ),
            children: DohProvider.values.map((provider) {
              final result = _dohResults[provider];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  result?.success == false
                      ? Icons.error_outline
                      : Icons.shield_outlined,
                  color: result?.success == false
                      ? Colors.redAccent
                      : AppColors.brand,
                ),
                title: Text(provider.label),
                subtitle: Text(
                  result == null
                      ? provider.uri
                      : result.addresses.isEmpty
                          ? '${result.message} · ${result.latencyLabel}'
                          : '${result.message} · ${result.latencyLabel} · ${result.addressesLabel}',
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
