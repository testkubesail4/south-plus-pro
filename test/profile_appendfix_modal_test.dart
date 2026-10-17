import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';

// The shared-preferences channel is the real storage boundary, so a note
// write can be held while the session scope changes under the open sheet.
const _customConfig = ForumNetworkConfig(
  site: ForumSite('first.invalid'),
  dohEnabled: false,
  dohProvider: ForumNetworkConfig.defaultProvider,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  Completer<bool>? heldWrite;
  Completer<void>? writeStarted;
  late ForumRepository repository;
  late GlobalKey<NavigatorState> navigator;
  bool? editorResult;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    heldWrite = null;
    writeStarted = null;
    editorResult = null;
    navigator = GlobalKey<NavigatorState>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      if (heldWrite case final held?) {
        heldWrite = null;
        writeStarted?.complete();
        if (!await held.future) return false;
      }
      // Same shapes as the plugin: set* carry a value, remove carries only a
      // key, clear carries neither.
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'remove':
          persisted.remove(args['key'] as String);
        case 'clear':
          persisted.clear();
        default:
          persisted[args['key'] as String] = args['value'] as Object;
      }
      return true;
    });
    // The client starts its resolver load at construction: the channel must
    // already answer.
    repository = ForumRepository(client: ForumClient());
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => editorResult = await showUserNoteEditor(
              context,
              repository: repository,
              uid: '1',
              name: 'Alice',
              note: 'old note',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
  }

  testWidgets('a save closes only its own sheet and reports success',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new note');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('用户备注'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(editorResult, isTrue);
    expect((await UserNoteStore.load())['1'], 'new note');
  });

  testWidgets('a scope change before the first frame never shows the old note',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('open'));
    // The sheet builder has not run yet.
    await repository.updateNetworkConfig(_customConfig);
    await tester.pumpAndSettle();

    expect(find.text('用户备注'), findsNothing);
    expect(find.text('old note'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(editorResult, isFalse);
    expect(persisted.keys.where((key) => key.contains('user_notes')), isEmpty,
        reason: 'no note was written to any scope');
  });

  testWidgets(
      'a write finishing in the revoke-to-disposal window closes no other route',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new note');

    final held = heldWrite = Completer<bool>();
    writeStarted = Completer<void>();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await writeStarted!.future;

    // A foreign route sits above the still-open sheet.
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('foreign page')),
    ));
    // The write is still held: bounded pumps, no settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('foreign page'), findsOneWidget);

    // Revoke removes the sheet route; its State is disposed only at the
    // next frame. Release the write before any frame is pumped.
    await repository.updateNetworkConfig(_customConfig);
    await tester.runAsync(() async {
      held.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('foreign page'), findsOneWidget,
        reason: 'the finished write must not pop the current foreign route');
    expect(find.text('用户备注'), findsNothing);
    expect(find.text('old note'), findsNothing);
  });
}
