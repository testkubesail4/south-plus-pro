import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'forum_client.dart';
import 'forum_request_exception.dart';

enum ScanState { idle, running, waiting, stopped, failed, done }

class ScanProgress {
  const ScanProgress({
    this.state = ScanState.idle,
    this.scannedPages = 0,
    this.totalPages,
    this.found = 0,
    this.pending = 0,
    this.unresolved = 0,
    this.retryAt,
    this.attempt = 0,
    this.maxAttempts = 3,
    this.failure,
    this.canResume = false,
    this.capped = false,
  });

  final ScanState state;
  final int scannedPages;
  final int? totalPages;
  final int found;
  final int pending;
  final int unresolved;
  final DateTime? retryAt;
  final int attempt;
  final int maxAttempts;
  final ForumRequestKind? failure;
  final bool canResume;
  final bool capped;
}

abstract class FullScan<T> extends ChangeNotifier {
  ScanProgress get progress;
  List<T> get hits;
  List<T> get unresolved;
  void start();
  void stop();
  void resume();
}

class ScanPage<T> {
  const ScanPage({
    required this.page,
    required this.hasMore,
    this.totalPages,
    this.hits = const [],
    this.unresolved = const [],
  });

  final int page;
  final int? totalPages;
  final bool hasMore;
  final Iterable<T> hits;
  final Iterable<T> unresolved;
}

class ScanRequest {
  ScanRequest._(this._client, this.checkCurrent);

  final ForumClient _client;
  final void Function() checkCurrent;
  bool _inFlight = false;

  Future<String> getOnce(String path) async {
    checkCurrent();
    if (_inFlight) throw StateError('Scan requests must be sequential');
    _inFlight = true;
    try {
      final body = await _client.getOnceGuarded(path,
          requireCurrentSession: checkCurrent);
      checkCurrent();
      return body;
    } finally {
      _inFlight = false;
    }
  }
}

class PageFullScan<T> extends FullScan<T> {
  PageFullScan({
    required ForumClient client,
    required bool Function() isCurrentSession,
    required Future<ScanPage<T>> Function(int page, ScanRequest request)
        readPage,
    Iterable<ScanPage<T>> loaded = const [],
    int? totalPages,
    this.maxResults = 200,
    this.maxAttempts = 3,
  })  : _client = client,
        _isCurrentSession = isCurrentSession,
        _readPage = readPage,
        _totalPages = totalPages {
    if (maxResults < 1 || maxAttempts < 1 || maxAttempts > 5) {
      throw ArgumentError('Invalid scan limits');
    }
    if (totalPages != null && totalPages < 1) {
      throw ArgumentError.value(totalPages, 'totalPages');
    }
    for (final page in loaded) {
      _validatePage(page);
      if (!_seeded.add(page.page)) continue;
      _acceptPage(page);
      if (_capped) break;
    }
    _progress = _snapshot(_capped ? ScanState.stopped : ScanState.idle);
  }

  final ForumClient _client;
  final bool Function() _isCurrentSession;
  final Future<ScanPage<T>> Function(int page, ScanRequest request) _readPage;
  final int maxResults;
  final int maxAttempts;
  final _random = Random.secure();
  final _seeded = <int>{};
  final _hits = <T>[];
  final _unresolved = <T>[];
  int _nextPage = 1;
  int _scannedPages = 0;
  int? _totalPages;
  bool _capped = false;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;
  Completer<void>? _waiting;
  late ScanProgress _progress;

  @override
  ScanProgress get progress => _progress;
  @override
  List<T> get hits => List.unmodifiable(_hits);
  @override
  List<T> get unresolved => List.unmodifiable(_unresolved);

  @override
  void start() {
    if (!_disposed && progress.state == ScanState.idle) _launch();
  }

  @override
  void stop() {
    if (_disposed ||
        !{ScanState.running, ScanState.waiting}.contains(progress.state))
      return;
    _generation++;
    _endWait();
    _publish(ScanState.stopped);
  }

  @override
  void resume() {
    if (_disposed || !progress.canResume) return;
    _launch();
  }

