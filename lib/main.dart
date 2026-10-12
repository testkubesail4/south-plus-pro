import 'package:flutter/material.dart';

import 'app.dart';
import 'services/forum_text_size_settings.dart';
import 'services/image_loading_settings.dart';
import 'services/perf_trace.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfTrace.installFrameLogger();
  await AppThemeController.load();
  await ImageLoadingSettings.loadMode();
  await ForumTextSizeSettings.load();
  runApp(const SouthPlusApp());
}
