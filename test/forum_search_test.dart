import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('advanced search submits explicit fields and parses server page links',
      () async {
    final client = _SearchClient();
    final repository = ForumRepository(client: client);
    final boards = await repository.fetchSearchBoards();
    expect(boards.map((board) => (board.id, board.name)), [
      ('all', 'Fixture all'),
      ('group', 'Fixture heading'),
      ('42', 'Fixture board')
    ]);
    expect(boards[1].selectable, false);

    final result = await repository.searchForum(const ForumSearchQuery(
      username: 'fixture-user',
      match: ForumSearchMatch.exact,
      boardId: '42',
      time: ForumSearchTime.week,
      order: ForumThreadOrder.hits,
      ascending: true,
    ));
    expect(client.fields, {
      'verify': 'fixture-token',
      'step': '2',
      'keyword': '',
      'pwuser': 'fixture-user',
      'method': 'AND',
      'f_fid': '42',
      'sch_time': '604800',
      'orderway': 'hits',
      'asc': 'ASC',
      'submit': '提 交',
      'sch_area': '0',
    });
    expect(result.total, 23);
    expect(result.threads.map((thread) => thread.title),
        ['Fixture first', 'Fixture second']);
    expect(result.nextPagePath, 'search.php?sid=fixture-session&page=2');
  });

  test(
      'verified enhanced form keeps hierarchy, wildcard, digest and true empty result',
      () async {
    final client = _SearchClient()
      ..formResponse = '''<form action="search.php?">
      <input type="checkbox" name="digest" value="1" checked>
      <input name="sch_area" value="2">
      <select name="f_fid"><option value="all">Fixture all</option>
        <option value="">&gt;&gt; Fixture group</option>
        <option value="42">|- Fixture duplicate</option>
        <option value="43">|- Fixture duplicate</option>
        <option value="44" disabled>Fixture unavailable</option></select>
    </form>''';
    final repository = ForumRepository(client: client);
    final boards = await repository.fetchSearchBoards();
    expect(boards.map((b) => (b.id, b.depth, b.selectable)), [
      ('all', 0, true),
      ('', 0, false),
      ('42', 1, true),
      ('43', 1, true),
      ('44', 0, false),
    ]);
    await repository.searchForum(const ForumSearchQuery(
        username: 'fixture*', digest: true, boardId: '43'));
    expect(client.fields!['digest'], '1');
    expect(client.fields!['sch_area'], '0');
    expect(client.fields!['pwuser'], 'fixture*');
    await repository.searchForum(const ForumSearchQuery(keyword: 'one | two'));
    expect(client.fields!['digest'], isNull);
    expect(client.fields!['keyword'], 'one | two');
    final submitted = client.fields;
    for (final id in ['', '44', '999']) {
      await expectLater(
          repository
              .searchForum(ForumSearchQuery(keyword: 'fixture', boardId: id)),
          throwsA(isA<ForumRepositoryException>()));
    }
    expect(client.fields, same(submitted));
    client.postResponse = '<html><body>没有查找匹配的内容</body></html>';
    final empty = await repository
        .searchForum(const ForumSearchQuery(keyword: 'fixture'));
    expect(empty.threads, isEmpty);
    expect(empty.total, 0);
  });

  test('foreign search form cannot receive keyword or username', () async {
    final client = _SearchClient()
      ..formResponse = '''<form action="https://example.invalid/search.php">
      <select name="f_fid"><option value="all">Fixture all</option></select>
    </form>''';
    await expectLater(
        ForumRepository(client: client).searchForum(const ForumSearchQuery(
            keyword: 'fixture-query', username: 'fixture-user')),
        throwsA(isA<ForumRepositoryException>()));
    expect(client.fields, isNull);
    expect(client.getPaths, ['search.php']);
  });

  test('search defaults and time values match the forum wire protocol',
      () async {
    final client = _SearchClient();
    final repository = ForumRepository(client: client);
    await repository
        .searchForum(const ForumSearchQuery(keyword: 'fixture-topic'));
    expect(client.fields!['method'], 'OR');
    expect(client.fields!['f_fid'], 'all');
    expect(client.fields!['sch_time'], '31536000');
    expect(client.fields!['orderway'], 'postdate');
    expect(client.fields!['asc'], 'DESC');
    for (final (time, value) in [
      (ForumSearchTime.all, 'all'),
      (ForumSearchTime.newTopics, 'newatc'),
      (ForumSearchTime.day, '86400'),
      (ForumSearchTime.twoDays, '172800'),
      (ForumSearchTime.week, '604800'),
      (ForumSearchTime.month, '2592000'),
      (ForumSearchTime.twoMonths, '5184000'),
      (ForumSearchTime.threeMonths, '7776000'),
      (ForumSearchTime.halfYear, '15552000'),
      (ForumSearchTime.year, '31536000'),
    ]) {
      await repository.searchForum(ForumSearchQuery(
        keyword: 'fixture-topic',
        username: 'fixture-user',
        time: time,
      ));
      expect(client.fields!['sch_time'], value);
      expect(client.fields!['keyword'], 'fixture-topic');
      expect(client.fields!['pwuser'], 'fixture-user');
    }
  });

  test('pagination GET preserves sid and never resubmits the query', () async {
    final client = _SearchClient();
    final repository = ForumRepository(client: client);
    const query = ForumSearchQuery(keyword: 'fixture-topic');
    final first = await repository.searchForum(query);
    final submitted = client.fields;
    client.pageResponse = '''
      <html><body>共搜索到了23条信息
        <div class="pages">Pages: 2/4
          <a href="search.php?sid=fixture-session&amp;page=1">1</a>
          <a href="search.php?sid=fixture-session&amp;page=2">2</a>
          <a href="https://example.invalid/search.php?sid=foreign&amp;page=3">3</a>
          <a href="search.php?sid=fixture-session&amp;page=4">4</a>
          <a href="search.php?sid=fixture-session&amp;page=3">3</a>
        </div>
      </body></html>
    ''';
    final second = await repository.searchForumPage(query, first.nextPagePath!);
    expect(client.getPaths.last, 'search.php?sid=fixture-session&page=2');
    expect(client.fields, same(submitted));
    expect(second.total, 23);
    expect(second.currentPage, 2);
    expect(second.previousPagePath, 'search.php?sid=fixture-session&page=1');
    expect(second.pageLinks.map((link) => link.page), [1, 2, 4, 3]);
    expect(second.nextPagePath, 'search.php?sid=fixture-session&page=3');
    client.pageResponse = '<html><body>共搜索到了0条信息</body></html>';
    final last = await repository.searchForumPage(query, second.nextPagePath!);
    expect(last.total, 0);
    expect(last.threads, isEmpty);
    expect(last.nextPagePath, isNull);
  });

  test('empty query and external page paths fail without requests', () async {
    final client = _SearchClient();
    final repository = ForumRepository(client: client);
    await expectLater(
      repository
          .searchForum(const ForumSearchQuery(keyword: ' ', username: ' ')),
      throwsA(isA<ForumRepositoryException>()),
    );
    for (final path in [
      'https://example.invalid/search.php?sid=fixture-session&page=2',
      '//example.invalid/search.php?sid=fixture-session&page=2',
      'read.php?tid-1.html',
    ]) {
      await expectLater(
        repository.searchForumPage(
            const ForumSearchQuery(keyword: 'fixture-topic'), path),
        throwsA(isA<ForumRepositoryException>()),
      );
    }
    expect(client.getPaths, isEmpty);
    expect(client.fields, isNull);
  });

  test('search and page errors retain classified exceptions', () async {
    for (final (html, kind) in [
      ('<html><body>搜索间隔9秒后再试</body></html>', ForumRequestKind.rateLimited),
      ('<html><body>请先登录</body></html>', ForumRequestKind.loginRequired),
      ('<html><body>没有权限</body></html>', ForumRequestKind.forbidden),
      (
        '<html><body>Fixture server failure</body></html>',
        ForumRequestKind.server
      ),
    ]) {
      final client = _SearchClient()..postResponse = html;
      final repository = ForumRepository(client: client);
      const query = ForumSearchQuery(keyword: 'fixture-topic');
      final failure = throwsA(isA<ForumRequestException>()
          .having((error) => error.kind, 'kind', kind));
      await expectLater(repository.searchForum(query), failure);
      client.formResponse = html;
      await expectLater(repository.fetchSearchBoards(), failure);
      client.pageResponse = html;
      await expectLater(
          repository.searchForumPage(
              query, 'search.php?sid=fixture-session&page=2'),
          failure);
    }
    final client = _SearchClient()
      ..postResponse = '<html><body>搜索结果</body></html>';
    final result = await ForumRepository(client: client)
        .searchForum(const ForumSearchQuery(keyword: 'fixture-topic'));
    expect(result.total, isNull);
    expect(result.threads, isEmpty);
  });
}

class _SearchClient extends ForumClient {
  Map<String, String>? fields;
  final getPaths = <String>[];
  String? postResponse;
  String? pageResponse;
  String? formResponse;

  @override
  Future<String> get(String path) async {
    getPaths.add(path);
    if (path != 'search.php') return pageResponse!;
    return formResponse ??
        '''
    <html><body><form action="search.php?">
      <input type="hidden" name="verify" value="fixture-token">
      <input name="digest" value="1"><input name="sch_area" value="0">
      <select name="f_fid">
        <option value="all">Fixture all</option>
        <option disabled value="group">Fixture heading</option>
        <option value="42">Fixture board</option>
      </select>
    </form></body></html>
  ''';
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    fields = form;
    return postResponse ??
        '''
      <html><body>共搜索到了23条信息
        <table>
          <tr><td><a href="read.php?tid-2.html">Fixture first</a></td></tr>
          <tr><td><a href="read.php?tid-1.html">Fixture second</a></td></tr>
        </table>
        <div class="pages"><b>1</b>
          <a href="search.php?sid=fixture-session&amp;page=2">2</a>
        </div>
      </body></html>
    ''';
  }
}
