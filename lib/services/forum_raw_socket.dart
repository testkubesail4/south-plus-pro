import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Retains the real FD during TLS; Socket.secure detaches the old Socket handle.
class ForumSocketAttempt {
  ForumSocketAttempt(this.uri,
      {Object? address,
      this.context,
      Duration timeout = const Duration(milliseconds: 2500)}) {
    _timer = Timer(
        timeout, () => cancel(const SocketException('Connection timed out')));
    unawaited(_connect(address ?? uri.host));
  }
  final Uri uri;
  final SecurityContext? context;
  final _result = Completer<Socket>();
  late final Timer _timer;
  ConnectionTask<RawSocket>? _task;
  RawSocket? _raw;
  Socket? _socket;
  Future<Socket> get socket => _result.future;

  void cancel([Object error = const SocketException('Connection cancelled')]) {
    _timer.cancel();
    _task?.cancel();
    unawaited(_raw?.close());
    _socket?.destroy();
    if (!_result.isCompleted) _result.completeError(error);
  }

  Future<void> _connect(Object address) async {
    try {
      _task = await RawSocket.startConnect(address, uri.port);
      if (_result.isCompleted) _task!.cancel();
      final raw = _raw = await _task!.socket;
      if (_result.isCompleted) {
        await raw.close();
        return;
      }
      Socket socket;
      if (uri.scheme == 'https') {
        final secure =
            await RawSecureSocket.secure(raw, host: uri.host, context: context);
        socket = _SecureSocket(secure);
      } else {
        socket = ForumRawSocket(raw);
      }
      _socket = socket;
      if (_result.isCompleted) {
        socket.destroy();
      } else {
        _result.complete(socket);
      }
    } catch (error, stack) {
      unawaited(_raw?.close());
      if (!_result.isCompleted) _result.completeError(error, stack);
    } finally {
      _timer.cancel();
    }
  }
}

/// Public RawSocket APIs with the stream/IOSink interface HttpClient consumes.
class ForumRawSocket extends Stream<Uint8List> implements Socket {
  ForumRawSocket(this.raw) {
    raw.readEventsEnabled = false;
    raw.writeEventsEnabled = false;
    _incoming = StreamController<Uint8List>(
        sync: true,
        onListen: () {
          if (!_destroyed) raw.readEventsEnabled = true;
        },
        onPause: () {
          if (!_destroyed) raw.readEventsEnabled = false;
        },
        onResume: () {
          if (!_destroyed) raw.readEventsEnabled = true;
        },
        onCancel: () {
          if (!_destroyed) raw.shutdown(SocketDirection.receive);
        });
    _writer = _RawWriter(raw);
    _sink = IOSink(_writer);
    unawaited(
        _sink.done.then((_) {}, onError: (Object error, StackTrace stack) {
      if (!_incoming.isClosed) _incoming.addError(error, stack);
      destroy();
    }));
    raw.listen((event) {
      if (_destroyed) return;
      if (event == RawSocketEvent.read) {
        while (!_incoming.isPaused) {
          final data = raw.read();
          if (data == null) break;
          _incoming.add(data);
        }
      } else if (event == RawSocketEvent.write) {
        _writer.ready();
      } else if (event == RawSocketEvent.readClosed) {
        if (!_incoming.isClosed) unawaited(_incoming.close());
      } else if (event == RawSocketEvent.closed) {
        if (!_incoming.isClosed) unawaited(_incoming.close());
        _writer.abort(const SocketException('Socket closed'));
      }
    }, onError: (Object error, StackTrace stack) {
      if (!_incoming.isClosed) _incoming.addError(error, stack);
      destroy();
    }, onDone: () {
      if (!_incoming.isClosed) unawaited(_incoming.close());
      _writer.abort(const SocketException('Socket closed'));
    });
  }
  final RawSocket raw;
  late final StreamController<Uint8List> _incoming;
  late final _RawWriter _writer;
  late final IOSink _sink;
  bool _destroyed = false;

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _incoming.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<Socket> close() async {
    await _sink.close();
    return this;
  }

  @override
  Future<Socket> get done => _sink.done.then((_) => this);
  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _writer.abort(const SocketException('Socket destroyed'));
    unawaited(raw.close());
    unawaited(_sink.close().then((_) {}, onError: (Object _) {}));
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  InternetAddress get address => raw.address;
  @override
  int get port => raw.port;
  @override
  InternetAddress get remoteAddress => raw.remoteAddress;
  @override
  int get remotePort => raw.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      raw.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => raw.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => raw.setRawOption(option);
}

class _SecureSocket extends ForumRawSocket implements SecureSocket {
  _SecureSocket(RawSecureSocket super.raw);
  RawSecureSocket get _secure => raw as RawSecureSocket;
  @override
  X509Certificate? get peerCertificate => _secure.peerCertificate;
  @override
  String? get selectedProtocol => _secure.selectedProtocol;
  @override
  void renegotiate(
          {bool useSessionCache = true,
          bool requestClientCertificate = false,
          bool requireClientCertificate = false}) =>
      throw UnsupportedError('TLS renegotiation is not supported by Dart');
}

class _RawWriter implements StreamConsumer<List<int>> {
  _RawWriter(this.raw);
  final RawSocket raw;
  Completer<void>? _ready;
  bool _closed = false;
  Object? _error;

  void ready() {
    raw.writeEventsEnabled = false;
    final ready = _ready;
    _ready = null;
    ready?.complete();
  }

  void abort(Object error) {
    _error ??= error;
    _closed = true;
    final ready = _ready;
    _ready = null;
    ready?.completeError(error);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      var offset = 0;
      while (offset < data.length) {
        if (_error != null) throw _error!;
        if (_closed) throw const SocketException('Socket closed');
        final written = raw.write(data, offset, data.length - offset);
        offset += written;
        if (written == 0) {
          final ready = _ready ??= Completer<void>();
          raw.writeEventsEnabled = true;
          await ready.future;
        }
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    raw.shutdown(SocketDirection.send);
  }
}
