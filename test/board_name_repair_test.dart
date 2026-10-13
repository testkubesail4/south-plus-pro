import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('inbound board identity comes from the matching server breadcrumb',
      () async {
    final client = _BoardClient();
    final page = await ForumRepository(client: client).fetchBoardThreadPage(
      const ForumCategory(name: 'f42', slug: 'f42'),
      page: 3,
      order: ForumThreadOrder.replies,
    );
    expect(page.threads.single.section, 'Fixture board');
    expect(page.boardName, 'Fixture board');
    expect(client.paths,
        ['thread_new.php?fid-42-orderway-replies-asc-DESC-page-3.html']);
  });

  test('child-only board pages carry the parent identity into their children',
      () async {
    final client = _BoardClient()
      ..response =
          '''<div id="breadcrumbs"><a href="thread.php?fid-42.html">Fixture parent</a></div>
        <table><tr><td>子版块</td></tr><tr><td>论坛</td><td>文章</td></tr>
          <tr><td><h3><a href="thread.php?fid-43.html">Fixture child</a></h3></td><td>12</td></tr></table>''';
    final page = await ForumRepository(client: client).fetchBoardThreadPage(
      const ForumCategory(
          name: '',
          slug: 'f42',
          url: 'https://south-plus.net/simple/index.php?f42_2.html'),
    );
    expect(page.boardName, 'Fixture parent');
    expect(page.threads, isEmpty);
    expect(page.subBoards.single.name, 'Fixture child');
    expect(page.subBoards.single.section, 'Fixture parent');
  });

  test('missing breadcrumb does not discard a previously known board identity',
      () async {
    final client = _BoardClient()
      ..response =
          _BoardClient.fixture.replaceAll('id="breadcrumbs"', 'id="unrelated"');
    final page = await ForumRepository(client: client).fetchBoardThreadPage(
      const ForumCategory(name: 'Fixture known', slug: 'f42'),
    );
    expect(page.boardName, isNull);
    expect(page.threads.single.section, 'Fixture known');
  });
}

class _BoardClient extends ForumClient {
  final paths = <String>[];
  String response = fixture;
  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<String> get(String path) async {
    paths.add(path);
    return response;
  }

  static const fixture =
      '''<a href="thread.php?fid-42.html">Fixture unrelated tab</a>
      <div id="breadcrumbs"><a href="index.php">Fixture home</a>
        <a href="thread.php?fid-7.html">Fixture parent</a>
        <a href="thread.php?fid-42.html">Fixture board</a></div>
      <ul class="stream"><li class="dcsns-li"><span class="section-title">
        <a href="read.php?tid-701.html">Fixture topic</a></span></li></ul>''';
}
