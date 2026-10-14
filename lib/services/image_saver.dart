import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ImageSaver {
  ImageSaver._();

  static const _channel = MethodChannel('south_plus_rewrite/image_saver');

  /// Sharing goes through the Android share sheet only.
  static bool get canShare => defaultTargetPlatform == TargetPlatform.android;

  /// Shares a file from the forum image cache directory.
  static Future<void> shareImageFile(String path) =>
      _share('shareImage', {'path': path});

  /// Shares [text] (a link) as plain text.
  static Future<void> shareText(String text) =>
      _share('shareText', {'text': text});

  static Future<void> _share(String method, Map<String, String> args) async {
    try {
      await _channel.invokeMethod<bool>(method, args);
    } on MissingPluginException {
      throw const ImageSaveException('当前平台不支持分享');
    } on PlatformException catch (error) {
      throw ImageSaveException(error.message ?? '分享失败');
    }
  }

  static Future<void> saveImage(
    Uint8List bytes, {
    String? sourceUrl,
  }) async {
    if (bytes.isEmpty) {
      throw const ImageSaveException('图片数据为空');
    }

    try {
      await _channel.invokeMethod<String>('saveImage', {
        'bytes': bytes,
        'fileName': _fileNameFromUrl(sourceUrl),
      });
    } on MissingPluginException {
      throw const ImageSaveException('当前平台不支持保存图片');
    } on PlatformException catch (error) {
      throw ImageSaveException(error.message ?? '保存图片失败');
    }
  }

  static String _fileNameFromUrl(String? url) {
    final extension = RegExp(
          r'\.(jpg|jpeg|png|gif|webp)(?:[?#]|$)',
          caseSensitive: false,
        ).firstMatch(url ?? '')?.group(1)?.toLowerCase() ??
        'jpg';
    return 'south_plus_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }
}

class ImageSaveException implements Exception {
  const ImageSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}
