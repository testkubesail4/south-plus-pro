import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../services/forum_network_probe.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import 'proxy_form.dart';

// Shared by the first-run guide and the network settings, so both describe
// and edit the same options the same way.

String networkModeLabel(ForumNetworkMode mode) => switch (mode) {
      ForumNetworkMode.native => '直接连接',
      ForumNetworkMode.optimized => '网络优化',
      ForumNetworkMode.proxy => '代理',
    };

String networkModeDescription(ForumNetworkMode mode) => switch (mode) {
      ForumNetworkMode.native => '只用系统网络与系统 DNS，应用不做改写。',
      ForumNetworkMode.optimized => '加密 DNS 解析，按候选 IP 连接；适合 DNS 受干扰的网络。',
      ForumNetworkMode.proxy => '全部经由你的代理；代理不可用时不会改为直连。',
    };

IconData networkModeIcon(ForumNetworkMode mode) => switch (mode) {
      ForumNetworkMode.native => Icons.router_outlined,
      ForumNetworkMode.optimized => Icons.alt_route_outlined,
      ForumNetworkMode.proxy => Icons.vpn_lock_outlined,
    };

String dohLabel(ForumNetworkConfig config) {
  final custom = config.customDohUri;
  if (custom == null) return config.dohProvider.label;
  return '自定义 · ${Uri.tryParse(custom)?.host ?? custom}';
}

/// Addresses the user set for [host]; empty when only built-ins apply.
List<String> customAddressesFor(ForumNetworkConfig config, String host) =>
    config.hostAddresses[host] ?? const [];

String hostAddressesLabel(ForumNetworkConfig config) {
  final count = customAddressesFor(config, config.site.host).length;
  return count == 0 ? '仅内置' : '$count 个自定义';
}

/// Shown with external links and downloads that leave the app.
const externalTrafficNote = '在外部浏览器中打开的链接，以及交给系统下载的文件，不经过这里的设置。';

/// One probe outcome for display. A result only describes the single
/// attempt it came from, so callers drop it when the config changes.
class ProbeReading {
  const ProbeReading._(this.success, this.label, this.elapsed);

  factory ProbeReading.site(ForumSiteProbeResult result) => ProbeReading._(
      result.success,
      result.success ? result.latencyLabel : result.message,
      result.elapsed);

  factory ProbeReading.doh(DohProbeResult result) => ProbeReading._(
      result.success,
      result.success ? result.latencyLabel : result.message,
      result.elapsed);

  final bool success;
  final String label;
  final Duration elapsed;

  /// The fastest successful key, or null when none succeeded.
  static K? fastest<K>(Map<K, ProbeReading> readings) {
    MapEntry<K, ProbeReading>? best;
    for (final entry in readings.entries) {
      if (!entry.value.success) continue;
      if (best == null || entry.value.elapsed < best.value.elapsed) {
        best = entry;
      }
    }
    return best?.key;
  }
}

typedef ProbeRun<K> = Future<ProbeReading> Function(
    K key, ForumProbeCancellation cancellation);

/// Runs probes for a set of keys without blocking anything: results arrive
/// as they finish. Replaced and disposed probes are cancelled, closing
/// their connections, and their results are dropped.
class ProbeBatch<K> extends ChangeNotifier {
  final Map<K, ProbeReading> readings = {};
  final Set<K> pending = {};
  // The live probe per key; any other result is stale.
  final Map<K, ForumProbeCancellation> _live = {};
  bool _disposed = false;

  bool get running => pending.isNotEmpty;

  void _cancelAll() {
    for (final token in _live.values) {
      token.cancel();
    }
    _live.clear();
  }

  /// Cancels every probe and forgets every reading.
  void reset() {
    _cancelAll();
    readings.clear();
    pending.clear();
    notifyListeners();
  }

  /// [reset], then probes [keys].
  void start(Iterable<K> keys, ProbeRun<K> probe) {
    reset();
    for (final key in keys) {
      add(key, probe);
    }
    notifyListeners();
  }

