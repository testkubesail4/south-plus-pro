import 'dart:typed_data';

import 'package:flutter/material.dart';

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
  late Future<LoginChallenge> _challengeFuture;
  LoginChallenge? _challenge;

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _challengeFuture = _loadChallenge();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<LoginChallenge> _loadChallenge() async {
    final challenge = await _repo.fetchLoginChallenge();
    _challenge = challenge;
    return challenge;
  }

  void _refreshChallenge() {
    _captcha.clear();
    setState(() {
      _error = null;
      _challenge = null;
      _challengeFuture = _loadChallenge();
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
      fields: challenge.fields,
    );

    if (!mounted) return;
    setState(() => _loading = false);
    if (!result.success) {
      setState(() => _error = result.message);
      _refreshChallenge();
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
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      enabled: !_loading,
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<LoginChallenge>(
                      future: _challengeFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _ChallengeError(
                            message: '${snapshot.error}',
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
                      Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Text(_loading ? '登录中...' : '登录'),
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
              ),
            ),
          ),
        ),
      ),
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
