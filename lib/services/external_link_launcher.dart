import 'package:flutter/services.dart';

class ExternalLinkLauncher {
  ExternalLinkLauncher._();

  static const _channel = MethodChannel('south_plus_rewrite/link_opener');

  static Future<void> open(String url) async {
    try {
      await _channel.invokeMethod<bool>('open', {'url': url});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: url));
      throw const ExternalLinkLaunchException('当前平台不支持打开链接，已复制链接');
    } on PlatformException catch (error) {
      await Clipboard.setData(ClipboardData(text: url));
      throw ExternalLinkLaunchException(
        error.message ?? '没有找到可打开该链接的应用，已复制链接',
      );
    }
  }
}

class ExternalLinkLaunchException implements Exception {
  const ExternalLinkLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}
