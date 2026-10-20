import 'dart:async';
import 'dart:io';

import 'forum_connection_race.dart';
import 'forum_http_routing.dart';
import 'forum_network_config.dart';

class ForumProbeCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  final _close = <void Function()>{};
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final close in _close.toList()) {
      close();
    }
    _close.clear();
  }

  void Function() _attach(void Function() close) {
    if (_cancelled) {
      close();
    } else {
      _close.add(close);
    }
    return () => _close.remove(close);
  }
}

class ForumNetworkProbe {
  const ForumNetworkProbe({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;

  Future<ForumSiteProbeResult> testConfig(
    ForumNetworkConfig config, {
    ForumProbeCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false)
      return ForumSiteProbeResult(
        site: config.site,
        elapsed: Duration.zero,
        success: false,
        message: '已取消',
      );
    return _testClient(
      config.site,
      createForumHttpClient(config),
      cancellation: cancellation,
    );
  }

  Future<ForumSiteProbeResult> _testClient(
    ForumSite site,
    HttpClient client, {
    ForumProbeCancellation? cancellation,
  }) async {
    final watch = Stopwatch()..start();
    final detach = cancellation?._attach(() => client.close(force: true));
    String message(String fallback) =>
        cancellation?.isCancelled == true ? '已取消' : fallback;
    try {
      client.connectionTimeout = timeout;
      HttpClientResponse? response;
      InternetAddress? remoteAddress;
      await (() async {
        final request = await client.getUrl(
          site.baseUri.resolve('simple/index.php'),
        );
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*');
        response = await request.close();
        remoteAddress = response!.connectionInfo?.remoteAddress;
        await response!.drain<void>();
      })()
          .timeout(timeout);
      final code = response!.statusCode;
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: code == HttpStatus.ok && cancellation?.isCancelled != true,
        statusCode: code,
        remoteAddress: remoteAddress,
        message: message(code == HttpStatus.ok ? '可用' : 'HTTP $code'),
      );
    } on TimeoutException {
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: false,
        message: message('超时'),
      );
    } on HandshakeException {
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: false,
        message: message('TLS 握手失败'),
      );
    } on Object {
      return ForumSiteProbeResult(
        site: site,
        elapsed: watch.elapsed,
        success: false,
        message: message('连接失败'),
      );
    } finally {
      detach?.call();
      client.close(force: true);
    }
  }

  Future<DohProbeResult> testDoh(
    DohProvider provider, {
    bool ipv6Enabled = false,
    String? host,
    ForumProbeCancellation? cancellation,
  }) =>
      _testDohResolver(
        DohResolver(
            provider: provider, timeout: timeout, ipv6Enabled: ipv6Enabled),
        host,
        cancellation,
      );

  Future<DohProbeResult> testCustomDoh(
    String uri, {
    List<String> bootstrapAddresses = const [],
    bool ipv6Enabled = false,
    String? host,
    ForumProbeCancellation? cancellation,
  }) async {
    final normalized = ForumNetworkConfig.normalizeDohUri(uri);
    if (normalized == null ||
        bootstrapAddresses.any(
          (ip) => ForumNetworkConfig.validateAddressLiteral(ip) != null,
        )) {
      return const DohProbeResult(
        elapsed: Duration.zero,
        success: false,
        message: '地址格式不正确',
        addresses: [],
      );
    }
    return _testDohResolver(
      DohResolver.custom(
        endpoint: Uri.parse(normalized),
        timeout: timeout,
        bootstrapAddresses: bootstrapAddresses,
        ipv6Enabled: ipv6Enabled,
      ),
      host,
      cancellation,
    );
  }

  Future<DohProbeResult> _testDohResolver(
    DohResolver resolver,
    String? host,
    ForumProbeCancellation? cancellation,
  ) async {
    final watch = Stopwatch()..start();
    final detach = cancellation?._attach(resolver.close);
    String message(String fallback) =>
        cancellation?.isCancelled == true ? '已取消' : fallback;
    try {
      final addresses = await resolver
          .lookup(host ?? ForumNetworkConfig.defaultSite.host)
          .timeout(timeout);
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: cancellation?.isCancelled != true,
        message: message('可用'),
        addresses: addresses,
      );
    } on TimeoutException {
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: false,
        message: message('超时'),
        addresses: const [],
      );
    } on Object {
      return DohProbeResult(
        elapsed: watch.elapsed,
        success: false,
        message: message('解析失败'),
        addresses: const [],
      );
    } finally {
      detach?.call();
      resolver.close();
    }
  }

  // Transitional callers use the same isolated v2 probe, never global routing.
  Future<ForumSiteProbeResult> testSite(
    ForumSite site, {
    required bool dohEnabled,
    required DohProvider dohProvider,
    String? customDohUri,
    String? fixedAddress,
  }) =>
      fixedAddress != null
          ? _testAddress(site, InternetAddress(fixedAddress))
          : testConfig(
              ForumNetworkConfig(
                site: site,
                mode: dohEnabled
                    ? ForumNetworkMode.optimized
                    : ForumNetworkMode.native,
                dohProvider: dohProvider,
                customDohUri: customDohUri,
              ),
            );

  Future<ForumSiteProbeResult> _testAddress(
    ForumSite site,
    InternetAddress address,
  ) {
    final client = createUnroutedHttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, _, __) async {
      final race = ForumConnectionRace(uri, timeout: timeout);
      race.add([address]);
      race.finishAdding();
      return ConnectionTask.fromSocket(race.socket, race.cancel);
    };
    return _testClient(site, client);
  }

  Future<ForumAddressProbeResult> testAddress(
    ForumSite site,
    InternetAddress address,
  ) async {
    final result = await _testAddress(site, address);
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
    this.remoteAddress,
  });
  final ForumSite site;
  final Duration elapsed;
  final bool success;
  final String message;
  final int? statusCode;
  final InternetAddress? remoteAddress;
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
