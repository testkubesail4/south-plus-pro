import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../services/forum_network_probe.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import 'network_setup_flow_screen.dart';

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
  final Map<String, DohProbeResult> _customDohResults = {};
  final Map<String, ForumAddressProbeResult> _addressResults = {};
  final Set<String> _testingSites = {};
  final Set<DohProvider> _testingDoh = {};
  final Set<String> _testingCustomDoh = {};
  final Set<String> _testingAddresses = {};
  List<ForumSite> _customSites = const [];
  List<String> _customDohUris = const [];
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
    unawaited(_loadCustomOptions());
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

  Future<void> _loadCustomOptions() async {
    final sites = ForumNetworkConfig.sites.contains(_config.site)
        ? await ForumNetworkSettings.loadCustomSites()
        : await ForumNetworkSettings.addCustomSite(_config.site);
    final currentCustomDoh = _config.normalizedCustomDohUri;
    final dohUris = currentCustomDoh == null
        ? await ForumNetworkSettings.loadCustomDohUris()
        : await ForumNetworkSettings.addCustomDohUri(currentCustomDoh);
    if (!mounted) return;
    setState(() {
      _customSites = sites;
      _customDohUris = dohUris;
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
      customDohUri: _config.normalizedCustomDohUri,
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

  Future<DohProbeResult> _testCustomDoh(String uri) async {
    final normalized = _normalizeDohInput(uri);
    if (normalized == null) {
      return const DohProbeResult(
        elapsed: Duration.zero,
        success: false,
        message: '请输入 https 开头的加密 DNS 地址',
        addresses: [],
      );
    }
    if (_testingCustomDoh.contains(normalized)) {
      return _customDohResults[normalized] ??
          const DohProbeResult(
            elapsed: Duration.zero,
            success: false,
            message: '正在测速',
            addresses: [],
          );
    }
    setState(() => _testingCustomDoh.add(normalized));
    final result = await _probe.testCustomDoh(normalized);
    if (result.addresses.isNotEmpty) {
      final cached =
          await ForumResolvedAddressStore.mergeAndSave(result.addresses);
      if (mounted) setState(() => _cachedAddresses = cached);
    }
    if (mounted) {
      setState(() {
        _customDohResults[normalized] = result;
        _testingCustomDoh.remove(normalized);
      });
    }
    return result;
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
        ? '专属线路'
        : _config.dohEnabled
            ? '加密 DNS'
            : '系统默认解析';
    final priorityStatus = _priorityStatus;
    final primaryLabel = fixedAddress != null
        ? '线路选择'
        : (_config.dohEnabled ? '加密 DNS' : '解析方式');
    final primaryValue = fixedAddress != null
        ? ForumNetworkConfig.routeLabelForAddress(fixedAddress, 1)
        : (_config.dohEnabled ? _config.dohLabel : '系统默认解析');

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络连接'),
        actions: [
          TextButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NetworkSetupFlowScreen(
                          repository: widget.repository,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    setState(() {
                      _config = widget.repository.networkConfig;
                    });
                  },
            icon: Icon(Icons.auto_fix_high_outlined),
            label: const Text('引导'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _ConnectionOverviewCard(
            controller: _pulseController,
            title: '当前最优先',
            mode: priorityTitle,
            primaryLabel: primaryLabel,
            primaryValue: primaryValue,
            site: _config.site.host,
            status: priorityStatus,
            stable: priorityStatus?.success ?? true,
          ),
          const SizedBox(height: 14),
          _ConnectionSwitchCard(
            value: _config.dohEnabled,
            saving: _saving,
            onChanged: (value) => _save(_config.copyWith(dohEnabled: value)),
          ),
          const SizedBox(height: 10),
          _ConnectionEntryTile(
            icon: Icons.route_outlined,
            title: '线路选择',
            subtitle: fixedAddress == null
                ? '智能优选（推荐）'
                : ForumNetworkConfig.routeLabelForAddress(fixedAddress, 1),
            status: _fixedAddressStatus,
            active: true,
            badgeLabel: fixedAddress == null ? '智能' : '专属',
            onTap: () => _openFixedAddressPage(context),
          ),
          const SizedBox(height: 10),
          _ConnectionEntryTile(
            icon: Icons.language,
            title: '访问入口',
            subtitle: _config.site.host,
            status: _siteStatus,
            active: true,
            badgeLabel: '已选',
            onTap: () => _openSitePage(context),
          ),
          const SizedBox(height: 10),
          _ConnectionEntryTile(
            icon: Icons.shield_outlined,
            title: '加密 DNS',
            subtitle: _config.dohEnabled ? _config.dohLabel : '系统默认解析',
            status: _dohStatus,
            active: true,
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
      _probeStatus(_config.normalizedCustomDohUri == null
          ? _dohResults[_config.dohProvider]
          : _customDohResults[_config.normalizedCustomDohUri]);

  _ProbeStatus? get _priorityStatus {
    final fixedAddress = _config.fixedInternetAddress?.address;
    if (fixedAddress != null)
      return _probeStatus(_addressResults[fixedAddress]);
    if (_config.dohEnabled) return _dohStatus;
    return _probeStatus(_siteResults[_config.site.host]);
  }

  Future<void> _openFixedAddressPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SelectionPage(
          title: '线路选择',
          subtitle: '智能优选适合大多数情况，专属线路适合备用。',
          actionBuilder: (context, refresh) => IconButton(
            tooltip: '添加专属线路',
            onPressed: _saving ? null : () => _openManualAddressPage(refresh),
            icon: Icon(Icons.add),
          ),
          builder: (context, refresh) => _buildFixedAddressOptions(refresh),
        ),
      ),
    );
  }

  Future<void> _openSitePage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SelectionPage(
          title: '访问入口',
          subtitle: '选择当前访问域名，也可以手动输入。',
          actionBuilder: (context, refresh) => IconButton(
            tooltip: '添加访问入口',
            onPressed: _saving ? null : () => _openManualSitePage(refresh),
            icon: Icon(Icons.add),
          ),
          builder: (context, refresh) => _buildSiteOptions(refresh),
        ),
      ),
    );
  }

  Future<void> _openDohPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SelectionPage(
          title: '加密 DNS',
          subtitle: '当前选择优先，失败后自动尝试其它可用线路。',
          actionBuilder: (context, refresh) => IconButton(
            tooltip: '添加加密 DNS',
            onPressed: _saving || !_config.dohEnabled
                ? null
                : () => _openManualDohPage(refresh),
            icon: Icon(Icons.add),
          ),
          builder: (context, refresh) => _buildDohOptions(refresh),
        ),
      ),
    );
  }

  List<Widget> _buildFixedAddressOptions(VoidCallback refresh) {
    final selectedFixedAddress = _config.fixedAddress ?? '';

    return [
      _Section(
        title: '线路选择',
        subtitle: '智能优选适合大多数情况，也可以手动指定专属线路。',
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
              : Icon(Icons.refresh),
        ),
        children: [
          _NetworkOptionTile(
            icon: Icons.route_outlined,
            title: '智能优选（推荐）',
            subtitle: '按当前网络自动选择连接路径。',
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
              title: '暂无缓存线路',
              subtitle: '点击右上角添加，或测试加密 DNS 后自动记录线路。',
            ),
          ..._addressOptions.map((address) {
            final result = _addressResults[address.address];
            final index = _addressOptions.indexOf(address) + 1;
            return _NetworkOptionTile(
              icon: Icons.dns_outlined,
              title: ForumNetworkConfig.routeLabelForAddress(
                  address.address, index),
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
        title: '访问入口',
        subtitle: '选择当前访问域名，或输入你想使用的域名。',
        children: [
          ...ForumNetworkConfig.sites.map((site) {
            final result = _siteResults[site.host];
            return _NetworkOptionTile(
              icon: Icons.language,
              title: site.host,
              subtitle: '访问域名',
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
          }),
          ..._customSites.map((site) {
            final result = _siteResults[site.host];
            return _NetworkOptionTile(
              icon: Icons.public_outlined,
              title: site.host,
              subtitle: '手动添加的访问入口',
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
          }),
        ],
      ),
    ];
  }

  List<Widget> _buildDohOptions(VoidCallback refresh) {
    return [
      _Section(
        title: '加密 DNS',
        subtitle: _config.dohEnabled
            ? '优先使用加密解析，失败后自动尝试其它可用线路'
            : '使用系统默认解析，仍可手动选择专属线路',
        children: [
          _SwitchTile(
            icon: Icons.enhanced_encryption_outlined,
            title: '启用加密 DNS',
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
        title: '解析线路',
        subtitle: '当前选择优先，失败后自动尝试其它可用线路。',
        children: [
          ...DohProvider.values.map((provider) {
            final result = _dohResults[provider];
            final subtitle = result == null || result.addresses.isEmpty
                ? '内置解析线路'
                : '已探测到 ${result.addresses.length} 条可用记录';
            return _NetworkOptionTile(
              icon: Icons.shield_outlined,
              title: provider.label,
              subtitle: subtitle,
              selected: _config.normalizedCustomDohUri == null &&
                  _config.dohProvider == provider,
              enabled: _config.dohEnabled,
              status: _probeStatus(result),
              onTap: _saving || !_config.dohEnabled
                  ? null
                  : () async {
                      await _save(
                        _config.copyWith(
                          dohProvider: provider,
                          clearCustomDohUri: true,
                        ),
                      );
                      refresh();
                    },
              onTest: () async {
                await _testDohProvider(provider);
                refresh();
              },
              testing: _testingDoh.contains(provider),
            );
          }),
          ..._customDohUris.map((uri) {
            final result = _customDohResults[uri];
            final subtitle = result == null || result.addresses.isEmpty
                ? '手动添加的解析线路'
                : '已探测到 ${result.addresses.length} 条可用记录';
            return _NetworkOptionTile(
              icon: Icons.verified_user_outlined,
              title: '自定义加密 DNS',
              subtitle: subtitle,
              selected: _config.normalizedCustomDohUri == uri,
              enabled: _config.dohEnabled,
              status: _probeStatus(result),
              onTap: _saving || !_config.dohEnabled
                  ? null
                  : () async {
                      await _save(
                        _config.copyWith(
                          dohEnabled: true,
                          customDohUri: uri,
                        ),
                      );
                      refresh();
                    },
              onTest: () async {
                await _testCustomDoh(uri);
                refresh();
              },
              testing: _testingCustomDoh.contains(uri),
            );
          }),
        ],
      ),
    ];
  }

  Future<void> _openManualSitePage(VoidCallback refresh) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManualNetworkInputPage(
          title: '手动输入访问入口',
          label: '访问域名',
          initialValue: '',
          hintText: 'south-plus.net',
          helperText: '支持直接粘贴完整网址，保存时会自动提取域名。',
          actionLabel: '保存入口',
          normalize: _normalizeHostInput,
          test: (value) async {
            final site = ForumSite(value);
            final result = await _probe.testSite(
              site,
              dohEnabled: _config.dohEnabled,
              dohProvider: _config.dohProvider,
              customDohUri: _config.normalizedCustomDohUri,
              fixedAddress: _config.fixedAddress,
            );
            if (mounted) {
              setState(() => _siteResults[site.host] = result);
            }
            return _probeStatus(result)!;
          },
          save: (value) async {
            final customSites =
                await ForumNetworkSettings.addCustomSite(ForumSite(value));
            if (mounted) setState(() => _customSites = customSites);
            await _save(_config.copyWith(site: ForumSite(value)));
            refresh();
          },
        ),
      ),
    );
  }

  Future<void> _openManualDohPage(VoidCallback refresh) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManualNetworkInputPage(
          title: '手动输入加密 DNS',
          label: '加密 DNS 地址',
          initialValue: '',
          hintText: 'https://example.com/dns-query',
          helperText: '需要使用 https 地址。保存后会优先使用这个解析线路。',
          actionLabel: '保存解析线路',
          keyboardType: TextInputType.url,
          normalize: _normalizeDohInput,
          test: (value) async => _probeStatus(await _testCustomDoh(value))!,
          save: (value) async {
            final customDohUris = await ForumNetworkSettings.addCustomDohUri(
              value,
            );
            if (mounted) setState(() => _customDohUris = customDohUris);
            await _save(
              _config.copyWith(dohEnabled: true, customDohUri: value),
            );
            refresh();
          },
        ),
      ),
    );
  }

  Future<void> _openManualAddressPage(VoidCallback refresh) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManualNetworkInputPage(
          title: '手动输入专属线路',
          label: '线路地址',
          initialValue: '',
          hintText: '203.0.113.7',
          helperText: '仅支持公网 IPv4 地址。保存后会优先直连这个线路。',
          actionLabel: '保存线路',
          keyboardType: TextInputType.number,
          normalize: _normalizeAddressInput,
          test: (value) async {
            final result = await _probe.testAddress(
              _config.site,
              InternetAddress(value),
            );
            if (mounted) {
              setState(() => _addressResults[value] = result);
            }
            return _probeStatus(result)!;
          },
          save: (value) async {
            await ForumResolvedAddressStore.mergeAndSave([
              InternetAddress(value),
            ]);
            await _save(_config.copyWith(fixedAddress: value));
            await _loadCachedAddresses(showLoading: false);
            refresh();
          },
        ),
      ),
    );
  }

  String? _normalizeHostInput(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .split(':')
        .first;
    if (normalized.isEmpty || normalized.contains(' ')) return null;
    return normalized;
  }

  String? _normalizeDohInput(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.toString();
  }

  String? _normalizeAddressInput(String value) {
    try {
      final address = InternetAddress(value.trim());
      if (address.type != InternetAddressType.IPv4) return null;
      final octets = address.address.split('.').map(int.tryParse).toList();
      if (octets.length != 4 || octets.any((octet) => octet == null)) {
        return null;
      }
      final first = octets[0]!;
      final second = octets[1]!;
      if (first == 0 || first == 10 || first == 127) return null;
      if (first == 100 && second >= 64 && second <= 127) return null;
      if (first == 169 && second == 254) return null;
      if (first == 172 && second >= 16 && second <= 31) return null;
      if (first == 192 && second == 168) return null;
      if (first == 198 && (second == 18 || second == 19)) return null;
      if (first >= 224) return null;
      return address.address;
    } on ArgumentError {
      return null;
    }
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
    this.actionBuilder,
  });

  final String title;
  final String subtitle;
  final Widget Function(BuildContext context, VoidCallback refresh)?
      actionBuilder;
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
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.actionBuilder != null)
            widget.actionBuilder!(context, _refresh),
        ],
      ),
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

