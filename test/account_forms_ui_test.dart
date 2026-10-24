import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/common/grouped_list.dart';
import 'package:south_plus_rewrite/features/common/native_form_fields.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/features/profile/forum_tasks_screen.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/loading_preferences.dart';

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
  // The system avatar sheet reads 加载与分页 if not read yet.
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('an unknown save outcome locks the form and offers 刷新',
      (tester) async {
    var saves = 0;
    await _pump(tester,
        load: () => _form(),
        save: (_) async {
          saves++;
          throw const ForumRequestException(
              ForumRequestKind.server, '表单请求返回了非预期状态，请刷新确认结果');
        });
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('提交结果未确认，请刷新核对。'), findsOneWidget);
    expect(_save(tester).onPressed, isNull);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    // The forum still holds the old value: the edit stays, saving is open.
    expect(find.text('提交后未能确认修改生效，请刷新核对'), findsOneWidget);
    expect(_save(tester).onPressed, isNotNull);
    expect(saves, 1);
  });

  testWidgets('a choice row titles itself with the field label, not the option',
      (tester) async {
    final form =
        ForumAccountForm(kind: ForumAccountFormKind.preferences, fields: [
      ForumAccountField(
        name: 'q',
        label: '好友',
        type: 'radio',
        values: const ['1'],
        options: const [
          ForumAccountOption(value: '1', label: '直接添加'),
          ForumAccountOption(value: '2', label: '需要验证'),
        ],
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: NativeFormPage(
        title: '测试',
        sessionEpoch: ValueNotifier<int>(0),
        load: () async => form,
        save: (_, __, ___) async {},
        builder: (context, c) => [NativeFieldRow(controller: c, name: 'q')],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('好友'), findsOneWidget);
    expect(find.text('直接添加'), findsOneWidget);
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

  testWidgets('a system avatar draft stays, but only the chosen mode is saved',
      (tester) async {
    final repo = _ProfileRepo();
    await _pumpProfile(tester, repo);
    await _chooseMode(tester, '系统头像');
    await tester.tap(_row('系统头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('a1.gif'));
    await tester.pumpAndSettle();
    await _chooseMode(tester, '头像上传');
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'facetype': ['3'],
      'uploadurl[1]': ['150'],
    });
    expect(repo.savedUpload, isNotNull);
  });

  group('system avatars page by 加载与分页', () {
    Future<_ProfileRepo> open(WidgetTester tester, LoadingMode mode) async {
      await LoadingPreferences.load();
      await LoadingPreferences.save(LoadingDomain.avatars, mode);
      final repo = _ProfileRepo()..avatarPages = 3;
      await _pumpProfile(tester, repo);
      await _chooseMode(tester, '系统头像');
      await tester.tap(_row('系统头像'));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> toEnd(WidgetTester tester) async {
      await tester.drag(
          find
              .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable))
              .first,
          const Offset(0, -20000));
      await tester.pumpAndSettle();
    }

    testWidgets('手动翻页: 下一页 turns to page 2 alone, and only on a tap',
        (tester) async {
      final repo = await open(tester, LoadingMode.manual);
      await toEnd(tester);
      expect(repo.avatarReads, [1]);
      // Changing the mode reads nothing by itself.
      await LoadingPreferences.save(LoadingDomain.avatars, LoadingMode.manual);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(repo.avatarReads, [1, 2]);
      expect(find.text('第 2 页'), findsOneWidget);
      expect(find.byTooltip('p2-0.gif'), findsOneWidget);
      expect(find.byTooltip('p1-1.gif', skipOffstage: false), findsNothing);
      await tester.tap(find.byTooltip('p2-0.gif'));
      await tester.pumpAndSettle();
    });

    testWidgets('two native duplicate pages pause until explicit resume',
        (tester) async {
      final repo = await open(tester, LoadingMode.manual);
      repo
        ..avatarPages = 4
        ..duplicateAvatarPages = true;
      await LoadingPreferences.save(
          LoadingDomain.avatars, LoadingMode.continuous);
      await tester.pumpAndSettle();
      expect(repo.avatarReads, [1]);
      await toEnd(tester);
      expect(repo.avatarReads, [1, 2, 3]);
      final resume = find.text('继续加载第 4 页');
      await toEnd(tester);
      expect(repo.avatarReads, [1, 2, 3],
          reason: 'Two pages with no fresh picture stop automatic reads');
      expect(resume, findsOneWidget);
      await tester.ensureVisible(resume);
      await tester.pumpAndSettle();
      expect(resume.hitTestable(), findsOneWidget);
      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(repo.avatarReads, [1, 2, 3, 4]);
      final picture = find.byTooltip('p4-0.gif');
      expect(picture, findsOneWidget);
      expect(resume, findsNothing);
      await tester.ensureVisible(picture);
      await tester.pumpAndSettle();
      expect(picture.hitTestable(), findsOneWidget);
      await tester.tap(picture);
      await tester.pumpAndSettle();
    });

    testWidgets('自动接续 appends on a scroll, each picture once', (tester) async {
      final repo = await open(tester, LoadingMode.manual);
      await LoadingPreferences.save(
          LoadingDomain.avatars, LoadingMode.continuous);
      await tester.pumpAndSettle();
      expect(repo.avatarReads, [1]);
      expect(find.text('下一页'), findsNothing);

      await toEnd(tester);
      expect(repo.avatarReads, [1, 2]);
      expect(find.text('第 2 页', skipOffstage: false), findsOneWidget);
      expect(find.byTooltip('p1-0.gif', skipOffstage: false), findsOneWidget);
      await toEnd(tester);
      await toEnd(tester);
      expect(repo.avatarReads, [1, 2, 3]);
      expect(find.text('已到最后一页', skipOffstage: false), findsNothing);
      // Back to 手动翻页, the pages stay and it turns from page 3, the last.
      await LoadingPreferences.save(LoadingDomain.avatars, LoadingMode.manual);
      await tester.pumpAndSettle();
      expect(repo.avatarReads, [1, 2, 3]);
      TextButton turn(String label) =>
          tester.widget<TextButton>(find.widgetWithText(TextButton, label));
      expect(turn('下一页').onPressed, isNull);
      expect(turn('上一页').onPressed, isNotNull);
      // A picture of an appended page is chosen like any other.
      await tester.tap(find.byTooltip('p3-29.gif'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  testWidgets('leaving upload mode keeps the file as a draft, unsent',
      (tester) async {
    final repo = _ProfileRepo(mode: '3');
    await _pumpProfile(tester, repo);
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('a.png'), findsOneWidget);
    await _chooseMode(tester, '头像链接');
    expect(find.textContaining('a.png'), findsNothing);
    await _chooseMode(tester, '头像上传');
    expect(find.textContaining('a.png'), findsOneWidget);
    await _chooseMode(tester, '头像链接');
    // An unrelated edit keeps Save open; the file must not travel with it.
    await tester.enterText(find.byType(TextField).last, 'new');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'facetype': ['2'],
      'httpurl[1]': ['150'],
      'field_1': ['new'],
    });
    expect(repo.savedUpload, isNull);
  });

  for (final kept in [true, false]) {
    testWidgets(
        'a file of the mode not chosen survives a save whose readback '
        '${kept ? 'confirms' : 'does not confirm'}', (tester) async {
      final repo = _ProfileRepo(mode: '3', forumKeepsSaves: kept);
      await _pumpProfile(tester, repo);
      await tester.tap(find.text('选择图片'));
      await tester.pumpAndSettle();
      await _chooseMode(tester, '头像链接');
      await tester.enterText(find.byType(TextField).last, 'new');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.savedUpload, isNull);
      expect(find.text('已保存'), kept ? findsOneWidget : findsNothing);
      await _chooseMode(tester, '头像上传');
      expect(find.textContaining('a.png'), findsOneWidget,
          reason: 'the dormant file is still a draft');
    });
  }

  testWidgets('only the chosen avatar mode shows its own fields',
      (tester) async {
    await _pumpProfile(tester, _ProfileRepo());
    ValueKey<String> key(String n) => ValueKey(n);
    expect(find.byKey(key('httpurl[0]')), findsOneWidget);
    expect(find.byKey(key('httpurl[1]')), findsOneWidget);
    expect(find.byKey(key('uploadurl[1]')), findsNothing);
    expect(find.text('选择图片'), findsNothing);
    expect(find.text('预览链接中的图片'), findsOneWidget);
    await _chooseMode(tester, '头像上传');
    expect(find.byKey(key('httpurl[0]')), findsNothing);
    expect(find.byKey(key('httpurl[1]')), findsNothing);
    expect(find.byKey(key('uploadurl[1]')), findsOneWidget);
    expect(find.text('选择图片'), findsOneWidget);
    await _chooseMode(tester, '系统头像');
    expect(find.byKey(key('uploadurl[1]')), findsNothing);
    expect(find.text('选择图片'), findsNothing);
    expect(_row('系统头像'), findsOneWidget);
  });

  testWidgets('a blank link width starts at the forum maximum, then saves',
      (tester) async {
    final repo = _ProfileRepo(mode: '1');
    await _pumpProfile(tester, repo);
    await _chooseMode(tester, '头像链接');
    expect(find.text('宽度 150'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('httpurl[0]')),
            matching: find.byType(TextField)),
        'https://img.example/a.png');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'facetype': ['2'],
      'httpurl[0]': ['https://img.example/a.png'],
      'httpurl[1]': ['150'],
    });
  });

  testWidgets('a width the forum already holds is never replaced',
      (tester) async {
    final repo = _ProfileRepo(mode: '1', linkWidth: '80');
    await _pumpProfile(tester, repo);
    await _chooseMode(tester, '头像链接');
    expect(find.text('宽度 80'), findsOneWidget);
    expect(find.text('宽度 150'), findsNothing);
  });

  testWidgets('the size fields name what they are and ask for a width',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpProfile(tester, _ProfileRepo());
    expect(find.bySemanticsLabel(RegExp('显示宽度')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('显示高度')), findsWidgets);
    expect(find.textContaining('必填'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'a link saves once its width and height are valid, '
      'after an invalid try and a cleared height', (tester) async {
    final repo = _FixtureSizeRepo(mode: '1');
    await _pumpProfile(tester, repo);
    await _chooseMode(tester, '头像链接');
    Finder field(String name) => find.descendant(
        of: find.byKey(ValueKey(name)), matching: find.byType(TextField));
    await tester.enterText(field('httpurl[0]'), 'http://127.0.0.1:8765/a.png');
    await tester.pump();
    await tester.tap(find.text('显示尺寸'));
    await tester.pumpAndSettle();

    await tester.enterText(field('httpurl[1]'), '151');
    await tester.pump();
    expect(find.textContaining('不能大于 150'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请先修正标出的项目'), findsOneWidget);
    expect(repo.saved, isNull, reason: 'an invalid width sends nothing');

    await tester.enterText(field('httpurl[1]'), '150');
    await tester.enterText(field('httpurl[2]'), '271');
    await tester.pump();
    expect(find.textContaining('不能大于 270'), findsOneWidget);
    await tester.enterText(field('httpurl[2]'), '');
    await tester.pump();
    expect(find.textContaining('不能大于'), findsNothing);
    for (final name in ['httpurl[0]', 'httpurl[1]', 'httpurl[2]']) {
      expect(
          tester.widget<TextField>(field(name)).decoration?.errorText, isNull,
          reason: '$name shows no error');
    }
    expect(_save(tester).onPressed, isNotNull);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
        repo.saved,
        {
          'facetype': ['2'],
          'httpurl[0]': ['http://127.0.0.1:8765/a.png'],
          'httpurl[1]': ['150'],
        },
        reason: 'a blank optional height is simply not sent');
  });

  testWidgets('typing into a blank forced-open width keeps the field in place',
      (tester) async {
    await _pumpProfile(tester, _FixtureSizeRepo(mode: '2'));
    final width = find.descendant(
        of: find.byKey(const ValueKey('httpurl[1]')),
        matching: find.byType(TextField));
    expect(width, findsOneWidget, reason: 'a blank width is shown at once');
    await tester.enterText(width, '1');
    await tester.pump();
    expect(width, findsOneWidget, reason: 'it does not fold away mid-typing');
  });

  testWidgets('clearing a height the forum holds is a valid change',
      (tester) async {
    final repo = _FixtureSizeRepo(mode: '2', linkWidth: '100', height: '200');
    await _pumpProfile(tester, repo);
    await tester.tap(find.text('显示尺寸'));
    await tester.pumpAndSettle();
    final height = find.descendant(
        of: find.byKey(const ValueKey('httpurl[2]')),
        matching: find.byType(TextField));
    await tester.enterText(height, '');
    await tester.pump();
    expect(tester.widget<TextField>(height).decoration?.errorText, isNull);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'httpurl[2]': ['']
    });
  });

  testWidgets('Save waits while a file is being chosen', (tester) async {
    final repo = _ProfileRepo(mode: '3');
    final gate = Completer<ForumAccountUpload?>();
    var asked = 0;
    await _pumpProfile(tester, repo, picker: () {
      asked++;
      return gate.future;
    });
    await tester.enterText(find.byType(TextField).last, 'new');
    await tester.pumpAndSettle();
    // Typing may have scrolled the button away; bring it back before tapping.
    await tester.ensureVisible(find.text('选择图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择图片'));
    await tester.pump();
    expect(asked, 1, reason: 'the picker was really started');
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

  test('avatar row and accept hint read in plain words', () {
    expect(systemAvatarValue(null, 'none.gif'), '未选择');
    expect(systemAvatarValue(null, ''), '未选择');
    expect(systemAvatarValue(null, 'a/None.GIF'), '未选择');
    expect(systemAvatarValue(null, '12.gif'), '已选择');
    final f = ForumAccountField(
        name: 'proicon',
        label: '系统头像',
        type: 'hidden',
        values: const ['12.gif'],
        options: const [ForumAccountOption(value: '12.gif', label: '小猫')]);
    expect(systemAvatarValue(f, '12.gif'), '小猫');
    expect(acceptLabel('image/png'), 'PNG');
    expect(acceptLabel('.JPG'), 'JPG');
    expect(acceptLabel('image/*'), '图片');
    expect(acceptLabel('application/x-foo'), 'application/x-foo');
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

ForumAccountField _dimension(String name, String label, int max,
        [String value = '']) =>
    ForumAccountField(
        name: name,
        label: label,
        type: 'number',
        values: [value],
        min: 1,
        max: max,
        group: 'avatar');

/// The form as the forum holds it once [applied] was saved.
ForumAccountForm _profileForm(
    String mode, String linkWidth, Map<String, List<String>> applied) {
  final base = _baseProfileForm(mode, linkWidth);
  return ForumAccountForm(kind: base.kind, fields: [
    for (final f in base.fields)
      applied.containsKey(f.name)
          ? ForumAccountField(
              name: f.name,
              label: f.label,
              type: f.type,
              values: applied[f.name]!,
              options: f.options,
              min: f.min,
              max: f.max,
              group: f.group)
          : f,
  ]);
}

ForumAccountForm _baseProfileForm(String mode, String linkWidth) =>
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
        values: [mode],
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
          name: 'httpurl[0]',
          label: '头像链接',
          type: 'text',
          values: const [''],
          group: 'avatar'),
      _dimension('httpurl[1]', '头像宽度', 150, linkWidth),
      _dimension('httpurl[2]', '头像高度', 270),
      ForumAccountField(
          name: 'upload',
          label: '头像上传',
          type: 'file',
          values: const [],
          group: 'avatar'),
      _dimension('uploadurl[1]', '头像宽度', 150),
      _dimension('uploadurl[2]', '头像高度', 270),
    ]);

/// The row titled [title], not a row that merely shows it as a value.
Finder _row(String title) => find.byWidgetPredicate(
    (w) => w is AppRow && w.title is Text && (w.title as Text).data == title);

Future<void> _pumpProfile(
  WidgetTester tester,
  _ProfileRepo repo, {
  AvatarPicker? picker,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: AccountProfileEditScreen(
      repository: repo,
      avatarPicker: picker ?? () async => _png(),
      // These bytes are no picture, so the file passes through uncropped.
      avatarCropper: (context, source, form) async => source,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _chooseMode(WidgetTester tester, String label) async {
  await tester.tap(find.text('头像方式'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

class _ProfileRepo extends ForumRepository {
  _ProfileRepo(
      {this.mode = '2', this.linkWidth = '', this.forumKeepsSaves = false});

  final String mode;
  final String linkWidth;

  /// Whether a later read shows what was saved.
  final bool forumKeepsSaves;
  final _held = <String, List<String>>{};
  Map<String, List<String>>? saved;
  ForumAccountUpload? savedUpload;

  @override
  Future<ForumAccountForm> fetchAccountProfileForm() async =>
      _profileForm(mode, linkWidth, _held);

  /// System avatar pages: one picture, or this many pages of 30 where
  /// each page after the first repeats the first picture of the one before.
  int avatarPages = 1;
  bool duplicateAvatarPages = false;
  final avatarReads = <int>[];

  @override
  Future<ForumAccountAvatarPage> fetchAccountSystemAvatars(
      {int page = 1}) async {
    avatarReads.add(page);
    if (avatarPages == 1) {
      return ForumAccountAvatarPage(page: 1, options: const [
        ForumAccountOption(value: 'a1.gif', label: 'a1.gif'),
      ]);
    }
    final picturePage =
        duplicateAvatarPages && (page == 2 || page == 3) ? 1 : page;
    return ForumAccountAvatarPage(
      page: page,
      nextPage: page < avatarPages ? page + 1 : null,
      previousPage: page > 1 ? page - 1 : null,
      options: [
        if (page > 1 && !duplicateAvatarPages)
          ForumAccountOption(
              value: 'p${page - 1}-0.gif', label: 'p${page - 1}-0.gif'),
        for (var i = 0; i < 30; i++)
          ForumAccountOption(
              value: 'p$picturePage-$i.gif', label: 'p$picturePage-$i.gif'),
      ],
    );
  }

  @override
  Future<void> saveAccountProfileForm(
    ForumAccountForm form,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) async {
    saved = changes;
    savedUpload = avatar;
    if (forumKeepsSaves) _held.addAll(changes);
  }
}

/// The size fields as the forum page describes them: plain text boxes of at
/// most three characters with a range in the words next to them.
class _FixtureSizeRepo extends _ProfileRepo {
  _FixtureSizeRepo({super.mode, super.linkWidth, this.height = ''});

  final String height;

  @override
  Future<ForumAccountForm> fetchAccountProfileForm() async {
    final form = await super.fetchAccountProfileForm();
    return ForumAccountForm(kind: form.kind, fields: [
      for (final f in form.fields)
        f.name == 'httpurl[1]' || f.name == 'httpurl[2]'
            ? ForumAccountField(
                name: f.name,
                label: f.label,
                type: 'text',
                values: f.name == 'httpurl[2]' && height.isNotEmpty
                    ? [height]
                    : f.values,
                min: f.min,
                max: f.max,
                maxLength: 3,
                group: f.group)
            : f,
    ]);
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
