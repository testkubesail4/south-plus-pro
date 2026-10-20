import 'package:flutter/material.dart';

import '../../services/forum_network_config.dart';
import '../../theme/app_theme.dart';
import 'network_options.dart';
import 'proxy_form.dart';

/// Shown at startup when the saved network settings cannot be read. Every
/// request stays paused until the user saves new settings, so a broken
/// proxy setting never turns into a silent direct connection.
class NetworkRepairScreen extends StatelessWidget {
  const NetworkRepairScreen({
    super.key,
    required this.message,
    required this.onRepaired,
  });

  /// A safe description from the loader; it never carries credentials.
  final String? message;
  final Future<void> Function() onRepaired;

  Future<void> _write(BuildContext context, ForumNetworkConfig config) async {
    await ForumNetworkSettings.save(config);
    await onRepaired();
  }

  Future<void> _useDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('改用默认设置？'),
        content: const Text('已保存的网络设置（包括代理）会被替换。之后的请求不经过代理，'
            '而是使用网络优化连接；接着会重新进入网络引导。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('改用默认设置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await _write(context,
          const ForumNetworkConfig(site: ForumNetworkConfig.defaultSite));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NetworkPage(
      title: '网络设置无法读取',
      children: [
        Text(
          '已保存的网络设置无法使用。为避免绕过你的代理直接连接，应用已暂停所有网络请求。'
          '请重新填写代理，或明确改用默认设置。',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(message!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpace.xl),
        ProxyForm(
          submitLabel: '保存代理并重试',
          onSubmit: (proxy) => _write(
            context,
            ForumNetworkConfig(
              site: ForumNetworkConfig.defaultSite,
              mode: ForumNetworkMode.proxy,
              proxy: proxy,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        OutlinedButton(
          onPressed: () => _useDefaults(context),
          child: const Text('改用默认设置'),
        ),
      ],
    );
  }
}
