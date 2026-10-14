import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/app.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_network_setup_store.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

// Reuse the app's repository injection; local HTTP stays out of production config.
class _FixtureSite extends ForumSite {
  const _FixtureSite() : super('127.0.0.1');

  @override
  Uri get baseUri => Uri.parse('http://127.0.0.1:8765/');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux launches, loads home, opens a thread and captures it',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ForumNetworkSetupStore.completedKey: true,
    });
    final repository = ForumRepository(
      config: const ForumNetworkConfig(
        site: _FixtureSite(),
        dohEnabled: false,
        dohProvider: ForumNetworkConfig.defaultProvider,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: SessionGate(repository: repository),
    ));

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    await waitFor(find.text('Fixture thread'));
    await tester.tap(find.text('Fixture thread').first);
    await waitFor(find.textContaining('Fixture post body', findRichText: true));
    expect(find.text('Fixture author'), findsWidgets);
    await tester.pumpAndSettle();
    // Linux integration_test has no native screenshot implementation.
    final screenshot = await Process.run('import', [
      '-window',
      'root',
      '/output/thread-smoke.png',
    ]);
    expect(screenshot.exitCode, 0, reason: '${screenshot.stderr}');
    expect(File('/output/thread-smoke.png').lengthSync(), greaterThan(1000));
  });
}
