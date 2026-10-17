import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final account in ['first', 'second']) {
    testWidgets(
        'cookie persistence completes in consecutive widget zone $account',
        (tester) async {
      final store = ForumSessionStore();
      final client = ForumClient(sessionStore: store);
      addTearDown(() => client.close(force: true));
      var completed = false;
      var restoredLogin = false;
      Map<String, ForumStoredCookie>? persisted;
      Object? error;
      final cookie = ForumStoredCookie.session(
        name: 'fixture_winduser',
        value: account,
        origin: client.baseUri,
      );
      store
          .saveCookies({'fixture': cookie})
          .then((_) {
            return client.restoreCookies();
          })
          .then((_) {
            restoredLogin = client.isLoggedIn;
            return client.clearSession();
          })
          .then((_) => store.loadCookies())
          .then<void>((value) {
            persisted = value;
            completed = true;
          }, onError: (Object failure, StackTrace _) {
            error = failure;
            completed = true;
          });

      await tester.pump();
      expect(completed, isTrue,
          reason: 'An idle cookie queue must not use a previous test zone.');
      expect(error, isNull);
      expect(restoredLogin, isTrue);
      expect(client.isLoggedIn, isFalse);
      expect(persisted, isEmpty);
    });
  }
}
