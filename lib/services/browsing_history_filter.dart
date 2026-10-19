import '../models/forum_models.dart';
import 'keyword_match.dart';

List<BrowsingHistoryEntry> filterBrowsingHistory(
  List<BrowsingHistoryEntry> entries, {
  String keyword = '',
  int? year,
  int? month,
  int? day,
}) {
  if ((year != null && (year < 1 || year > 9999)) ||
      (month != null && (year == null || month < 1 || month > 12)) ||
      (day != null && (month == null || year == null || day < 1))) {
    throw ArgumentError('日期筛选需要有效的年、月、日');
  }
  if (day != null) {
    final date = DateTime(year!, month!, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw ArgumentError('日期不存在');
    }
  }
  return List.unmodifiable(entries.where((entry) {
    final date = entry.viewedAt.toLocal();
    return (year == null || date.year == year) &&
        (month == null || date.month == month) &&
        (day == null || date.day == day) &&
        matchKeyword(keyword, [
              entry.thread.title,
              entry.thread.author,
              entry.thread.section,
            ]) ==
            true;
  }));
}
