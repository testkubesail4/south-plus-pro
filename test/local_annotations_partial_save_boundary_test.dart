import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/user_note.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/user_note_store.dart';
import 'package:south_plus_rewrite/services/user_tag_store.dart';

class _Repository extends ForumRepository {
  String scope = 'account-a';
  final epoch = ValueNotifier<int>(0);

  @override
  String? get localPreferenceAccount => scope;

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  void switchAccount() {
    scope = 'account-b';
    epoch.value++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final persisted = <String, Object>{};
  final attempts = <String>[];
  var rejectTags = false;
  late _Repository repository;
  bool? editorResult;

  setUp(() {
    SharedPreferences.resetStatic();
    persisted.clear();
    attempts.clear();
    rejectTags = false;
    editorResult = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return Map<String, Object>.of(persisted);
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String;
      attempts.add(key);
      if (rejectTags && key.endsWith('/user_tags_v1')) return false;
      if (call.method == 'remove') {
        persisted.remove(key);
      } else {
        persisted[key] = args['value'] as Object;
      }
      return true;
    });
    repository = _Repository();
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> seed() async {
    await UserNoteStore.save('42', 'old note', account: 'account-a');
    await UserNoteStore.save('43', 'other user', account: 'account-a');
    await UserTagStore.save('42', ['Old'], account: 'account-a');
    await UserNoteStore.save('42', 'account B note', account: 'account-b');
    await UserTagStore.save('42', ['Account B tag'], account: 'account-b');
    attempts.clear();
  }

  Future<void> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              editorResult = await showUserNoteEditor(
                context,
                repository: repository,
                uid: '42',
                name: 'Probe user',
                note: 'old note',
                tags: const ['Old'],
              );
            },
            child: const Text('open editor'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'new note');
    await tester.tap(find.widgetWithText(ActionChip, '+ 添加标签'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('user-tag-input')), ' New ');
    await tester.tap(find.byTooltip('添加标签'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'New'), findsOneWidget);
  }

  Future<void> reloadDurableState() async =>
      (await SharedPreferences.getInstance()).reload();

  testWidgets(
      'partial save keeps acknowledged note durable, reports unsaved tags and retries only tags',
      (tester) async {
    await seed();
    await openEditor(tester);
    final noteRevision = UserNoteStore.revision.value;
    final tagRevision = UserTagStore.revision.value;
    rejectTags = true;
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(editorResult, isNull);
    expect(find.text('备注与标签'), findsOneWidget);
    expect(find.text('备注已保存'), findsOneWidget);
    expect(find.text('备注已保存；标签未保存，请重试'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'unsaved later note');
    await tester.pump();
    expect(find.text('备注已保存'), findsNothing,
        reason: 'the new note draft is not the acknowledged note');
    expect(find.text('备注已保存；标签未保存，请重试'), findsNothing);
    expect(find.text('标签未保存，请重试'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'new note');
    await tester.pump();
    expect(find.text('备注已保存'), findsOneWidget,
        reason: 'returning to the acknowledged draft restores saved status');
    expect(find.widgetWithText(InputChip, 'New'), findsOneWidget,
        reason: 'failed tags stay in the editable draft');
    expect(find.widgetWithText(FilledButton, '重试保存'), findsOneWidget);
    expect(UserNoteStore.revision.value, noteRevision + 1);
    expect(UserTagStore.revision.value, tagRevision,
        reason: 'a rejected platform write is not a tag revision');
    await reloadDurableState();
    expect(await UserNoteStore.load(account: 'account-a'),
        {'42': 'new note', '43': 'other user'});
    expect(await UserTagStore.load(account: 'account-a'), {
      '42': ['Old']
    });
    final noteWrites =
        attempts.where((key) => key.endsWith('/user_notes_v1')).length;
    expect(noteWrites, 1);
    expect(
        attempts.where((key) => key.endsWith('/user_tags_v1')), hasLength(1));

    rejectTags = false;
    await tester.tap(find.widgetWithText(FilledButton, '重试保存'));
    await tester.pumpAndSettle();
    expect(editorResult, isTrue);
    expect(find.text('备注与标签'), findsNothing);
    expect(attempts.where((key) => key.endsWith('/user_notes_v1')),
        hasLength(noteWrites),
        reason: 'retry must not write the already acknowledged note again');
    expect(
        attempts.where((key) => key.endsWith('/user_tags_v1')), hasLength(2));
    expect(UserNoteStore.revision.value, noteRevision + 1);
    expect(UserTagStore.revision.value, tagRevision + 1);
    await reloadDurableState();
    expect(await UserTagStore.load(account: 'account-a'), {
      '42': ['Old', 'New']
    });
    expect(await UserNoteStore.load(account: 'account-a'),
        {'42': 'new note', '43': 'other user'});
    expect(await UserNoteStore.load(account: 'account-b'),
        {'42': 'account B note'});
    expect(await UserTagStore.load(account: 'account-b'), {
      '42': ['Account B tag']
    });
  });

  testWidgets(
      'scope switch after note acknowledgement never starts the tag stage or writes the new account',
      (tester) async {
    await seed();
    await openEditor(tester);
    final newAccountBefore = {
      for (final entry in persisted.entries)
        if (entry.key.contains('account/account-b/')) entry.key: entry.value,
    };
    expect(newAccountBefore, hasLength(2));
    final tagRevision = UserTagStore.revision.value;
    var switched = false;
    // The notifier is after the real platform acknowledgement, before the
    // editor's awaited note save can continue into its second storage stage.
    void switchAfterAcknowledgement() {
      switched = true;
      repository.switchAccount();
    }

    UserNoteStore.revision.addListener(switchAfterAcknowledgement);
    try {
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
    } finally {
      UserNoteStore.revision.removeListener(switchAfterAcknowledgement);
    }

    expect(switched, isTrue);
    expect(repository.scope, 'account-b');
    expect(editorResult, isFalse);
    expect(find.text('备注与标签'), findsNothing);
    expect(
        attempts.where((key) => key.endsWith('/user_notes_v1')), hasLength(1));
    expect(attempts.where((key) => key.endsWith('/user_tags_v1')), isEmpty,
        reason: 'no tag write may start after the between-stage revoke');
    expect(UserTagStore.revision.value, tagRevision);
    expect({
      for (final entry in persisted.entries)
        if (entry.key.contains('account/account-b/')) entry.key: entry.value,
    }, newAccountBefore);
    await reloadDurableState();
    expect(await UserNoteStore.load(account: 'account-a'),
        {'42': 'new note', '43': 'other user'});
    expect(await UserTagStore.load(account: 'account-a'), {
      '42': ['Old']
    });
    expect(await UserNoteStore.load(account: 'account-b'),
        {'42': 'account B note'});
    expect(await UserTagStore.load(account: 'account-b'), {
      '42': ['Account B tag']
    });
  });
}
