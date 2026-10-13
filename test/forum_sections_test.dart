import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

class _SectionsClient extends ForumClient {
  _SectionsClient(this.response);

  final String response;
  final paths = <String>[];

  @override
  Future<String> get(String path) async {
    paths.add(path);
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('forum sections loads desktop hierarchy with one GET', () async {
    final client = _SectionsClient('''<table>
      <tr><th><h2><a href="index.php?cateid-903.html">Fixture group</a></h2></th></tr>
      <tr><td></td><th><h3><a href="thread.php?fid-901.html">Fixture parent</a></h3>
      子版：<h3><a href="thread.php?fid-902.html">Fixture child</a></h3>
      </th><td>1 / 2</td></tr></table>''');
    final sections = await ForumRepository(client: client).fetchForumSections();
    expect(client.paths, ['index.php']);
    expect(sections.single.title, 'Fixture group');
    expect(sections.single.items.single.children.single.url,
        'https://south-plus.net/thread.php?fid-902.html');
  });

  test('valid empty forum directory is not a request failure', () async {
    final client = _SectionsClient('<html></html>');
    expect(await ForumRepository(client: client).fetchForumSections(), isEmpty);
    expect(client.paths, ['index.php']);
  });

  for (final entry in {
    '请先登录': ForumRequestKind.loginRequired,
    '没有权限': ForumRequestKind.forbidden,
    '请求过于频繁': ForumRequestKind.rateLimited,
  }.entries) {
    test('forum directory preserves ${entry.value.name} page errors', () async {
      final client = _SectionsClient('<html><body>${entry.key}</body></html>');
      await expectLater(
        ForumRepository(client: client).fetchForumSections(),
        throwsA(isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          entry.value,
        )),
      );
      expect(client.paths, ['index.php']);
    });
  }
}
