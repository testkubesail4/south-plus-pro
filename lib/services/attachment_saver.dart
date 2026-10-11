import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'forum_repository.dart';

class AttachmentSaver {
  AttachmentSaver._();
  static const _channel = MethodChannel('south_plus_rewrite/attachment_saver');

  static Future<bool> save(
    ForumRepository repository,
    String url, {
    String? suggestedName,
  }) async {
    final directory = await (await getTemporaryDirectory()).createTemp(
      'attachment_export_',
    );
    try {
      final attachment = await repository.downloadAttachment(
        url,
        directory: directory,
        suggestedName: suggestedName,
      );
      return await _channel.invokeMethod<bool>('saveAttachment', {
            'path': attachment.file.path,
            'fileName': attachment.fileName,
            'mimeType': attachment.mimeType,
          }) ??
          false;
    } on MissingPluginException {
      throw const AttachmentSaveException('当前平台不支持保存附件');
    } on PlatformException catch (error) {
      throw AttachmentSaveException(error.message ?? '保存附件失败');
    } finally {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}

class AttachmentSaveException implements Exception {
  const AttachmentSaveException(this.message);
  final String message;
  @override
  String toString() => message;
}
