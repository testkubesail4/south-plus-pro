import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/profile/forum_preferences_screen.dart';
import 'package:south_plus_rewrite/models/forum_account_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

// Synthetic fixtures only. Native labels are deliberately noisy, as the
// shared table cell makes them, so the screen's own titles must carry the page.
const _noisy = '时间格式(格式如:yyyy-mm-dd,yy-m-d)yyyy:4位数年份';

ForumAccountField _choice(String name, List<(String, String)> options,
        {String? value, String group = 'personal'}) =>
    ForumAccountField(
      name: name,
      label: _noisy,
      type: 'select',
      values: [value ?? options.first.$1],
      options: [
        for (final (v, l) in options) ForumAccountOption(value: v, label: l),
      ],
      group: group,
      hint: _noisy,
    );

ForumAccountForm _form({
  String dateType = '0',
  List<(String, String)> skins = const [('', '使用默认')],
}) =>
    ForumAccountForm(kind: ForumAccountFormKind.preferences, fields: [
      ForumAccountField(
          name: 'msggroups[]',
          label: '组',
          type: 'checkbox',
          values: const [],
          options: const [ForumAccountOption(value: '1', label: '甲')],
          group: 'pm'),
      ForumAccountField(
          name: 'banidinfo',
          label: _noisy,
          type: 'textarea',
          values: const [''],
          group: 'pm'),
      _choice(
          'friendcheck', const [('0', '允许任何人加我为好友'), ('1', '需要身份验证才能加我为好友')],
          group: 'friend'),
      _choice('timedf', const [('0', '使用默认'), ('8', '(北京时间) 北京')]),
      _choice('d_type', const [('0', '使用默认'), ('1', '自定义')], value: dateType),
      ForumAccountField(
          name: 'date_f',
          label: _noisy,
          type: 'text',
          values: const ['yyyy-mm-dd'],
          group: 'personal'),
      _choice('time_f', const [('24', '24'), ('12', '12')]),
      _choice('t_num', const [('0', '0'), ('10', '10')]),
      _choice('p_num', const [('0', '0'), ('10', '10')]),
      _choice('tpskin', skins),
      _choice('editor', const [('1', '所见即所得'), ('0', 'code 模式')]),
      _choice('proreceivemail', const [('1', '接收邮件'), ('0', '不接收邮件')]),
    ]);

class _Repo extends ForumRepository {
  _Repo(this.form);

  final ForumAccountForm form;
  Map<String, List<String>>? saved;

  @override
  Future<ForumAccountForm> fetchForumPreferences() async => form;

  @override
  Future<void> saveForumPreferences(
      ForumAccountForm form, Map<String, List<String>> changes) async {
    saved = changes;
  }
}

Future<_Repo> _pump(WidgetTester tester, ForumAccountForm form) async {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo(form);
  // A fresh key remounts the page, so it reads this repository's form.
  await tester.pumpWidget(MaterialApp(
      home: ForumPreferencesScreen(key: UniqueKey(), repository: repo)));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _choose(WidgetTester tester, String title, String option) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  test('a date pattern reads as the date it produces', () {
    expect(dateFormatExample('yyyy-mm-dd'), '2026-03-07');
    expect(dateFormatExample('yy-m-d'), '26-3-7');
    expect(dateFormatExample('dd/mm/yyyy'), '07/03/2026');
  });

  testWidgets('settings sit in short groups under their own titles',
      (tester) async {
    await _pump(tester, _form());
    for (final title in [
      '私讯与好友',
      '屏蔽用户组',
      '私讯黑名单',
      '加好友验证',
      '日期与时间',
      '时区',
      '日期格式',
      '时间制',
      '阅读',
      '主题列表每页数量',
      '阅读页每页帖子数',
      '原站设置',
      '网页默认编辑器',
      '论坛邮件',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.textContaining('yyyy:4位数年份'), findsNothing);
    expect(find.textContaining('填写对方的数字 UID'), findsOneWidget);
    // Plain words for the forum's bare choices.
    expect(find.text('24 小时制'), findsOneWidget);
    expect(find.text('论坛默认'), findsWidgets);
  });

  testWidgets('a skin choice with only the default is not offered',
      (tester) async {
    await _pump(tester, _form());
    expect(find.text('网页风格'), findsNothing);
    await _pump(tester, _form(skins: const [('', '使用默认'), ('wind', 'Wind')]));
    expect(find.text('网页风格'), findsOneWidget);
  });

  testWidgets('the custom date pattern shows only when custom is chosen',
      (tester) async {
    final repo = await _pump(tester, _form());
    expect(find.text('自定义日期格式'), findsNothing);
    await _choose(tester, '日期格式', '自定义');
    expect(find.text('自定义日期格式'), findsOneWidget);
    expect(find.textContaining('示例 2026-03-07'), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('date_f')),
            matching: find.byType(TextField)),
        'yy-m-d');
    await tester.pump();
    expect(find.textContaining('示例 26-3-7'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'd_type': ['1'],
      'date_f': ['yy-m-d'],
    });
  });

  testWidgets('a pattern typed and then left behind is not saved',
      (tester) async {
    final repo = await _pump(tester, _form());
    await _choose(tester, '日期格式', '自定义');
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('date_f')),
            matching: find.byType(TextField)),
        'yy-m-d');
    await tester.pump();
    await _choose(tester, '日期格式', '论坛默认');
    expect(find.text('自定义日期格式'), findsNothing);
    final save =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '保存'));
    expect(save.onPressed, isNull);
    expect(repo.saved, isNull);
  });
}
