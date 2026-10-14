import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'forum_network_config.dart';

Future<ConnectionTask<Socket>> connectForumProxy(
  ForumProxy proxy,
  Uri target, {
  SecurityContext? context,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final result = Completer<Socket>();
  ConnectionTask<Socket>? connecting;
  Socket? active;
  var cancelled = false;
  void cancel() {
    if (result.isCompleted) return;
    cancelled = true;
    connecting?.cancel();
    active?.destroy();
    result.completeError(const SocketException('代理连接已取消'));
  }

  final timer = Timer(timeout, cancel);
  Future<void> connect() async {
    try {
      if (proxy.type != ForumProxyType.http) {
        throw const SocketException('此代理类型暂不可用');
      }
      connecting = await Socket.startConnect(proxy.host, proxy.port);
      if (cancelled) connecting!.cancel();
      final socket = active = await connecting!.socket;
      if (cancelled) {
        socket.destroy();
        return;
      }
      final reader = _HandshakeReader(socket);
      final authority =
          '${target.host.contains(':') ? '[${target.host}]' : target.host}:${target.port}';
      final auth = proxy.username == null
          ? ''
          : 'Proxy-Authorization: Basic ${base64Encode(utf8.encode('${proxy.username}:${proxy.password}'))}\r\n';
      socket.write(
          'CONNECT $authority HTTP/1.1\r\nHost: $authority\r\n${auth}Proxy-Connection: Keep-Alive\r\n\r\n');
      await socket.flush();
      final header = await reader.header();
      final match =
          RegExp(r'^HTTP/1\.[01] ([0-9]{3})(?: |\r)').firstMatch(header);
      if (match == null || match.group(1) != '200') {
        throw SocketException(match?.group(1) == '407' ? '代理认证失败' : '代理拒绝连接');
      }
      reader.pause();
      Socket tunnel;
      if (target.scheme == 'https') {
        tunnel = await SecureSocket.secure(socket,
            host: target.host, context: context);
      } else {
        tunnel = _TunnelSocket(socket, reader.subscription);
      }
      active = tunnel;
      if (cancelled) {
        tunnel.destroy();
        return;
      }
      result.complete(tunnel);
    } catch (error, stack) {
      active?.destroy();
      connecting?.cancel();
      if (!result.isCompleted) result.completeError(error, stack);
    } finally {
      timer.cancel();
    }
  }

  unawaited(connect());
  return ConnectionTask.fromSocket(result.future, cancel);
}

class _HandshakeReader {
  _HandshakeReader(this.socket) {
    subscription = socket.listen((data) {
      _bytes.addAll(data);
      _changed?.complete();
      _changed = null;
    }, onError: (Object error) {
      _error = error;
      _wake();
    }, onDone: () {
      _error = const SocketException('代理提前关闭连接');
      _wake();
    });
  }
  final Socket socket;
  late final StreamSubscription<Uint8List> subscription;
  final _bytes = <int>[];
  Completer<void>? _changed;
  Object? _error;
  void _wake() {
    _changed?.complete();
    _changed = null;
  }

  Future<String> header() async {
    while (true) {
      if (_bytes.length > 16384) throw const SocketException('代理响应过大');
      final text = latin1.decode(_bytes);
      final end = text.indexOf('\r\n\r\n');
      if (end >= 0) {
        // No origin data can precede our first tunneled request/TLS handshake.
        if (end + 4 != _bytes.length) throw const SocketException('代理响应无效');
        return text;
      }
      if (_error != null) throw _error!;
      await (_changed ??= Completer<void>()).future;
    }
  }

  void pause() => subscription.pause();
}

// Reuse the handshake subscription for plain HTTP: Socket streams are single-use.
class _TunnelSocket extends Stream<Uint8List> implements Socket {
  _TunnelSocket(this.socket, this.subscription);
  final Socket socket;
  final StreamSubscription<Uint8List> subscription;
  bool _listened = false;
  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    if (_listened) throw StateError('Socket already listened to');
    _listened = true;
    subscription.onData(onData);
    subscription.onError(onError);
    subscription.onDone(onDone);
    subscription.resume();
    return subscription;
  }

  @override
  void add(List<int> data) => socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => socket.addStream(stream);
  @override
  Encoding get encoding => socket.encoding;
  @override
  set encoding(Encoding value) => socket.encoding = value;
  @override
  void write(Object? object) => socket.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => socket.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => socket.writeln(object);
  @override
  Future<void> flush() => socket.flush();
  @override
  Future get done => socket.done;
  @override
  Future close() => socket.close();
  @override
  void destroy() => socket.destroy();
  @override
  InternetAddress get address => socket.address;
  @override
  InternetAddress get remoteAddress => socket.remoteAddress;
  @override
  int get port => socket.port;
  @override
  int get remotePort => socket.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      socket.setOption(option, enabled);
  @override
  void setRawOption(RawSocketOption option) => socket.setRawOption(option);
  @override
  Uint8List getRawOption(RawSocketOption option) => socket.getRawOption(option);
}
