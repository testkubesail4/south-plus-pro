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

  test('desktop boards expose today count, last post and exact new-post icon',
      () {
    for (final icon in ['new.gif', 'old.gif']) {
      final sections = HomePageParser().parseDesktopForumSections(html.parse('''
<table><tr><th><h2>Fixture section</h2></th></tr><tr id="fid_42">
<td class="icon"><img src="images/theme/$icon"></td><th>
<h3><a id="fn_42" href="thread.php?fid-42.html">Fixture board</a></h3>
<span class="s3 f10">(12)</span><span id="desc_42">Fixture description</span>
<div>子版：<h3><a href="thread.php?fid-43.html">Fixture child</a></h3></div></th>
<td class="y-style">200 / 800</td><th><a class="a2" href="read.php?tid-123-page-e.html#a">Fixture last post</a>
<span class="gray2"><span class="f9">[2026-01-01 12:30]</span></span></th></tr></table>'''));
      final board = sections.single.items.single;
      expect(board.todayCount, 12);
      expect(board.lastPostTitle, 'Fixture last post');
      expect(board.lastPostTime, '2026-01-01 12:30');
      expect(board.hasNew, icon == 'new.gif');
      expect(board.topicCount, 200);
      expect(board.postCount, 800);
      expect(board.children.single.name, 'Fixture child');
    }
  });

  test(
      'quick lists fetch only the active script eagerly, cache lazy loads and expire on refresh',
      () async {
    final client = _HomeClient();
    final repository = ForumRepository(client: client);
    final home = await repository.fetchHome();
    expect(home.quickLists.map((list) => list.title), ['最新讨论', '最新回复', '提问求物']);
    expect(home.quickLists.first.threads!.single.title, 'Fixture topic');
    expect(home.quickLists[1].threads, isNull);
    expect(client.gets.where((path) => path.contains('new.php')), hasLength(1));
    final lazy = home.quickLists[1];
    final results = await Future.wait([
      repository.fetchQuickList(lazy),
      repository.fetchQuickList(lazy),
    ]);
    expect(results.first.single.title, 'Fixture topic');
    await repository.fetchQuickList(lazy);
    expect(client.gets.where((path) => path.contains('order=1')), hasLength(1));
    await repository.fetchHome();
    await expectLater(repository.fetchQuickList(lazy),
        throwsA(isA<ForumRepositoryException>()));
  });

  test('lazy result cannot survive logout and foreign scripts are ignored',
      () async {
    final client = _HomeClient()..pending = Completer<String>();
    final repository = ForumRepository(client: client);
    final home = await repository.fetchHome();
    final pending = repository.fetchQuickList(home.quickLists[1]);
    await repository.clearSession();
    final assertion =
        expectLater(pending, throwsA(isA<ForumRepositoryException>()));
    client.pending!.complete(
        'document.write("<a href=\'/simple/index.php?t123.html\'>Old topic</a>");');
    await assertion;
    final parser = HomePageParser();
    expect(
        parser.latestThreadsScriptUrl(html.parse(
            '<div class="carousel-item active">'
            '<script src="https://outside.invalid/new.php"></script></div>')),
        isNull);
    expect(
        parser.latestThreadsScriptUrl(
            html.parse('<body><script src="./new.php"></script></body>')),
        'https://south-plus.net/simple/new.php');
  });
}

class _HomeClient extends ForumClient {
  final gets = <String>[];
  Completer<String>? pending;
  @override
  Future<void> clearSession() async {}
  @override
  Future<String> get(String path) async {
    gets.add(path);
    if (path.contains('order=1') && pending != null) return pending!.future;
    if (path.contains('new.php')) {
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
