import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/services/update_checker.dart';

void main() {
  test('detects a newer GitHub release', () async {
    final checker = UpdateChecker(
      fetcher: (uri) async {
        expect(
          uri.toString(),
          'https://api.github.com/repos/testkubesail4/south-plus-pro/releases/latest',
        );
        return _releaseJson(tagName: 'v0.1.8');
      },
    );

    final result = await checker.check(currentVersion: '0.1.7');

    expect(result.hasUpdate, isTrue);
    expect(result.release.version, '0.1.8');
    expect(result.release.htmlUrl, 'https://github.com/release');
    for (final (abi, suffix) in [
      (Abi.androidArm, 'armeabi-v7a'),
      (Abi.androidArm64, 'arm64-v8a'),
      (Abi.androidX64, 'x86_64'),
    ]) {
      expect(
        result.release.downloadUrlForPlatform(
          operatingSystem: 'android',
          abi: abi,
        ),
        'https://github.com/release/download/south_plus_rewrite-android-$suffix.apk',
      );
    }
    expect(
      result.release.downloadUrlForPlatform(operatingSystem: 'windows'),
      'https://github.com/release/download/south_plus_rewrite-windows-x64.zip',
    );
  });

  test('treats the same version as up to date', () async {
    final checker = UpdateChecker(
      fetcher: (_) async => _releaseJson(tagName: 'v0.1.7'),
    );

    final result = await checker.check(currentVersion: '0.1.7');

    expect(result.hasUpdate, isFalse);
  });

  test('checks numeric versions and ignores build-only changes', () async {
    for (final (latest, current, hasUpdate) in [
      ('0.1.10', '0.1.9', true),
      ('v1.2.0', '1.2', false),
      ('1.2.0+4', '1.2.1+1', false),
      ('v1.2.0+5', '1.2.0+4', false),
    ]) {
      final result = await UpdateChecker(
        fetcher: (_) async => _releaseJson(tagName: latest),
      ).check(currentVersion: current);
      expect(result.hasUpdate, hasUpdate, reason: '$latest vs $current');
    }
  });

  test('rejects malformed release payloads', () {
    expect(
      () => AppRelease.fromGitHubJson({'tag_name': 'v1.0.0'}),
      throwsA(isA<UpdateCheckException>()),
    );
  });

  test('falls back to the release page without the process ABI APK', () {
    final json = _releaseJson(tagName: 'v0.1.8');
    (json['assets'] as List).removeWhere(
      (asset) => (asset['name'] as String).endsWith('android-arm64-v8a.apk'),
    );
    final release = AppRelease.fromGitHubJson(json);

    expect(
      release.downloadUrlForPlatform(
        operatingSystem: 'android',
        abi: Abi.androidArm64,
      ),
      'https://github.com/release',
    );
    expect(
      release.downloadUrlForPlatform(operatingSystem: 'ios'),
      'https://github.com/release',
    );
  });
}

Map<String, Object?> _releaseJson({required String tagName}) {
  return {
    'tag_name': tagName,
    'name': 'South Plus Pro $tagName',
    'html_url': 'https://github.com/release',
    'published_at': '2026-06-17T08:00:00Z',
    'body': '- 更新内容',
    'assets': [
      for (final suffix in ['armeabi-v7a', 'arm64-v8a', 'x86_64'])
        {
          'name': 'south_plus_rewrite-android-$suffix.apk',
          'browser_download_url':
              'https://github.com/release/download/south_plus_rewrite-android-$suffix.apk',
        },
      {
        'name': 'south_plus_rewrite-android-universal.apk',
        'browser_download_url':
            'https://github.com/release/download/south_plus_rewrite-android-universal.apk',
      },
      {
        'name': 'south_plus_rewrite-windows-x64.zip',
        'browser_download_url':
            'https://github.com/release/download/south_plus_rewrite-windows-x64.zip',
      },
    ],
  };
}
