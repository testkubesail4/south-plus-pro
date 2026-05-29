import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WhatsLinkPreviewService {
  const WhatsLinkPreviewService({HttpClient? client}) : _client = client;

  final HttpClient? _client;

  Future<WhatsLinkPreview> fetch(String link) async {
    final client = _client ?? HttpClient();
    final uri = Uri.https('whatslink.info', '/api/v1/link', {'url': link});
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.refererHeader, 'https://whatslink.info/');

      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WhatsLinkPreviewException('预览服务返回 ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const WhatsLinkPreviewException('预览数据格式不正确');
      }
      if (decoded['error'] != null) {
        throw WhatsLinkPreviewException('${decoded['error']}');
      }
      return WhatsLinkPreview.fromJson(decoded, sourceUrl: link);
    } on WhatsLinkPreviewException {
      rethrow;
    } on TimeoutException {
      throw const WhatsLinkPreviewException('预览请求超时');
    } on FormatException {
      throw const WhatsLinkPreviewException('预览数据解析失败');
    } on SocketException {
      throw const WhatsLinkPreviewException('无法连接预览服务');
    } finally {
      if (_client == null) client.close(force: true);
    }
  }
}

class WhatsLinkPreview {
  const WhatsLinkPreview({
    required this.sourceUrl,
    this.name,
    this.type,
    this.fileType,
    this.sizeBytes,
    this.fileCount,
  });

  final String sourceUrl;
  final String? name;
  final String? type;
  final String? fileType;
  final int? sizeBytes;
  final int? fileCount;

  factory WhatsLinkPreview.fromJson(
    Map<String, dynamic> json, {
    required String sourceUrl,
  }) {
    return WhatsLinkPreview(
      sourceUrl: sourceUrl,
      name: _stringValue(json['name'] ?? json['title'] ?? json['filename']),
      type: _stringValue(json['type']),
      fileType: _stringValue(json['file_type'] ?? json['fileType']),
      sizeBytes: _intValue(json['size'] ?? json['length']),
      fileCount: _intValue(json['count'] ?? json['file_count']),
    );
  }

  bool get hasData {
    return name != null ||
        type != null ||
        fileType != null ||
        sizeBytes != null ||
        fileCount != null;
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return int.tryParse(text);
  }
}

class WhatsLinkPreviewException implements Exception {
  const WhatsLinkPreviewException(this.message);

  final String message;

  @override
  String toString() => message;
}
