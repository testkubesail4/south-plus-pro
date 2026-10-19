import '../models/forum_models.dart';

enum UserContentSortKey { time, views, replies }

class UserContentSort {
  const UserContentSort(this.key, {this.descending = true});
  final UserContentSortKey key;
  final bool descending;
}

List<UserListItem> sortUserContent(
    List<UserListItem> items, UserContentSort sort) {
  int? value(UserListItem item) => switch (sort.key) {
        UserContentSortKey.time => _date(item.date),
        UserContentSortKey.views => _count(item.views),
        UserContentSortKey.replies => _count(item.replies),
      };
  final rows = [
    for (var index = 0; index < items.length; index++)
      (index: index, item: items[index], value: value(items[index])),
  ];
  rows.sort((a, b) {
    final left = a.value;
    final right = b.value;
    if (left == null && right != null) return 1;
    if (right == null && left != null) return -1;
    final comparison =
        left == null || right == null ? 0 : left.compareTo(right);
    if (comparison == 0) return a.index.compareTo(b.index);
    return sort.descending ? -comparison : comparison;
  });
  return List.unmodifiable(rows.map((row) => row.item));
}

int? _count(int? value) => value != null && value >= 0 ? value : null;

int? _date(String? value) {
  if (value == null) return null;
  final match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$')
          .firstMatch(value.trim());
  if (match == null) return null;
  int part(int index) => int.parse(match.group(index) ?? '0');
  final year = part(1);
  final month = part(2);
  final day = part(3);
  final hour = part(4);
  final minute = part(5);
  final second = part(6);
  if (year < 1 || hour > 23 || minute > 59 || second > 59) return null;
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date.millisecondsSinceEpoch;
}
