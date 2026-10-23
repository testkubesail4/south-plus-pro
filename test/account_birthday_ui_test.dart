import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/common/grouped_list.dart';
import 'package:south_plus_rewrite/features/profile/account_birthday_field.dart';
import 'package:south_plus_rewrite/features/profile/account_profile_edit_screen.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures shaped like the forum's 生日 cell: three selects whose
// first option is blank.
List<ForumAccountOption> _range(int from, int to) => [
      const ForumAccountOption(value: '', label: ''),
      for (var i = from; i <= to; i++)
        ForumAccountOption(value: '$i', label: '$i'),
    ];

ForumAccountField _select(
        String name, List<String> values, List<ForumAccountOption> options) =>
    ForumAccountField(
        name: name,
        label: '生日',
        type: 'select',
        values: values,
        options: options,
        group: 'basic');

class _Repo extends ForumRepository {
  _Repo({
    this.year = '',
    this.month = '',
    this.day = '',
    this.withDay = true,
    this.textDay = false,
  });

  String year;
  String month;
  String day;
  final bool withDay;
  final bool textDay;
  Map<String, List<String>>? saved;

  @override
  Future<ForumAccountForm> fetchAccountProfileForm() async =>
      ForumAccountForm(kind: ForumAccountFormKind.profile, fields: [
        ForumAccountField(
          name: 'progender',
          label: '性别',
          type: 'select',
          values: const ['0'],
          options: const [
            ForumAccountOption(value: '0', label: '保密'),
            ForumAccountOption(value: '1', label: '男'),
          ],
          group: 'basic',
        ),
        _select('proyear', [year], _range(1960, 2010)),
        _select('promonth', [month], _range(1, 12)),
        if (withDay)
          textDay
              ? ForumAccountField(
                  name: 'proday',
                  label: '生日',
                  type: 'text',
                  values: [day],
                  group: 'basic')
              : _select('proday', [day], _range(1, 31)),
        ForumAccountField(
            name: 'profrom',
            label: '来自',
            type: 'text',
            values: const [''],
            group: 'basic'),
      ]);

  @override
  Future<void> saveAccountProfileForm(
    ForumAccountForm form,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) async {
    saved = changes;
    // The forum keeps what was sent.
    year = changes['proyear']?.single ?? year;
    month = changes['promonth']?.single ?? month;
    day = changes['proday']?.single ?? day;
  }
}

Finder _row(String title) => find.byWidgetPredicate(
    (w) => w is AppRow && w.title is Text && (w.title as Text).data == title);