  /// Probes [key], cancelling an earlier probe of it.
  void add(K key, ProbeRun<K> probe) {
    _live.remove(key)?.cancel();
    final token = _live[key] = ForumProbeCancellation();
    readings.remove(key);
    pending.add(key);
    notifyListeners();
    bool current() => !_disposed && identical(_live[key], token);
    unawaited(probe(key, token).then((reading) {
      if (!current()) return;
      readings[key] = reading;
      pending.remove(key);
      notifyListeners();
    }, onError: (Object _) {
      if (!current()) return;
      pending.remove(key);
      notifyListeners();
    }));
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAll();
    super.dispose();
  }
}

/// A probe result as a compact label: latency, failure reason, or progress.
class ProbeLabel extends StatelessWidget {
  const ProbeLabel({super.key, this.reading, this.pending = false});

  final ProbeReading? reading;
  final bool pending;

  // A result fades in over 测速中.
  @override
  Widget build(BuildContext context) => AppSwitcher(
      id: (reading?.success, reading?.label, pending), child: _label(context));

  Widget _label(BuildContext context) {
    final theme = Theme.of(context);
    final reading = this.reading;
    if (reading == null) {
      if (!pending) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: AppSpace.xs + 2),
          Text('测速中',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppColors.textMuted)),
        ],
      );
    }
    final color = reading.success ? AppColors.success : theme.colorScheme.error;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Text(
        reading.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

/// The IPv6 option of the optimized mode, identical in guide and settings.
class Ipv6Row extends StatelessWidget {
  const Ipv6Row({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AppRow(
      icon: Icons.looks_6_outlined,
      title: const Text('使用 IPv6'),
      subtitle: const Text('默认关闭。开启后也会尝试 IPv6 地址，IPv6 连不上时改用 IPv4。'),
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// Page scaffold shared by the option and editor pages.
class NetworkPage extends StatelessWidget {
  const NetworkPage({
    super.key,
    required this.title,
    required this.children,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final gutter = appGutter(MediaQuery.sizeOf(context).width, AppWidths.form);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xxl),
        children: children,
      ),
    );
  }
}

/// Body text under a group, explaining what an option really does.
class NetworkNote extends StatelessWidget {
  const NetworkNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xs),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// A selectable option with its latest probe reading.
class _ProbedChoiceRow extends StatelessWidget {
  const _ProbedChoiceRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.reading,
    this.pending = false,
    this.fastest = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final ProbeReading? reading;
  final bool pending;
  final bool fastest;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final probe = ProbeLabel(reading: reading, pending: pending);
    return AppRow(
      icon: icon,
      selected: selected,
      onTap: onTap,
      title: Text(title),
      subtitle: subtitle == null && reading == null && !pending
          ? null
          : Wrap(
              spacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (subtitle != null) Text(subtitle!),
                probe,
                if (fastest)
                  Text('本次最快',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: AppColors.success)),
              ],
            ),
      trailing: trailing == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) Icon(Icons.check, color: AppColors.brand),
              trailing!,
            ]),
    );
  }
}

class _RetestButton extends StatelessWidget {
  const _RetestButton({required this.running, required this.onPressed});

  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: running ? null : onPressed,
      icon: const Icon(Icons.speed_outlined, size: 18),
      label: Text(running ? '测速中' : '重新测速'),
    );
  }
}

/// Built-in and saved forum entrances. Probes run in the background through
/// [config]'s mode; the selection never moves on its own.
class SiteChoiceList extends StatefulWidget {
  const SiteChoiceList({
    super.key,
    required this.config,
    required this.onSelected,
    this.probe = const ForumNetworkProbe(),
  });

  final ForumNetworkConfig config;
  final ValueChanged<ForumSite>? onSelected;
  final ForumNetworkProbe probe;

  @override
  State<SiteChoiceList> createState() => _SiteChoiceListState();
}

class _SiteChoiceListState extends State<SiteChoiceList> {
  final _probes = ProbeBatch<ForumSite>();
  List<ForumSite> _customSites = const [];

  List<ForumSite> get _sites => [
        ...ForumNetworkConfig.sites,
        ..._customSites,
        if (!ForumNetworkConfig.sites.contains(widget.config.site) &&
            !_customSites.contains(widget.config.site))
          widget.config.site,
      ];

  @override
  void initState() {
    super.initState();
    _probes.addListener(_changed);
    unawaited(_loadCustomSites());
    _test();
  }

