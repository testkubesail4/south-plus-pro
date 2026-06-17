import 'package:flutter/material.dart';

import 'app.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppThemeController.load();
  runApp(const SouthPlusApp());
}