Future<void> _pump(WidgetTester tester, _Repo repo, {double scale = 1}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Sheets read the app-wide text scale, as on a device.
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(MaterialApp(
    home: AccountProfileEditScreen(repository: repo),
  ));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String part, String value) async {
  await tester.tap(find.byWidgetPredicate((w) =>
      w is DropdownButtonFormField<String> &&
      (w.key as ValueKey<String>?)?.value.startsWith('birthday-$part:') ==
          true));
  await tester.pumpAndSettle();
  final item = find.text(value).last;
  if (find.text(value).evaluate().isEmpty) {
    await tester.dragUntilVisible(
        find.text(value), find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(item);
  await tester.pumpAndSettle();
}

FilledButton _apply(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('birthday-apply')));

void main() {
  testWidgets('the three selects are one 生日 row between the other basic fields',
      (tester) async {
    await _pump(tester, _Repo());
    expect(_row('生日'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    final gender = tester.getTopLeft(_row('性别')).dy;
    final birthday = tester.getTopLeft(_row('生日')).dy;
    final from = tester.getTopLeft(find.text('来自')).dy;
    expect(gender < birthday && birthday < from, isTrue,
        reason: 'the date sits where the year was; nothing else moves');
  });

  testWidgets('a whole date saves under the three native names and reads back',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await tester.tap(_row('生日'));
    await tester.pumpAndSettle();
    await _choose(tester, 'year', '1990');
    await _choose(tester, 'month', '6');
    await _choose(tester, 'day', '15');
    await tester.tap(find.byKey(const ValueKey('birthday-apply')));
    await tester.pumpAndSettle();
    expect(find.text('1990-06-15'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'proyear': ['1990'],
      'promonth': ['6'],
      'proday': ['15'],
    });
    // The readback is the forum's form again: still one row, same date.
    expect(_row('生日'), findsOneWidget);
    expect(find.text('1990-06-15'), findsOneWidget);
  });

  testWidgets('a partial choice is never applied and says why', (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await tester.tap(_row('生日'));
    await tester.pumpAndSettle();
    expect(_apply(tester).onPressed, isNull);
    await _choose(tester, 'year', '1990');
    expect(_apply(tester).onPressed, isNull);
    expect(find.text('不完整的日期，请选择年、月、日或清空'), findsOneWidget);
    await _choose(tester, 'month', '2');
    // February 1990 has no 30th, so it is not offered.
    await tester.tap(find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<String> &&
        (w.key as ValueKey<String>?)?.value.startsWith('birthday-day:') ==
            true));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
        find.text('28'), find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('29'), findsNothing);
    expect(find.text('30'), findsNothing);
    await tester.tap(find.text('28').last);
    await tester.pumpAndSettle();
    expect(_apply(tester).onPressed, isNotNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
    expect(find.text('未设置'), findsOneWidget, reason: 'cancel applies nothing');
  });

  testWidgets('clearing a date posts the three empty values', (tester) async {
    final repo = _Repo(year: '1990', month: '6', day: '15');
    await _pump(tester, repo);
    expect(find.text('1990-06-15'), findsOneWidget);
    await tester.tap(_row('生日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('birthday-clear')));
    await tester.pumpAndSettle();
    expect(find.text('未设置'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'proyear': [''],
      'promonth': [''],
      'proday': [''],
    });
  });

  testWidgets(
      'an untouched half date is never patched or repaired; an unrelated edit still saves',
      (tester) async {
    final repo = _Repo(year: '1990');
    await _pump(tester, repo);
    expect(find.text('1990 年 · 月日未设置'), findsOneWidget);
    expect(find.text('不完整的日期，请选择年、月、日或清空'), findsOneWidget);
    // Another field changes; the birthday is no edit of its own.
    await tester.tap(_row('性别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('男').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
        repo.saved,
        {
          'progender': ['1']
        },
        reason:
            'no birthday patch; the native form re-posts what the forum holds');
    expect(find.text('1990 年 · 月日未设置'), findsOneWidget,
        reason: 'the readback keeps the forum value as it was');
  });

  testWidgets(
      'a touched half or impossible birthday blocks Save with its reason and sends nothing',
      (tester) async {
    final repo = _Repo(year: '1990', month: '6', day: '15');
    await _pump(tester, repo);
    final c = tester
        .widget<NativeBirthdayRow>(find.byType(NativeBirthdayRow))
        .controller;
    // A half tuple can only come from outside the sheet (a carried draft).
    c.set('promonth', ['']);
    await tester.pump();
    expect(find.text('不完整的日期，请选择年、月、日或清空'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请先修正标出的项目'), findsOneWidget);
    expect(repo.saved, isNull);
    c.set('promonth', ['2']);
    c.set('proday', ['30']);
    await tester.pump();
    expect(find.text('日期不存在，请重新选择'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
  });

  testWidgets('without all three numeric selects each field keeps its own row',
      (tester) async {
    await _pump(tester, _Repo(withDay: false));
    expect(_row('生日'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _Repo(textDay: true));
    expect(find.byKey(const ValueKey('native-birthday')), findsNothing);
  });

  testWidgets('large text stacks the three choices without overflow',
      (tester) async {
    await _pump(tester, _Repo(), scale: 2);
    await tester.tap(_row('生日'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final year = tester.getTopLeft(find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<String> &&
        (w.key as ValueKey<String>?)?.value.startsWith('birthday-year:') ==
            true));
    final month = tester.getTopLeft(find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<String> &&
        (w.key as ValueKey<String>?)?.value.startsWith('birthday-month:') ==
            true));
    expect(month.dy, greaterThan(year.dy));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
