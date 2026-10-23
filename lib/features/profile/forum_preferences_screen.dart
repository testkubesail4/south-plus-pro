import 'package:flutter/material.dart';

import '../../models/forum_account_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/grouped_list.dart';
import '../common/native_form_fields.dart';

/// 论坛偏好: the settings the forum keeps on the account, grouped by what they
/// change. Titles and hints are short; the forum's own choices stay as they are.
class ForumPreferencesScreen extends StatelessWidget {
  const ForumPreferencesScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return NativeFormPage(
      title: '论坛偏好',
      sessionEpoch: repository.sessionEpoch,
      load: repository.fetchForumPreferences,
      save: (form, changes, _) =>
          repository.saveForumPreferences(form, changes),
      // A custom pattern only counts while the custom format is chosen.
      activeField: (c, name) => name != 'date_f' || _customDate(c),
      builder: _sections,
    );
  }
}

bool _customDate(NativeFormController c) {
  final value = c.value('d_type');
  final label = c.form
          .field('d_type')
          ?.options
          .where((o) => o.value == value)
          .map((o) => o.label)
          .firstOrNull ??
      '';
  return label.contains('自定义') || (label.isEmpty && value == '1');
}

/// A date pattern written out for 7 March 2026, so its letters read as a date.
String dateFormatExample(String pattern) =>
    pattern.replaceAllMapped(RegExp(r'yyyy|yy|mm|dd|m|d'), (m) {
      return switch (m[0]) {
        'yyyy' => '2026',
        'yy' => '26',
        'mm' => '03',
        'dd' => '07',
        'm' => '3',
        _ => '7',
      };
    });

String _optionLabel(ForumAccountOption o) {
  final label = o.label.trim();
  if (label.contains('使用默认')) return '论坛默认';
  return switch ((label, o.value)) {
    ('24', _) => '24 小时制',
    ('12', _) => '12 小时制',
    ('0', '0') => '论坛默认',
    _ => label,
  };
}

/// A skin choice means something only when the forum offers more than its default.
bool _hasSkinChoice(ForumAccountField? field) =>
    field != null &&
    field.options.any((o) =>
        o.value.isNotEmpty && !o.label.contains('默认') && o.label.isNotEmpty);

const _knownNames = {
  'msggroups[]',
  'banidinfo',
  'friendcheck',
  'timedf',
  'd_type',
  'date_f',
  'time_f',
  't_num',
  'p_num',
  'tpskin',
  'editor',
  'proreceivemail',
};

List<Widget> _sections(BuildContext context, NativeFormController c) {
  Widget row(String name) {
    switch (name) {
      case 'msggroups[]':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '屏蔽用户组',
          emptyValue: '未屏蔽',
          summary: (chosen) =>
              chosen.isEmpty ? '未屏蔽' : '已屏蔽 ${chosen.length} 个分组',
        );
      case 'banidinfo':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '私讯黑名单',
          helper: '填写对方的数字 UID，用逗号分隔',
        );
      case 'friendcheck':
        return NativeFieldRow(
            key: ValueKey(name), controller: c, name: name, title: '加好友验证');
      case 'timedf':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '时区',
          optionLabel: _optionLabel,
        );
      case 'd_type':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '日期格式',
          optionLabel: _optionLabel,
        );
      case 'date_f':
        final pattern = c.value('date_f');
        const letters = '年 yyyy 或 yy，月 mm 或 m，日 dd 或 d';
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '自定义日期格式',
          helper: pattern.trim().isEmpty
              ? '$letters · 例如 yyyy-mm-dd'
              : '$letters · 示例 ${dateFormatExample(pattern)}',
        );
      case 'time_f':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '时间制',
          optionLabel: _optionLabel,
        );
      case 't_num':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '主题列表每页数量',
          optionLabel: _optionLabel,
        );
      case 'p_num':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '阅读页每页帖子数',
          optionLabel: _optionLabel,
        );
      case 'tpskin':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '网页风格',
          optionLabel: _optionLabel,
        );
      case 'editor':
        return NativeFieldRow(
          key: ValueKey(name),
          controller: c,
          name: name,
          title: '网页默认编辑器',
          optionLabel: _optionLabel,
        );
      case 'proreceivemail':
        return NativeFieldRow(
            key: ValueKey(name), controller: c, name: name, title: '论坛邮件');
      default:
        // A setting the forum adds later keeps its own label.
        return NativeFieldRow(key: ValueKey(name), controller: c, name: name);
    }
  }

  final groups = <(String, List<String>)>[
    ('私讯与好友', ['msggroups[]', 'banidinfo', 'friendcheck']),
    ('日期与时间', ['timedf', 'd_type', if (_customDate(c)) 'date_f', 'time_f']),
    ('阅读', ['t_num', 'p_num']),
    (
      '原站设置',
      [
        if (_hasSkinChoice(c.form.field('tpskin'))) 'tpskin',
        'editor',
        'proreceivemail',
      ]
    ),
    (
      '其他',
      [
        for (final f in c.form.fields)
          if (!_knownNames.contains(f.name)) f.name,
      ]
    ),
  ];
  return [
    for (final (label, names) in groups)
      if (names.any(c.has)) ...[
        AppGroup(
          label: label,
          dividerIndent: AppSpace.lg,
          children: [
            for (final name in names)
              if (c.has(name)) row(name),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
      ],
  ];
}