  @override
  void didUpdateWidget(SiteChoiceList old) {
    super.didUpdateWidget(old);
    // Readings describe the old routing once anything but the site changes.
    if (old.config.copyWith(site: widget.config.site) != widget.config) {
      _test();
    }
  }

  @override
  void dispose() {
    _probes.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _loadCustomSites() async {
    final sites = await ForumNetworkSettings.loadCustomSites();
    if (mounted) setState(() => _customSites = sites);
  }

  void _test() {
    final config = widget.config;
    _probes.start(
        _sites,
        (site, cancellation) async => ProbeReading.site(await widget.probe
            .testConfig(config.copyWith(site: site),
                cancellation: cancellation)));
  }

  Future<void> _add() async {
    final host = await showDialog<String>(
      context: context,
      builder: (_) => const _AddSiteDialog(),
    );
    if (host == null || !mounted) return;
    final site = ForumSite(host);
    try {
      final sites = await ForumNetworkSettings.addCustomSite(site);
      if (mounted) setState(() => _customSites = sites);
    } catch (_) {
      // Remembering the entrance is a convenience; selecting it still works.
    }
    widget.onSelected?.call(site);
    final config = widget.config;
    _probes.add(
        site,
        (site, cancellation) async => ProbeReading.site(await widget.probe
            .testConfig(config.copyWith(site: site),
                cancellation: cancellation)));
  }

  @override
  Widget build(BuildContext context) {
    final fastest = ProbeReading.fastest(_probes.readings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _RetestButton(running: _probes.running, onPressed: _test),
        ),
        AppGroup(
          children: [
            for (final site in _sites)
              _ProbedChoiceRow(
                icon: Icons.language,
                title: site.host,
                subtitle:
                    site == ForumNetworkConfig.defaultSite ? '默认入口' : null,
                selected: site == widget.config.site,
                reading: _probes.readings[site],
                pending: _probes.pending.contains(site),
                fastest: site == fastest,
                onTap: widget.onSelected == null
                    ? null
                    : () => widget.onSelected!(site),
              ),
            AppRow(
              icon: Icons.add,
              title: const Text('添加访问入口'),
              onTap: widget.onSelected == null ? null : _add,
            ),
          ],
        ),
        const NetworkNote('入口只决定访问哪个论坛域名，与连接方式互不影响。'
            '测速结果只代表刚才那一次请求。'),
      ],
    );
  }
}

class _AddSiteDialog extends StatefulWidget {
  const _AddSiteDialog();

  @override
  State<_AddSiteDialog> createState() => _AddSiteDialogState();
}

class _AddSiteDialogState extends State<_AddSiteDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final host = ForumNetworkConfig.normalizeHost(_controller.text);
    if (host == null) {
      setState(() => _error = '请输入有效的域名，例如 south-plus.net');
      return;
    }
    Navigator.of(context).pop(host);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加访问入口'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: '论坛域名',
          hintText: 'south-plus.net',
          helperText: '可粘贴完整网址，只保留域名。',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}

/// Built-in encrypted DNS services plus one custom service.
class DohChoiceList extends StatefulWidget {
  const DohChoiceList({
    super.key,
    required this.config,
    required this.onChanged,
    this.probe = const ForumNetworkProbe(),
  });

  final ForumNetworkConfig config;
  final ValueChanged<ForumNetworkConfig>? onChanged;
  final ForumNetworkProbe probe;

  @override
  State<DohChoiceList> createState() => _DohChoiceListState();
}

class _DohChoiceListState extends State<DohChoiceList> {
  final _probes = ProbeBatch<Object>();
  static const _custom = 'custom';

  @override
  void initState() {
    super.initState();
    _probes.addListener(_changed);
    _test();
  }

  @override
  void didUpdateWidget(DohChoiceList old) {
    super.didUpdateWidget(old);
    final a = old.config, b = widget.config;
    if (a.ipv6Enabled != b.ipv6Enabled ||
        a.site != b.site ||
        a.customDohUri != b.customDohUri ||
        !listEquals(a.dohBootstrapAddresses, b.dohBootstrapAddresses)) {
      _test();
    }
  }

