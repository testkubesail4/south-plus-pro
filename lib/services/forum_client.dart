import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ForumClient {
  ForumClient({
    HttpClient? httpClient,
    Uri? baseUri,
  })  : baseUri = baseUri ?? Uri.parse('https://south-plus.net/'),
        _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final Uri baseUri;
  final Map<String, String> _cookies = <String, String>{};

  Future<String> get(String path) async {
    final request = await _httpClient.getUrl(baseUri.resolve(path));
    _applyCookies(request);
    final response = await request.close();
    _storeCookies(response);
    return utf8.decode(
        await response.fold<List<int>>(<int>[], (b, d) => b..addAll(d)));
  }

  Future<Uint8List> getBytes(String path) async {
    final request = await _httpClient.getUrl(baseUri.resolve(path));
    _applyCookies(request);
    final response = await request.close();
    _storeCookies(response);
    final bytes =
        await response.fold<List<int>>(<int>[], (b, d) => b..addAll(d));
    return Uint8List.fromList(bytes);
  }

  Future<String> post(String path, Map<String, String> form) async {
    final request = await _httpClient.postUrl(baseUri.resolve(path));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    _applyCookies(request);
    request.write(Uri(queryParameters: form).query);
    final response = await request.close();
    _storeCookies(response);
    return utf8.decode(
        await response.fold<List<int>>(<int>[], (b, d) => b..addAll(d)));
  }

  void _applyCookies(HttpClientRequest request) {
    if (_cookies.isEmpty) return;
    request.headers.set(
      HttpHeaders.cookieHeader,
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    );
  }

  void _storeCookies(HttpClientResponse response) {
    for (final header
        in response.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
      final parts = header.split(';').first.split('=');
      if (parts.length == 2) {
        _cookies[parts[0]] = parts[1];
      }
    }
  }

  bool get isLoggedIn {
    return _cookies.keys.any((key) => key.toLowerCase().contains('winduser'));
  }
}
