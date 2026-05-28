import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';
import 'theme/app_theme.dart';

class SouthPlusApp extends StatelessWidget {
  const SouthPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'South Plus',
      theme: AppTheme.light,
      home: const HomeShell(),
    );
  }
}
