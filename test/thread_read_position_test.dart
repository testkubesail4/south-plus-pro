import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/browsing_history_store.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

const _thread = ForumThread(
    title: 'Fixture thread',
    url: 'read.php?tid-123-uid-42-page-2.html#99',
    replies: 90,
    section: 'Fixture board');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'first/latest URLs keep author filter and page-e survives default page argument',
      () async {
    final client = _ThreadClient();
    final repository =
        ForumRepository(client: client, historyStore: _History());
    expect(repository.firstThreadPageUrl(_thread),
        'https://south-plus.net/read.php?tid-123-uid-42-page-1.html#tpc');
    final latest =
        _thread.copyWith(url: repository.latestThreadPageUrl(_thread)!);
    expect(latest.url,
        'https://south-plus.net/read.php?tid-123-uid-42-page-e.html');
    final detail = await repository.fetchThreadDetail(latest, page: 1);
    expect(client.paths.first, 'read.php?tid-123-uid-42-page-e.html');
    expect(detail.pagination.currentPage, 4);
    expect(detail.pagination.totalPages, 4);
    expect(detail.replies.single.anchors, contains('991'));
    final latestRequest = client.paths.length;
    await repository.fetchThreadDetail(latest,
        page: detail.pagination.currentPage + 1);
    expect(client.paths[latestRequest],
        'read.php?tid-123-uid-42-fpage-0-toread--page-5.html');
    final firstRequest = client.paths.length;
    await repository.fetchThreadDetail(
        _thread.copyWith(url: repository.firstThreadPageUrl(_thread)!));
    expect(client.paths[firstRequest], 'read.php?tid-123-uid-42-page-1.html');
  });

  test(
      'positions persist across repository recreation and mirror/page aliases but not filters',
      () async {
    final repository = ForumRepository();
    await repository.saveThreadReadPosition(
        _thread, const ThreadReadPosition(page: 4, anchor: '#991'));
    final recreated = ForumRepository();
    final alias = _thread.copyWith(
        url: 'https://blue-plus.net/read.php?tid=123&uid=42&page=1');
    final position = await recreated.loadThreadReadPosition(alias);
    expect(position!.page, 4);
    expect(position.anchor, '991');
    expect(
        await recreated.loadThreadReadPosition(
            _thread.copyWith(url: 'read.php?tid-123.html')),
        isNull);
    await recreated.saveThreadReadPosition(
        _thread, const ThreadReadPosition(page: 1, anchor: 'tpc'));
    expect((await recreated.loadThreadReadPosition(_thread))!.anchor, 'tpc');
  });

  test('position storage is bounded and clearing history clears positions',
      () async {
    final repository = ForumRepository(historyStore: _History());
    for (var tid = 1; tid <= 501; tid++) {
      await repository.saveThreadReadPosition(
          _thread.copyWith(url: 'read.php?tid-$tid.html'),
          const ThreadReadPosition(page: 2));
    }
    expect(
        await repository.loadThreadReadPosition(
            _thread.copyWith(url: 'read.php?tid-1.html')),
        isNull);
    expect(
        (await repository.loadThreadReadPosition(
                _thread.copyWith(url: 'read.php?tid-501.html')))!
            .page,
        2);
    await repository.clearBrowsingHistory();
    expect(
        await repository.loadThreadReadPosition(
            _thread.copyWith(url: 'read.php?tid-501.html')),
        isNull);
  });

  test('malformed saved data is ignored and can be replaced', () async {
    for (final raw in ['not json', '{"123:42":{"page":"bad"}}']) {
      SharedPreferences.setMockInitialValues({'thread_read_positions_v1': raw});
      final repository = ForumRepository();
      expect(await repository.loadThreadReadPosition(_thread), isNull);
      await repository.saveThreadReadPosition(
          _thread, const ThreadReadPosition(page: 3));
      expect((await repository.loadThreadReadPosition(_thread))!.page, 3);
    }
  });

  test('invalid positions cannot replace a valid position', () async {
    final repository = ForumRepository();
    await repository.saveThreadReadPosition(
        _thread, const ThreadReadPosition(page: 2, anchor: '991'));
    for (final invalid in [
      const ThreadReadPosition(page: 0),
      const ThreadReadPosition(page: 2, anchor: 'javascript:bad')
    ]) {
      await expectLater(repository.saveThreadReadPosition(_thread, invalid),
          throwsArgumentError);
    }
    expect((await repository.loadThreadReadPosition(_thread))!.page, 2);
  });
}

class _History extends BrowsingHistoryStore {
  @override
  Future<void> recordThread(ForumThread thread, {DateTime? viewedAt}) async {}
  @override
  Future<void> clear() async {}
}

class _ThreadClient extends ForumClient {
  final paths = <String>[];
  @override
  Future<String> get(String path) async {
    paths.add(path);
    return '<div class="pages">Pages: 4/4</div><form><a name="991"></a>'
        '<table class="js-post"><tr><th class="r_two">'
        '<a href="u.php?action-show-uid-42.html"><strong>Fixture author</strong></a>'
        '</th><th class="r_one" id="td_991"><div class="tiptop"><span class="fl">'
        '<a class="s3">B91F</a></span></div><div class="tpc_content">'
        '<div id="read_991">Fixture post</div></div></th></tr></table></form>';
  }
}
