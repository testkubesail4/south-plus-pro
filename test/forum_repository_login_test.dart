import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fetchLoginChallenge accepts action-based login forms', () async {
    final client = _FakeForumClient('''
      <html>
        <body>
          <form action="login.php">
            <input type="hidden" name="step" value="2">
            <input type="hidden" name="cktime" value="31536000">
            <input name="pwuser" value="">
            <input type="password" name="pwpwd" value="">
            <input name="gdcode" value="">
            <img src="ck.php?foo=1">
          </form>
        </body>
      </html>
    ''');
    final repository = ForumRepository(client: client);

    final challenge = await repository.fetchLoginChallenge();

    expect(challenge, isA<LoginChallenge>());
    expect(challenge.fields, {
      'step': '2',
      'cktime': '31536000',
    });
    expect(client.bytesPath, startsWith('ck.php?foo=1&nowtime='));
  });

  test('fetchLoginChallenge accepts login forms identified by fields',
      () async {
    final client = _FakeForumClient('''
      <html>
        <body>
          <form action="member.php">
            <input type="hidden" name="lgt" value="0">
            <input name="pwuser">
            <input type="password" name="pwpwd">
            <input name="gdcode">
            <img id="ckcode" src="/ck.php">
          </form>
        </body>
      </html>
    ''');
    final repository = ForumRepository(client: client);

    final challenge = await repository.fetchLoginChallenge();

    expect(challenge.fields, {'lgt': '0'});
    expect(client.bytesPath, startsWith('ck.php?nowtime='));
  });
}

class _FakeForumClient extends ForumClient {
  _FakeForumClient(this.html);

  final String html;
  String? bytesPath;

  @override
  Future<String> get(String path) async => html;

  @override
  Future<Uint8List> getBytes(String path) async {
    bytesPath = path;
    return Uint8List.fromList([1, 2, 3]);
  }
}
