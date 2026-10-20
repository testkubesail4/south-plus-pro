import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/features/profile/network_settings_screen.dart';
import 'package:south_plus_rewrite/features/profile/network_setup_flow_screen.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_probe.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic loopback proxy and documentation-free public addresses only.
final _proxy =
    ForumProxy(type: ForumProxyType.http, host: '127.0.0.1', port: 8080);
const _defaults = ForumNetworkConfig(site: ForumNetworkConfig.defaultSite);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void tallView(WidgetTester tester, {double width = 400}) {
    tester.view.physicalSize = Size(width, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<_Repo> pumpGuide(WidgetTester tester,
      {ForumNetworkConfig config = _defaults, _Probe? probe}) async {
    tallView(tester);
    final repo = _Repo(config);
    await tester.pumpWidget(MaterialApp(
      home: NetworkSetupFlowScreen(
          repository: repo, firstRun: true, probe: probe ?? _Probe()),
    ));
    await settle(tester);
    return repo;
  }

  Future<_Repo> pumpSettings(WidgetTester tester,
      {ForumNetworkConfig config = _defaults, _Probe? probe}) async {
    tallView(tester);
    final repo = _Repo(config);
    await tester.pumpWidget(MaterialApp(
      home: NetworkSettingsScreen(repository: repo, probe: probe ?? _Probe()),
    ));
    await settle(tester);
    return repo;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> enterProxy(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextField, '主机'), '127.0.0.1');
    await tester.enterText(find.widgetWithText(TextField, '端口'), '8080');
  }

  group('guide', () {
    testWidgets('only 下一步 saves optimized, south-plus.net and IPv6 off',
        (tester) async {
      final repo = await pumpGuide(tester);
      for (var i = 0; i < 3; i++) {
        await tapText(tester, '下一步');
      }
      await tapText(tester, '开始使用');
      final saved = repo.saved.single;
      expect(saved.mode, ForumNetworkMode.optimized);
      expect(saved.site.host, 'south-plus.net');
      expect(saved.ipv6Enabled, isFalse);
      expect(saved.dohProvider, ForumNetworkConfig.defaultProvider);
      expect(await ForumNetworkSetupStore.isCompleted(), isTrue);
    });

    testWidgets('chosen DNS, IPv6 and entrance are what gets saved',
        (tester) async {
      final repo = await pumpGuide(tester);
      await tapText(tester, '下一步');
      await tapText(tester, DohProvider.tiarap.label);
      await tapText(tester, '使用 IPv6');
      await tapText(tester, '下一步');
      await tapText(tester, 'blue-plus.net');
      await tapText(tester, '下一步');
      expect(find.text('开启'), findsOneWidget, reason: 'summary shows IPv6');
      await tapText(tester, '开始使用');
      final saved = repo.saved.single;
      expect(saved.dohProvider, DohProvider.tiarap);
      expect(saved.ipv6Enabled, isTrue);
      expect(saved.site.host, 'blue-plus.net');
    });

    testWidgets('pending or failed probes never hold the user back',
        (tester) async {
      // DNS probes never finish; the connection check fails.
      final probe = _Probe(check: (_) async => _failure('连接超时'));
      final repo = await pumpGuide(tester, probe: probe);
      await tapText(tester, '下一步');
      expect(find.text('测速中'), findsWidgets);
      await tapText(tester, '下一步');
      await tapText(tester, '下一步');
      expect(find.textContaining('测试未通过：连接超时'), findsOneWidget);
      expect(find.textContaining('成功'), findsNothing);
      await tapText(tester, '开始使用');
      expect(repo.saved, hasLength(1));
    });

    testWidgets('proxy mode needs a proxy, then saves proxy mode',
        (tester) async {
      final repo = await pumpGuide(tester);
      await tapText(tester, '代理');
      await tapText(tester, '下一步');
      final next = find.widgetWithText(FilledButton, '下一步');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      expect(find.textContaining('明文'), findsOneWidget,
          reason: 'HTTP proxies warn about clear-text credentials');

      await enterProxy(tester);
      await tapText(tester, '使用此代理');
      await tapText(tester, '下一步');
      expect(find.text('HTTP 127.0.0.1:8080'), findsOneWidget);
      await tapText(tester, '开始使用');
      expect(repo.saved.single.mode, ForumNetworkMode.proxy);
      expect(repo.saved.single.proxy, _proxy);
    });

    testWidgets('an invalid proxy is explained and never saved',
        (tester) async {
      final repo = await pumpGuide(tester);
      await tapText(tester, '代理');
      await tapText(tester, '下一步');
      await tester.enterText(
          find.widgetWithText(TextField, '主机'), 'not a host!');
      await tester.enterText(find.widgetWithText(TextField, '端口'), '1080');
      await tapText(tester, '使用此代理');
      expect(find.text('请输入有效的代理主机和端口'), findsOneWidget);
      final next = find.widgetWithText(FilledButton, '下一步');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      expect(repo.saved, isEmpty);
    });

    testWidgets('leaving proxy mode saves the new mode, proxy kept unused',
        (tester) async {
      final repo = await pumpGuide(tester);
      await tapText(tester, '代理');
      await tapText(tester, '下一步');
      await enterProxy(tester);
      await tapText(tester, '使用此代理');
      for (var i = 0; i < 2; i++) {
        await tapText(tester, '上一步');
      }
      await tapText(tester, '直接连接');
      await tapText(tester, '下一步');
      await tapText(tester, '下一步');
      await tapText(tester, '开始使用');
      expect(repo.saved.single.mode, ForumNetworkMode.native);
      expect(repo.saved.single.proxy, _proxy);
    });

    testWidgets('a failed save stays retryable and leaks nothing',
        (tester) async {
      final repo = await pumpGuide(tester);
      repo.failSaves = 1;
      for (var i = 0; i < 3; i++) {
        await tapText(tester, '下一步');
      }
      await tapText(tester, '开始使用');
      expect(tester.takeException(), isNull);
      expect(find.text('保存网络设置失败，请重试'), findsOneWidget);
      expect(find.textContaining('proxy-secret-token'), findsNothing);
      expect(await ForumNetworkSetupStore.isCompleted(), isFalse);

      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      await tapText(tester, '开始使用');
      expect(repo.saved, hasLength(1));
      expect(await ForumNetworkSetupStore.isCompleted(), isTrue);
    });

    testWidgets('saving keeps the button label and adds a spinner',
        (tester) async {
      final repo = await pumpGuide(tester);
      final gate = repo.gate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        await tapText(tester, '下一步');
      }
      await tapText(tester, '开始使用');
      final button = find.ancestor(
          of: find.text('开始使用'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
      expect(
          find.descendant(
              of: button, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(repo.saved, hasLength(1));
    });

    testWidgets('target addresses are validated and kept per host',
        (tester) async {
      final repo = await pumpGuide(tester);
      for (var i = 0; i < 3; i++) {
        await tapText(tester, '下一步');
      }
      await tapText(tester, '目标地址');
      final field = find.byType(TextField);
      await tester.enterText(field, '10.0.0.1');
      await tapText(tester, '保存');
      expect(find.textContaining('10.0.0.1：'), findsOneWidget,
          reason: 'private addresses are rejected');

      await tester.enterText(field, '104.18.26.110\n2606:4700::6812:1a6e');
      await settle(tester);
      expect(find.text('IPv6 未开启，其中的 IPv6 地址暂不使用。'), findsOneWidget);
      await tapText(tester, '保存');
      expect(find.text('2 个自定义'), findsOneWidget);
      await tapText(tester, '开始使用');
      expect(repo.saved.single.hostAddresses, {
        'south-plus.net': ['104.18.26.110', '2606:4700::6812:1a6e'],
      });
    });

    testWidgets('proxy types stay on one line at large text', (tester) async {
      tallView(tester, width: 360);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: NetworkSetupFlowScreen(
              repository: _Repo(_defaults), firstRun: true, probe: _Probe()),
        ),
      ));
      await settle(tester);
      await tapText(tester, '代理');
      await tapText(tester, '下一步');
      final height = tester.getRect(find.text('HTTP')).height;
      for (final label in ['HTTPS', 'SOCKS5']) {
        final text = tester.getRect(find.text(label));
        expect(text.height, moreOrLessEquals(height, epsilon: 0.5),
            reason: '$label is one line');
        final chip = tester.getRect(find.widgetWithText(ChoiceChip, label));
        expect(chip.contains(text.topLeft) && chip.contains(text.bottomRight),
            isTrue,
            reason: '$label fits its chip');
      }
    });
  });

  group('settings', () {
    testWidgets('status claims nothing until a test has run', (tester) async {
      final check = Completer<ForumSiteProbeResult>();
      await pumpSettings(tester, probe: _Probe(check: (_) => check.future));
      expect(find.text('正在测试…'), findsOneWidget);
      expect(find.textContaining('稳定'), findsNothing);
      check.complete(_failure('TLS 握手失败'));
      await settle(tester);
      expect(find.text('刚才的测试失败：TLS 握手失败'), findsOneWidget);
    });

    testWidgets('a change cancels the running test and drops its result',
        (tester) async {
      final first = Completer<ForumSiteProbeResult>();
      final probe = _Probe(check: (_) => first.future);
      await pumpSettings(tester, probe: probe);
      await tapText(tester, '使用 IPv6');
      expect(probe.checks.single!.isCancelled, isTrue);

      first.complete(_success());
      await settle(tester);
      expect(find.text('尚未测试当前设置'), findsOneWidget);
      expect(find.textContaining('成功'), findsNothing);
    });

    testWidgets('an editor test result belongs to the input it ran with',
        (tester) async {
      final first = Completer<ForumSiteProbeResult>();
      final probe = _Probe(check: (_) => first.future);
      await pumpSettings(tester, probe: probe);
      await tapText(tester, '目标地址');
      final field = find.byType(TextField);
      await tester.enterText(field, '104.18.26.110');
      await tapText(tester, '测试');
      final token = probe.checks.last!;

      await tester.enterText(field, '104.18.27.110');
      await settle(tester);
      expect(token.isCancelled, isTrue);
      first.complete(_success());
      await settle(tester);
      expect(find.textContaining('可以连接'), findsNothing);
    });

    testWidgets('modes are exclusive; leaving proxy asks first',
        (tester) async {
      final repo = await pumpSettings(tester);
      expect(find.text('加密 DNS'), findsOneWidget);

      await tapText(tester, '代理');
      expect(find.text('保存代理'), findsOneWidget,
          reason: 'proxy mode without a proxy opens the form');
      await enterProxy(tester);
      await tapText(tester, '保存代理');
      expect(repo.networkConfig.mode, ForumNetworkMode.proxy);
      expect(repo.networkConfig.proxy, _proxy);
      expect(find.text('加密 DNS'), findsNothing,
          reason: 'optimization details hide outside their mode');

      await tapText(tester, '直接连接');
      await tapText(tester, '取消');
      expect(repo.networkConfig.mode, ForumNetworkMode.proxy);

      await tapText(tester, '直接连接');
      await tapText(tester, '停用代理，改为直接连接');
      expect(repo.networkConfig.mode, ForumNetworkMode.native);
      expect(repo.networkConfig.proxy, _proxy, reason: 'kept, unused');
      expect(find.text('已保存的代理'), findsOneWidget);
    });

    testWidgets('a failed save shows the settings that still apply',
        (tester) async {
      final repo = await pumpSettings(tester);
      repo.failSaves = 1;
      await tapText(tester, '使用 IPv6');
      expect(find.text('保存失败，设置未更改'), findsOneWidget);
      expect(find.textContaining('proxy-secret-token'), findsNothing);
      final ipv6 = find.descendant(
          of: find.ancestor(
              of: find.text('使用 IPv6'), matching: find.byType(InkWell)),
          matching: find.byType(Switch));
      expect(tester.widget<Switch>(ipv6).value, isFalse);

      await tapText(tester, '使用 IPv6');
      expect(repo.networkConfig.ipv6Enabled, isTrue);
    });

    testWidgets('a custom entrance is validated, saved and selected',
        (tester) async {
      final repo = await pumpSettings(tester);
      await tapText(tester, 'south-plus.net');
      await tapText(tester, '添加访问入口');
      await tester.enterText(find.byType(TextField), 'not a host');
      await tapText(tester, '添加');
      expect(find.textContaining('请输入有效的域名'), findsOneWidget);
      await tester.enterText(
          find.byType(TextField), 'https://example-plus.net/index.php');
      await tapText(tester, '添加');
      expect(repo.networkConfig.site.host, 'example-plus.net');
      expect(await ForumNetworkSettings.loadCustomSites(),
          [const ForumSite('example-plus.net')]);
    });

    testWidgets('a custom DNS service needs https and keeps its bootstrap',
        (tester) async {
      final repo = await pumpSettings(tester);
      await tapText(tester, '加密 DNS');
      await tapText(tester, '自定义加密 DNS');
      await tester.enterText(find.widgetWithText(TextField, '服务地址'),
          'http://dns.example-plus.net/dns-query');
      await tapText(tester, '使用此服务');
      expect(find.text('请输入 https:// 开头的完整地址'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '服务地址'),
          'https://dns.example-plus.net/dns-query');
      await tester.enterText(
          find.widgetWithText(TextField, '引导地址（可选）'), '1.1.1.1');
      await tapText(tester, '使用此服务');
      expect(repo.networkConfig.customDohUri,
          'https://dns.example-plus.net/dns-query');
      expect(repo.networkConfig.dohBootstrapAddresses, ['1.1.1.1']);
    });
  });

  group('startup', () {
    const corrupt = {
      'forum_network_config_v2': '{"version": 2',
      ForumNetworkSetupStore.completedKey: true,
    };

    testWidgets('unreadable settings pause everything until repaired',
        (tester) async {
      SharedPreferences.setMockInitialValues(corrupt);
      tallView(tester);
      await tester.pumpWidget(const MaterialApp(home: SessionGate()));
      await tester.pumpAndSettle();
      expect(find.text('网络设置无法读取'), findsOneWidget);
      expect(find.text('先浏览公开内容'), findsNothing);

      await enterProxy(tester);
      await tapText(tester, '保存代理并重试');
      await tester.pumpAndSettle();
      final config = await ForumNetworkSettings.load();
      expect(config.mode, ForumNetworkMode.proxy);
      expect(config.proxy, _proxy);
      expect(find.text('网络设置无法读取'), findsNothing);
    });

    testWidgets('defaults replace broken settings only after confirmation',
        (tester) async {
      SharedPreferences.setMockInitialValues(corrupt);
      tallView(tester);
      await tester.pumpWidget(const MaterialApp(home: SessionGate()));
      await tester.pumpAndSettle();
      await tapText(tester, '改用默认设置');
      await tapText(tester, '取消');
      await expectLater(ForumNetworkSettings.load(), throwsFormatException);

      await tapText(tester, '改用默认设置');
      await tapText(tester, '改用默认设置');
      await tester.pumpAndSettle();
      expect(
          (await ForumNetworkSettings.load()).mode, ForumNetworkMode.optimized);
      expect(find.text('选择连接方式'), findsOneWidget,
          reason: 'the guide starts over');
    });

    testWidgets('a failed session restore still reaches network settings',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {ForumNetworkSetupStore.completedKey: true});
      tallView(tester);
      await tester.pumpWidget(
          MaterialApp(home: SessionGate(repository: _OfflineRepo())));
      await tester.pumpAndSettle();
      await tapText(tester, '网络设置');
      expect(find.text('网络连接'), findsOneWidget);
    });

    test('finishing the guide clears the legacy choice', () async {
      SharedPreferences.setMockInitialValues(
          {'forum_network_setup_choice_v1': 'skip'});
      await ForumNetworkSetupStore.markCompleted();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ForumNetworkSetupStore.completedKey), isTrue);
      expect(prefs.containsKey('forum_network_setup_choice_v1'), isFalse);
      await ForumNetworkSetupStore.reset();
      expect(await ForumNetworkSetupStore.isCompleted(), isFalse);
    });
  });
}

