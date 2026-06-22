import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/scheduler.dart';

class PerfTrace {
  PerfTrace._();

  static const bool enabled =
      bool.fromEnvironment('FORUM_PERF_TRACE', defaultValue: false);

  static bool _frameLoggerInstalled = false;
  static String _currentScreen = 'unknown';

  static void markScreen(String screen) {
    if (!enabled) return;
    _currentScreen = screen;
  }

  static void installFrameLogger() {
    if (!enabled || _frameLoggerInstalled) return;
    _frameLoggerInstalled = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
        final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
        if (buildMs < 8.0 && rasterMs < 8.0) continue;
        _log(
          'Slow frame screen=$_currentScreen '
          'build=${buildMs.toStringAsFixed(1)}ms '
          'raster=${rasterMs.toStringAsFixed(1)}ms',
        );
      }
    });
  }

  static T span<T>(
    String name,
    T Function() action, {
    Map<String, Object?>? arguments,
  }) {
    if (!enabled) return action();
    developer.Timeline.startSync(name, arguments: arguments);
    try {
      return action();
    } finally {
      developer.Timeline.finishSync();
    }
  }

  static void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    stdout.writeln('[PerfTrace][$timestamp] $message');
  }
}
