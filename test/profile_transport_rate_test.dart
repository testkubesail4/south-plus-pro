import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

class _RealHttp extends HttpOverrides {}

class _Clock {
  DateTime now = DateTime.utc(2020);
  Future<void> wait(Duration delay) async {
    now = now.add(delay);
  }
}

class _LocalClient extends ForumClient {
  _LocalClient(this.origin, HttpClient transport, _Clock clock)
      : super(httpClient: transport, clock: () => clock.now, delay: clock.wait);
  final Uri origin;
  @override
  Uri get baseUri => origin;
}

String page(String title) =>
    '<div id="u-top"><h1 class="u-h1">fixture-header</h1></div>'
    '<table class="u-table"><tr><td><a href="read.php?tid-456.html">$title</a></td></tr></table>';
const overview = UserProfile(uid: '123', name: 'fixture-header', url: 'u.php');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scenario in [
    'valid title',
    '200 cooldown once',
    '429 cooldown once',
    'permanent cooldown'
  ]) {
    test('real profile transport: $scenario', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final transport =
          HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
      final client = _LocalClient(
          Uri.parse('http://127.0.0.1:${server.port}/'), transport, _Clock());
      final repository = ForumRepository(client: client);
      addTearDown(() async {
        await repository.clearSession();
        transport.close(force: true);
        await server.close(force: true);
      });
      var count = 0;
      final perPath = <String, int>{};
      server.listen((request) {
        count++;
        final key = request.uri.toString();
        final attempt = perPath.update(key, (v) => v + 1, ifAbsent: () => 1);
        final firstCooldown = attempt == 1 && scenario != 'valid title';
        if (scenario == 'permanent cooldown' || firstCooldown) {
          request.response.statusCode = scenario.startsWith('429') ? 429 : 200;
          request.response.write('<html><body>请求过于频繁</body></html>');
        } else {
          request.response.write(page(scenario == 'valid title'
              ? 'fixture 请求过于频繁 title'
              : 'fixture title'));
        }
        request.response.close();
      });
      if (scenario == 'permanent cooldown') {
        await expectLater(
            repository.fetchUserProfileDetails(overview),
            throwsA(isA<ForumRequestException>()
                .having((e) => e.kind, 'kind', ForumRequestKind.rateLimited)));
      } else {
        final result = await repository.fetchUserProfileDetails(overview);
        expect(
            result.favorites.single.title,
            scenario == 'valid title'
                ? 'fixture 请求过于频繁 title'
                : 'fixture title');
      }
      print('PROFILE_TRANSPORT scenario=$scenario requests=$count');
      expect(count, scenario == 'valid title' ? 4 : 8);
    });
  }
}
