import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'watch_notifications.dart';

class LiveNotice {
  const LiveNotice({
    required this.serial,
    required this.kind,
    required this.count,
    this.title,
  });

  final int serial;
  final NoticeNotificationKind kind;
  final int count;
  final String? title;
}

/// Foreground signals share the repository's paced, budgeted notice reader.
class ForumLiveSync with WidgetsBindingObserver {
  ForumLiveSync({required this.checkMessages, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  static const messageInterval = Duration(minutes: 1);
  static const homeInterval = Duration(minutes: 5);
  final Future<void> Function() checkMessages;
  final DateTime Function() clock;
  final _homeRevision = ValueNotifier(0);
  final _messagesSyncing = ValueNotifier(false);
  final _latestNotice = ValueNotifier<LiveNotice?>(null);
  ValueListenable<int> get homeRevision => _homeRevision;
  ValueListenable<bool> get messagesSyncing => _messagesSyncing;
  ValueListenable<LiveNotice?> get latestNotice => _latestNotice;
  Timer? _timer;
  Future<void>? _syncing;
  DateTime? _backgroundAt;
  DateTime? _homeUpdatedAt;
  bool _started = false;
  bool _foreground = true;
  bool _disposed = false;
  int _serial = 0;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _homeUpdatedAt = clock();
    if (!_foreground) _backgroundAt = clock();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    _backgroundAt = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void sessionChanged() {
    _latestNotice.value = null;
    _homeUpdatedAt = clock();
  }

  void noticeReceived(NoticeNotificationKind kind, int count, String? title) {
    if (_disposed || !_started || !_foreground) return;
    _latestNotice.value = LiveNotice(
      serial: ++_serial,
      kind: kind,
      count: count,
      title: title,
    );
  }

  Future<void> _sync() {
    if (_disposed) return Future.value();
    final pending = _syncing;
    if (pending != null) return pending;
    _messagesSyncing.value = true;
    late Future<void> request;
    request = Future<void>.sync(checkMessages).whenComplete(() {
      if (identical(_syncing, request)) _syncing = null;
      if (!_disposed) _messagesSyncing.value = false;
    });
    _syncing = request;
    return request;
  }

  /// User intent changes error reporting, never the shared request budget.
  Future<void> syncMessages({bool user = false}) {
    final pending = _sync();
    return user ? pending : pending.catchError((_) {});
  }

  void _invalidateHome() {
    _homeUpdatedAt = clock();
    _homeRevision.value++;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_started || !_foreground || _disposed) return;
    _timer = Timer(messageInterval, () {
      if (!_started || !_foreground || _disposed) return;
      if (clock().difference(_homeUpdatedAt!) >= homeInterval) {
        _invalidateHome();
      }
      unawaited(syncMessages());
      _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _disposed) return;
    if (state == AppLifecycleState.detached) {
      stop();
      return;
    }
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _backgroundAt ??= clock();
      _timer?.cancel();
      return;
    }
    final away = _backgroundAt;
    _backgroundAt = null;
    if (away != null && clock().difference(away) >= messageInterval) {
      _invalidateHome();
      unawaited(syncMessages());
    }
    _schedule();
  }

  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    _homeRevision.dispose();
    _messagesSyncing.dispose();
    _latestNotice.dispose();
  }
}
