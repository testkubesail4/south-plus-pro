import 'package:flutter/services.dart';

class ImageSaver {
  ImageSaver._();

  static const _channel = MethodChannel('south_plus_rewrite/image_saver');

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