  void _launch() {
    if (_disposed || _capped) return;
    final generation = ++_generation;
    // A stopped HTTP response must drain before a resumed request can start.
    if (_busy) {
      _publish(ScanState.running);
      return;
    }
    _busy = true;
    _publish(ScanState.running);
    unawaited(_run(generation));
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) throw const _ScanCancelled();
    if (!_isCurrentSession()) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变，请重新搜索');
    }
  }

  Future<void> _run(int generation) async {
    try {
      final request = ScanRequest._(_client, () => _check(generation));
      while (true) {
        _check(generation);
        while (_seeded.contains(_nextPage)) {
          _nextPage++;
        }
        if (_totalPages != null && _nextPage > _totalPages!) {
          _publish(ScanState.done);
          return;
        }
        ScanPage<T>? result;
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          _check(generation);
          try {
            result = await _readPage(_nextPage, request);
            _check(generation);
            _validatePage(result);
            if (result.page != _nextPage) {
              throw const ForumRequestException(
                  ForumRequestKind.invalidInput, '页码与请求不符');
            }
            break;
          } on ForumRequestException catch (error) {
            _check(generation);
            final retryable = {
              ForumRequestKind.network,
              ForumRequestKind.server,
              ForumRequestKind.rateLimited,
            }.contains(error.kind);
            if (!retryable || attempt == maxAttempts) {
              _publish(ScanState.failed,
                  failure: error.kind, canResume: retryable, attempt: attempt);
              return;
            }
            final limited = error.kind == ForumRequestKind.rateLimited;
            final baseSeconds = (limited ? 10 : 1) * (1 << (attempt - 1));
            final milliseconds = min(limited ? 60000 : 30000,
                (baseSeconds * 1000 * (1 + _random.nextDouble() / 4)).round());
            final delay = Duration(milliseconds: milliseconds);
            _publish(ScanState.waiting,
                failure: error.kind,
                attempt: attempt,
                retryAt: DateTime.now().add(delay));
            _check(generation);
            final waiting = _waiting = Completer<void>();
            _timer = Timer(delay, waiting.complete);
            await waiting.future;
            _check(generation);
            _endWait();
            _publish(ScanState.running);
          }
        }
        _acceptPage(result!);
        _nextPage++;
        if (_capped) {
          _publish(ScanState.stopped);
          return;
        }
        _publish(ScanState.running);
      }
    } on _ScanCancelled {
      // Stop/dispose invalidates the response without closing a shared client.
    } on ForumRequestException catch (error) {
      if (!_disposed && generation == _generation) {
        _publish(ScanState.failed, failure: error.kind);
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _publish(ScanState.failed, failure: ForumRequestKind.invalidInput);
      }
    } finally {
      _busy = false;
      if (!_disposed && progress.state == ScanState.running) _launch();
    }
  }

  void _validatePage(ScanPage<T> page) {
    if (page.page < 1 ||
        (page.totalPages != null && page.totalPages! < page.page) ||
        (page.totalPages != null &&
            page.hasMore != (page.page < page.totalPages!))) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '无效的分页数据');
    }
  }

  void _acceptPage(ScanPage<T> page) {
    _scannedPages++;
    if (page.totalPages != null) _totalPages = page.totalPages;
    if (!page.hasMore) _totalPages = page.page;
    for (final (source, destination) in [
      (page.hits, _hits),
      (page.unresolved, _unresolved),
    ]) {
      for (final hit in source) {
        if (_hits.length + _unresolved.length >= maxResults) {
          _capped = true;
          return;
        }
        destination.add(hit);
      }
    }
  }

  ScanProgress _snapshot(ScanState state,
          {ForumRequestKind? failure,
          bool? canResume,
          int attempt = 0,
          DateTime? retryAt}) =>
      ScanProgress(
        state: state,
        scannedPages: _scannedPages,
        totalPages: _totalPages,
        found: _hits.length,
        unresolved: _unresolved.length,
        capped: _capped,
        maxAttempts: maxAttempts,
        attempt: attempt,
        retryAt: retryAt,
        failure: failure,
        canResume: !_capped && (canResume ?? state == ScanState.stopped),
      );

  void _publish(ScanState state,
      {ForumRequestKind? failure,
      bool? canResume,
      int attempt = 0,
      DateTime? retryAt}) {
    if (_disposed) return;
    _progress = _snapshot(state,
        failure: failure,
        canResume: canResume,
        attempt: attempt,
        retryAt: retryAt);
    notifyListeners();
  }

  void _endWait() {
    _timer?.cancel();
    _timer = null;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _endWait();
    super.dispose();
  }
}

class _ScanCancelled implements Exception {
  const _ScanCancelled();
}
