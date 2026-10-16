import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/common/forum_link_opener.dart';
import 'features/home/home_shell.dart';
import 'features/profile/network_setup_flow_screen.dart';
import 'features/profile/proxy_form.dart';
import 'features/search/search_screen.dart';
import 'models/forum_models.dart';
import 'services/forum_incoming_link_service.dart';
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
          home: const SessionGate(),
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
  const SessionGate({super.key, ForumRepository? repository})
      : repository = repository;

  final ForumRepository? repository;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  ForumRepository? _repository;
  late Future<_SessionGateResult> _restoreFuture = _restoreSession();
  final _links = ForumIncomingLinkService();
  // Set while HomeShell is showing; links are held by the service until then.
  ForumRepository? _readyRepository;
  String? _linkKey;
  Route<dynamic>? _linkRoute;

  @override
  void initState() {
    super.initState();
    _links.start(onLink: _openLink, onRejected: _showRejectedLink);
  }

  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  void _setReady(ForumRepository? repository) {
    if (identical(repository, _readyRepository)) return;
    _readyRepository = repository;
    if (repository == null) {
      _links.setReady(false);
      return;
    }
    // Deliver after the shell's first frame so pushes land above it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_readyRepository, repository)) {
        _links.setReady(true);
      }
    });
  }

  // The same link while its page is still on top is a repeat, not a reopen.
  bool _alreadyShowing(String key) =>
      key == _linkKey && (_linkRoute?.isCurrent ?? false);

  void _rememberTopRoute(String key) {
    _linkKey = key;
    Navigator.of(context).popUntil((route) {
      _linkRoute = route;
      return true;
    });
  }

  void _openLink(String url) {
    final repository = _readyRepository;
    if (!mounted || repository == null || _alreadyShowing(url)) return;
    final prefill = repository.searchLinkPrefill(url);
    if (prefill != null) {
      final boardId = prefill.boardId;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SearchScreen(
          repository: repository,
          initialKeyword: prefill.keyword ?? '',
          initialUsername: prefill.username ?? '',
          initialBoard: boardId == null || boardId == 'all'
              ? null
              : ForumSearchBoard(id: boardId, name: ''),
        ),
      ));
    } else {
      switch (repository.forumLinkTarget(url)) {
        case ForumThreadLinkTarget() ||
              ForumUserLinkTarget() ||
              ForumBoardLinkTarget():
          openForumLink(context, repository, url);
        case ForumPageLinkTarget(:final url):
          _showRejectedLink(url);
          return;
        case ForumExternalLinkTarget() || ForumBlockedLinkTarget():
          _showRejectedLink(null);
          return;
      }
    }
    _rememberTopRoute(url);
  }

  // Inbound links never go to the browser: it may hand them straight back.
  void _showRejectedLink(String? copyableUrl) {
    final key = 'rejected:${copyableUrl ?? ''}';
    if (!mounted || _alreadyShowing(key)) return;
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _RejectedLinkSheet(
        url: copyableUrl,
        onCopy: () {
          Navigator.of(sheetContext).pop();
          Clipboard.setData(ClipboardData(text: copyableUrl!));
          messenger.showSnackBar(const SnackBar(content: Text('已复制链接')));
        },
      ),
    );
    _rememberTopRoute(key);
  }

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
        final result = snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError &&
                !snapshot.requireData.needsNetworkSetup
            ? snapshot.requireData
            : null;
        _setReady(result?.repository);

        if (snapshot.hasError) {
          if (_repository == null) {
            return ProxyRepairScreen(
              onSaveProxy: (proxy) async {
                await ForumNetworkSettings.saveProxy(proxy);
                if (mounted) _retry();
              },
              onDisableProxy: () async {
                await ForumNetworkSettings.disableProxy();
                if (mounted) _retry();
              },
            );
          }
          return _SessionError(
            message: '${snapshot.error}',
            onRetry: _retry,
            onContinue: _repository == null
                ? null
                : () {
                    setState(() {
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

        if (result == null) {
          return NetworkSetupFlowScreen(
            repository: snapshot.requireData.repository,
            allowSkip: true,
            onFinished: () async {
              if (!mounted) return;
              setState(() {
                _restoreFuture = _restoreSession();
              });
            },
          );
        }

        return HomeShell(repository: result.repository);
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
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '正在恢复登录状态',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RejectedLinkSheet extends StatelessWidget {
  const _RejectedLinkSheet({required this.url, required this.onCopy});

  final String? url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = this.url;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.link_off, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '暂不支持在应用内打开',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              url == null
                  ? '这个链接不是可在应用内浏览的论坛页面，已忽略。'
                  : '这个论坛页面还没有对应的应用内页面。为避免在应用和浏览器之间来回跳转，'
                      '不会自动打开浏览器，可以复制链接后自行打开。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
            if (url != null) ...[
              const SizedBox(height: 12),
              SelectableText(url, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (url != null)
                  OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制链接'),
                  ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ],
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
  final VoidCallback? onContinue;

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
                if (onContinue != null)
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