class _ConnectionSwitchCard extends StatelessWidget {
  const _ConnectionSwitchCard({
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  final bool value;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: value ? AppColors.brand : AppColors.border),
      ),
      child: Row(
        children: [
          _LeadingIcon(
            icon: Icons.enhanced_encryption_outlined,
            active: value,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('加密 DNS', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  value ? '已启用加密解析，优先使用当前解析线路。' : '当前使用系统默认解析。',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: saving ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class _ManualNetworkInputPage extends StatefulWidget {
  const _ManualNetworkInputPage({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.hintText,
    required this.helperText,
    required this.actionLabel,
    required this.normalize,
    required this.test,
    required this.save,
    this.keyboardType,
  });

  final String title;
  final String label;
  final String initialValue;
  final String hintText;
  final String helperText;
  final String actionLabel;
  final String? Function(String value) normalize;
  final Future<_ProbeStatus> Function(String value) test;
  final Future<void> Function(String value) save;
  final TextInputType? keyboardType;

  @override
  State<_ManualNetworkInputPage> createState() =>
      _ManualNetworkInputPageState();
}

class _ManualNetworkInputPageState extends State<_ManualNetworkInputPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  _ProbeStatus? _status;
  String? _error;
  bool _testing = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final value = widget.normalize(_controller.text);
    if (value == null) {
      setState(() => _error = '输入格式不正确');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    final status = await widget.test(value);
    if (!mounted) return;
    setState(() {
      _status = status;
      _testing = false;
    });
  }

  Future<void> _save() async {
    final value = widget.normalize(_controller.text);
    if (value == null) {
      setState(() => _error = '输入格式不正确');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(value);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          TextField(
            controller: _controller,
            keyboardType: widget.keyboardType,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hintText,
              helperText: widget.helperText,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_status != null || _error != null) {
                setState(() {
                  _status = null;
                  _error = null;
                });
              }
            },
          ),
          const SizedBox(height: 14),
          if (_status != null) ...[
            _InlineProbeResult(status: _status!),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing || _saving ? null : _test,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.speed_outlined),
                  label: const Text('测试'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _testing || _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.actionLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineProbeResult extends StatelessWidget {
  const _InlineProbeResult({required this.status});

  final _ProbeStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: status.success ? AppColors.successSoft : AppColors.brandSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status.success ? AppColors.successBorder : AppColors.brand,
        ),
      ),
      child: Row(
        children: [
          Icon(
            status.success ? Icons.check_circle : Icons.error_outline,
            color: status.success ? AppColors.success : AppColors.brand,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              status.success ? '测试通过 · ${status.label}' : status.label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
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
    required this.primaryLabel,
    required this.primaryValue,
    required this.site,
    required this.stable,
    this.status,
  });

  final AnimationController controller;
  final String title;
  final String mode;
  final String primaryLabel;
  final String primaryValue;
  final String site;
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
          Row(
            children: [
              Expanded(
                child: _OverviewValueTile(
                  label: primaryLabel,
                  value: primaryValue,
                  icon: Icons.shield_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OverviewValueTile(
                  label: '访问入口',
                  value: site,
                  icon: Icons.language,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewValueTile extends StatelessWidget {
  const _OverviewValueTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.inkSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.link),
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
          const SizedBox(height: 8),
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
              Icon(
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
        dividedChildren.add(Divider(indent: 58, endIndent: 12));
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
                        : Icon(Icons.speed_outlined),
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
    final color = status.success ? AppColors.success : AppColors.brandDark;
    final background =
        status.success ? AppColors.successSoft : AppColors.brandSoft;
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
