import 'dart:async';
import 'dart:convert';
import 'dart:io';

// All forum/preview HTTP stays on a local server with harmless fixture images.
class ImageHttpFixture extends HttpOverrides {
  ImageHttpFixture._(this.server);

  final HttpServer server;
  final requests = <String>[];
  final _clients = <HttpClient>[];
  static const imageUrl = 'https://fixture.invalid/image.png';
  static const avatarUrl = 'https://fixture.invalid/avatar.png';
  static const screenshotUrl = 'https://fixture.invalid/screenshot.png';
  static const emojiUrl = 'https://fixture.invalid/emoji.png';

  static Future<ImageHttpFixture> start({
    Map<String, List<int>> images = const {},
  }) async {
    final fixture = ImageHttpFixture._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      final original = request.uri.queryParameters['original']!;
      fixture.requests.add(original);
      if (Uri.parse(original).host == 'whatslink.info') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'name': 'Safe sample',
          'size': 1024,
          'count': 1,
          'screenshots': [screenshotUrl],
        }));
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(images[original] ??
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ));
      }
      await request.response.close();
    });
    return fixture;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    _clients.add(client);
    return _LocalClient(client, server.port);
  }

  Future<void> close() async {
    for (final client in _clients) {
      client.close(force: true);
    }
    await server.close(force: true);
  }
}

class _LocalClient implements HttpClient {
  _LocalClient(this.client, this.port);
  final HttpClient client;
  final int port;

  Uri _local(Uri uri) => Uri.http('127.0.0.1:$port', '/', {'original': '$uri'});
  @override
  Future<HttpClientRequest> getUrl(Uri url) => client.getUrl(_local(url));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      client.openUrl(method, _local(url));
  @override
  set autoUncompress(bool value) => client.autoUncompress = value;
  @override
  set userAgent(String? value) => client.userAgent = value;
  @override
  set connectionTimeout(Duration? value) => client.connectionTimeout = value;
  @override
  void close({bool force = false}) => client.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