ForumSiteProbeResult _failure(String message) => ForumSiteProbeResult(
    site: ForumNetworkConfig.defaultSite,
    elapsed: const Duration(seconds: 1),
    success: false,
    message: message);

ForumSiteProbeResult _success() => ForumSiteProbeResult(
    site: ForumNetworkConfig.defaultSite,
    elapsed: const Duration(milliseconds: 120),
    success: true,
    statusCode: 200,
    message: '可用');

/// Probes that never touch the network: unanswered unless told otherwise.
class _Probe extends ForumNetworkProbe {
  _Probe({this.check});

  final Future<ForumSiteProbeResult> Function(ForumNetworkConfig)? check;

  /// Every token handed to a connection test, in order.
  final checks = <ForumProbeCancellation?>[];

  @override
  Future<ForumSiteProbeResult> testConfig(ForumNetworkConfig config,
      {ForumProbeCancellation? cancellation}) {
    checks.add(cancellation);
    return check?.call(config) ?? Completer<ForumSiteProbeResult>().future;
  }

  @override
  Future<DohProbeResult> testDoh(DohProvider provider,
          {bool ipv6Enabled = false,
          String? host,
          ForumProbeCancellation? cancellation}) =>
      Completer<DohProbeResult>().future;

  @override
  Future<DohProbeResult> testCustomDoh(String uri,
          {List<String> bootstrapAddresses = const [],
          bool ipv6Enabled = false,
          String? host,
          ForumProbeCancellation? cancellation}) =>
      Completer<DohProbeResult>().future;
}

class _Repo extends ForumRepository {
  _Repo(this._config);

  ForumNetworkConfig _config;
  final saved = <ForumNetworkConfig>[];
  var failSaves = 0;

  /// While set, saves wait for it.
  Completer<void>? gate;

  @override
  ForumNetworkConfig get networkConfig => _config;

  @override
  Future<void> updateNetworkConfig(ForumNetworkConfig config) async {
    await gate?.future;
    if (failSaves > 0) {
      failSaves--;
      throw StateError('leaked proxy-secret-token');
    }
    saved.add(config);
    _config = config;
  }
}

class _OfflineRepo extends _Repo {
  _OfflineRepo() : super(_defaults);

  @override
  Future<bool> restoreSession() async => throw const SocketException('offline');
}