  @override
  void dispose() {
    _probes.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _test() {
    final config = widget.config;
    final host = config.site.host;
    _probes.start([
      ...DohProvider.values,
      if (config.customDohUri != null) _custom,
    ], (key, cancellation) async {
      final result = key is DohProvider
          ? await widget.probe.testDoh(key,
              ipv6Enabled: config.ipv6Enabled,
              host: host,
              cancellation: cancellation)
          : await widget.probe.testCustomDoh(config.customDohUri!,
              bootstrapAddresses: config.dohBootstrapAddresses,
              ipv6Enabled: config.ipv6Enabled,
              host: host,
              cancellation: cancellation);
      return ProbeReading.doh(result);
    });
  }

  Future<void> _editCustom() async {
    final result = await Navigator.of(context).push<_CustomDoh>(
      MaterialPageRoute(
        builder: (_) => _CustomDohPage(
          config: widget.config,
          probe: widget.probe,
        ),
      ),
    );
    if (result == null || !mounted) return;
    widget.onChanged?.call(widget.config.copyWith(
      customDohUri: result.uri,
      dohBootstrapAddresses: result.bootstrap,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final onChanged = widget.onChanged;
    final custom = config.customDohUri;
    final fastest = ProbeReading.fastest(_probes.readings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _RetestButton(running: _probes.running, onPressed: _test),
        ),
        AppGroup(
          children: [
            for (final provider in DohProvider.values)
              _ProbedChoiceRow(
                icon: Icons.shield_outlined,
                title: provider.label,
                subtitle: provider == ForumNetworkConfig.defaultProvider
                    ? '默认'
                    : null,
                selected: custom == null && config.dohProvider == provider,
                reading: _probes.readings[provider],
                pending: _probes.pending.contains(provider),
                fastest: provider == fastest,
                onTap: onChanged == null
                    ? null
                    : () => onChanged(config.copyWith(
                        dohProvider: provider, clearCustomDohUri: true)),
              ),
            if (custom == null)
              AppRow(
                icon: Icons.add,
                title: const Text('自定义加密 DNS'),
                onTap: onChanged == null ? null : _editCustom,
              )
            else
              _ProbedChoiceRow(
                icon: Icons.verified_user_outlined,
                title: '自定义 · ${Uri.tryParse(custom)?.host ?? custom}',
                subtitle: config.dohBootstrapAddresses.isEmpty
                    ? null
                    : '${config.dohBootstrapAddresses.length} 个引导地址',
                selected: true,
                reading: _probes.readings[_custom],
                pending: _probes.pending.contains(_custom),
                fastest: fastest == _custom,
                onTap: onChanged == null ? null : _editCustom,
                trailing: IconButton(
                  tooltip: '编辑自定义加密 DNS',
                  onPressed: onChanged == null ? null : _editCustom,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
        const NetworkNote('所选服务优先使用，失败时依次尝试其它内置服务。测速会查询当前入口的域名。'),
      ],
    );
  }
}

class _CustomDoh {
  const _CustomDoh(this.uri, this.bootstrap);
  final String uri;
  final List<String> bootstrap;
}

/// Parses one address per line; returns the first error instead.
({List<String> addresses, String? error}) parseAddressLines(String text) {
  final addresses = <String>[];
  for (final line in text.split(RegExp(r'[\s,，]+'))) {
    if (line.isEmpty) continue;
    final error = ForumNetworkConfig.validateAddressLiteral(line);
    if (error != null) return (addresses: const [], error: '$line：$error');
    if (!addresses.contains(line)) addresses.add(line);
  }
  return (addresses: addresses, error: null);
}

bool _hasIpv6(List<String> addresses) => addresses.any((a) => a.contains(':'));

class _CustomDohPage extends StatefulWidget {
  const _CustomDohPage({required this.config, required this.probe});

  final ForumNetworkConfig config;
  final ForumNetworkProbe probe;

  @override
  State<_CustomDohPage> createState() => _CustomDohPageState();
}

class _CustomDohPageState extends State<_CustomDohPage> {
  late final _uri = TextEditingController(text: widget.config.customDohUri);
  late final _bootstrap = TextEditingController(
      text: widget.config.dohBootstrapAddresses.join('\n'));
  String? _uriError;
  String? _bootstrapError;
  final _check = SingleCheck();

  @override
  void initState() {
    super.initState();
    _check.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _check.dispose();
    _uri.dispose();
    _bootstrap.dispose();
    super.dispose();
  }

  _CustomDoh? _read() {
    final uri = ForumNetworkConfig.normalizeDohUri(_uri.text);
    final bootstrap = parseAddressLines(_bootstrap.text);
    setState(() {
      _uriError = uri == null ? '请输入 https:// 开头的完整地址' : null;
      _bootstrapError = bootstrap.error;
    });
    if (uri == null || bootstrap.error != null) return null;
    return _CustomDoh(uri, bootstrap.addresses);
  }

  void _test() {
    final value = _read();
    if (value == null) return;
    _check.run((cancellation) async => ProbeReading.doh(await widget.probe
        .testCustomDoh(value.uri,
            bootstrapAddresses: value.bootstrap,
            ipv6Enabled: widget.config.ipv6Enabled,
            host: widget.config.site.host,
            cancellation: cancellation)));
  }

  void _save() {
    final value = _read();
    if (value != null) Navigator.of(context).pop(value);
  }

  // A result describes the input it was run with, not the edited one.
  void _inputChanged(String _) => _check.reset();

  @override
  Widget build(BuildContext context) {
    final bootstrap = parseAddressLines(_bootstrap.text).addresses;
    return NetworkPage(
      title: '自定义加密 DNS',
      children: [
        TextField(
          controller: _uri,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onChanged: _inputChanged,
          decoration: InputDecoration(
            labelText: '服务地址',
            hintText: 'https://dns.example/dns-query',
            errorText: _uriError,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _bootstrap,
          autocorrect: false,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          onChanged: _inputChanged,
          decoration: InputDecoration(
            labelText: '引导地址（可选）',
            hintText: '1.1.1.1\n2606:4700:4700::1111',
            helperText: '这个 DNS 服务自身的 IP，每行一个。填写后直接连接这些 IP；'
                '留空则用系统 DNS 查询该服务的域名。',
            helperMaxLines: 3,
            errorText: _bootstrapError,
            errorMaxLines: 2,
          ),
        ),
        if (!widget.config.ipv6Enabled && _hasIpv6(bootstrap)) ...[
          const SizedBox(height: AppSpace.sm),
          const NetworkNote('IPv6 未开启，其中的 IPv6 地址暂不使用。'),
        ],
        _TestAndSave(
          check: _check,
          successText: '可以解析',
          onTest: _test,
          saveLabel: '使用此服务',
          onSave: _save,
        ),
        const SizedBox(height: AppSpace.md),
        const NetworkNote('保存不要求测试通过，离线时也可以先填好。自定义服务失败时会依次尝试内置服务。'),
      ],
    );
  }
}

/// One on-demand test whose result belongs to the input it ran with.
class SingleCheck extends ProbeBatch<int> {
  ProbeReading? get reading => readings[0];
  bool get testing => pending.contains(0);

  void run(Future<ProbeReading> Function(ForumProbeCancellation) probe) =>
      start(const [0], (_, cancellation) => probe(cancellation));
}

/// The result of [check] above 测试 and a save button. Saving never waits
/// for a test, so the editors work offline.
class _TestAndSave extends StatelessWidget {
  const _TestAndSave({
    required this.check,
    required this.successText,
    required this.onTest,
    required this.saveLabel,
    required this.onSave,
  });

  final SingleCheck check;
  final String successText;
  final VoidCallback onTest;
  final String saveLabel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final reading = check.reading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reading != null) ...[
          const SizedBox(height: AppSpace.lg),
          _InlineResult(reading: reading, successText: successText),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: check.testing ? null : onTest,
                icon: check.testing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_outlined),
                label: const Text('测试'),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: FilledButton(onPressed: onSave, child: Text(saveLabel)),
            ),
          ],
        ),
      ],
    );
  }
}

