import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';
import 'services/forum_network_config.dart';
import 'services/forum_repository.dart';
import 'theme/app_theme.dart';

class SouthPlusApp extends StatelessWidget {
  const SouthPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'South Plus',
      theme: AppTheme.light,
      home: const SessionGate(),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, ForumRepository? repository})
      : repository = repository;

  final ForumRepository? repository;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  ForumRepository? _repository;
  late Future<bool> _restoreFuture = _restoreSession();

  Future<bool> _restoreSession() async {
    _repository ??= widget.repository ??
        ForumRepository(config: await ForumNetworkSettings.load());
    return _repository!.restoreSession();
  }

  void _retry() {
    setState(() {
      _restoreFuture = _restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
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
                _restoreFuture = Future<bool>.value(false);
              });
            },
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const _SessionSplash();
        }

        return HomeShell(repository: _repository!);
      },
    );
  }
}

class _SessionSplash extends StatelessWidget {
  const _SessionSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 18),
              Text(
                'South Plus',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
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
                  icon: const Icon(Icons.refresh),
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
