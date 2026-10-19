import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/user_content_sort.dart';
import 'package:south_plus_rewrite/services/parsers/user_profile_parser.dart';

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

  for (final tab in [UserProfileTab.topics, UserProfileTab.posts]) {
    test(
        '$tab metadata comes from the native row, never from user title tokens',
        () {
      String row(int id, String title, String metadata) =>
          '<tr><td><a href="${tab == UserProfileTab.posts ? 'job.php?action-topost-tid-7-pid-$id.html' : 'read.php?tid-$id.html'}">'
          '$title</a></td><td>$metadata</td></tr>';
      final document = html.parse(
          '<div id="u-contentmain"><table class="u-table">'
          '${row(101, '[1999-01-01] 浏览:999 回复:999', '[2024-01-01] 浏览:90 回复:9')}'
          '${row(102, 'Normal title', '[2024-02-01] 浏览:40 回复:4')}'
          '${row(103, '[2000-01-01] 浏览:888 回复:888', '')}'
          '</table></div>');
      final rows = UserProfileParser()
          .parseContentPage(document, uid: '7', tab: tab, page: 1)
          .items;
      expect(rows.map((row) => row.date), ['2024-01-01', '2024-02-01', null]);
      expect(rows.map((row) => row.views),
          tab == UserProfileTab.topics ? [90, 40, null] : [null, null, null]);
      expect(rows.map((row) => row.replies),
          tab == UserProfileTab.topics ? [9, 4, null] : [null, null, null]);
      final sorted =
          sortUserContent(rows, const UserContentSort(UserContentSortKey.time));
      expect(sorted, [rows[1], rows[0], rows[2]]);
    });
  }

  test('empty and all-unknown lists retain their row identities', () {
    const sort = UserContentSort(UserContentSortKey.time);
    expect(sortUserContent([], sort), isEmpty);
    final rows = [_row('1'), _row('2'), _row('3')];
    expect(sortUserContent(rows, sort), orderedEquals(rows));
  });
}
