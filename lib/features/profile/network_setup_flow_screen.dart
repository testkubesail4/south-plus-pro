import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../services/forum_network_config.dart';
import '../../services/forum_network_probe.dart';
import '../../services/forum_network_setup_store.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';

enum _SetupStep {
  mode,
  encrypted,
  entrance,
  route,
  summary,
}

class NetworkSetupFlowScreen extends StatefulWidget {
  const NetworkSetupFlowScreen({
    super.key,
    required this.repository,
    this.allowSkip = false,
    this.onFinished,
  });

  final ForumRepository repository;
  final bool allowSkip;
  final Future<void> Function()? onFinished;

  @override
  State<NetworkSetupFlowScreen> createState() => _NetworkSetupFlowScreenState();
}

class _NetworkSetupFlowScreenState extends State<NetworkSetupFlowScreen>
    with TickerProviderStateMixin {
  final ForumNetworkProbe _probe =
      const ForumNetworkProbe(timeout: Duration(seconds: 6));
  late ForumNetworkConfig _draft = widget.repository.networkConfig;
  late final AnimationController _ambientController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();
  final Map<DohProvider, DohProbeResult> _dohResults = {};
  final Map<String, ForumSiteProbeResult> _siteResults = {};
  final Map<String, ForumAddressProbeResult> _addressResults = {};
  ForumSiteProbeResult? _dynamicRouteResult;
  List<InternetAddress> _cachedAddresses = const [];
  late _SetupStep _step =
      widget.allowSkip ? _SetupStep.mode : _SetupStep.encrypted;
  late bool _optimizeEnabled = widget.allowSkip ? _draft.dohEnabled : true;
  int _probeRunId = 0;
  bool _probing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (!widget.allowSkip) {
      _draft = _draft.copyWith(dohEnabled: true, clearFixedAddress: true);
    }
    unawaited(_loadCachedAddresses());
    WidgetsBinding.instance.addPostFrameCallback((_) => _probeCurrentStep());
  }

  List<_SetupStep> get _steps {
    return _SetupFlowPlan.steps(
      allowSkip: widget.allowSkip,
      optimizeEnabled: _optimizeEnabled,
    );
  }

  int get _stepIndex => _steps.indexOf(_step);

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedAddresses() async {
    final addresses = await ForumResolvedAddressStore.load();
    if (!mounted) return;
    setState(() => _cachedAddresses = addresses);
  }

  Future<void> _probeCurrentStep() async {
    final runId = ++_probeRunId;
    setState(() => _probing = true);
    switch (_step) {
      case _SetupStep.mode:
        break;
      case _SetupStep.encrypted:
        await _probeEncrypted(runId);
      case _SetupStep.entrance:
        await _probeEntrance(runId);
      case _SetupStep.route:
        await _probeRoute(runId);
      case _SetupStep.summary:
        break;
    }
    if (!mounted || runId != _probeRunId) return;
    setState(() => _probing = false);
  }

  Future<void> _probeEncrypted(int runId) async {
    final results = await Future.wait(
      DohProvider.values.map(
        (provider) async => MapEntry(provider, await _probe.testDoh(provider)),
      ),
    );
    if (!mounted || runId != _probeRunId) return;

    final addresses = results.expand((entry) => entry.value.addresses);
    if (addresses.isNotEmpty) {
      final cached = await ForumResolvedAddressStore.mergeAndSave(addresses);
      if (mounted && runId == _probeRunId) {
        _cachedAddresses = cached;
      }
    }

    if (!mounted || runId != _probeRunId) return;
    setState(() {
      for (final entry in results) {
        _dohResults[entry.key] = entry.value;
      }
    });
  }

  Future<void> _probeEntrance(int runId) async {
    final results = await Future.wait(
      ForumNetworkConfig.sites.map(
        (site) => _probe.testSite(
          site,
          dohEnabled: _draft.dohEnabled,
          dohProvider: _draft.dohProvider,
          customDohUri: _draft.normalizedCustomDohUri,
          fixedAddress: null,
        ),
      ),
    );
    if (!mounted || runId != _probeRunId) return;
    setState(() {
      for (final result in results) {
        _siteResults[result.site.host] = result;
      }
    });
  }

  Future<void> _probeRoute(int runId) async {
    await _loadCachedAddresses();
    final dynamicResult = await _probe.testSite(
      _draft.site,
      dohEnabled: _draft.dohEnabled,
      dohProvider: _draft.dohProvider,
      customDohUri: _draft.normalizedCustomDohUri,
      fixedAddress: null,
    );
    final addressResults = await Future.wait(
      _cachedAddresses
          .map((address) => _probe.testAddress(_draft.site, address)),
    );
    if (!mounted || runId != _probeRunId) return;
    setState(() {
      _dynamicRouteResult = dynamicResult;
      for (final result in addressResults) {
        _addressResults[result.address.address] = result;
      }
    });
  }

  void _selectEncrypted(bool enabled, [DohProvider? provider]) {
    setState(() {
      _optimizeEnabled = enabled;
      _draft = _draft.copyWith(
        dohEnabled: enabled,
        dohProvider: provider ?? _draft.dohProvider,
        clearFixedAddress: true,
      );
    });
  }

  void _selectMode({required bool optimize}) {
    setState(() {
      _optimizeEnabled = optimize;
      _draft = _draft.copyWith(
        dohEnabled: optimize,
        clearFixedAddress: true,
      );
      _step = optimize ? _SetupStep.encrypted : _SetupStep.entrance;
    });
    unawaited(_probeCurrentStep());
  }

  void _selectSite(ForumSite site) {
    setState(() => _draft = _draft.copyWith(site: site));
  }

  void _selectRoute(String? fixedAddress) {
    setState(() {
      _draft = fixedAddress == null
          ? _draft.copyWith(clearFixedAddress: true)
          : _draft.copyWith(fixedAddress: fixedAddress);
    });
  }

  void _goBack() {
    final steps = _steps;
    final index = steps.indexOf(_step);
    if (index <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step = steps[index - 1]);
    unawaited(_probeCurrentStep());
  }

  Future<void> _goNext() async {
    if (_step == _SetupStep.summary) {
      await _finish(skipSave: false);
      return;
    }
    final steps = _steps;
    final index = steps.indexOf(_step);
    setState(() => _step = steps[(index + 1).clamp(0, steps.length - 1)]);
    unawaited(_probeCurrentStep());
  }

  Future<void> _skip() async {
    await _finish(skipSave: true);
  }

  Future<void> _finish({required bool skipSave}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!skipSave) {
        await widget.repository.updateNetworkConfig(_draft);
      }
      await ForumNetworkSetupStore.markCompleted();
      await widget.onFinished?.call();
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(!skipSave);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepMeta = _step.meta;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _NetworkBackdropPainter(_ambientController.value),
                );
              },
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      if (widget.allowSkip)
                        TextButton(
                          onPressed: _saving ? null : _skip,
                          child: const Text('跳过'),
                        )
                      else
                        IconButton(
                          tooltip: '关闭',
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      const Spacer(),
                      _ProbeBadge(
                        probing: _probing,
                        onTap: _probing ? null : _probeCurrentStep,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    children: [
                      const _SignalHeroVisual(),
                      const SizedBox(height: 16),
                      _SegmentedProgress(
                        current: _steps.indexOf(_step),
                        total: _steps.length,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        stepMeta.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.08),
                      const SizedBox(height: 8),
                      Text(
                        stepMeta.subtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textMuted,
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: 20),
                      PageTransitionSwitcher(
                        duration: 320.ms,
                        reverse: false,
                        transitionBuilder:
                            (child, primaryAnimation, secondaryAnimation) {
                          return SharedAxisTransition(
                            animation: primaryAnimation,
                            secondaryAnimation: secondaryAnimation,
                            transitionType: SharedAxisTransitionType.horizontal,
                            fillColor: Colors.transparent,
                            child: child,
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _buildStepContent(),
                        ),
                      ),
                    ],
                  ),
                ),
                _BottomBar(
                  backLabel: _stepIndex <= 0 ? '关闭' : '上一步',
                  nextLabel: _step == _SetupStep.summary ? '开始使用' : '下一步',
                  saving: _saving,
                  onBack: _saving ? null : _goBack,
                  onNext: _saving ? null : _goNext,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _SetupStep.mode:
        return _buildModeStep();
      case _SetupStep.encrypted:
        return _buildEncryptedStep();
      case _SetupStep.entrance:
        return _buildEntranceStep();
      case _SetupStep.route:
        return _buildRouteStep();
      case _SetupStep.summary:
        return _buildSummaryStep();
    }
  }

  Widget _buildEncryptedStep() {
    final providers = [...DohProvider.values]..sort(
        (a, b) => _ProbeReading.compare(
          _ProbeReading.fromDoh(_dohResults[a]),
          _ProbeReading.fromDoh(_dohResults[b]),
        ),
      );
    final fastest =
        providers.where((item) => _dohResults[item]?.success == true);
    final fastestProvider = fastest.isEmpty ? null : fastest.first;

    return Column(
      children: [
        ...providers.indexed.map((entry) {
          final index = entry.$1;
          final provider = entry.$2;
          final result = _dohResults[provider];
          final status = _ProbeStatus.fromDoh(result, probing: _probing);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SetupOptionCard(
              icon: Icons.bolt_outlined,
              title: '解析线路 ${index + 1}',
              subtitle: '自动探测可用性与响应速度。',
              selected: _draft.dohProvider == provider,
              fastest: provider == fastestProvider,
              statusLabel: status.label,
              success: status.success,
              onTap: () => _selectEncrypted(true, provider),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildModeStep() {
    return Column(
      children: [
        _SetupOptionCard(
          icon: Icons.auto_fix_high_outlined,
          title: '开启网络优化',
          subtitle: '自动探测解析线路、访问入口和专属线路。',
          selected: _optimizeEnabled,
          recommended: true,
          onTap: () => _selectMode(optimize: true),
        ),
        const SizedBox(height: 12),
        _SetupOptionCard(
          icon: Icons.router_outlined,
          title: '系统默认解析',
          subtitle: '能够直接访问，无需网络优化。',
          selected: !_optimizeEnabled,
          statusLabel: !_optimizeEnabled ? '已选择' : null,
          onTap: () => _selectMode(optimize: false),
        ),
      ],
    );
  }

  Widget _buildEntranceStep() {
    final sites = [...ForumNetworkConfig.sites]..sort(
        (a, b) => _ProbeReading.compare(
          _ProbeReading.fromSite(_siteResults[a.host]),
          _ProbeReading.fromSite(_siteResults[b.host]),
        ),
      );
    final fastest =
        sites.where((item) => _siteResults[item.host]?.success == true);
    final fastestSite = fastest.isEmpty ? null : fastest.first;

    return Column(
      children: sites.map((site) {
        final result = _siteResults[site.host];
        final status = _ProbeStatus.fromSite(result, probing: _probing);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SetupOptionCard(
            icon: Icons.public_outlined,
            title: site.host,
            subtitle: '当前访问域名',
            selected: _draft.site == site,
            fastest: site == fastestSite,
            statusLabel: status.label,
            success: status.success,
            onTap: () => _selectSite(site),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRouteStep() {
    final dynamicResult = _dynamicRouteResult;
    final dynamicStatus =
        _ProbeStatus.fromSite(dynamicResult, probing: _probing);
    final addresses = [..._cachedAddresses]..sort(
        (a, b) => _compareAddress(
          _addressResults[a.address],
          _addressResults[b.address],
        ),
      );
    final fastestAddresses = addresses
        .where((item) => _addressResults[item.address]?.success == true);
    final fastestAddress =
        fastestAddresses.isEmpty ? null : fastestAddresses.first;

    return Column(
      children: [
        _SetupOptionCard(
          icon: Icons.sync_alt,
          title: '智能优选（推荐）',
          subtitle: '让当前网络自动选择连接路径，适合大多数情况。',
          selected: _draft.fixedAddress == null,
          recommended: true,
          fastest: dynamicResult?.success == true &&
              _isDynamicFastest(dynamicResult, fastestAddress),
          statusLabel: dynamicStatus.label,
          success: dynamicStatus.success,
          onTap: () => _selectRoute(null),
        ),
        const SizedBox(height: 12),
        if (addresses.isEmpty)
          const _SetupEmptyState()
        else
          ...addresses.indexed.map((entry) {
            final index = entry.$1;
            final address = entry.$2;
            final result = _addressResults[address.address];
            final status = _ProbeStatus.fromAddress(result, probing: _probing);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SetupOptionCard(
                icon: Icons.cable_outlined,
                title: ForumNetworkConfig.routeLabelForAddress(
                  address.address,
                  index + 1,
                ),
                subtitle: '已完成线路探测。',
                selected: _draft.fixedAddress == address.address,
                fastest: address == fastestAddress &&
                    !_isDynamicFastest(dynamicResult, fastestAddress),
                statusLabel: status.label,
                success: status.success,
                onTap: () => _selectRoute(address.address),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSummaryStep() {
    final fixedAddress = _draft.fixedAddress;
    return Column(
      children: [
        _SummaryPanel(
          rows: [
            _SummaryRow(
              label: '解析方式',
              value: _draft.dohEnabled ? '智能加密解析' : '系统默认解析',
            ),
            _SummaryRow(
              label: '访问入口',
              value: _draft.site.host,
            ),
            _SummaryRow(
              label: '线路策略',
              value: fixedAddress == null
                  ? '智能优选（推荐）'
                  : ForumNetworkConfig.routeLabelForAddress(fixedAddress, 1),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ConfidencePanel(
          title: '连接方案已准备好',
          subtitle:
              fixedAddress == null ? '应用会按当前网络环境自动选择连接路径。' : '当前会优先使用你选择的专属线路。',
        ),
      ],
    );
  }

  bool _isDynamicFastest(
    ForumSiteProbeResult? dynamicResult,
    InternetAddress? fastestAddress,
  ) {
    if (dynamicResult?.success != true) return false;
    if (fastestAddress == null) return true;
    final addressResult = _addressResults[fastestAddress.address];
    if (addressResult?.success != true) return true;
    return dynamicResult!.elapsed <= addressResult!.elapsed;
  }

  int _compareAddress(ForumAddressProbeResult? a, ForumAddressProbeResult? b) =>
      _ProbeReading.compare(
        _ProbeReading.fromAddress(a),
        _ProbeReading.fromAddress(b),
      );
}

class _SetupFlowPlan {
  const _SetupFlowPlan._();

  static List<_SetupStep> steps({
    required bool allowSkip,
    required bool optimizeEnabled,
  }) {
    if (!allowSkip) {
      return const [
        _SetupStep.encrypted,
        _SetupStep.entrance,
        _SetupStep.route,
        _SetupStep.summary,
      ];
    }
    if (!optimizeEnabled) {
      return const [
        _SetupStep.mode,
        _SetupStep.entrance,
        _SetupStep.summary,
      ];
    }
    return const [
      _SetupStep.mode,
      _SetupStep.encrypted,
      _SetupStep.entrance,
      _SetupStep.route,
      _SetupStep.summary,
    ];
  }
}

extension _SetupStepMeta on _SetupStep {
  _StepMeta get meta {
    switch (this) {
      case _SetupStep.mode:
        return const _StepMeta(
          '网络优化',
          '如果当前网络能直接访问，可以只选择访问入口。',
        );
      case _SetupStep.encrypted:
        return const _StepMeta(
          '加密解析',
          '正在为你探测更稳定的解析线路。',
        );
      case _SetupStep.entrance:
        return const _StepMeta(
          '访问入口',
          '选择你喜欢的入口，或是更快的入口。',
        );
      case _SetupStep.route:
        return const _StepMeta(
          '线路选择',
          '智能优选适合大多数情况，专属线路适合备用。',
        );
      case _SetupStep.summary:
        return const _StepMeta(
          '连接就绪',
          '这是即将应用的连接方案。',
        );
    }
  }
}

class _StepMeta {
  const _StepMeta(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _ProbeReading {
  const _ProbeReading({required this.success, this.elapsed});

  factory _ProbeReading.fromDoh(DohProbeResult? result) {
    return _ProbeReading(success: result?.success, elapsed: result?.elapsed);
  }

  factory _ProbeReading.fromSite(ForumSiteProbeResult? result) {
    return _ProbeReading(success: result?.success, elapsed: result?.elapsed);
  }

  factory _ProbeReading.fromAddress(ForumAddressProbeResult? result) {
    return _ProbeReading(success: result?.success, elapsed: result?.elapsed);
  }

  final bool? success;
  final Duration? elapsed;

  static int compare(_ProbeReading a, _ProbeReading b) {
    if (a.success == true && b.success != true) return -1;
    if (a.success != true && b.success == true) return 1;
    if (a.success == true && b.success == true) {
      return a.elapsed!.compareTo(b.elapsed!);
    }
    return 0;
  }
}

class _ProbeStatus {
  const _ProbeStatus({this.label, this.success});

  factory _ProbeStatus.fromDoh(
    DohProbeResult? result, {
    required bool probing,
  }) {
    return _ProbeStatus.fromValues(
      success: result?.success,
      latencyLabel: result?.latencyLabel,
      message: result?.message,
      probing: probing,
    );
  }

  factory _ProbeStatus.fromSite(
    ForumSiteProbeResult? result, {
    required bool probing,
  }) {
    return _ProbeStatus.fromValues(
      success: result?.success,
      latencyLabel: result?.latencyLabel,
      message: result?.message,
      probing: probing,
    );
  }

  factory _ProbeStatus.fromAddress(
    ForumAddressProbeResult? result, {
    required bool probing,
  }) {
    return _ProbeStatus.fromValues(
      success: result?.success,
      latencyLabel: result?.latencyLabel,
      message: result?.message,
      probing: probing,
    );
  }

  factory _ProbeStatus.fromValues({
    required bool? success,
    required String? latencyLabel,
    required String? message,
    required bool probing,
  }) {
    if (success == null) {
      return _ProbeStatus(label: probing ? '测速中' : null);
    }
    return _ProbeStatus(
      label: success ? latencyLabel : message,
      success: success,
    );
  }

  final String? label;
  final bool? success;
}

class _SignalHeroVisual extends StatelessWidget {
  const _SignalHeroVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFFFEEF0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1FFF5F6D),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ...List.generate(3, (index) {
                  return Container(
                    width: 58 + index * 28,
                    height: 58 + index * 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brand.withValues(
                          alpha: 0.18 - index * 0.035,
                        ),
                        width: 1.4,
                      ),
                    ),
                  )
                      .animate(
                        onPlay: (controller) => controller.repeat(),
                        delay: (index * 180).ms,
                      )
                      .scale(
                        begin: const Offset(0.88, 0.88),
                        end: const Offset(1.06, 1.06),
                        duration: 1800.ms,
                        curve: Curves.easeInOut,
                      )
                      .fade(
                        begin: 0.8,
                        end: 0.28,
                        duration: 1800.ms,
                      );
                }),
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hub_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 420.ms).scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          curve: Curves.easeOutCubic,
        );
  }
}

class _ProbeBadge extends StatelessWidget {
  const _ProbeBadge({required this.probing, required this.onTap});

  final bool probing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: 220.ms,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEFFAF3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF9DE7B4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                probing ? '线路探测中' : '重新测速',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (index) {
        final active = index <= current;
        return Expanded(
          child: AnimatedContainer(
            duration: 240.ms,
            height: 5,
            margin: EdgeInsets.only(right: index == total - 1 ? 0 : 6),
            decoration: BoxDecoration(
              color: active ? AppColors.brand : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? AppColors.brand : AppColors.border,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SetupOptionCard extends StatelessWidget {
  const _SetupOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.statusLabel,
    this.success,
    this.recommended = false,
    this.fastest = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? statusLabel;
  final bool? success;
  final bool selected;
  final bool recommended;
  final bool fastest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.brand : Colors.transparent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: 220.ms,
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? 0.94 : 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? AppColors.brand.withValues(alpha: 0.14)
                    : const Color(0x08000000),
                blurRadius: selected ? 20 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _SetupIcon(icon: icon, selected: selected),
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
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    if (fastest || recommended || statusLabel != null) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (fastest)
                            const _MiniPill(label: '最快', positive: true),
                          if (recommended)
                            const _MiniPill(label: '推荐', positive: true),
                          if (statusLabel != null)
                            _MiniPill(
                              label: statusLabel!,
                              positive: success ?? true,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppColors.brand : AppColors.textFaint,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.04);
  }
}

class _SetupIcon extends StatelessWidget {
  const _SetupIcon({required this.icon, required this.selected});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: 220.ms,
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: selected ? AppColors.brandSoft : AppColors.inkSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: selected ? AppColors.brand : AppColors.link,
        size: 22,
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? const Color(0xFF168A46) : AppColors.brandDark;
    final background = positive ? const Color(0xFFEAF7EF) : AppColors.brandSoft;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 22, maxWidth: 96),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SetupEmptyState extends StatelessWidget {
  const _SetupEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const _SetupIcon(icon: Icons.route_outlined, selected: false),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '暂时没有可用的专属线路，使用智能优选即可。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.rows});

  final List<_SummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Text(
                  row.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    row.value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryRow {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _ConfidencePanel extends StatelessWidget {
  const _ConfidencePanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB8EBC8)),
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF16A34A),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x6616A34A),
                    blurRadius: 18,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Icon(Icons.done, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ).animate(onPlay: (controller) => controller.repeat()).shimmer(
          duration: 2200.ms,
          color: Colors.white.withValues(alpha: 0.35),
        );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.backLabel,
    required this.nextLabel,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });

  final String backLabel;
  final String nextLabel;
  final bool saving;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          border: const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: Text(backLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onNext,
                child: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(nextLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkBackdropPainter extends CustomPainter {
  const _NetworkBackdropPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const background = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFF7F8),
        Color(0xFFF7FBFF),
        Color(0xFFF5FFF8),
      ],
    );
    canvas.drawRect(rect, Paint()..shader = background.createShader(rect));

    final nodes = List.generate(8, (index) {
      final angle = t * math.pi * 2 + index * 0.72;
      final x = size.width * (0.15 + (index % 4) * 0.24) + math.sin(angle) * 10;
      final y = size.height * (0.12 + (index ~/ 4) * 0.34) +
          math.cos(angle * 0.8) * 16;
      return Offset(x, y);
    });

    final linePaint = Paint()
      ..color = AppColors.brand.withValues(alpha: 0.12)
      ..strokeWidth = 1.2;
    for (var i = 0; i < nodes.length - 1; i++) {
      canvas.drawLine(nodes[i], nodes[i + 1], linePaint);
    }

    for (var i = 0; i < nodes.length; i++) {
      final pulse = (math.sin((t * math.pi * 2) + i) + 1) / 2;
      final point = nodes[i];
      canvas.drawCircle(
        point,
        10 + pulse * 10,
        Paint()..color = const Color(0xFF16A34A).withValues(alpha: 0.05),
      );
      canvas.drawCircle(
        point,
        3.4,
        Paint()..color = AppColors.brand.withValues(alpha: 0.32),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkBackdropPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}
