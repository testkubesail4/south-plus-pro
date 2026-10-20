import 'dart:async';

import 'package:flutter/services.dart';

import '../models/forum_models.dart';
import 'forum_url_resolver.dart';

class ForumIncomingLinkService {
  ForumIncomingLinkService({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('south_plus_rewrite/incoming_links');

  final MethodChannel _channel;
  final _urls = ForumUrlResolver();
  void Function(String)? _onLink;
  void Function(String?)? _onRejected;
  (int, String)? _pending;
  int _lastSeen = 0;
  bool _ready = false;
  bool _started = false;
  bool _disposed = false;

  Future<void> start({
    required void Function(String url) onLink,
    required void Function(String? copyableUrl) onRejected,
  }) async {
    if (_disposed || _started) return;
    _started = true;
    _onLink = onLink;
    _onRejected = onRejected;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openLink') _receive(call.arguments);
    });
    try {
      _receive(await _channel.invokeMethod<Object?>('takeInitialLink'));
    } on MissingPluginException {
      // Non-Android platforms have no inbound bridge.
    } on PlatformException {
      // A failed bridge must not prevent session restoration.
    }
  }

  void _receive(Object? value) {
    if (_disposed || value is! Map) return;
    final id = value['id'];
    if (id is! int || id <= _lastSeen) return;
    _lastSeen = id;
    final url = value['url'];
    _pending = (id, url is String && url.length <= 8192 ? url : '');
    _deliver();
  }

  void setReady(bool ready) {
    if (_disposed) return;
    _ready = ready;
    _deliver();
  }

  void _deliver() {
    final event = _pending;
    if (_disposed || !_ready || event == null) return;
    _pending = null;
    final raw = event.$2;
    try {
      final uri = Uri.tryParse(raw);
      final target = _urls.forumLinkTarget(raw);
      final owned = uri != null &&
          uri.hasAuthority &&
          ForumUrlResolver.isSafeExternalUrl(raw) &&
          {'http', 'https'}.contains(uri.scheme) &&
          _urls.isForumUrl(raw) &&
          target is! ForumBlockedLinkTarget;
      if (owned &&
          (target is ForumThreadLinkTarget ||
              target is ForumUserLinkTarget ||
              target is ForumBoardLinkTarget ||
              target is ForumAppPageLinkTarget ||
              _urls.searchLinkPrefill(raw) != null)) {
        _onLink?.call(raw);
      } else {
        _onRejected?.call(owned ? raw : null);
      }
    } catch (_) {
      // UI callback failures still consume the event without exposing its URL.
    } finally {
      unawaited(_acknowledge(event.$1));
    }
  }

  Future<void> _acknowledge(int id) async {
    try {
      await _channel.invokeMethod<void>('acknowledgeLink', id);
    } catch (_) {
      // Receipt stays memory-only if the native side disappears.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = null;
    _onLink = null;
    _onRejected = null;
    try {
      _channel.setMethodCallHandler(null);
    } catch (_) {
      // Disposal must also be safe after the platform messenger shuts down.
    }
  }
}
