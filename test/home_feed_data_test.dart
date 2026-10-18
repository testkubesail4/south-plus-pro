import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/parsers/home_page_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('quick feeds preserve every row with its own metadata', () {
    for (final simple in [true, false]) {
      final threads =
          HomePageParser().parseLatestThreadsFromScript(_feed(simple: simple));
      expect(threads, hasLength(8));
      for (var i = 0; i < 8; i++) {
        final thread = threads[i];
        expect(thread.title, 'Synthetic topic $i');
        expect(thread.author, 'Synthetic author $i');
        expect(thread.authorUid, '${901 + i}');
        expect(thread.section, 'Synthetic board $i');
        expect(thread.replies, i * 7);
        expect(thread.lastPost, '2026-01-01 12:0$i');
      }
    }
  });

  test('inline lists are not truncated and do not invent absent metadata', () {
    final links = List.generate(
            5,
            (i) =>
                '<li><a href="/simple/index.php?t${701 + i}.html">Synthetic $i</a></li>')
        .join();
    final threads = HomePageParser().parseLatestThreads(html.parse(links));
    expect(threads, hasLength(5));
    expect(threads.first.author, isNull);
    expect(threads.first.section, isEmpty);
    expect(threads.first.lastPost, isNull);
  });

  test('inline preview survives a feed request failure', () async {
    final repository =
        ForumRepository(client: _FeedClient()..failScript = true);
    final home = await repository.fetchHome();
    expect(home.latest, hasLength(3));
    expect(home.latest.first.title, 'Preview 0');
  });

  test(
      'lazy expanded-feed failures retain inline previews only in their session',
      () async {
    final client = _FeedClient();
    final repository = ForumRepository(client: client);
    final home = await repository.fetchHome();
    client.failScript = true;
    final fallbacks = await Future.wait([
      repository.fetchQuickList(home.quickLists[1]),
      repository.fetchQuickList(home.quickLists[1]),
    ]);
    for (final fallback in fallbacks) {
      expect(fallback, hasLength(3));
      expect(fallback.first.title, 'Preview 0');
    }

    client.failScript = false;
    client.pendingScript = Completer<String>();
    final fresh = await repository.fetchHome();
    final pending = repository.fetchQuickList(fresh.quickLists[1]);
    await repository.clearSession();
    final assertion = expectLater(pending, throwsException);
    client.pendingScript!.complete(_feed());
    await assertion;
  });

  test('active and lazy tabs request eight longer titles and metadata',
      () async {
    final client = _FeedClient();
    final repository = ForumRepository(client: client);
    final home = await repository.fetchHome();
    expect(home.latest, hasLength(8), reason: 'inline preview has only 3 rows');
    expect(home.latest.first.authorUid, '901');
    final lazy = home.quickLists[1];
    expect(lazy.threads, isNull);
    expect(await repository.fetchQuickList(lazy), hasLength(8));
    expect(await repository.fetchQuickList(home.quickLists[2]), hasLength(8));
    expect(client.scripts, hasLength(3));
    for (final script in client.scripts) {
      final query = Uri.parse(script).queryParameters;
      expect(query['num'], '8');
      expect(query['length'], '120');
      expect(query['simple'], '1');
      for (final field in ['postdate', 'author', 'replies', 'fname']) {
        expect(query[field], '1');
      }
    }
    expect(Uri.parse(client.scripts.last).queryParameters['fidin'], '44');
  });
}

String _feed({bool simple = true}) => List.generate(8, (i) {
      final href = simple
          ? '/simple/index.php?t${701 + i}.html'
          : '//blue-plus.net/read.php?tid=${701 + i}';
      return '''document.write("● <a href='$href' target='_blank'>Synthetic topic $i</a> <font color='#666666'>(2026-01-01 12:0$i)</font> <a href='//blue-plus.net/u.php?action=show&uid=${901 + i}'><font>(Synthetic author $i)</font></a> <font>(回复：${i * 7})</font></a> <a href='//blue-plus.net/thread.php?fid=${801 + i}'><font>(Synthetic board $i)</font></a><br>");''';
    }).join('\n');

class _FeedClient extends ForumClient {
  final scripts = <String>[];
  bool failScript = false;
  Completer<String>? pendingScript;

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
      scripts.add(path);
      if (failScript) throw const ForumRepositoryException('Synthetic failure');
      if (path.contains('order=1') && pendingScript != null) {
        return pendingScript!.future;
      }
      return _feed();
    }
    if (path == 'index.php') return '';
    final inline = List.generate(
            3,
            (i) =>
                '<a href="/simple/index.php?t${701 + i}.html">Preview $i</a>')
        .join();
    return '''<head><base href="/"></head><body>
      <div class="carousel-item active"><div>最新讨论</div>$inline
        <script src="new.php?action=article&amp;num=3&amp;order=2&amp;simple=1"></script></div>
      <div class="carousel-item"><div>最新回复</div>$inline
        <script src="new.php?action=article&amp;num=3&amp;order=1&amp;simple=1"></script></div>
      <div class="carousel-item"><div>提问求物</div>
        <script src="new.php?action=article&amp;fidin=44&amp;num=3&amp;simple=1"></script></div>
      <table><tr><th><h2>Synthetic section</h2></th></tr><tr><th>
        <h3><a href="thread.php?fid-801.html">Synthetic board</a></h3>
      </th></tr></table></body>''';
  }
}
