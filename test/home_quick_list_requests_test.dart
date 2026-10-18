import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/home/home_shell.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'home loads the two other quick lists once after it shows, '
      'and again only on refresh', (tester) async {
    final client = _HomeClient();
    await tester.pumpWidget(MaterialApp(
      home: HomeShell(repository: ForumRepository(client: client)),
    ));
    expect(client.deferred, isEmpty, reason: 'nothing before home shows');

    await tester.pumpAndSettle();
    expect(find.text('Fixture topic'), findsWidgets);
    expect(client.deferred, hasLength(2));
    expect(client.deferred.toSet(), hasLength(2), reason: 'one GET per list');
    expect(find.text('点按加载'), findsNothing);

    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(client.deferred, hasLength(4), reason: 'two more per home load');
  });
}

/// Counts the quick-list script GETs that the home page did not embed.
class _HomeClient extends ForumClient {
  final deferred = <String>[];

  @override
  Future<void> clearSession() async {}

  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy =
          ForumReadRedirectPolicy.none}) async {
    requireCurrentSession();
    final response = await get(path);
    requireCurrentSession();
    return response;
  }

  @override
  Future<String> get(String path) async {
    if (path.contains('new.php')) {
      if (!path.contains('order=2')) deferred.add(path);
      return 'document.write("<li><a href=\'/simple/index.php?t123.html\'>Fixture topic</a></li>");';
    }
    if (path == 'index.php') return '';
    return '<head><base href="/"></head><body>'
        '<div class="carousel-item active"><div>最新讨论</div>'
        '<ul><script src="./new.php?action=article&amp;num=3&amp;order=2&amp;simple=1"></script></ul></div>'
        '<div class="carousel-item"><div>最新回复</div>'
        '<ul><script src="./new.php?action=article&amp;num=3&amp;order=1&amp;simple=1"></script></ul></div>'
        '<div class="carousel-item"><div>提问求物</div>'
        '<ul><script src="./new.php?action=article&amp;fidin=44&amp;num=3&amp;simple=1"></script></ul></div>'
        '<table><tr><th><h2>Fixture section</h2></th></tr><tr><th>'
        '<h3><a href="thread.php?fid-42.html">Fixture board</a></h3>'
        '</th><td>1 / 2</td></tr></table></body>';
  }
}
