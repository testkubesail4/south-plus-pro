import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../services/forum_network_probe.dart';
import '../../services/forum_network_setup_store.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/content_width.dart';
import '../common/grouped_list.dart';
import 'network_options.dart';
import 'proxy_form.dart';

enum _Step { mode, proxy, optimize, site, confirm }

/// The network guide: connection mode, its details, the entrance, then a
/// summary. Nothing waits on the network, so it also works offline; the
/// defaults (optimized, south-plus.net, IPv6 off) need only 下一步.
class NetworkSetupFlowScreen extends StatefulWidget {
  const NetworkSetupFlowScreen({
    super.key,
    required this.repository,
    this.firstRun = false,
    this.onFinished,
    this.probe = const ForumNetworkProbe(),
  });

  final ForumRepository repository;

  /// At first run there is nothing to close back to.
  final bool firstRun;
  final Future<void> Function()? onFinished;
  final ForumNetworkProbe probe;

  @override
  State<NetworkSetupFlowScreen> createState() => _NetworkSetupFlowScreenState();
}

class _NetworkSetupFlowScreenState extends State<NetworkSetupFlowScreen> {
  late ForumNetworkConfig _draft = widget.repository.networkConfig;

  // Kept apart from the draft: proxy mode is only valid once a proxy exists.
  late ForumNetworkMode _mode = _draft.mode;
  _Step _step = _Step.mode;
  bool _saving = false;

  /// The summary's connection test of the result.
  final _check = SingleCheck();

