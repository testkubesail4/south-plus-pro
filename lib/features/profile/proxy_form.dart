import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../theme/app_theme.dart';

/// "SOCKS5 [::1]:1080"-style summary; credentials are never included.
String proxyLabel(ForumProxy proxy) {
  final host = proxy.host.contains(':') ? '[${proxy.host}]' : proxy.host;
  return '${proxy.type.name.toUpperCase()} $host:${proxy.port}';
}

/// Asks before turning the proxy off, since requests then go out directly.
Future<bool> confirmDisableProxy(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('停用代理？'),
      content: const Text('之后所有请求将不经代理，直接连接论坛。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('停用代理，改为直接连接'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Proxy type, host, port and optional credentials. [ForumProxy] validates;
/// its message is shown as-is so the form and the model never disagree.
class ProxyForm extends StatefulWidget {
  const ProxyForm({
    super.key,
    this.initial,
    required this.submitLabel,
    required this.onSubmit,
  });

  final ForumProxy? initial;
  final String submitLabel;
  final Future<void> Function(ForumProxy proxy) onSubmit;

  @override
  State<ProxyForm> createState() => _ProxyFormState();
}

class _ProxyFormState extends State<ProxyForm> {
  late var _type = widget.initial?.type ?? ForumProxyType.http;
  late final _host = TextEditingController(text: widget.initial?.host);
  late final _port =
      TextEditingController(text: widget.initial?.port.toString());
  late final _username = TextEditingController(text: widget.initial?.username);
  late final _password = TextEditingController(text: widget.initial?.password);
  String? _error;
  var _saving = false;

  @override
  void dispose() {
    for (final controller in [_host, _port, _username, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final ForumProxy proxy;
    try {
      proxy = ForumProxy(
        type: _type,
        host: _host.text,
        port: int.tryParse(_port.text.trim()) ?? 0,
        username: _username.text,
        password: _password.text,
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.onSubmit(proxy);
    } catch (_) {
      // Never show the error itself: it may carry the proxy credentials.
      if (mounted) setState(() => _error = '保存代理失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ForumProxyType>(
            segments: const [
              ButtonSegment(value: ForumProxyType.http, label: Text('HTTP')),
              ButtonSegment(value: ForumProxyType.https, label: Text('HTTPS')),
              ButtonSegment(
                value: ForumProxyType.socks5,
                label: Text('SOCKS5'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.single),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '主机',
                    hintText: '127.0.0.1',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '7890',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            autocorrect: false,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: '用户名（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: '密码（可选）'),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '使用代理时，所有请求都经由代理发送，网络优化与加密解析会关闭。'
            '${_type == ForumProxyType.http ? 'HTTP 代理的用户名和密码以明文发送给代理，请只使用可信任的代理。' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

/// Shown at startup when the saved proxy cannot be used: fix it, or turn
/// it off deliberately. The app never falls back to a direct connection.
class ProxyRepairScreen extends StatelessWidget {
  const ProxyRepairScreen({
    super.key,
    required this.onSaveProxy,
    required this.onDisableProxy,
  });

  final Future<void> Function(ForumProxy proxy) onSaveProxy;
  final Future<void> Function() onDisableProxy;

  Future<void> _confirmDisable(BuildContext context) async {
    if (!await confirmDisableProxy(context)) return;
    try {
      await onDisableProxy();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('停用代理失败，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('代理设置无法使用')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '保存的代理设置无效，为避免绕过代理直接连接，已暂停所有网络请求。请重新填写代理，或明确停用代理。',
              style: TextStyle(color: AppColors.text, height: 1.45),
            ),
            const SizedBox(height: 18),
            ProxyForm(submitLabel: '保存并重试', onSubmit: onSaveProxy),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _confirmDisable(context),
              child: const Text('停用代理，改为直接连接'),
            ),
          ],
        ),
      ),
    );
  }
}
