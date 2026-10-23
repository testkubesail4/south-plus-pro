import 'package:flutter/material.dart';

import '../../models/forum_account_models.dart';
import '../../services/native_date_validator.dart';
import '../../theme/app_theme.dart';
import '../common/grouped_list.dart';
import '../common/native_form_fields.dart';

/// The forum's three birthday selects, posted under these names unchanged.
const birthdayYear = 'proyear';
const birthdayMonth = 'promonth';
const birthdayDay = 'proday';
const birthdayFields = {birthdayYear, birthdayMonth, birthdayDay};

final _digits = RegExp(r'^[0-9]+$');

/// Whether [form] holds all three birthday selects with numeric choices, so
/// they can be shown as one date. Anything else keeps one row per field.
bool hasNativeBirthday(ForumAccountForm form) {
  final group = form.field(birthdayYear)?.group;
  for (final name in birthdayFields) {
    final field = form.field(name);
    if (field == null || field.type != 'select' || field.group != group) {
      return false;
    }
    final chosen = [
      for (final o in field.options)
        if (o.value.isNotEmpty) o.value
    ];
    if (chosen.isEmpty || !chosen.every(_digits.hasMatch)) return false;
  }
  return true;
}

List<String> _choices(NativeFormController c, String name) => [
      for (final o
          in c.form.field(name)?.options ?? const <ForumAccountOption>[])
        if (o.value.isNotEmpty) o.value
    ];

String? _problem(NativeFormController c, String y, String m, String d) =>
    validateNativeDate(
      year: y,
      month: m,
      day: d,
      yearOptions: _choices(c, birthdayYear),
      monthOptions: _choices(c, birthdayMonth),
      dayOptions: _choices(c, birthdayDay),
    );

String _two(String v) => v.padLeft(2, '0');

/// The page-wide check for a touched birthday field: a half or impossible
/// date blocks saving. An untouched one never does; it is not this edit.
String? birthdayFieldCheck(NativeFormController c, String name) {
  if (!birthdayFields.contains(name) || !hasNativeBirthday(c.form)) return null;
  return _problem(
      c, c.value(birthdayYear), c.value(birthdayMonth), c.value(birthdayDay));
}

/// One 生日 row for the three selects: the whole date, 未设置, or a half date
/// the forum already holds, said as it is and never repaired silently.
///
/// An untouched half date is no edit: the app never patches or completes it.
/// The save service still re-posts the whole native form, so the forum's own
/// value travels unchanged with it; only clearing all three or choosing a
/// whole date changes it.
class NativeBirthdayRow extends StatelessWidget {
  const NativeBirthdayRow({super.key, required this.controller});

  final NativeFormController controller;

  String get _title {
    final label = controller.form.field(birthdayYear)?.label.trim() ?? '';
    return label.isEmpty ? '生日' : label;
  }

  Future<void> _open(BuildContext context) async {
    final c = controller;
    final picked = await showModalBottomSheet<(String, String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => NativeFormOverlay(
        controller: c,
        child: _BirthdaySheet(
          controller: c,
          title: _title,
          year: c.value(birthdayYear),
          month: c.value(birthdayMonth),
          day: c.value(birthdayDay),
        ),
      ),
    );
    if (picked == null || c.retired) return;
    c.set(birthdayYear, [picked.$1]);
    c.set(birthdayMonth, [picked.$2]);
    c.set(birthdayDay, [picked.$3]);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final y = c.value(birthdayYear);
    final m = c.value(birthdayMonth);
    final d = c.value(birthdayDay);
    final problem = _problem(c, y, m, d);
    final String shown;
    if (y.isEmpty && m.isEmpty && d.isEmpty) {
      shown = '未设置';
    } else if (y.isNotEmpty && m.isNotEmpty && d.isNotEmpty) {
      shown = '$y-${_two(m)}-${_two(d)}';
    } else {
      final known = [
        if (y.isNotEmpty) '$y 年',
        if (m.isNotEmpty) '$m 月',
        if (d.isNotEmpty) '$d 日',
      ].join(' ');
      final missing = [
        if (y.isEmpty) '年',
        if (m.isEmpty) '月',
        if (d.isEmpty) '日',
      ].join();
      shown = '$known · $missing未设置';
    }
    return AppRow(
      key: const ValueKey('native-birthday'),
      title: Text(_title),
      subtitle: problem == null
          ? null
          : Text(problem,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      value: shown,
      onTap: () => _open(context),
    );
  }
}

/// Year, month and day together. Only a whole real date can be applied;
/// 清除 empties all three.
class _BirthdaySheet extends StatefulWidget {
  const _BirthdaySheet({
    required this.controller,
    required this.title,
    required this.year,
    required this.month,
    required this.day,
  });

  final NativeFormController controller;
  final String title;
  final String year;
  final String month;
  final String day;

  @override
  State<_BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends State<_BirthdaySheet> {
  late String _y = widget.year;
  late String _m = widget.month;
  late String _d = widget.day;

  NativeFormController get _c => widget.controller;

  /// Days that make a real date with the chosen year and month.
  List<String> get _days {
    final all = _choices(_c, birthdayDay);
    if (_y.isEmpty || _m.isEmpty) return all;
    return [
      for (final d in all)
        if (_problem(_c, _y, _m, d) == null) d
    ];
  }

  void _pick({String? y, String? m, String? d}) {
    setState(() {
      _y = y ?? _y;
      _m = m ?? _m;
      _d = d ?? _d;
      // A day the new month does not have is unchosen, not moved.
      if (_d.isNotEmpty && !_days.contains(_d)) _d = '';
    });
  }

  Widget _menu(String key, String label, String suffix, String value,
      List<String> options, ValueChanged<String> onPick) {
    return DropdownButtonFormField<String>(
      key: ValueKey('birthday-$key:$value'),
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text('$o$suffix')),
      ],
      onChanged: (v) {
        if (v != null) onPick(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem(_c, _y, _m, _d);
    final empty = _y.isEmpty && _m.isEmpty && _d.isEmpty;
    final year = _menu(
        'year', '年', '', _y, _choices(_c, birthdayYear), (v) => _pick(y: v));
    final month = _menu(
        'month', '月', '', _m, _choices(_c, birthdayMonth), (v) => _pick(m: v));
    final day = _menu('day', '日', '', _d, _days, (v) => _pick(d: v));
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg,
            AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: AppSpace.lg),
            // Side by side while there is room; stacked with large text.
            LayoutBuilder(builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (box.maxWidth / scale >= 300) {
                return Row(children: [
                  Expanded(flex: 4, child: year),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(flex: 3, child: month),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(flex: 3, child: day),
                ]);
              }
              return Column(children: [
                year,
                const SizedBox(height: AppSpace.sm),
                month,
                const SizedBox(height: AppSpace.sm),
                day,
              ]);
            }),
            if (problem != null && !empty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(problem,
                  key: const ValueKey('birthday-problem'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(children: [
              TextButton(
                key: const ValueKey('birthday-clear'),
                onPressed: () => Navigator.of(context).pop(('', '', '')),
                child: const Text('清除'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton(
                key: const ValueKey('birthday-apply'),
                onPressed: empty || problem != null
                    ? null
                    : () => Navigator.of(context).pop((_y, _m, _d)),
                child: const Text('确定'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
