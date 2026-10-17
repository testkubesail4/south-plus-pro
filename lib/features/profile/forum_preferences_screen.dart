import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/grouped_list.dart';
import '../common/native_form_fields.dart';

/// 论坛偏好: the forum's own 短消息, 好友 and personal settings, with the
/// labels and choices the forum itself offers.
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
      builder: _sections,
    );
  }
}

List<Widget> _sections(BuildContext context, NativeFormController c) {
  final byGroup = <String, List<String>>{};
  for (final field in c.form.fields) {
    byGroup.putIfAbsent(field.group ?? 'personal', () => []).add(field.name);
  }
  Widget row(String name) {
    if (name == 'msggroups[]') {
      return NativeFieldRow(
        controller: c,
        name: name,
        title: '屏蔽用户组',
        helper: '勾选的用户组无法给你发短消息；不勾选即接收所有用户组',
        emptyValue: '未屏蔽',
        summary: (chosen) =>
            chosen.isEmpty ? '未屏蔽' : '已屏蔽 ${chosen.length} 个分组',
      );
    }
    if (name == 'banidinfo') {
      return NativeFieldRow(
        controller: c,
        name: name,
        helper: '加入黑名单的用户无法给你发短消息。填写数字 UID，多个用逗号分隔',
      );
    }
    return NativeFieldRow(controller: c, name: name);
  }

  const sections = [
    ('pm', '短消息'),
    ('friend', '好友'),
    ('personal', '个人偏好'),
  ];
  final known = {for (final s in sections) s.$1};
  // A group the forum adds later is shown with the personal ones.
  final extra = [
    for (final e in byGroup.entries)
      if (!known.contains(e.key)) ...e.value,
  ];
  return [
    for (final (key, label) in sections)
      if ((byGroup[key] ?? const <String>[]).isNotEmpty ||
          (key == 'personal' && extra.isNotEmpty)) ...[
        AppGroup(
          label: label,
          dividerIndent: AppSpace.lg,
          children: [
            for (final name in [
              ...?byGroup[key],
              if (key == 'personal') ...extra,
            ])
              row(name),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
      ],
  ];
}
