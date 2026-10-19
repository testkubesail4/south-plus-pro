import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/browsing_history_filter.dart';

BrowsingHistoryEntry _entry(String title, DateTime local,
        {String? author, String section = ''}) =>
    BrowsingHistoryEntry(
        thread: ForumThread(
            title: title,
            url: 'read.php?tid-1.html',
            replies: 0,
            section: section,
            author: author),
        viewedAt: local.toUtc());

void main() {
  final rows = [
    _entry('Needle latest', DateTime(2025, 1, 1, 0, 15),
        author: 'Alice', section: 'Board'),
    _entry('needle leap', DateTime(2024, 2, 29, 23, 45),
        author: 'Bob', section: 'Board'),
    _entry('older', DateTime(2024, 2, 1), author: 'Needle Alice'),
    _entry('different month', DateTime(2024, 1, 1), section: 'Needle Board'),
    _entry('different year', DateTime(2023, 2, 28)),
  ];

  test('year/month/day filter uses local view dates and retains source order',
      () {
    expect(filterBrowsingHistory(rows, year: 2024), rows.sublist(1, 4));
    expect(
        filterBrowsingHistory(rows, year: 2024, month: 2), rows.sublist(1, 3));
    expect(
        filterBrowsingHistory(rows, year: 2024, month: 2, day: 29), [rows[1]]);
    expect(
        filterBrowsingHistory(rows, year: 2025, month: 1, day: 1), [rows[0]]);
    expect(filterBrowsingHistory(rows, year: 2026), isEmpty);
  });

  test(
      'date composes with existing title/author/board AND-word keyword matching',
      () {
    expect(
        filterBrowsingHistory(rows, keyword: ' NEEDLE '), rows.sublist(0, 4));
    expect(filterBrowsingHistory(rows, keyword: 'needle board', year: 2024),
        [rows[1], rows[3]]);
    expect(
        filterBrowsingHistory(rows,
            keyword: 'needle alice', year: 2024, month: 2),
        [rows[2]]);
    expect(
        filterBrowsingHistory(rows,
            keyword: 'alice', year: 2024, month: 2, day: 29),
        isEmpty);
    expect(filterBrowsingHistory(rows), rows,
        reason: 'clearing returns every retained row');
    expect(filterBrowsingHistory(rows).first, same(rows.first));
  });

  test('invalid dates and incomplete date targets are rejected', () {
    for (final target in [
      (year: null, month: 1, day: null),
      (year: 2024, month: null, day: 1),
      (year: 2024, month: 13, day: null),
      (year: 2023, month: 2, day: 29),
      (year: 2024, month: 2, day: 30),
      (year: 2024, month: 1, day: 0),
      (year: 0, month: null, day: null),
    ]) {
      expect(
          () => filterBrowsingHistory(rows,
              year: target.year, month: target.month, day: target.day),
          throwsArgumentError);
    }
  });
}
