import 'package:flutter/services.dart';

import 'image_saver.dart';

class ThreadShareService {
  ThreadShareService._();

  /// Returns true when the native chooser opens, false after copying the URL.
  static Future<bool> share({
    required String title,
    required String url,
  }) async {
    if (ImageSaver.canShare) {
      try {
        await ImageSaver.shareText('$title\n$url');
        return true;
      } on ImageSaveException {
        // A missing native handler must still leave a usable share action.
      }
    }
    await Clipboard.setData(ClipboardData(text: url));
    return false;
  }
}
