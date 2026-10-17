import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStatePreferences {
  static Future<void>? _pending;
  static bool _needsReload = false;

  static Future<T> _run<T>(Future<T> Function(SharedPreferences) operation) {
    final previous = _pending;
    final tail = Completer<void>();
    _pending = tail.future;
    Future<T> run() async {
      try {
        if (previous != null) await previous;
        final prefs = await SharedPreferences.getInstance();
        if (_needsReload) {
          await prefs.reload();
          _needsReload = false;
        }
        return await operation(prefs);
      } finally {
        // An idle queue must not retain a completed Future's scheduling zone.
        if (identical(_pending, tail.future)) _pending = null;
        tail.complete();
      }
    }

    return run();
  }

  static Future<T> read<T>(T Function(SharedPreferences) read) =>
      _run((prefs) async => read(prefs));

  static Future<void> write(Future<bool> Function(SharedPreferences) write) =>
      _run((prefs) async {
        try {
          if (!await write(prefs)) throw StateError('无法保存本地数据');
        } catch (_) {
          // The plugin changes its cache before the platform acknowledges writes.
          _needsReload = true;
          try {
            await prefs.reload();
            _needsReload = false;
          } catch (_) {/* Keep reads blocked until recovery succeeds. */}
          rethrow;
        }
      });
}
