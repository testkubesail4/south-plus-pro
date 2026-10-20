import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';

// Its own file: failing writes need the platform channel, which an
// in-memory SharedPreferences mock elsewhere in the isolate would replace.
void main() {
  testWidgets('a failed repair stays retryable and leaks nothing',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final persisted = <String, Object>{
      'flutter.forum_network_config_v2': '{"version": 2',
      'flutter.forum_network_setup_completed_v1': true,
    };
    var failWrites = 1;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final args = call.arguments as Map;
      if (failWrites > 0) {
        failWrites--;
        throw PlatformException(
            code: 'fixture-write-failure', message: 'proxy-secret-token');
      }
      if (call.method == 'remove') {
        persisted.remove(args['key']);
      } else {
        persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      SharedPreferences.resetStatic();
    });
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SessionGate()));
    await tester.pumpAndSettle();
    expect(find.text('网络设置无法读取'), findsOneWidget);

    Future<void> submitProxy() async {
      await tester.enterText(find.widgetWithText(TextField, '主机'), '127.0.0.1');
      await tester.enterText(find.widgetWithText(TextField, '端口'), '8080');
      final submit = find.text('保存代理并重试');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
    }

    await submitProxy();
    expect(find.text('保存代理失败，请稍后重试'), findsOneWidget);
    expect(find.textContaining('proxy-secret-token'), findsNothing);
    expect(find.text('网络设置无法读取'), findsOneWidget);

    await submitProxy();
    expect(find.text('网络设置无法读取'), findsNothing);
    final saved =
        jsonDecode(persisted['flutter.forum_network_config_v2'] as String)
            as Map<String, dynamic>;
    expect(saved['mode'], 'proxy');
  });
}
