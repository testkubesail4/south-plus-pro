import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/network_settings_screen.dart';
import 'package:south_plus_rewrite/features/profile/network_setup_flow_screen.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic loopback proxy only.
final _proxy =
    ForumProxy(type: ForumProxyType.http, host: '127.0.0.1', port: 8080);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The setup flow animates forever, so settle with bounded pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<_Repo> pumpFlow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo(const ForumNetworkConfig(
      site: ForumNetworkConfig.defaultSite,
      dohEnabled: true,
      dohProvider: ForumNetworkConfig.defaultProvider,
    ));
    await tester.pumpWidget(MaterialApp(
      home: NetworkSetupFlowScreen(repository: repo, allowSkip: true),
    ));
    await settle(tester);
    return repo;
  }

  testWidgets('first run offers optimize, proxy and skip; proxy is saved',
      (tester) async {
    final repo = await pumpFlow(tester);
    expect(find.text('开启网络优化'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    await tester.tap(find.text('使用代理'));
    await settle(tester);
    final next = find.widgetWithText(FilledButton, '下一步');
    expect(tester.widget<FilledButton>(next).onPressed, isNull,
        reason: 'no proxy entered yet');

    await tester.enterText(find.widgetWithText(TextField, '主机'), '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, '端口'), '8080');
    await tester.tap(find.text('使用此代理'));
    await settle(tester);
    expect(find.text('HTTP 127.0.0.1:8080'), findsOneWidget);

    await tester.tap(find.text('开始使用'));
    await settle(tester);
    expect(repo.saved.single.proxy, _proxy);
    expect(repo.saved.single.dohEnabled, isFalse);
    expect(await ForumNetworkSetupStore.loadChoice(),
        ForumNetworkSetupChoice.proxy);
  });

  testWidgets('a failed final save stays retryable and leaks nothing',
      (tester) async {
    final repo = await pumpFlow(tester);
    repo.failSaves = 1;
    await tester.tap(find.text('使用代理'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '主机'), '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, '端口'), '8080');
    await tester.tap(find.text('使用此代理'));
    await settle(tester);

    await tester.tap(find.text('开始使用'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('保存网络设置失败，请重试'), findsOneWidget);
    expect(find.textContaining('proxy-secret-token'), findsNothing);
    expect(await ForumNetworkSetupStore.isCompleted(), isFalse);

    // Retry once the message has gone from over the bottom bar.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    await tester.tap(find.text('开始使用'));
    await settle(tester);
    expect(repo.saved.single.proxy, _proxy);
    expect(await ForumNetworkSetupStore.isCompleted(), isTrue);
  });

  testWidgets('picking another mode after proxy drops the proxy',
      (tester) async {
    final repo = await pumpFlow(tester);
    await tester.tap(find.text('使用代理'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '主机'), '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, '端口'), '8080');
    await tester.tap(find.text('使用此代理'));
    await settle(tester);
    await tester.tap(find.text('上一步'));
    await settle(tester);
    await tester.tap(find.text('上一步'));
    await settle(tester);

    await tester.tap(find.text('系统默认解析'));
    await settle(tester);
    await tester.tap(find.text('跳过'));
    await settle(tester);
    expect(repo.saved.single.proxy, isNull);
  });

  testWidgets('skip saves a plain direct setup', (tester) async {
    final repo = await pumpFlow(tester);
    await tester.tap(find.text('跳过'));
    await settle(tester);
    expect(repo.saved.single.dohEnabled, isFalse);
    expect(repo.saved.single.proxy, isNull);
    expect(repo.saved.single.fixedAddress, isNull);
    expect(await ForumNetworkSetupStore.loadChoice(),
        ForumNetworkSetupChoice.skip);
  });

  testWidgets('settings set and disable a proxy; optimization is hidden',
      (tester) async {
    final repo = _Repo(const ForumNetworkConfig(
      site: ForumNetworkConfig.defaultSite,
      dohEnabled: true,
      dohProvider: ForumNetworkConfig.defaultProvider,
    ));
    await tester.pumpWidget(
      MaterialApp(home: NetworkSettingsScreen(repository: repo)),
    );
    await settle(tester);
    expect(find.text('未使用'), findsOneWidget);

    await tester.tap(find.text('代理'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '主机'), '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, '端口'), '8080');
    await tester.tap(find.text('保存代理'));
    await settle(tester);
    expect(repo.networkConfig.proxy, _proxy);
    expect(find.text('HTTP 127.0.0.1:8080'), findsWidgets);
    expect(find.text('加密 DNS'), findsNothing, reason: 'exclusive with proxy');
    expect(find.text('线路选择'), findsNothing);

    // The overview card now also reads 代理; the entry tile comes last.
    await tester.tap(find.text('代理').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '停用代理，改为直接连接'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, '停用代理，改为直接连接'));
    await settle(tester);
    expect(repo.networkConfig.proxy, isNull);
    expect(find.text('加密 DNS'), findsWidgets);
  });

  testWidgets('settings guide clears the proxy before optimizing',
      (tester) async {
    final repo = _Repo(ForumNetworkConfig(
      site: ForumNetworkConfig.defaultSite,
      dohEnabled: false,
      dohProvider: ForumNetworkConfig.defaultProvider,
      proxy: _proxy,
    ));
    await tester.pumpWidget(
      MaterialApp(home: NetworkSettingsScreen(repository: repo)),
    );
    await settle(tester);

    await tester.tap(find.text('引导'));
    await settle(tester);
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.byType(NetworkSetupFlowScreen), findsNothing);
    expect(repo.networkConfig.proxy, _proxy);

    await tester.tap(find.text('引导'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, '停用代理，改为直接连接'));
    await settle(tester);
    expect(repo.networkConfig.proxy, isNull);
    expect(find.byType(NetworkSetupFlowScreen), findsOneWidget);
  });
}

class _Repo extends ForumRepository {
  _Repo(this._config);

  ForumNetworkConfig _config;
  final saved = <ForumNetworkConfig>[];
  var failSaves = 0;

  @override
  ForumNetworkConfig get networkConfig => _config;

  @override
  Future<void> updateNetworkConfig(ForumNetworkConfig config) async {
    if (failSaves > 0) {
      failSaves--;
      throw StateError('leaked proxy-secret-token');
    }
    saved.add(config);
    _config = config;
  }
}
