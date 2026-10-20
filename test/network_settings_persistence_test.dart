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
  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    reject = false;
    throwOnWrite = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      if (reject) {
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
      'repair ${disable ? 'disable' : 'save'} replaces corrupt JSON only after persistence succeeds',
      () async {
        persisted['flutter.forum_network_config_v2'] = '{corrupt-synthetic';
        final before = Map<String, Object>.of(persisted);
        final proxy = ForumProxy(
          type: ForumProxyType.http,
          host: 'proxy.fixture.invalid',
          port: 8080,
        );
        Future<void> save() => disable
            ? ForumNetworkSettings.disableProxy()
            : ForumNetworkSettings.saveProxy(proxy);
        reject = true;
        await expectLater(save(), throwsA(isA<Exception>()));
        expect(persisted, before);
        await expectLater(ForumNetworkSettings.load(), throwsFormatException);
        reject = false;
        await save();
        final loaded = await ForumNetworkSettings.load();
        expect(loaded.proxy, disable ? isNull : proxy);
        expect(
          loaded.mode,
          disable ? ForumNetworkMode.native : ForumNetworkMode.proxy,
        );
      },
    );
  }

  for (final throws in [false, true]) {
    test(
      'atomic settings ${throws ? 'exception' : 'false'} preserves live route, session and disk until retry',
      () async {
        throwOnWrite = throws;
        final original = ForumNetworkConfig(
          site: const ForumSite('fixture.invalid'),
          mode: ForumNetworkMode.proxy,
          proxy: ForumProxy(
            type: ForumProxyType.http,
            host: 'proxy.fixture.invalid',
            port: 8080,
          ),
        );
        await ForumNetworkSettings.save(original);
        final beforeDisk = Map<String, Object>.of(persisted);
        final client = _TrackedClient(original);
        final repository = ForumRepository(client: client);
        final epoch = repository.sessionEpoch.value;
        final requested = original.copyWith(mode: ForumNetworkMode.native);
        reject = true;
        await expectLater(
          repository.updateNetworkConfig(requested),
          throwsA(isA<Exception>()),
        );
        expect(repository.networkConfig, original);
        expect(repository.sessionEpoch.value, epoch);
        expect(client.closed, isFalse);
        expect(ForumHttpRouting.proxyEnabled, isTrue);
        expect(persisted, beforeDisk);
        expect(await ForumNetworkSettings.load(), original);
        reject = false;
        await repository.updateNetworkConfig(requested);
        expect(repository.networkConfig, requested);
        expect(client.closed, isTrue);
        expect(ForumHttpRouting.proxyEnabled, isFalse);
        expect(requested.proxy, original.proxy);
        await (await SharedPreferences.getInstance()).reload();
        expect(await ForumNetworkSettings.load(), requested);
      },
    );
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
