import 'package:flutter/material.dart';

import 'app.dart';
import 'services/perf_trace.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfTrace.installFrameLogger();
  await AppThemeController.load();
  runApp(const SouthPlusApp());
}
