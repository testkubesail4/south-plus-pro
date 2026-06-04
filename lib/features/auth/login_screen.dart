import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeShell(repository: _repo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          const Icon(Icons.forum_outlined, color: Colors.white),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '登录 South Plus',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '使用账号和验证码继续参与讨论。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                    const SizedBox(height: 24),
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
                          const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                            height: 72,
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
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _InlineError(message: _error!),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _loading
                            ? const _LoadingButtonLabel()
                            : const Text('登录'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => HomeShell(repository: _repo),
                                ),
                              );
                            },
                      child: const Text('先浏览公开内容'),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 260.ms, curve: Curves.easeOutCubic)
                  .slideY(
                    begin: 0.04,
                    duration: 260.ms,
                    curve: Curves.easeOutCubic,
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
      '2' => 'Email',
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
      segments: const [
        ButtonSegment(
          value: '0',
          icon: Icon(Icons.person_outline),
          label: Text('用户名'),
        ),
        ButtonSegment(
          value: '1',
          icon: Icon(Icons.tag),
          label: Text('UID'),
        ),
        ButtonSegment(
          value: '2',
          icon: Icon(Icons.alternate_email),
          label: Text('Email'),
        ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '登录设置',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: cookieTime,
          decoration: const InputDecoration(
            labelText: 'Cookie 有效期',
            prefixIcon: Icon(Icons.schedule_outlined),
          ),
          items: const [
            DropdownMenuItem(value: '31536000', child: Text('一年')),
            DropdownMenuItem(value: '2592000', child: Text('一个月')),
            DropdownMenuItem(value: '86400', child: Text('一天')),
            DropdownMenuItem(value: '3600', child: Text('一小时')),
            DropdownMenuItem(value: '0', child: Text('即时')),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onCookieTimeChanged(value);
                }
              : null,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: hideLogin,
          onChanged:
              enabled ? (value) => onHideLoginChanged(value ?? false) : null,
          title: const Text('隐身登录'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
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
        const SizedBox(width: 12),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showCaptchaPreview(context),
          child: Container(
            height: 64,
            width: 154,
            padding: const EdgeInsets.all(4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
            ),
          ),
        ),
        IconButton(
          tooltip: '刷新验证码',
          onPressed: enabled ? onRefresh : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
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
    return const Row(
      key: ValueKey('login-loading-label'),
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
        SizedBox(width: 10),
        Text('登录中...'),
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
      icon: const Icon(Icons.refresh),
      label: Text('验证码加载失败：$message'),
    );
  }
}
