import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  final writes = <String>[];
  var rejectReads = false;
  var rejectWrites = false;
  var throwWrites = false;
  Completer<bool>? heldWrite;
  Completer<void>? writeStarted;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    writes.clear();
    rejectReads = false;
    rejectWrites = false;
    throwWrites = false;
    heldWrite = null;
    writeStarted = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (rejectReads) throw PlatformException(code: 'fixture-read-failure');
        return Map<String, Object>.of(persisted);
      }
      final args = call.arguments as Map;
      final key = args['key'] as String;
      writes.add(key);
      final held = heldWrite;
      if (held != null) {
        heldWrite = null;
        writeStarted!.complete();
        if (!await held.future) return false;
      }
      if (rejectWrites) {
        if (throwWrites) throw PlatformException(code: 'fixture-write-failure');
        return false;
      }
      persisted[key] = args['value'] as Object;
      return true;
    });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('defaults preserve each existing loading behavior without writing',
      () async {
    final modes = await LoadingPreferences.load();
    expect(LoadingPreferences.isReady, isTrue);
    expect(modes, {
      LoadingDomain.thread: LoadingMode.manual,
      LoadingDomain.board: LoadingMode.continuous,
      LoadingDomain.search: LoadingMode.manual,
      LoadingDomain.favorites: LoadingMode.manual,
      LoadingDomain.userContent: LoadingMode.continuous,
      LoadingDomain.pm: LoadingMode.manual,
      LoadingDomain.friends: LoadingMode.manual,
      LoadingDomain.avatars: LoadingMode.manual,
    });
    expect(() => modes[LoadingDomain.thread] = LoadingMode.continuous,
        throwsUnsupportedError);
    expect(writes, isEmpty);
  });

  test('thread shares its original boolean key in both directions', () async {
    persisted['flutter.settings.autoLoadNextPage'] = true;
    await LoadingPreferences.load();
    expect(LoadingPreferences.modeFor(LoadingDomain.thread),
        LoadingMode.continuous);
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.manual);
    expect(persisted['flutter.settings.autoLoadNextPage'], false);
    expect(persisted.containsKey('flutter.settings.loading.thread'), isFalse);
    await LoadingPreferences.save(LoadingDomain.thread, LoadingMode.continuous);
    expect(persisted['flutter.settings.autoLoadNextPage'], true);
    expect(writes, everyElement('flutter.settings.autoLoadNextPage'));
  });

  test(
      'domain choices restore independently and invalid values remain untouched',
      () async {
    persisted.addAll({
      'flutter.settings.loading.board': 'manual',
      'flutter.settings.loading.avatars': 'continuous',
      'flutter.settings.loading.userContent': 'unknown-future-mode',
      'flutter.settings.loading.pm': 42,
      'flutter.unrelated.preference': 'keep',
    });
    await LoadingPreferences.load();
    expect(LoadingPreferences.modeFor(LoadingDomain.board), LoadingMode.manual);
    expect(LoadingPreferences.modeFor(LoadingDomain.avatars),
        LoadingMode.continuous);
    expect(LoadingPreferences.modeFor(LoadingDomain.userContent),
        LoadingMode.continuous);
    expect(LoadingPreferences.modeFor(LoadingDomain.pm), LoadingMode.manual);
    expect(writes, isEmpty);
    expect(persisted['flutter.settings.loading.userContent'],
        'unknown-future-mode');
    await LoadingPreferences.save(LoadingDomain.pm, LoadingMode.continuous);
    expect(writes, ['flutter.settings.loading.pm']);
    expect(persisted['flutter.settings.loading.userContent'],
        'unknown-future-mode');
    expect(persisted['flutter.unrelated.preference'], 'keep');
    SharedPreferences.resetStatic();
    await LoadingPreferences.load();
    expect(
        LoadingPreferences.modeFor(LoadingDomain.pm), LoadingMode.continuous);
    expect(LoadingPreferences.modeFor(LoadingDomain.board), LoadingMode.manual);
  });

  test('failed reads disable all automatic loading and lock writes until retry',
      () async {
    await LoadingPreferences.load();
    expect(LoadingPreferences.modeFor(LoadingDomain.board),
        LoadingMode.continuous);
    SharedPreferences.resetStatic();
    rejectReads = true;
    await expectLater(
        LoadingPreferences.load(), throwsA(isA<PlatformException>()));
    expect(LoadingPreferences.isReady, isFalse);
    for (final domain in LoadingDomain.values) {
      expect(LoadingPreferences.modeFor(domain), LoadingMode.manual);
    }
    rejectReads = false;
    persisted['flutter.settings.loading.board'] = 'manual';
    await expectLater(
      LoadingPreferences.save(LoadingDomain.board, LoadingMode.continuous),
      throwsStateError,
    );
    expect(writes, isEmpty);
    expect(persisted['flutter.settings.loading.board'], 'manual');
    await LoadingPreferences.load();
    expect(LoadingPreferences.isReady, isTrue);
    await LoadingPreferences.save(LoadingDomain.board, LoadingMode.continuous);
    expect(persisted['flutter.settings.loading.board'], 'continuous');
  });

  for (final throws in [false, true]) {
    test(
        'unacknowledged ${throws ? 'throwing' : 'false'} writes cannot pollute '
        'notifications or later saves', () async {
      await LoadingPreferences.load();
      final before = LoadingPreferences.notifier.value;
      rejectWrites = true;
      throwWrites = throws;
      await expectLater(
        LoadingPreferences.save(LoadingDomain.board, LoadingMode.manual),
        throwsA(anything),
      );
      expect(LoadingPreferences.notifier.value, same(before));
      expect(LoadingPreferences.modeFor(LoadingDomain.board),
          LoadingMode.continuous);
      rejectWrites = false;
      await LoadingPreferences.save(LoadingDomain.pm, LoadingMode.continuous);
      expect(persisted.containsKey('flutter.settings.loading.board'), isFalse);
      expect(persisted['flutter.settings.loading.pm'], 'continuous');
      await LoadingPreferences.load();
      expect(LoadingPreferences.modeFor(LoadingDomain.board),
          LoadingMode.continuous);
    });
  }

  test('overlapping domain saves publish only acknowledged ordered choices',
      () async {
    await LoadingPreferences.load();
    final gate = heldWrite = Completer<bool>();
    writeStarted = Completer<void>();
    final board =
        LoadingPreferences.save(LoadingDomain.board, LoadingMode.manual);
    final pm =
        LoadingPreferences.save(LoadingDomain.pm, LoadingMode.continuous);
    await writeStarted!.future;
    expect(writes, ['flutter.settings.loading.board']);
    expect(LoadingPreferences.modeFor(LoadingDomain.board),
        LoadingMode.continuous);
    expect(LoadingPreferences.modeFor(LoadingDomain.pm), LoadingMode.manual);
    gate.complete(true);
    await Future.wait([board, pm]);
    expect(writes,
        ['flutter.settings.loading.board', 'flutter.settings.loading.pm']);
    expect(LoadingPreferences.modeFor(LoadingDomain.board), LoadingMode.manual);
    expect(
        LoadingPreferences.modeFor(LoadingDomain.pm), LoadingMode.continuous);
    await LoadingPreferences.load();
    expect(LoadingPreferences.modeFor(LoadingDomain.board), LoadingMode.manual);
    expect(
        LoadingPreferences.modeFor(LoadingDomain.pm), LoadingMode.continuous);
  });
}
