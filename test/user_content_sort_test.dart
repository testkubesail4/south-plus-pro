import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/user_content_sort.dart';

UserListItem _row(String id, {int? count, String? date}) => UserListItem(
    title: id,
    url: 'job.php?action-topost-tid-1-pid-$id.html',
    threadId: '1',
    postId: id,
    replies: count,
    views: count,
    date: date);

void main() {
  for (final key in [UserContentSortKey.views, UserContentSortKey.replies]) {
    for (final descending in [false, true]) {
      test(
          '$key sorts ${descending ? 'descending' : 'ascending'} unknown-last with stable ties',
          () {
        final items = [
          _row('unknown'),
          _row('first', count: 4),
          _row('zero', count: 0),
          _row('second', count: 4),
          _row('negative', count: -1),
        ];
        final sorted = sortUserContent(
            items, UserContentSort(key, descending: descending));
        expect(
            sorted.map((row) => row.title),
            descending
                ? ['first', 'second', 'zero', 'unknown', 'negative']
                : ['zero', 'first', 'second', 'unknown', 'negative']);
        expect(items.first.title, 'unknown',
            reason: 'source order is not mutated');
        expect(sorted.first, same(items[descending ? 1 : 2]));
        expect(sorted.map((row) => row.postId).toSet(),
            items.map((row) => row.postId).toSet());
      });
    }
  }

  for (final descending in [false, true]) {
    test(
        'row time sorts ${descending ? 'descending' : 'ascending'} without borrowing thread time',
        () {
      final rows = [
        _row('missing'),
        _row('old', date: '2023-12-31'),
        _row('invalid', date: '2024-02-31'),
        _row('first', date: '2024-02-29 10:30'),
        _row('second', date: '2024-02-29 10:30'),
        _row('new', date: '2024-02-29 11:30'),
        _row('bad-clock', date: '2024-02-29 24:00'),
      ];
      final sorted = sortUserContent(rows,
          UserContentSort(UserContentSortKey.time, descending: descending));
      expect(
          sorted.map((row) => row.postId),
          descending
              ? [
                  'new',
                  'first',
                  'second',
                  'old',
                  'missing',
                  'invalid',
                  'bad-clock'
                ]
              : [
                  'old',
                  'first',
                  'second',
                  'new',
                  'missing',
                  'invalid',
                  'bad-clock'
                ]);
      expect(sorted.map((row) => row.threadId).toSet(), {'1'});
    });
  }

  test('empty and all-unknown lists retain their row identities', () {
    const sort = UserContentSort(UserContentSortKey.time);
    expect(sortUserContent([], sort), isEmpty);
    final rows = [_row('1'), _row('2'), _row('3')];
    expect(sortUserContent(rows, sort), orderedEquals(rows));
  });
}
