import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';

class ForumTasksParser {
  const ForumTasksParser();

  List<ForumTask> parse(dom.Document document, ForumTaskStatus status) {
    final tasks = <ForumTask>[];
    final seen = <String>{};
    final rows = document.querySelectorAll('tr');
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final text = _cleanText(row.text);
      if (!text.contains('任务时效') || !text.contains('奖励')) continue;
      if (text.contains('社区论坛任务功能简介')) continue;

      final name = _taskName(row, text);
      if (name == null || name.isEmpty) continue;
      final id = _taskId(row);
      final key = '${id ?? ''}:$name:$status';
      if (!seen.add(key)) continue;

      final detailRow = index + 1 < rows.length ? rows[index + 1] : null;
      final detailText = _cleanText(detailRow?.text ?? '');
      final reward = _matchText(
          text,
          RegExp(
              r'奖励\s*:\s*(.*?)(?:\s*(?:上次领取未超过|按这申请此任务|领取此奖励|正在领取中|\s{2,})|$)'));
      tasks.add(
        ForumTask(
          id: id,
          name: name,
          status: status,
          description: _description(detailText),
          reward: reward,
          popularity: _intMatch(text, RegExp(r'人气\s*:\s*(\d+)')),
          startedAt: _matchText(text, RegExp(r'任务时效\s*(\d{4}-\d{2}-\d{2})')),
          endsAt: _matchText(text, RegExp(r'~\s*(\d{4}-\d{2}-\d{2})')),
          progressPercent: _intMatch(detailText, RegExp(r'已完成\s*(\d+)\s*%')),
          completedAt: _matchText(detailText, RegExp(r'完成时间\s*(.+)$')),
          actionLabel: _actionLabel(row),
          cooldownRemaining: _cooldownRemaining(text),
        ),
      );
    }
    return tasks;
  }

  String emptyMessage(dom.Document document) {
    final text = _cleanText(document.body?.text ?? '');
    final match = RegExp(r'你无任何[^ 操作]+任务').firstMatch(text);
    return match?.group(0) ?? '没有任务';
  }

  String? _taskName(dom.Element row, String text) {
    final bold = _cleanText(row.querySelector('b')?.text ?? '');
    if (bold.isNotEmpty) return bold;
    return _matchText(text, RegExp(r'^(.+?)\s*\(人气\s*:'));
  }

  String? _taskId(dom.Element row) {
    final html = row.outerHtml;
    return RegExp(r"startjob\('(\d+)'\)").firstMatch(html)?.group(1);
  }

  String? _actionLabel(dom.Element row) {
    for (final link in row.querySelectorAll('a[title]')) {
      final title = _cleanText(link.attributes['title'] ?? '');
      if (title.contains('任务') || title.contains('奖励')) return title;
    }
    return null;
  }

  String? _description(String text) {
    if (text.isEmpty) return null;
    final cleaned = text
        .replaceAll(RegExp(r'已完成\s*\d+\s*%'), '')
        .replaceAll(RegExp(r'完成时间\s*.+$'), '')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  int? _intMatch(String text, RegExp pattern) {
    final value = _matchText(text, pattern);
    return value == null ? null : int.tryParse(value);
  }

  Duration? _cooldownRemaining(String text) {
    final match = RegExp(r'上次领取未超过\s*(\d+)\s*小时').firstMatch(text);
    final hours = int.tryParse(match?.group(1) ?? '');
    return hours == null ? null : Duration(hours: hours);
  }

  String? _matchText(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    final value = _cleanText(match?.group(1) ?? '');
    return value.isEmpty ? null : value;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
