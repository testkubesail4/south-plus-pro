import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('session owner notifies once for login, restoration, expiry and clear',
      () async {
    final client = _SessionClient();
    final repository = ForumRepository(client: client);
    final owners = <String?>[];
    repository.sessionUser.addListener(() {
      expect(repository.sessionUser.value, repository.currentUsername);
      owners.add(repository.sessionUser.value);
    });
    expect(repository.sessionUser.value, isNull);
    expect(
        await repository.login(
            username: 'Fixture One', password: 'fixture', captcha: '1234'),
        true);
    expect(owners, ['Fixture One']);
    expect(await repository.restoreSession(), true);
    expect(owners, ['Fixture One']);
    client.username = 'Fixture Two';
    expect(await repository.restoreSession(), true);
    expect(owners, ['Fixture One', 'Fixture Two']);
    client.username = null;
    expect(await repository.restoreSession(), false);
    expect(owners, ['Fixture One', 'Fixture Two', null]);
    await repository.clearSession();
    expect(owners, ['Fixture One', 'Fixture Two', null]);
    expect(
        await repository.login(
            username: 'Fixture One', password: 'fixture', captcha: '1234'),
        true);
    await repository.clearSession();
    expect(owners, ['Fixture One', 'Fixture Two', null, 'Fixture One', null]);
    expect(
        await repository.login(
            username: 'Fixture One', password: 'fixture', captcha: '1234'),
        true);
    client.loggedIn = false;
    final requests = client.requests;
    expect(await repository.restoreSession(), false);
    expect(client.requests, requests);
    expect(repository.currentUsername, isNull);
    expect(owners, [
      'Fixture One',
      'Fixture Two',
      null,
      'Fixture One',
      null,
      'Fixture One',
      null
    ]);
  });
}

class _SessionClient extends ForumClient {
  String? username;
  bool loggedIn = false;
  int requests = 0;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<void> restoreCookies() async {}
  @override
  Future<void> clearSession() async {
    loggedIn = false;
    username = null;
  }

  @override
  Future<String> get(String path) async {
    requests++;
    return username == null ? '' : '<a href="u.php">$username</a>';
  }

  @override
  Future<String> post(String path, Map<String, String> form) async {
    username = form['pwuser'];
    loggedIn = true;
    return '<a href="u.php">$username</a>';
  }
}
