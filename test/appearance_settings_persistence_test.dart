import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_text_size_settings.dart';
import 'package:south_plus_rewrite/services/image_loading_settings.dart';
import 'package:south_plus_rewrite/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const preferences = MethodChannel('plugins.flutter.io/shared_preferences');
  const network = MethodChannel('south_plus_rewrite/network_state');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  var rejectWrites = false;
  var throwWrites = false;
  var wifi = true;
  var networkReads = 0;
  Completer<bool>? acknowledgement;
  Completer<void>? writeStarted;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    rejectWrites = false;
    throwWrites = false;
    wifi = true;
    networkReads = 0;
    acknowledgement = null;
    writeStarted = null;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final held = acknowledgement;
      if (held != null) {
        acknowledgement = null;
        writeStarted!.complete();
        if (!await held.future) return false;
      }
      if (throwWrites) throw PlatformException(code: 'fixture-write-failed');
      if (rejectWrites) return false;
      final args = call.arguments as Map;
      persisted[args['key'] as String] = args['value'] as Object;
      return true;
    });
    messenger.setMockMethodCallHandler(network, (_) async {
      networkReads++;
      return wifi;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(preferences, null);
    messenger.setMockMethodCallHandler(network, null);
  });

  Future<void> seed(String setting) => switch (setting) {
        'theme' => AppThemeController.setMode(ThemeMode.light),
        'text' => ForumTextSizeSettings.save(ForumTextSize.normal),
        _ => ImageLoadingSettings.saveMode(ImageLoadMode.wifiOnly),
      };
  Future<void> change(String setting) => switch (setting) {
        'theme' => AppThemeController.setMode(ThemeMode.dark),
        'text' => ForumTextSizeSettings.save(ForumTextSize.large),
        _ => ImageLoadingSettings.saveMode(ImageLoadMode.noImages),
      };
  String current(String setting) => switch (setting) {
        'theme' => AppThemeController.themeMode.name,
        'text' => ForumTextSizeSettings.notifier.value.name,
        _ => ImageLoadingSettings.notifier.value!.name,
      };
  Future<void> reload(String setting) async {
    switch (setting) {
      case 'theme':
        await AppThemeController.load();
      case 'text':
        await ForumTextSizeSettings.load();
      default:
        await ImageLoadingSettings.loadMode();
    }
  }

  for (final (setting, key, before, after) in [
    ('theme', 'app.themeMode', 'light', 'dark'),
    ('text', 'settings.forumTextSize', 'normal', 'large'),
    ('image', 'settings.imageLoadMode', 'wifiOnly', 'noImages'),
  ]) {
    for (final throws in [false, true]) {
      test('$setting rejected ${throws ? 'throw' : 'false'} keeps saved state',
          () async {
        await seed(setting);
        if (setting == 'image') {
          expect(await ImageLoadingSettings.canAutoLoadImages(), isTrue);
          expect(networkReads, 1);
          wifi = false;
        }
        rejectWrites = true;
        throwWrites = throws;
        await expectLater(change(setting),
            throwsA(throws ? isA<PlatformException>() : isA<StateError>()));
        expect(current(setting), before);
        expect(persisted['flutter.$key'], before);
        expect((await SharedPreferences.getInstance()).getString(key), before);
        await reload(setting);
        expect(current(setting), before);
        if (setting == 'image') {
          expect(await ImageLoadingSettings.canAutoLoadImages(), isTrue);
          expect(networkReads, 1,
              reason: 'failed saves keep the previous cache');
        }
        rejectWrites = false;
        throwWrites = false;
        await change(setting);
        expect(current(setting), after);
        expect(persisted['flutter.$key'], after);
        if (setting == 'image') {
          expect(await ImageLoadingSettings.canAutoLoadImages(), isFalse);
        }
        SharedPreferences.resetStatic();
        await reload(setting);
        expect(current(setting), after);
        expect((await SharedPreferences.getInstance()).getString(key), after);
      });
    }

    test('$setting applies only after the platform acknowledges the write',
        () async {
      await seed(setting);
      final ack = acknowledgement = Completer<bool>();
      writeStarted = Completer<void>();
      final saving = change(setting);
      await writeStarted!.future;
      final pendingSelection = current(setting);
      final pendingStored = persisted['flutter.$key'];
      ack.complete(true);
      await saving;
      expect(pendingSelection, before);
      expect(pendingStored, before);
      expect(current(setting), after);
      expect(persisted['flutter.$key'], after);
    });

    test('$setting overlapping choices finish in the requested order',
        () async {
      await seed(setting);
      final ack = acknowledgement = Completer<bool>();
      writeStarted = Completer<void>();
      final first = change(setting);
      await writeStarted!.future;
      final second = seed(setting);
      await pumpEventQueue();
      ack.complete(true);
      await Future.wait([first, second]);
      expect(current(setting), before);
      expect(persisted['flutter.$key'], before);
      expect((await SharedPreferences.getInstance()).getString(key), before);
    });
  }
}
