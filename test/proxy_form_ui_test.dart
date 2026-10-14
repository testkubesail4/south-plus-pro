import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/profile/proxy_form.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';

// Synthetic proxy endpoint and credentials only.
void main() {
  late List<ForumProxy> saved;
  late int disabled;

  Future<void> pumpRepair(WidgetTester tester, {bool fail = false}) async {
    saved = [];
    disabled = 0;
    // A failure message that would leak a secret if shown verbatim.
    Never secretError() => throw StateError('leaked proxy-secret-token');
    await tester.pumpWidget(MaterialApp(
      home: ProxyRepairScreen(
        onSaveProxy: (proxy) async => fail ? secretError() : saved.add(proxy),
        onDisableProxy: () async => fail ? secretError() : disabled++,
      ),
    ));
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('repair saves only a proxy the model accepts', (tester) async {
    await pumpRepair(tester);

    await tester.enterText(field('主机'), 'not a host!');
    await tester.enterText(field('端口'), '1080');
    await tester.tap(find.text('保存并重试'));
    await tester.pump();
    expect(find.text('请输入有效的代理主机和端口'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.tap(find.text('SOCKS5'));
    await tester.enterText(field('主机'), '127.0.0.1');
    await tester.enterText(field('用户名（可选）'), 'fixture-user');
    await tester.enterText(field('密码（可选）'), 'fixture-pass');
    await tester.tap(find.text('保存并重试'));
    await tester.pump();
    expect(saved, [
      ForumProxy(
        type: ForumProxyType.socks5,
        host: '127.0.0.1',
        port: 1080,
        username: 'fixture-user',
        password: 'fixture-pass',
      ),
    ]);
    expect(find.text('请输入有效的代理主机和端口'), findsNothing);
  });

  testWidgets('disabling the proxy needs an explicit confirmation',
      (tester) async {
    await pumpRepair(tester);
    final disable = find.widgetWithText(OutlinedButton, '停用代理，改为直接连接');

    await tester.ensureVisible(disable);
    await tester.tap(disable);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(disabled, 0);

    await tester.tap(disable);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '停用代理，改为直接连接'));
    await tester.pumpAndSettle();
    expect(disabled, 1);
    expect(saved, isEmpty);
  });

  testWidgets('failed save or disable stays usable and leaks nothing',
      (tester) async {
    await pumpRepair(tester, fail: true);
    await tester.enterText(field('主机'), '127.0.0.1');
    await tester.enterText(field('端口'), '8080');
    await tester.tap(find.text('保存并重试'));
    await tester.pumpAndSettle();
    expect(find.text('保存代理失败，请稍后重试'), findsOneWidget);

    final disable = find.widgetWithText(OutlinedButton, '停用代理，改为直接连接');
    await tester.ensureVisible(disable);
    await tester.tap(disable);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '停用代理，改为直接连接'));
    await tester.pumpAndSettle();
    expect(find.text('停用代理失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('proxy-secret-token'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('保存并重试'), findsOneWidget, reason: 'button usable again');
  });

  testWidgets('HTTP proxies warn that credentials are sent in clear text',
      (tester) async {
    await pumpRepair(tester);
    expect(find.textContaining('明文'), findsOneWidget);
    await tester.tap(find.text('HTTPS'));
    await tester.pump();
    expect(find.textContaining('明文'), findsNothing);
  });
}