class _InlineResult extends StatelessWidget {
  const _InlineResult({required this.reading, required this.successText});

  final ProbeReading reading;
  final String successText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: reading.success ? AppColors.successSoft : AppColors.inkSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(
              reading.success
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color:
                  reading.success ? AppColors.success : theme.colorScheme.error,
            ),
            const SizedBox(width: AppSpace.sm + 2),
            Expanded(
              child: Text(
                reading.success
                    ? '$successText · ${reading.label}（仅代表这一次）'
                    : '未通过：${reading.label}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edits the user's IP candidates for one host. They are tried before the
/// built-in candidates, which still follow when they all fail.
class HostAddressesPage extends StatefulWidget {
  const HostAddressesPage({
    super.key,
    required this.config,
    this.probe = const ForumNetworkProbe(),
  });

  final ForumNetworkConfig config;
  final ForumNetworkProbe probe;

  /// Returns the updated config, or null when the user backs out.
  static Future<ForumNetworkConfig?> open(
          BuildContext context, ForumNetworkConfig config,
          {ForumNetworkProbe probe = const ForumNetworkProbe()}) =>
      Navigator.of(context).push<ForumNetworkConfig>(MaterialPageRoute(
          builder: (_) => HostAddressesPage(config: config, probe: probe)));

  @override
  State<HostAddressesPage> createState() => _HostAddressesPageState();
}

class _HostAddressesPageState extends State<HostAddressesPage> {
  String get _host => widget.config.site.host;
  late final _controller = TextEditingController(
      text: customAddressesFor(widget.config, _host).join('\n'));
  String? _error;
  final _check = SingleCheck();

  @override
  void initState() {
    super.initState();
    _check.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _check.dispose();
    _controller.dispose();
    super.dispose();
  }

  ForumNetworkConfig? _read() {
    final parsed = parseAddressLines(_controller.text);
    setState(() => _error = parsed.error);
    if (parsed.error != null) return null;
    final map = {...widget.config.hostAddresses};
    if (parsed.addresses.isEmpty) {
      map.remove(_host);
    } else {
      map[_host] = parsed.addresses;
    }
    return widget.config.copyWith(hostAddresses: map);
  }

  void _test() {
    final config = _read();
    if (config == null) return;
    _check.run((cancellation) async => ProbeReading.site(
        await widget.probe.testConfig(config, cancellation: cancellation)));
  }

  void _save() {
    final config = _read();
    if (config != null) Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final builtIn = ForumNetworkConfig.builtInHostAddresses(_host);
    final addresses = parseAddressLines(_controller.text).addresses;
    return NetworkPage(
      title: '目标地址',
      children: [
        Text(_host, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpace.xs),
        Text(
          '这里的 IP 地址会先于内置候选尝试；全部连不上时仍会尝试'
          '${builtIn.isEmpty ? '加密 DNS 的解析结果' : '内置的 ${builtIn.length} 个候选'}。'
          '连接时仍按 $_host 验证证书。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _controller,
          autocorrect: false,
          minLines: 3,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          // A result describes the input it was run with.
          onChanged: (_) => _check.reset(),
          decoration: InputDecoration(
            labelText: 'IPv4 / IPv6 地址',
            helperText: '每行一个。留空即只用内置候选。',
            errorText: _error,
            errorMaxLines: 2,
          ),
        ),
        if (!widget.config.ipv6Enabled && _hasIpv6(addresses)) ...[
          const SizedBox(height: AppSpace.sm),
          const NetworkNote('IPv6 未开启，其中的 IPv6 地址暂不使用。'),
        ],
        _TestAndSave(
          check: _check,
          successText: '可以连接',
          onTest: _test,
          saveLabel: '保存',
          onSave: _save,
        ),
      ],
    );
  }
}

/// Proxy form page. A saved proxy can be deleted only while another mode
/// is active, since the proxy mode cannot run without one.
class ProxyPage extends StatelessWidget {
  const ProxyPage({
    super.key,
    required this.initial,
    required this.onSubmit,
    this.onDelete,
  });

  final ForumProxy? initial;
  final Future<void> Function(ForumProxy proxy) onSubmit;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return NetworkPage(
      title: '代理',
      children: [
        ProxyForm(
          initial: initial,
          submitLabel: '保存代理',
          onSubmit: (proxy) async {
            await onSubmit(proxy);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        if (onDelete != null && initial != null) ...[
          const SizedBox(height: AppSpace.md),
          OutlinedButton(
            onPressed: () async {
              try {
                await onDelete!();
                if (context.mounted) Navigator.of(context).pop();
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('删除代理失败，请稍后重试')),
                );
              }
            },
            child: const Text('删除已保存的代理'),
          ),
        ],
      ],
    );
  }
}
