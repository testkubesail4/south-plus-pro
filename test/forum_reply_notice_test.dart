import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('thread reply notice is sent only when explicitly enabled', () async {
    final client = _PostClient();
    final repository = ForumRepository(client: client);
    const category = ForumCategory(name: 'Fixture board', slug: 'fid-42');
    final defaultResult = await repository.submitThread(
      category: category,
      title: 'Fixture title',
      content: 'Fixture content',
    );
    expect(defaultResult.unconfirmed, isTrue);
    expect(client.forms.single.containsKey('atc_newrp'), isFalse);

    for (final checked in [false, true]) {
      client.checked = checked;
      for (final enabled in [true, false]) {
        final result = await repository.submitThread(
          category: category,
          title: 'Fixture title',
          content: 'Fixture content',
          enableReplyNotice: enabled,
        );
        expect(result.unconfirmed, isTrue);
        expect(client.forms.last, {
          'verify': 'fixture-token',
          'fid': '42',
          'atc_title': 'Fixture title',
          'atc_content': 'Fixture content',
          'Submit': '提 交',
          if (enabled) 'atc_newrp': '1',
        });
      }
    }
    expect(client.getPaths, everyElement('post.php?fid=42'));
    expect(client.postPaths, everyElement('post.php?'));
  });
}

class _PostClient extends ForumClient {
  bool checked = false;
  final forms = <Map<String, String>>[];
  final getPaths = <String>[];
  final postPaths = <String>[];

  @override
  bool get isLoggedIn => true;

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    getPaths.add(path);
    return '''
      <html><body><form name="FORM" method="post" action="post.php?">
        <input type="hidden" name="fid" value="42">
        <input type="hidden" name="verify" value="fixture-token">
        <input name="atc_title"><textarea name="atc_content"></textarea>
        <label><input type="checkbox" name="atc_newrp" value="1"
          ${checked ? 'checked' : ''}>新回复站内通知</label>
      </form></body></html>
    ''';
  }

  @override
  Future<String> postForm(String path, List<MapEntry<String, String>> fields,
      {bool multipart = false,
      List<ForumFormFile> files = const [],
      void Function()? requireCurrentSession}) async {
    requireCurrentSession?.call();
    postPaths.add(path);
    forms.add(Map.fromEntries(fields));
    return '<html><title>发帖完毕</title><body>发帖完毕</body></html>';
  }
}
