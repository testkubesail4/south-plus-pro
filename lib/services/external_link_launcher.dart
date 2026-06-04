import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalLinkLauncher {
  ExternalLinkLauncher._();

  static Future<void> open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      await _copyFailedUrl(url);
      throw const ExternalLinkLaunchException('链接格式无效，已复制链接');
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;

      await _copyFailedUrl(url);
      throw const ExternalLinkLaunchException('没有找到可打开该链接的应用，已复制链接');
    } on PlatformException catch (error) {
      await _copyFailedUrl(url);
      throw ExternalLinkLaunchException(
        error.message ?? '没有找到可打开该链接的应用，已复制链接',
      );
    } catch (error) {
      await _copyFailedUrl(url);
      throw ExternalLinkLaunchException('打开链接失败：$error，已复制链接');
    }
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
