import 'package:flutter/material.dart';

import 'app.dart';
import 'services/forum_text_size_settings.dart';
import 'services/forum_http_routing.dart';
import 'services/image_loading_settings.dart';
import 'services/loading_preferences.dart';
import 'services/perf_trace.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ForumHttpRouting.install();
  PerfTrace.installFrameLogger();
  await AppThemeController.load();
  await ImageLoadingSettings.loadMode();
  await ForumTextSizeSettings.load();
  // Unreadable, every list pages by hand; 设置 › 加载与分页 retries.
  await LoadingPreferences.load().then((_) {}, onError: (_) {});
  runApp(const SouthPlusApp());
}
