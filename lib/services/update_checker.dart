import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const defaultUpdateRepository = 'testkubesail4/south-plus-pro';

typedef ReleaseFetcher = Future<Map<String, Object?>> Function(Uri uri);

class UpdateChecker {
  const UpdateChecker({
    this.repository = defaultUpdateRepository,
    ReleaseFetcher? fetcher,
  }) : _fetcher = fetcher ?? _fetchLatestRelease;

  final String repository;
  final ReleaseFetcher _fetcher;

  Future<UpdateCheckResult> check({
    required String currentVersion,
  }) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$repository/releases/latest',
    );
    final data = await _fetcher(uri);
    final release = AppRelease.fromGitHubJson(data);
    return UpdateCheckResult(
      currentVersion: currentVersion,
      release: release,
      hasUpdate: compareAppVersions(release.version, currentVersion) > 0,
    );
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.release,
    required this.hasUpdate,
  });

  final String currentVersion;
  final AppRelease release;
  final bool hasUpdate;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.tagName,
    required this.name,
    required this.htmlUrl,
    required this.publishedAt,
    required this.body,
    required this.assets,
  });

  final String version;
  final String tagName;
  final String name;
  final String htmlUrl;
  final DateTime? publishedAt;
  final String body;
  final List<ReleaseAsset> assets;

  factory AppRelease.fromGitHubJson(Map<String, Object?> json) {
    final tagName = (json['tag_name'] as String?)?.trim();
    final htmlUrl = (json['html_url'] as String?)?.trim();
    if (tagName == null || tagName.isEmpty) {
      throw const UpdateCheckException('发布信息缺少版本号');
    }
    if (htmlUrl == null || htmlUrl.isEmpty) {
      throw const UpdateCheckException('发布信息缺少下载链接');
    }

    final assetsValue = json['assets'];
    final assets = assetsValue is List
        ? assetsValue
            .whereType<Map<String, Object?>>()
            .map(ReleaseAsset.fromGitHubJson)
            .toList(growable: false)
        : const <ReleaseAsset>[];

    final publishedAtText = json['published_at'] as String?;
    return AppRelease(
      version: normalizeAppVersion(tagName),
      tagName: tagName,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tagName,
      htmlUrl: htmlUrl,
      publishedAt: publishedAtText == null
          ? null
          : DateTime.tryParse(publishedAtText)?.toLocal(),
      body: (json['body'] as String?)?.trim() ?? '',
      assets: assets,
    );
  }

  String downloadUrlForPlatform({String? operatingSystem}) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final asset = switch (os) {
      'android' => _assetNamed('android-universal.apk'),
      'windows' => _assetNamed('windows-x64.zip'),
      _ => null,
    };
    return asset?.browserDownloadUrl ?? htmlUrl;
  }

  ReleaseAsset? _assetNamed(String suffix) {
    for (final asset in assets) {
      if (asset.name.endsWith(suffix)) return asset;
    }
    return null;
  }
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
  });

  final String name;
  final String browserDownloadUrl;

  factory ReleaseAsset.fromGitHubJson(Map<String, Object?> json) {
    return ReleaseAsset(
      name: (json['name'] as String?)?.trim() ?? '',
      browserDownloadUrl:
          (json['browser_download_url'] as String?)?.trim() ?? '',
    );
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, Object?>> _fetchLatestRelease(Uri uri) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers
        .set(HttpHeaders.userAgentHeader, 'SouthPlusProUpdateChecker');
    final response = await request.close();
    final body = await utf8.decodeStream(response);

    if (response.statusCode != HttpStatus.ok) {
      throw UpdateCheckException('GitHub 返回 ${response.statusCode}');
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) return decoded;
    throw const UpdateCheckException('发布信息格式不正确');
  } on UpdateCheckException {
    rethrow;
  } on SocketException {
    throw const UpdateCheckException('网络连接失败，请稍后重试');
  } on FormatException {
    throw const UpdateCheckException('发布信息解析失败');
  } finally {
    client.close(force: true);
  }
}

@visibleForTesting
String normalizeAppVersion(String version) {
  final trimmed = version.trim();
  final withoutPrefix = trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1)
      : trimmed;
  return withoutPrefix.split('+').first.trim();
}

@visibleForTesting
int compareAppVersions(String left, String right) {
  final leftParts = _parseVersionParts(left);
  final rightParts = _parseVersionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var index = 0; index < length; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

List<int> _parseVersionParts(String version) {
  final normalized = normalizeAppVersion(version);
  final main = normalized.split('-').first;
  return main
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList(growable: false);
}
