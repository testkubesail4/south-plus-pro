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

  test('fetchBoardThreadPage carries desktop sub boards with simple threads',
      () async {
    final client = _PathForumClient({
      'simple/index.php?f218.html': '''
        <html>
          <body>
            <ul class="threadlist">
              <li>
                <a href="?t1.html">父版公告<span class="by">论坛公告</span></a>
                <span class="num">0</span>
              </li>
            </ul>
            <ul class="pagination"><li class="active"><b>1</b></li></ul>
          </body>
        </html>
      ''',
      'thread.php?fid-218.html': '''
        <html>
          <body>
            <table>
              <tr><td class="h" colspan="5"><b>子版块</b></td></tr>
              <tr class="tr2">
                <td></td><td>论坛</td><td>版主</td><td>文章</td><td>最后发表</td>
              </tr>
              <tr class="f_one tr3">
                <td><a href="thread.php?fid-213.html"><img src="old.gif"></a></td>
                <th>
                  <a class="bklogo" href="thread.php?fid-213.html"></a>
                  <h2>
                    <a href="thread.php?fid-213.html" class="fnamecolor a1">
                      <b>同人志&CG</b>
                    </a>
                  </h2>
                </th>
                <td></td><td>26246</td><th></th>
              </tr>
            </table>
          </body>
        </html>
      ''',
    });
    final repository = ForumRepository(client: client);

    final page = await repository.fetchBoardThreadPage(
      const ForumCategory(
        name: 'C103',
        slug: 'fid-218',
        url: 'https://south-plus.net/thread.php?fid-218.html',
      ),
    );

    expect(client.paths, [
      'simple/index.php?f218.html',
      'thread.php?fid-218.html',
    ]);
    expect(page.subBoards.map((board) => board.name), ['同人志&CG']);
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

class _PathForumClient extends ForumClient {
  _PathForumClient(this.htmlByPath);

  final Map<String, String> htmlByPath;
  final paths = <String>[];

  @override
  Future<String> get(String path) async {
    paths.add(path);
    final normalized = path.replaceFirst('https://south-plus.net/', '');
    return htmlByPath[normalized] ?? htmlByPath[path] ?? '<html></html>';
  }
}
