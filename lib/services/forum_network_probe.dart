import 'dart:async';
import 'dart:io';

import 'forum_network_config.dart';

class ForumNetworkProbe {
  const ForumNetworkProbe({
    this.timeout = const Duration(seconds: 8),
  });

  final Duration timeout;

  Future<ForumSiteProbeResult> testSite(
    ForumSite site, {
    required bool dohEnabled,
    required DohProvider dohProvider,
    String? customDohUri,
    String? fixedAddress,
  }) async {
    final config = ForumNetworkConfig(
      site: site,
      dohEnabled: dohEnabled,
      dohProvider: dohProvider,
      customDohUri: customDohUri,
      fixedAddress: fixedAddress,
    );
    final client = createForumHttpClient(config);
    final watch = Stopwatch()..start();
    try {
      final uri = site.baseUri.resolve('simple/index.php');
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*');
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      watch.stop();
      final success = response.statusCode >= 200 && response.statusCode < 400;
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        statusCode: response.statusCode,
        success: success,
        message: success ? '可用' : 'HTTP ${response.statusCode}',
      );
    } on TimeoutException {
      watch.stop();
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: false,
        message: '超时',
      );
    } on SocketException catch (error) {
      watch.stop();
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: false,
        message: error.message,
      );
    } on HandshakeException {
      watch.stop();
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: false,
        message: 'TLS 握手失败',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<DohProbeResult> testDoh(DohProvider provider) async {
    final resolver = DohResolver(provider: provider, timeout: timeout);
    return _testDohResolver(resolver);
  }

  Future<DohProbeResult> testCustomDoh(String uri) async {
    final endpoint = Uri.tryParse(uri);
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      return const DohProbeResult(
        elapsed: Duration.zero,
        success: false,
        message: '地址格式不正确',
        addresses: [],
      );
    }
    final resolver = DohResolver.custom(endpoint: endpoint, timeout: timeout);
    return _testDohResolver(resolver);
  }

  Future<DohProbeResult> _testDohResolver(DohResolver resolver) async {
    final watch = Stopwatch()..start();
    try {
      final addresses = await resolver
          .lookup(ForumNetworkConfig.defaultSite.host)
          .timeout(timeout);
      watch.stop();
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: addresses.isNotEmpty,
        message: addresses.isEmpty ? '无记录' : '可用',
        addresses: addresses,
      );
    } on TimeoutException {
      watch.stop();
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: false,
        message: '超时',
        addresses: const [],
      );
    } on SocketException catch (error) {
      watch.stop();
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: false,
        message: error.message,
        addresses: const [],
      );
    } on FormatException {
      watch.stop();
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: false,
        message: '响应解析失败',
        addresses: const [],
      );
    } on Object catch (error) {
      watch.stop();
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: false,
        message: '$error',
        addresses: const [],
      );
    }
  }

  Future<ForumAddressProbeResult> testAddress(
    ForumSite site,
    InternetAddress address,
  ) async {
    final result = await testSite(
      site,
      dohEnabled: false,
      dohProvider: ForumNetworkConfig.defaultProvider,
      fixedAddress: address.address,
    );
    return ForumAddressProbeResult(
      address: address,
      elapsed: result.elapsed,
      success: result.success,
      message: result.message,
      statusCode: result.statusCode,
    );
  }
}

class ForumSiteProbeResult {
  const ForumSiteProbeResult({
    required this.site,
    required this.elapsed,
    required this.success,
    required this.message,
    this.statusCode,
  });

  final ForumSite site;
  final Duration elapsed;
  final bool success;
  final String message;
  final int? statusCode;

  String get latencyLabel => success ? '${elapsed.inMilliseconds} ms' : '-';
}

class DohProbeResult {
  const DohProbeResult({
    required this.elapsed,
    required this.success,
    required this.message,
    required this.addresses,
  });

  final Duration elapsed;
  final bool success;
  final String message;
  final List<InternetAddress> addresses;

  String get latencyLabel => success ? '${elapsed.inMilliseconds} ms' : '-';

  String get addressesLabel =>
      addresses.map((address) => address.address).join(', ');
}

class ForumAddressProbeResult {
  const ForumAddressProbeResult({
    required this.address,
    required this.elapsed,
    required this.success,
    required this.message,
    this.statusCode,
  });

  final InternetAddress address;
  final Duration elapsed;
  final bool success;
  final String message;
  final int? statusCode;

  String get latencyLabel => success ? '${elapsed.inMilliseconds} ms' : '-';
}
