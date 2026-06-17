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
    expect(
      result.release.downloadUrlForPlatform(operatingSystem: 'android'),
      'https://github.com/release/download/south_plus_rewrite-android-universal.apk',
    );
  });

  test('treats the same version as up to date', () async {
    final checker = UpdateChecker(
      fetcher: (_) async => _releaseJson(tagName: 'v0.1.7'),
    );

    final result = await checker.check(currentVersion: '0.1.7');

    expect(result.hasUpdate, isFalse);
  });

  test('compares dotted versions numerically', () {
    expect(compareAppVersions('0.1.10', '0.1.9'), greaterThan(0));
    expect(compareAppVersions('v1.2.0', '1.2'), 0);
    expect(compareAppVersions('1.2.0+4', '1.2.1+1'), lessThan(0));
  });

  test('rejects malformed release payloads', () {
    expect(
      () => AppRelease.fromGitHubJson({'tag_name': 'v1.0.0'}),
      throwsA(isA<UpdateCheckException>()),
    );
  });

  test('falls back to the release page without a matching asset', () {
    final release = AppRelease.fromGitHubJson(_releaseJson(tagName: 'v0.1.8'));

    expect(
      release.downloadUrlForPlatform(operatingSystem: 'linux'),
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
