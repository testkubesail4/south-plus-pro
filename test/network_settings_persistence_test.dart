import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_http_routing.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var reject = false;
  var throwOnWrite = false;
  var writes = 0;
  var rejectAt = 0;
  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    reject = false;
    writes = 0;
    rejectAt = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      writes++;
      if (reject && writes >= rejectAt) {
        if (throwOnWrite)
          throw PlatformException(code: 'fixture-write-failure');
        return false;
      }
      final args = call.arguments as Map;
      final key = args['key'] as String;
      if (call.method == 'remove') {
        persisted.remove(key);
      } else {
        persisted[key] = args['value'] as Object;
      }
      return true;
    });
  });
  tearDown(() {
    ForumHttpRouting.updateProxy(null);
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final disable in [false, true]) {
    test(
        'repair ${disable ? 'disable' : 'save'} reports rejected persistence and can retry',
        () async {
      throwOnWrite = false;
      final original = ForumNetworkConfig(
          site: const ForumSite('fixture.invalid'),
          dohEnabled: true,
          dohProvider: ForumNetworkConfig.defaultProvider);
      await ForumNetworkSettings.save(original);
      final proxy = ForumProxy(
          type: ForumProxyType.http, host: 'proxy.fixture.invalid', port: 8080);
      Future<void> save() => disable
          ? ForumNetworkSettings.disableProxy()
          : ForumNetworkSettings.saveProxy(proxy);
      reject = true;
      await expectLater(save(), throwsA(isA<Exception>()));
      expect(await ForumNetworkSettings.load(), original);
      reject = false;
      await save();
      final loaded = await ForumNetworkSettings.load();
      expect(loaded.proxy, disable ? isNull : proxy);
      expect(loaded.dohEnabled, isFalse);
    });
  }

  for (final failAfter in [0, 2]) {
    for (final throws in [false, true]) {
      test(
          'failed settings ${throws ? 'exception' : 'false'} after $failAfter writes preserves live route and retry persists',
          () async {
        throwOnWrite = throws;
        final original = ForumNetworkConfig(
            site: const ForumSite('fixture.invalid'),
            dohEnabled: false,
            dohProvider: ForumNetworkConfig.defaultProvider,
            proxy: ForumProxy(
                type: ForumProxyType.http,
                host: 'proxy.fixture.invalid',
                port: 8080));
        await ForumNetworkSettings.save(original);
        final beforeDisk = Map<String, Object>.of(persisted);
        final client = _TrackedClient(original);
        final repository = ForumRepository(client: client);
        final epoch = repository.sessionEpoch.value;
        final requested = original.copyWith(clearProxy: true);
        rejectAt = writes + failAfter + 1;
        reject = true;
        await expectLater(repository.updateNetworkConfig(requested),
            throwsA(isA<Exception>()));
        expect(repository.networkConfig, original);
        expect(repository.sessionEpoch.value, epoch);
        expect(client.closed, isFalse);
        expect(ForumHttpRouting.proxyEnabled, isTrue);
        expect(persisted, beforeDisk);
        expect(await ForumNetworkSettings.load(), original);
        final attempts = writes;
        reject = false;
        await repository.updateNetworkConfig(requested);
        expect(writes, greaterThan(attempts));
        expect(repository.networkConfig, requested);
        expect(client.closed, isTrue);
        expect(ForumHttpRouting.proxyEnabled, isFalse);
        await (await SharedPreferences.getInstance()).reload();
        expect(await ForumNetworkSettings.load(), requested);
      });
    }
  }
}

class _TrackedClient extends ForumClient {
  _TrackedClient(ForumNetworkConfig config) : super(config: config);
  bool closed = false;
  @override
  void close({bool force = false}) {
    closed = true;
    super.close(force: force);
  }
}
