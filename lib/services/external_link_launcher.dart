import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'forum_url_resolver.dart';

class ExternalLinkLauncher {
  ExternalLinkLauncher._();

  static Future<void> open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !ForumUrlResolver.isSafeExternalUrl(url)) {
      await _copyFailedUrl(url);
      throw const ExternalLinkLaunchException('链接格式无效，已复制链接');
    }

    try {
      final launched = await launchUrlString(
        url.trim(),
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;

      await _copyFailedUrl(url);
      throw const ExternalLinkLaunchException('没有找到可打开该链接的应用，已复制链接');
    } catch (_) {
      await _copyFailedUrl(url);
      throw const ExternalLinkLaunchException('打开链接失败，已复制链接');
    }
  }

  static Future<void> openInBrowser(String url) async {
    final raw = url.trim();
    if (!ForumUrlResolver.isSafeExternalUrl(raw) ||
        !{'http', 'https'}.contains(Uri.tryParse(raw)?.scheme)) {
      throw const ExternalLinkLaunchException('无法在浏览器中打开此链接');
    }
    try {
      if (await supportsLaunchMode(LaunchMode.inAppBrowserView) &&
          await launchUrlString(raw, mode: LaunchMode.inAppBrowserView)) return;
    } catch (_) {
      throw const ExternalLinkLaunchException('无法在浏览器中打开此链接');
    }
    throw const ExternalLinkLaunchException('无法在浏览器中打开此链接');
  }

  static Future<void> _copyFailedUrl(String url) {
    return Clipboard.setData(ClipboardData(text: url));
  }
}

class ExternalLinkLaunchException implements Exception {
  const ExternalLinkLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}
