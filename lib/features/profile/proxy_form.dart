import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';

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
          // Choice chips, not segments: at large text a chip moves to the
          // next line whole instead of splitting or shrinking SOCKS5.
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final (type, label) in const [
                (ForumProxyType.http, 'HTTP'),
                (ForumProxyType.https, 'HTTPS'),
                (ForumProxyType.socks5, 'SOCKS5'),
              ])
                ChoiceChip(
                  label: Text(label),
                  showCheckmark: false,
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
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
          // Only HTTP sends the credentials in the clear; its warning
          // cross-fades in.
          AppSwitcher(
            id: _type == ForumProxyType.http,
            child: _type != ForumProxyType.http
                ? const SizedBox(width: double.infinity)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_open_outlined,
                          size: 16, color: AppColors.textMuted),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          'HTTP 代理以明文发送用户名和密码，请只用可信任的代理',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          // While saving, a spinner joins the label (DESIGN §6).
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            label: Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
