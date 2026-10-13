import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:south_plus_rewrite/services/external_link_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UrlLauncherPlatform original;
  late _Launcher platform;
  setUp(() {
    original = UrlLauncherPlatform.instance;
    platform = _Launcher();
    UrlLauncherPlatform.instance = platform;
  });
  tearDown(() => UrlLauncherPlatform.instance = original);

  test(
      'browser handoff preserves raw SEO bytes and uses only supported browser mode',
      () async {
    const url =
        'https://south-plus.net/search.php?keyword-fixture%2Dtopic.html#fixture%2Danchor';
    await ExternalLinkLauncher.openInBrowser(url);
    expect(platform.probed, [PreferredLaunchMode.inAppBrowserView]);
    expect(platform.launched, [(url, PreferredLaunchMode.inAppBrowserView)]);
  });

  test('unsupported browser mode never falls back to an application intent',
      () async {
    platform.supported = false;
    await expectLater(
        ExternalLinkLauncher.openInBrowser('https://south-plus.net/faq.php'),
        throwsA(isA<ExternalLinkLaunchException>()));
    expect(platform.launched, isEmpty);
  });

  test('browser refuses unsafe or non-web links before probing the platform',
      () async {
    for (final url in [
      'file:///fixture',
      'javascript:alert(1)',
      'https://fixture-user:fixture-password@example.invalid/file',
      'mailto:reader@example.invalid'
    ]) {
      await expectLater(ExternalLinkLauncher.openInBrowser(url),
          throwsA(isA<ExternalLinkLaunchException>()));
    }
    expect(platform.probed, isEmpty);
    expect(platform.launched, isEmpty);
  });

  test(
      'browser launch failures have generic feedback without leaking a private URI',
      () async {
    platform.failure = PlatformException(
        code: 'fixture', message: 'fixture-private-uri-canary');
    await expectLater(
        ExternalLinkLauncher.openInBrowser('https://south-plus.net/faq.php'),
        throwsA(isA<ExternalLinkLaunchException>().having(
            (error) => error.message, 'message', isNot(contains('canary')))));
    expect(platform.launched.single.$2, PreferredLaunchMode.inAppBrowserView);
  });

  test(
      'external handoff preserves escaped URL bytes instead of normalizing Uri',
      () async {
    const url =
        'https://example.invalid/file?token=fixture%2Dsignature#fixture%2Danchor';
    await ExternalLinkLauncher.open(url);
    expect(platform.launched, [(url, PreferredLaunchMode.externalApplication)]);
  });
}

class _Launcher extends UrlLauncherPlatform {
  bool supported = true;
  PlatformException? failure;
  final probed = <PreferredLaunchMode>[];
  final launched = <(String, PreferredLaunchMode)>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async {
    probed.add(mode);
    return supported;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add((url, options.mode));
    if (failure != null) throw failure!;
    return true;
  }
}
