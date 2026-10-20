import 'dart:async';
import 'dart:io';

/// Races connections, never HTTP requests: no request body can be replayed here.
class ForumConnectionRace {
  ForumConnectionRace(
    this.uri, {
    required Duration timeout,
    this.context,
    this.onFailure,
  }) {
    _deadline = Timer(
      timeout,
      () => _finishError(
        TimeoutException('Connection deadline exceeded', timeout),
      ),
    );
  }

  final Uri uri;
  final SecurityContext? context;
  final void Function(InternetAddress)? onFailure;
  final _result = Completer<Socket>();
  final _queue = <InternetAddress>[];
  final _seen = <String>{};
  final _active = <_ConnectionAttempt>{};
  late final Timer _deadline;
  Timer? _stagger;
  bool _finishedAdding = false;
  Object _lastError = const SocketException('No usable addresses');

  Future<Socket> get socket => _result.future;

  void add(Iterable<InternetAddress> addresses, {bool priority = false}) {
    if (_result.isCompleted) return;
    final unique = addresses.where((a) => _seen.add(a.address)).toList();
    if (priority) {
      _queue.insertAll(0, unique);
    } else {
      _queue.addAll(unique);
    }
    _pump();
  }

  void finishAdding() {
    _finishedAdding = true;
    _pump();
  }

  void cancel() => _finishError(const SocketException('Connection cancelled'));

  void _finishError(Object error) {
    if (_result.isCompleted) return;
    _result.completeError(error);
    _cleanup();
  }

  void _cleanup([_ConnectionAttempt? winner]) {
    _deadline.cancel();
    _stagger?.cancel();
    for (final attempt in _active.toList()) {
      if (attempt != winner) attempt.cancel();
    }
    _queue.clear();
  }

  void _pump() {
    if (_result.isCompleted) return;
    if (_queue.isEmpty) {
      if (_active.isEmpty && _finishedAdding) _finishError(_lastError);
      return;
    }
    if (_active.length >= 2) return;
    if (_active.isNotEmpty && _stagger == null) {
      _stagger = Timer(const Duration(milliseconds: 150), () {
        _stagger = null;
        if (_active.length < 2) _start();
      });
    } else if (_active.isEmpty) {
      _start();
    }
  }

  void _start() {
    if (_result.isCompleted || _queue.isEmpty || _active.length >= 2) return;
    final address = _queue.removeAt(0);
    final attempt = _ConnectionAttempt(uri, address, context);
    _active.add(attempt);
    unawaited(
      attempt.socket.then(
        (socket) {
          if (_result.isCompleted) {
            socket.destroy();
            return;
          }
          _result.complete(socket);
          _cleanup(attempt);
        },
        onError: (Object error, StackTrace stack) {
          _lastError = error;
          if (!_result.isCompleted) onFailure?.call(address);
        },
      ).whenComplete(() {
        _active.remove(attempt);
        _pump();
      }),
    );
    _pump();
  }
}

class _ConnectionAttempt {
  _ConnectionAttempt(this.uri, this.address, this.context) {
    _timer = Timer(
      const Duration(milliseconds: 2500),
      () => cancel(const SocketException('Address connection timed out')),
    );
    unawaited(_connect());
  }
  final Uri uri;
  final InternetAddress address;
  final SecurityContext? context;
  final _result = Completer<Socket>();
  late final Timer _timer;
  ConnectionTask<Socket>? _task;
  Socket? _socket;
  Future<Socket> get socket => _result.future;

  void cancel([Object error = const SocketException('Connection cancelled')]) {
    _timer.cancel();
    _task?.cancel();
    _socket?.destroy();
    if (!_result.isCompleted) _result.completeError(error);
  }

  Future<void> _connect() async {
    try {
      _task = await Socket.startConnect(address, uri.port);
      if (_result.isCompleted) _task!.cancel();
      var socket = _socket = await _task!.socket;
      if (_result.isCompleted) {
        socket.destroy();
        return;
      }
      if (uri.scheme == 'https') {
        socket = _socket = await SecureSocket.secure(
          socket,
          host: uri.host,
          context: context,
        );
      }
      if (_result.isCompleted) {
        socket.destroy();
      } else {
        _result.complete(socket);
      }
    } catch (error, stack) {
      _socket?.destroy();
      if (!_result.isCompleted) _result.completeError(error, stack);
    } finally {
      _timer.cancel();
    }
  }
}
