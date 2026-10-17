import 'package:shared_preferences/shared_preferences.dart';

class LocalStatePreferences {
  static Future<void> _pending = Future.value();
  static bool _needsReload = false;

  static Future<T> _run<T>(Future<T> Function(SharedPreferences) operation) {
    final result = _pending.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (_needsReload) {
        await prefs.reload();
        _needsReload = false;
      }
      return operation(prefs);
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
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
