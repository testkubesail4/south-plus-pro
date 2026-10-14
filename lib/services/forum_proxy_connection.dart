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
      if (cancelled) return;
      if (proxy.type == ForumProxyType.https) {
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
      if (proxy.type == ForumProxyType.socks5) {
        await _socksConnect(proxy, target, reader);
      } else {
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

  unawaited(Future<void>(connect));
  return ConnectionTask.fromSocket(result.future, cancel);
}

Future<void> _socksConnect(
    ForumProxy proxy, Uri target, _HandshakeReader reader) async {
  final socket = reader.socket;
  final authenticated = proxy.username != null;
  socket.add(authenticated ? [5, 2, 0, 2] : [5, 1, 0]);
  await socket.flush();
  final method = await reader.read(2);
  if (method[0] != 5 ||
      !(method[1] == 0 || (authenticated && method[1] == 2))) {
    throw const SocketException('SOCKS5 认证方式无效');
  }
  if (method[1] == 2) {
    final user = utf8.encode(proxy.username!);
    final password = utf8.encode(proxy.password!);
    socket.add([1, user.length, ...user, password.length, ...password]);
    await socket.flush();
    final auth = await reader.read(2);
    if (auth[0] != 1 || auth[1] != 0) throw const SocketException('代理认证失败');
  }
  final host = utf8.encode(target.host);
  if (host.isEmpty || host.length > 255)
    throw const SocketException('SOCKS5 目标主机无效');
  socket.add(
      [5, 1, 0, 3, host.length, ...host, target.port >> 8, target.port & 255]);
  await socket.flush();
  final reply = await reader.read(4);
  if (reply[0] != 5 || reply[1] != 0 || reply[2] != 0) {
    throw const SocketException('SOCKS5 代理拒绝连接');
  }
  final int length;
  switch (reply[3]) {
    case 1:
      length = 4;
    case 4:
      length = 16;
    case 3:
      length = (await reader.read(1)).single;
      if (length == 0) throw const SocketException('SOCKS5 响应地址无效');
    default:
      throw const SocketException('SOCKS5 响应地址类型无效');
  }
  await reader.read(length + 2);
  if (reader._bytes.isNotEmpty) throw const SocketException('SOCKS5 响应无效');
}

class _HandshakeReader {
  _HandshakeReader(this.socket) {
    subscription = socket.listen((data) {
      if (_bytes.length + data.length > 16384) {
        _error = const SocketException('代理响应过大');
        socket.destroy();
        _wake();
        return;
      }
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

  Future<List<int>> read(int count) async {
    if (_error != null) throw _error!;
    while (_bytes.length < count) {
      if (_error != null) throw _error!;
      await (_changed ??= Completer<void>()).future;
    }
    final result = _bytes.take(count).toList();
    _bytes.removeRange(0, count);
    return result;
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
    final stream = StreamController<Uint8List>(
        sync: true,
        onListen: subscription.resume,
        onPause: subscription.pause,
        onResume: subscription.resume,
        onCancel: subscription.cancel);
    subscription.onData(stream.add);
    subscription.onError(stream.addError);
    subscription.onDone(stream.close);
    return stream.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
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
