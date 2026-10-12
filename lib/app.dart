import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';
import 'features/profile/network_setup_flow_screen.dart';
import 'services/forum_network_config.dart';
import 'services/forum_network_setup_store.dart';
import 'services/forum_repository.dart';
import 'services/forum_text_size_settings.dart';
import 'theme/app_theme.dart';

class SouthPlusApp extends StatefulWidget {
  const SouthPlusApp({super.key});

  @override
  State<SouthPlusApp> createState() => _SouthPlusAppState();
}

class _SouthPlusAppState extends State<SouthPlusApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.notifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '南+',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          builder: (context, child) {
            return ValueListenableBuilder<ForumTextSize>(
              valueListenable: ForumTextSizeSettings.notifier,
              builder: (context, size, _) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: _ScaledTextScaler(
                      media.textScaler,
                      size.scale,
                    ),
                  ),
                  child: child!,
                );
              },
            );
          },
          home: SessionGate(onToggleTheme: AppThemeController.toggle),
        );
      },
    );
  }
}

/// Applies the user's text size on top of the system scaler, keeping any
/// nonlinear system scaling intact.
class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is _ScaledTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

class SessionGate extends StatefulWidget {
  const SessionGate({
    super.key,
    ForumRepository? repository,
    this.onToggleTheme,
  }) : repository = repository;

  final ForumRepository? repository;
  final VoidCallback? onToggleTheme;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  ForumRepository? _repository;
  late Future<_SessionGateResult> _restoreFuture = _restoreSession();

  Future<_SessionGateResult> _restoreSession() async {
    _repository ??= widget.repository ??
        ForumRepository(config: await ForumNetworkSettings.load());
    if (!await ForumNetworkSetupStore.isCompleted()) {
      return _SessionGateResult(
        repository: _repository!,
        needsNetworkSetup: true,
        restored: false,
      );
    }
    return _SessionGateResult(
      repository: _repository!,
      needsNetworkSetup: false,
      restored: await _repository!.restoreSession(),
    );
  }

  void _retry() {
    setState(() {
      _restoreFuture = _restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SessionGateResult>(
      future: _restoreFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SessionError(
            message: '${snapshot.error}',
            onRetry: _retry,
            onContinue: () {
              setState(() {
                _repository ??= widget.repository ??
                    ForumRepository(
                      config: const ForumNetworkConfig(
                        site: ForumNetworkConfig.defaultSite,
                        dohEnabled: true,
                        dohProvider: ForumNetworkConfig.defaultProvider,
                      ),
                    );
                _restoreFuture = Future<_SessionGateResult>.value(
                  _SessionGateResult(
                    repository: _repository!,
                    needsNetworkSetup: false,
                    restored: false,
                  ),
                );
              });
            },
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const _SessionSplash();
        }

        final result = snapshot.requireData;
        if (result.needsNetworkSetup) {
          return NetworkSetupFlowScreen(
            repository: result.repository,
            allowSkip: true,
            onFinished: () async {
              if (!mounted) return;
              setState(() {
                _restoreFuture = _restoreSession();
              });
            },
          );
        }

        return HomeShell(
          repository: result.repository,
          onToggleTheme: widget.onToggleTheme,
        );
      },
    );
  }
}

class _SessionGateResult {
  const _SessionGateResult({
    required this.repository,
    required this.needsNetworkSetup,
    required this.restored,
  });

  final ForumRepository repository;
  final bool needsNetworkSetup;
  final bool restored;
}

class _SessionSplash extends StatelessWidget {
  const _SessionSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 18),
              Text(
                '南+',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '正在恢复登录状态',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionError extends StatelessWidget {
  const _SessionError({
    required this.message,
    required this.onRetry,
    required this.onContinue,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '登录状态恢复失败',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: onContinue,
                  child: const Text('先浏览公开内容'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
