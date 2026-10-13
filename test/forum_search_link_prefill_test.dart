import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('search links decode draft fields once without submitting a request',
      () {
    final client = _NoNetworkClient();
    final repository = ForumRepository(client: client);
    final query = repository.searchLinkPrefill(
        'https://blue-plus.net/search.php?keyword=foo%2Dbar%2520baz&pwuser=Fixture%2BUser&f_fid=42')!;
    expect(query.keyword, 'foo-bar%20baz');
    expect(query.username, 'Fixture+User');
    expect(query.boardId, '42');
    final seo = repository.searchLinkPrefill(
        'https://south-plus.net/search.php?keyword-foo%2Dbar-pwuser-Fixture-f_fid-all.html')!;
    expect(seo.keyword, 'foo-bar');
    expect(seo.username, 'Fixture');
    expect(seo.boardId, 'all');
    final prefill = repository.searchLinkPrefill(
        'https://south-plus.net/search.php#prefill(%22keyword%22,%22foo%252Dbar%22,%22pwuser%22,%22Fixture%22,%22fid%22,42)')!;
    expect(prefill.keyword, 'foo%2Dbar');
    expect(prefill.username, 'Fixture');
    expect(prefill.boardId, '42');
    expect(
        repository
            .searchLinkPrefill('https://south-plus.net/search.php')!
            .keyword,
        isNull);
    expect(client.requests, 0);
  });

  test('unsafe or malformed search prefill is rejected without requests', () {
    final client = _NoNetworkClient();
    final repository = ForumRepository(client: client);
    for (final raw in [
      'https://example.invalid/search.php?keyword=fixture',
      'https://user:password@south-plus.net/search.php',
      'https://south-plus.net/search.php?action=logout',
      'https://south-plus.net/search.php?keyword=a&keyword=b',
      'https://south-plus.net/search.php?f_fid=-1',
      'https://south-plus.net/search.php#prefill(%22keyword%22)',
      'https://south-plus.net/search.php#prefill(%22keyword%22,%7B%7D)',
      'https://south-plus.net/search.php#prefill(%22keyword%22,%22a%22,%22keyword%22,%22b%22)',
    ]) {
      expect(repository.searchLinkPrefill(raw), isNull, reason: raw);
    }
    expect(client.requests, 0);
  });
}

class _NoNetworkClient extends ForumClient {
  int requests = 0;
  @override
  Future<String> get(String path) async {
    requests++;
    throw StateError('no request expected');
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    requests++;
    throw StateError('no request expected');
  }
}