  @override
  void initState() {
    super.initState();
    _check.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  List<_Step> get _steps => [
        _Step.mode,
        if (_mode == ForumNetworkMode.proxy) _Step.proxy,
        if (_mode == ForumNetworkMode.optimized) _Step.optimize,
        _Step.site,
        _Step.confirm,
      ];

  ForumNetworkConfig get _result => _draft.copyWith(mode: _mode);

  bool get _canContinue =>
      !_saving && (_step != _Step.proxy || _draft.proxy != null);

  void _go(int delta) {
    final steps = _steps;
    final index = steps.indexOf(_step) + delta;
    if (index < 0) {
      Navigator.of(context).maybePop();
      return;
    }
    if (index >= steps.length) {
      unawaited(_finish());
      return;
    }
    setState(() => _step = steps[index]);
    // The summary's test only describes the summary; leaving it ends it.
    if (_step == _Step.confirm) {
      _runCheck();
    } else {
      _check.reset();
    }
  }

  void _update(ForumNetworkConfig config) => setState(() => _draft = config);

  void _runCheck() {
    final config = _result;
    _check.run((cancellation) async => ProbeReading.site(
        await widget.probe.testConfig(config, cancellation: cancellation)));
  }

  Future<void> _finish() async {
    if (_saving) return;
    // Its connections must not outlive the config they tested.
    _check.reset();
    setState(() => _saving = true);
    try {
      await widget.repository.updateNetworkConfig(_result);
      await ForumNetworkSetupStore.markCompleted();
      await widget.onFinished?.call();
      if (mounted && !widget.firstRun) Navigator.of(context).pop(true);
    } on FormatException catch (error) {
      _showError('无法保存：${error.message}');
    } catch (_) {
      // The setup stays incomplete and retryable; a raw error may carry
      // proxy credentials, so it is never shown.
      _showError('保存网络设置失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final index = steps.indexOf(_step);
    final gutter = appGutter(MediaQuery.sizeOf(context).width, AppWidths.form);
    final (title, subtitle) = _copy(_step);
    return PopScope(
      canPop: !widget.firstRun && index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && index > 0 && !_saving) _go(-1);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: widget.firstRun
              ? null
              : IconButton(
                  tooltip: '关闭',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
          title: Text('网络设置 · ${index + 1}/${steps.length}'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(
              value: (index + 1) / steps.length,
              minHeight: 3,
              backgroundColor: AppColors.inkSoft,
            ),
          ),
        ),
        body: ListView(
          padding:
              EdgeInsets.fromLTRB(gutter, AppSpace.xl, gutter, AppSpace.xl),
          children: [
            Semantics(
              header: true,
              child:
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textMuted, height: 1.45)),
            const SizedBox(height: AppSpace.xl),
            AnimatedSwitcher(
              duration: AppMotion.medium,
              switchInCurve: AppMotion.enter,
              switchOutCurve: AppMotion.exit,
              child: KeyedSubtree(key: ValueKey(_step), child: _content()),
            ),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          gutter: gutter,
          backLabel: index == 0 ? null : '上一步',
          nextLabel: _step == _Step.confirm ? '开始使用' : '下一步',
          saving: _saving,
          onBack: _saving ? null : () => _go(-1),
          onNext: _canContinue ? () => _go(1) : null,
        ),
      ),
    );
  }

  (String, String) _copy(_Step step) => switch (step) {
        _Step.mode => ('选择连接方式', '三种方式只会同时使用一种，之后可在「设置 › 网络连接」随时更改。'),
        _Step.proxy => ('填写代理', '所有请求都会经由这个代理发送。'),
        _Step.optimize => ('网络优化', '选择加密 DNS 服务。不确定时保持默认即可，后台测速不影响继续。'),
        _Step.site => ('访问入口', '入口是要访问的论坛域名，与连接方式各自独立。'),
        _Step.confirm => ('确认设置', '下面是即将保存的设置。'),
      };

  Widget _content() => switch (_step) {
        _Step.mode => _modeStep(),
        _Step.proxy => _proxyStep(),
        _Step.optimize => _optimizeStep(),
        // The proxy step comes first, so a proxy result is always valid here.
        _Step.site => SiteChoiceList(
            config: _result,
            probe: widget.probe,
            onSelected: (site) => _update(_draft.copyWith(site: site)),
          ),
        _Step.confirm => _confirmStep(),
      };

  Widget _modeStep() {
    return Column(
      children: [
        for (final mode in const [
          ForumNetworkMode.optimized,
          ForumNetworkMode.native,
          ForumNetworkMode.proxy,
        ]) ...[
          _ModeCard(
            mode: mode,
            selected: _mode == mode,
            recommended: mode == ForumNetworkMode.optimized,
            onTap: () => setState(() => _mode = mode),
          ),
          const SizedBox(height: AppSpace.md),
        ],
      ],
    );
  }

  Widget _proxyStep() {
    final proxy = _draft.proxy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (proxy != null) ...[
          AppGroup(children: [
            AppRow(
              icon: Icons.check_circle_outline,
              title: Text(proxyLabel(proxy)),
              subtitle: const Text('将使用此代理，可在下方修改'),
              enabled: true,
            ),
          ]),
          const SizedBox(height: AppSpace.lg),
        ],
        ProxyForm(
          initial: proxy,
          submitLabel: '使用此代理',
          onSubmit: (proxy) async {
            _update(_draft.copyWith(proxy: proxy));
            _go(1);
          },
        ),
      ],
    );
  }

  Widget _optimizeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DohChoiceList(
          config: _result,
          probe: widget.probe,
          onChanged: _update,
        ),
        const SizedBox(height: AppSpace.lg),
        AppGroup(children: [
          Ipv6Row(
            value: _draft.ipv6Enabled,
            onChanged: (value) => _update(_draft.copyWith(ipv6Enabled: value)),
          ),
        ]),
      ],
    );
  }

  Widget _confirmStep() {
    final config = _result;
    final optimized = config.mode == ForumNetworkMode.optimized;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroup(children: [
          AppRow(
            icon: networkModeIcon(config.mode),
            title: const Text('连接方式'),
            value: networkModeLabel(config.mode),
            enabled: true,
          ),
          if (config.mode == ForumNetworkMode.proxy)
            AppRow(
              icon: Icons.dns_outlined,
              title: const Text('代理服务器'),
              value: proxyLabel(config.proxy!),
              enabled: true,
            ),
          if (optimized) ...[
            AppRow(
              icon: Icons.shield_outlined,
              title: const Text('加密 DNS'),
              value: dohLabel(config),
              enabled: true,
            ),
            AppRow(
              icon: Icons.looks_6_outlined,
              title: const Text('IPv6'),
              value: config.ipv6Enabled ? '开启' : '关闭',
              enabled: true,
            ),
          ],
          AppRow(
            icon: Icons.language,
            title: const Text('访问入口'),
            value: config.site.host,
            enabled: true,
          ),
          if (optimized)
            AppRow(
              icon: Icons.pin_drop_outlined,
              title: const Text('目标地址'),
              subtitle: const Text('可选，为当前入口指定优先尝试的 IP'),
              value: hostAddressesLabel(config),
              onTap: _saving
                  ? null
                  : () async {
                      final updated = await HostAddressesPage.open(
                          context, _result,
                          probe: widget.probe);
                      if (updated == null || !mounted) return;
                      _update(updated);
                      _runCheck();
                    },
            ),
        ]),
        const SizedBox(height: AppSpace.lg),
        _CheckPanel(
          check: _check,
          onRetry: _saving ? null : _runCheck,
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final ForumNetworkMode mode;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: selected ? AppColors.brand : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(networkModeIcon(mode),
                    color: selected ? AppColors.brand : AppColors.textMuted),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(networkModeLabel(mode),
                              style: theme.textTheme.titleMedium),
                          if (recommended)
                            Text('推荐',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(color: AppColors.brand)),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(networkModeDescription(mode),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.brand : AppColors.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one connection test of the summary. It never gates 开始使用.
class _CheckPanel extends StatelessWidget {
  const _CheckPanel({required this.check, required this.onRetry});

  final SingleCheck check;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checking = check.testing;
    final result = check.reading;
    final (icon, color, text) = checking
        ? (null, AppColors.textMuted, '正在用这组设置测试连接…')
        : result == null
            ? (Icons.help_outline, AppColors.textMuted, '未能完成测试。')
            : result.success
                ? (
                    Icons.check_circle_outline,
                    AppColors.success,
                    '刚才的测试请求成功（${result.label}）。'
                        '这只说明当下可以连上，之后网络变化时可能不同。'
                  )
                : (
                    Icons.error_outline,
                    theme.colorScheme.error,
                    '测试未通过：${result.label}。'
                        '仍可开始使用，之后在「设置 › 网络连接」调整。'
                  );
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.inkSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon == null)
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: theme.textTheme.bodyMedium),
                  if (!checking)
                    TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft),
                      onPressed: onRetry,
                      child: const Text('重新测试'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.gutter,
    required this.backLabel,
    required this.nextLabel,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });

  final double gutter;
  final String? backLabel;
  final String nextLabel;
  final bool saving;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            if (backLabel != null) ...[
              Expanded(
                child:
                    OutlinedButton(onPressed: onBack, child: Text(backLabel!)),
              ),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: onNext,
                // While saving, a spinner joins the label (DESIGN §6).
                icon: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                label: Text(nextLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
