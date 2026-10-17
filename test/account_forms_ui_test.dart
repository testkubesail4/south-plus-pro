import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/native_form_fields.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_tasks_screen.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

// Synthetic fixtures only.
ForumAccountForm _form({String nick = 'old', List<String> block = const []}) =>
    ForumAccountForm(kind: ForumAccountFormKind.preferences, fields: [
      ForumAccountField(
          name: 'field_1',
          label: '昵称',
          type: 'text',
          values: [nick],
          maxLength: 10),
      ForumAccountField(
        name: 'msggroups[]',
        label: '组',
        type: 'checkbox',
        values: block,
        options: const [
          ForumAccountOption(value: '1', label: '甲'),
          ForumAccountOption(value: '2', label: '乙'),
        ],
      ),
    ]);

Future<void> _pump(
  WidgetTester tester, {
  required ForumAccountForm Function() load,
  required Future<void> Function(Map<String, List<String>>) save,
  ValueNotifier<int>? epoch,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: NativeFormPage(
      title: '测试',
      sessionEpoch: epoch ?? ValueNotifier<int>(0),
      load: () async => load(),
      save: (form, changes, _) => save(changes),
      builder: (context, c) => [
        NativeFieldRow(controller: c, name: 'field_1'),
        NativeFieldRow(controller: c, name: 'msggroups[]', emptyValue: '未屏蔽'),
      ],
    ),
  ));
  await tester.pumpAndSettle();
}

TextButton _save(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, '保存'));

