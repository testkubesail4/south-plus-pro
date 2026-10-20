import 'package:flutter/foundation.dart';

import 'local_state_preferences.dart';

enum LoadingDomain {
  thread,
  board,
  search,
  favorites,
  userContent,
  pm,
  friends,
  avatars,
}

enum LoadingMode { manual, continuous }

class LoadingPreferences {
  LoadingPreferences._();

  static const _threadKey = 'settings.autoLoadNextPage';
  static const _defaults = {
    LoadingDomain.thread: LoadingMode.manual,
    LoadingDomain.board: LoadingMode.continuous,
    LoadingDomain.search: LoadingMode.manual,
    LoadingDomain.favorites: LoadingMode.manual,
    LoadingDomain.userContent: LoadingMode.continuous,
    LoadingDomain.pm: LoadingMode.manual,
    LoadingDomain.friends: LoadingMode.manual,
    LoadingDomain.avatars: LoadingMode.manual,
  };
  static final notifier = ValueNotifier<Map<LoadingDomain, LoadingMode>>(
    _manualModes(),
  );
  static bool _ready = false;

  static bool get isReady => _ready;

  static LoadingMode modeFor(LoadingDomain domain) => notifier.value[domain]!;

  static Map<LoadingDomain, LoadingMode> _manualModes() => Map.unmodifiable({
        for (final domain in LoadingDomain.values) domain: LoadingMode.manual,
      });

  static String _key(LoadingDomain domain) => 'settings.loading.${domain.name}';

  static Future<Map<LoadingDomain, LoadingMode>> load() async {
    try {
      return await LocalStatePreferences.read((prefs) {
        final modes = <LoadingDomain, LoadingMode>{};
        for (final domain in LoadingDomain.values) {
          final raw = prefs.get(
            domain == LoadingDomain.thread ? _threadKey : _key(domain),
          );
          modes[domain] = domain == LoadingDomain.thread
              ? raw == true
                  ? LoadingMode.continuous
                  : LoadingMode.manual
              : LoadingMode.values
                      .where((mode) => mode.name == raw)
                      .firstOrNull ??
                  _defaults[domain]!;
        }
        _ready = true;
        return notifier.value = Map.unmodifiable(modes);
      });
    } catch (_) {
      _ready = false;
      notifier.value = _manualModes();
      rethrow;
    }
  }

  static Future<void> save(LoadingDomain domain, LoadingMode mode) =>
      LocalStatePreferences.write((prefs) async {
        if (!_ready) throw StateError('Loading preferences are not loaded');
        final written = domain == LoadingDomain.thread
            ? await prefs.setBool(_threadKey, mode == LoadingMode.continuous)
            : await prefs.setString(_key(domain), mode.name);
        if (written) {
          notifier.value = Map.unmodifiable({...notifier.value, domain: mode});
        }
        return written;
      });
}
