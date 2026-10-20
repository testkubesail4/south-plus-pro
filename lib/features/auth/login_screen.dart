import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/async_state_view.dart';
import '../common/brand_mark.dart';

/// Opens the login page; true once a login succeeded. The app shell follows
/// the session itself, so callers only refresh their own screen.
///
/// Pages pushed under the old session may hold its private content, so
/// login starts from the shell: every pushed page closes first, the caller's
/// own included unless it is a shell tab.
Future<bool> openLogin(BuildContext context, ForumRepository repository) async {
  final navigator = Navigator.of(context, rootNavigator: true)
    ..popUntil((route) => route.isFirst);
  final loggedIn = await navigator.push<bool>(
    MaterialPageRoute(builder: (_) => LoginScreen(repository: repository)),
  );
  return loggedIn ?? false;
}

/// Shown in place of account-only content while logged out (DESIGN.md §10).
class LoginPrompt extends StatelessWidget {
  const LoginPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onLogin,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    // Scrollable so it fits at large text sizes.
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl * 2),
      children: [
        EmptyStateView(
          icon: icon,
          title: title,
          message: message,
          action: FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login),
            label: const Text('去登录'),
          ),
        ),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, ForumRepository? repository})
    : repository = repository;

  final ForumRepository? repository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final ForumRepository _repo = widget.repository ?? ForumRepository();
  late Future<LoginChallenge?> _challengeFuture;
  LoginChallenge? _challenge;
  String? _challengeLoadError;

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  bool _loading = false;
  String? _error;
  String _loginType = '0';
  bool _hideLogin = false;
  String _cookieTime = '31536000';
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _challengeFuture = _newChallengeFuture();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<LoginChallenge?> _loadChallenge() async {
    try {
      final challenge = await _repo.fetchLoginChallenge();
      _challenge = challenge;
      _challengeLoadError = null;
      return challenge;
    } catch (error) {
      _challenge = null;
      _challengeLoadError = '$error';
      return null;
    }
  }

  Future<LoginChallenge?> _newChallengeFuture() {
    return Future<LoginChallenge?>(() => _loadChallenge());
  }

  void _refreshChallenge({String? error}) {
    _captcha.clear();
    setState(() {
      _error = error;
      _challenge = null;
      _challengeLoadError = null;
      _challengeFuture = _newChallengeFuture();
    });
  }

  Future<void> _submit() async {
    final challenge = _challenge;
    if (challenge == null) {
      setState(() => _error = '验证码还没有加载完成');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _repo.submitLogin(
      username: _username.text,
      password: _password.text,
      captcha: _captcha.text,
      fields: {
        ...challenge.fields,
        'lgt': _loginType,
        'hideid': _hideLogin ? '1' : '0',
        'cktime': _cookieTime,
      },
    );

    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      _refreshChallenge(error: result.message);
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    // Back to the screen that asked for login; never a second app shell.
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // No card: the form sits on the canvas in one narrow column.
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.xl,
              AppSpace.sm,
              AppSpace.xl,
              AppSpace.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(size: 48),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text('登录南+', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpace.xs),
                  Text('使用账号和验证码继续参与讨论。', style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpace.xl),
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LoginTypeSelector(
                          value: _loginType,
                          enabled: !_loading,
                          onChanged: (value) {
                            setState(() => _loginType = value);
                          },
                        ),
                        const SizedBox(height: AppSpace.md),
                        TextField(
                          controller: _username,
                          decoration: InputDecoration(
                            labelText: _accountLabel,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          keyboardType: _accountKeyboardType,
                          autofillHints: _accountAutofillHints,
                          textInputAction: TextInputAction.next,
                          enabled: !_loading,
                        ),
                        const SizedBox(height: AppSpace.md),
                        TextField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              onPressed: _loading
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.next,
                          enabled: !_loading,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  FutureBuilder<LoginChallenge?>(
                    future: _challengeFuture,
                    builder: (context, snapshot) {
                      final challengeLoadError = _challengeLoadError;
                      if (challengeLoadError != null && !snapshot.hasData) {
                        return _ChallengeError(
                          message: challengeLoadError,
                          onRetry: _refreshChallenge,
                        );
                      }
                      if (!snapshot.hasData) {
                        return const SizedBox(
                          height: 56,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return _CaptchaField(
                        bytes: snapshot.data!.captchaBytes,
                        controller: _captcha,
                        enabled: !_loading,
                        onRefresh: _refreshChallenge,
                        onSubmit: _submit,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpace.sm),
                  _LoginOptions(
                    hideLogin: _hideLogin,
                    cookieTime: _cookieTime,
                    enabled: !_loading,
                    onHideLoginChanged: (value) {
                      setState(() => _hideLogin = value);
                    },
                    onCookieTimeChanged: (value) {
                      setState(() => _cookieTime = value);
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpace.md),
                    _InlineError(message: _error!),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  // The page's one primary action: large and full width.
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: AnimatedSwitcher(
                      duration: AppMotion.short,
                      child: _loading
                          ? const _LoadingButtonLabel()
                          : const Text('登录'),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).maybePop(false),
                    child: const Text('先浏览公开内容'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _accountLabel {
    return switch (_loginType) {
      '1' => 'UID',
      '2' => '邮箱',
      _ => '用户名',
    };
  }

  TextInputType get _accountKeyboardType {
    return switch (_loginType) {
      '1' => TextInputType.number,
      '2' => TextInputType.emailAddress,
      _ => TextInputType.text,
    };
  }

  Iterable<String>? get _accountAutofillHints {
    return switch (_loginType) {
      '2' => const [AutofillHints.email],
      _ => const [AutofillHints.username],
    };
  }
}

class _LoginTypeSelector extends StatelessWidget {
  const _LoginTypeSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      // Text only, so each label stays on one line at large text.
      segments: const [
        ButtonSegment(value: '0', label: Text('用户名')),
        ButtonSegment(value: '1', label: Text('UID')),
        ButtonSegment(value: '2', label: Text('邮箱')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: enabled
          ? (selected) {
              if (selected.isEmpty) return;
              onChanged(selected.first);
            }
          : null,
    );
  }
}

class _LoginOptions extends StatelessWidget {
  const _LoginOptions({
    required this.hideLogin,
    required this.cookieTime,
    required this.enabled,
    required this.onHideLoginChanged,
    required this.onCookieTimeChanged,
  });

  final bool hideLogin;
  final String cookieTime;
  final bool enabled;
  final ValueChanged<bool> onHideLoginChanged;
  final ValueChanged<String> onCookieTimeChanged;

  static const _cookieLabels = {
    '31536000': '一年',
    '2592000': '一个月',
    '86400': '一天',
    '3600': '一小时',
    '0': '即时',
  };

  // Rarely changed, so folded behind one row that names the current choice.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      // Top room for the dropdown's floating label.
      childrenPadding: const EdgeInsets.only(top: AppSpace.sm),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text('登录选项', style: theme.textTheme.titleSmall),
      subtitle: Text(
        '保持登录${_cookieLabels[cookieTime]}${hideLogin ? ' · 隐身登录' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        DropdownButtonFormField<String>(
          initialValue: cookieTime,
          decoration: const InputDecoration(
            labelText: 'Cookie 有效期',
            prefixIcon: Icon(Icons.schedule_outlined),
          ),
          items: [
            for (final MapEntry(:key, :value) in _cookieLabels.entries)
              DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onCookieTimeChanged(value);
                }
              : null,
        ),
        SwitchListTile(
          value: hideLogin,
          onChanged: enabled ? onHideLoginChanged : null,
          title: const Text('隐身登录'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _CaptchaField extends StatelessWidget {
  const _CaptchaField({
    required this.bytes,
    required this.controller,
    required this.enabled,
    required this.onRefresh,
    required this.onSubmit,
  });

  final Uint8List bytes;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onRefresh;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    // The image box takes the field's height at every text scale.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '验证码'),
              textInputAction: TextInputAction.done,
              enabled: enabled,
              onSubmitted: (_) {
                if (enabled) onSubmit();
              },
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Tooltip(
            message: '放大验证码',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => _showCaptchaPreview(context),
              child: Container(
                width: 136,
                padding: const EdgeInsets.all(AppSpace.xs),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Captchas are drawn for a white page.
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新验证码',
            onPressed: enabled ? onRefresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  void _showCaptchaPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Image.memory(
              bytes,
              width: 300,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          ),
        );
      },
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: errorColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: errorColor, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _LoadingButtonLabel extends StatelessWidget {
  const _LoadingButtonLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('login-loading-label'),
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          // The button's own (disabled) label colour, in light and dark.
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DefaultTextStyle.of(context).style.color,
          ),
        ),
        const SizedBox(width: 10),
        const Text('登录中...'),
      ],
    );
  }
}

class _ChallengeError extends StatelessWidget {
  const _ChallengeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onRetry,
      icon: Icon(Icons.refresh),
      label: Text('验证码加载失败：$message'),
    );
  }
}