void main() {
  testWidgets('Save needs a change and sends only the touched fields',
      (tester) async {
    var nick = 'old';
    Map<String, List<String>>? sent;
    await _pump(tester,
        load: () => _form(nick: nick),
        save: (changes) async {
          sent = changes;
          nick = changes['field_1']!.single;
        });
    expect(_save(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    expect(_save(tester).onPressed, isNotNull);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(sent, {
      'field_1': ['new']
    });
    expect(find.text('已保存'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('a result the forum does not hold keeps the edit and warns',
      (tester) async {
    await _pump(tester, load: () => _form(), save: (_) async {});
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('提交后未能确认修改生效，请刷新核对'), findsOneWidget);
    expect(find.text('已保存'), findsNothing);
    expect(_save(tester).onPressed, isNotNull);
  });

  testWidgets('a rejected save shows the forum message and keeps the edit',
      (tester) async {
    await _pump(
      tester,
      load: () => _form(),
      save: (_) async =>
          throw ForumAccountValidationException('field_1', '昵称已被使用'),
    );
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('昵称已被使用'), findsWidgets);
    expect(_save(tester).onPressed, isNotNull);
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    await _pump(tester, load: () => _form(), save: (_) async {});
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(NativeFormPage), findsOneWidget);
  });

  testWidgets('a multi-choice row summarises the chosen options',
      (tester) async {
    await _pump(tester, load: () => _form(block: ['2']), save: (_) async {});
    expect(find.textContaining('乙'), findsOneWidget);
  });

  testWidgets('a session change wipes the old form before the next loads',
      (tester) async {
    final epoch = ValueNotifier<int>(0);
    final next = Completer<ForumAccountForm>();
    var calls = 0;
    // The second read stays pending.
    await tester.pumpWidget(MaterialApp(
      home: NativeFormPage(
        title: '测试',
        sessionEpoch: epoch,
        load: () =>
            ++calls == 1 ? Future.value(_form(nick: 'secret')) : next.future,
        save: (_, __, ___) async {},
        builder: (context, c) =>
            [NativeFieldRow(controller: c, name: 'field_1')],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('secret'), findsOneWidget);
    epoch.value++;
    await tester.pump();
    expect(find.text('secret'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    next.complete(_form(nick: 'other'));
    await tester.pumpAndSettle();
    expect(find.text('other'), findsOneWidget);
  });

  testWidgets('an open choice sheet closes with the form on a session change',
      (tester) async {
    final epoch = ValueNotifier<int>(0);
    final next = Completer<ForumAccountForm>();
    final navigator = GlobalKey<NavigatorState>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: NativeFormPage(
        title: '测试',
        sessionEpoch: epoch,
        load: () =>
            ++calls == 1 ? Future.value(_form(block: ['2'])) : next.future,
        save: (_, __, ___) async {},
        builder: (context, c) =>
            [NativeFieldRow(controller: c, name: 'msggroups[]')],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组'));
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsOneWidget);
    // A page of some other flow lies above the sheet.
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('外部页面'))));
    await tester.pumpAndSettle();
    epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('外部页面'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    expect(find.text('甲'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a form retired before the sheet\'s first frame never shows it',
      (tester) async {
    final epoch = ValueNotifier<int>(0);
    final next = Completer<ForumAccountForm>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: NativeFormPage(
        title: '测试',
        sessionEpoch: epoch,
        load: () =>
            ++calls == 1 ? Future.value(_form(block: ['2'])) : next.future,
        save: (_, __, ___) async {},
        builder: (context, c) =>
            [NativeFieldRow(controller: c, name: 'msggroups[]')],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组'));
    epoch.value++;
    await tester.pumpAndSettle();
    expect(find.text('完成'), findsNothing);
    expect(find.text('甲'), findsNothing);
  });

  testWidgets('a failed readback offers a read-only refresh, then saving works',
      (tester) async {
    var loads = 0;
    var nick = 'old';
    final saves = <Map<String, List<String>>>[];
    await _pump(tester, load: () {
      if (++loads == 2) throw StateError('readback');
      return _form(nick: nick);
    }, save: (changes) async {
      saves.add(changes);
      nick = changes['field_1']!.single;
    });
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('已提交，但未能刷新核对。'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);
    // Read-only for the keyboard too.
    final node =
        tester.widget<EditableText>(find.byType(EditableText)).focusNode;
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isFalse);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('已保存'), findsOneWidget);
    expect(saves, hasLength(1));
    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saves, [
      {
        'field_1': ['a']
      },
      {
        'field_1': ['b']
      },
    ]);
  });

  testWidgets(
      'a save finishing after a session change leaves the new form alone',
      (tester) async {
    final epoch = ValueNotifier<int>(0);
    final gate = Completer<void>();
    await _pump(tester,
        epoch: epoch, load: () => _form(), save: (_) => gate.future);
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    epoch.value++;
    await tester.pumpAndSettle();
    gate.completeError(
        const ForumRequestException(ForumRequestKind.server, '旧错误'));
    await tester.pumpAndSettle();
    expect(find.text('旧错误'), findsNothing);
    expect(_save(tester).onPressed, isNull);
  });

  testWidgets('a system avatar and a picked file never travel together',
      (tester) async {
    final repo = _ProfileRepo();
    await tester.pumpWidget(MaterialApp(
      home: AccountProfileEditScreen(
          repository: repo, avatarPicker: () async => _png()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('a1.gif'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'facetype': ['3']
    });
    expect(repo.savedUpload, isNotNull);
  });

  testWidgets('leaving upload mode drops the picked file', (tester) async {
    final repo = _ProfileRepo();
    await tester.pumpWidget(MaterialApp(
      home: AccountProfileEditScreen(
          repository: repo, avatarPicker: () async => _png()),
    ));
    await tester.pumpAndSettle();
    // An unrelated edit keeps the form dirty so Save really dispatches.
    await tester.enterText(find.byType(TextField).first, 'new');
    await tester.pump();
    await tester.tap(find.text('上传图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('头像上传'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('头像链接').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'field_1': ['new']
    });
    expect(repo.savedUpload, isNull);
  });

  testWidgets('Save waits while a file is being chosen', (tester) async {
    final repo = _ProfileRepo();
    final gate = Completer<ForumAccountUpload?>();
    await tester.pumpWidget(MaterialApp(
      home: AccountProfileEditScreen(
          repository: repo, avatarPicker: () => gate.future),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'new');
    await tester.pump();
    await tester.tap(find.text('上传图片'));
    await tester.pump();
    expect(_save(tester).onPressed, isNull);
    // The form is not editable meanwhile: a newer choice cannot be overwritten.
    expect(
      tester
          .widgetList<IgnorePointer>(find.byType(IgnorePointer))
          .any((w) => w.ignoring),
      isTrue,
    );
    gate.complete(_png());
    await tester.pumpAndSettle();
    expect(_save(tester).onPressed, isNotNull);
  });

  test('avatar files are checked against the form and image types', () {
    final field = ForumAccountField(
        name: 'upload', label: '头像上传', type: 'file', values: const []);
    ForumAccountUpload up(String name, String mime, int size) =>
        ForumAccountUpload(
            bytes: Uint8List(size), fileName: name, mimeType: mime);
    expect(avatarUploadProblem(up('a.png', 'image/png', 10), field), isNull);
    expect(avatarUploadProblem(up('a.svg', 'image/svg+xml', 10), field),
        isNotNull);
    expect(avatarUploadProblem(up('a.png', 'image/png', 0), field), isNotNull);
    final limited = ForumAccountField(
        name: 'upload',
        label: '头像上传',
        type: 'file',
        values: const [],
        accept: '.jpg');
    expect(
        avatarUploadProblem(up('a.png', 'image/png', 10), limited), isNotNull);
    expect(avatarUploadProblem(up('a.JPG', 'image/jpeg', 10), limited), isNull);
  });

  testWidgets('a claimed task shows the threshold, never a countdown',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ForumTasksScreen(repository: _TaskRepo()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新任务'));
    await tester.pumpAndSettle();
    expect(find.text('已领取'), findsOneWidget);
    expect(find.text('上次领取未超过 158 小时'), findsOneWidget);
    expect(find.textContaining('剩余'), findsNothing);
  });

  testWidgets('a task the forum offers now is not overridden by memory',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ForumTasksScreen(repository: _TaskRepo(offered: true)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新任务'));
    await tester.pumpAndSettle();
    expect(find.text('已领取'), findsNothing);
    // FilledButton.icon builds a private subclass, so match by `is`.
    final apply = find.ancestor(
      of: find.text('申请任务'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );
    expect(apply, findsOneWidget);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
  });
}

ForumAccountForm _profileForm() =>
    ForumAccountForm(kind: ForumAccountFormKind.profile, fields: [
      ForumAccountField(
          name: 'field_1',
          label: '昵称',
          type: 'text',
          values: const ['old'],
          group: 'nickname'),
      ForumAccountField(
        name: 'facetype',
        label: '头像方式',
        type: 'radio',
        values: const ['2'],
        group: 'avatar',
        options: const [
          ForumAccountOption(value: '1', label: '系统头像'),
          ForumAccountOption(value: '2', label: '头像链接'),
          ForumAccountOption(value: '3', label: '头像上传'),
        ],
      ),
      ForumAccountField(
          name: 'proicon',
          label: '系统头像',
          type: 'system-avatar',
          values: const [''],
          group: 'avatar'),
      ForumAccountField(
          name: 'upload',
          label: '头像上传',
          type: 'file',
          values: const [],
          group: 'avatar'),
    ]);

class _ProfileRepo extends ForumRepository {
  Map<String, List<String>>? saved;
  ForumAccountUpload? savedUpload;

  @override
  Future<ForumAccountForm> fetchAccountProfileForm() async => _profileForm();

  @override
  Future<ForumAccountAvatarPage> fetchAccountSystemAvatars(
          {int page = 1}) async =>
      ForumAccountAvatarPage(page: 1, options: const [
        ForumAccountOption(value: 'a1.gif', label: 'a1.gif'),
      ]);

  @override
  Future<void> saveAccountProfileForm(
    ForumAccountForm form,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) async {
    saved = changes;
    savedUpload = avatar;
  }
}

ForumAccountUpload _png() => ForumAccountUpload(
    bytes: Uint8List.fromList([1, 2, 3]),
    fileName: 'a.png',
    mimeType: 'image/png');

class _TaskRepo extends ForumRepository {
  _TaskRepo({this.offered = false});

  /// The forum offers the task now, whatever the remembered state says.
  final bool offered;

  @override
  bool get isLoggedIn => true;

  @override
  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async =>
      ForumTaskSnapshot(updatedAt: DateTime.now(), tasks: const [
        ForumTaskState(
            name: '周常任务', availability: ForumTaskAvailability.completed),
      ]);

  @override
  Future<ForumTaskSnapshot> refreshForumTaskSnapshot() async =>
      (await loadCachedForumTaskSnapshot())!;

  @override
  Future<List<ForumTask>> fetchForumTasks(ForumTaskStatus status) async =>
      status == ForumTaskStatus.available
          ? [
              ForumTask(
                name: '周常任务',
                status: ForumTaskStatus.available,
                id: offered ? '15' : null,
                actionLabel: offered ? '申请任务' : null,
                cooldownThreshold: offered ? null : const Duration(hours: 158),
              ),
            ]
          : const [];
}
