import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

const _thread = ForumThread(
    title: 'Thread',
    url: 'read.php?tid-3002979.html',
    replies: 31,
    section: '');

ThreadDetail _loaded(int page,
        {int total = 2, int? floor, String? url, ThreadFavorite? favorite}) =>
    ThreadDetail(
        thread: url == null ? _thread : _thread.copyWith(url: url),
        favorite: favorite,
        body: '',
        replies: [
          if (floor != null)
            ThreadReply(
                author: 'Author',
                content: 'Body',
                floor: 'B${floor}F',
                anchors: ['fl-$floor'])
        ],
        pagination: ThreadPagination(currentPage: page, totalPages: total));

String _page(int page, List<int> floors,
        {String tid = '3002979', int total = 2}) =>
    '''
<a href="read.php?tid-$tid.html">Thread</a><div class="pages">Pages: $page/$total</div>
${floors.map((floor) => '''<table class="js-post"><tr>
<th class="r_two"><a href="u.php?action-show-uid-1.html">Author</a></th>
<th class="r_one" id="td_${1000 + floor}"><div class="tiptop"><span class="fl"><a class="s3">B${floor}F</a></span></div>
<div class="tpc_content"><div id="read_${1000 + floor}">Body</div></div></th></tr></table>''').join()}
''';

class _FloorClient extends ForumClient {
  final paths = <String>[];
  final responses = <String>[];
  Object? failure;
  Completer<void>? barrier;
  final entered = Completer<void>();

  @override
  Future<String> getOnceGuarded(String path,
      {required void Function() requireCurrentSession,
      ForumReadRedirectPolicy redirectPolicy =
          ForumReadRedirectPolicy.none}) async {
    requireCurrentSession();
    paths.add(path);
    if (!entered.isCompleted) entered.complete();
    await barrier?.future;
    requireCurrentSession();
    if (failure != null) throw failure!;
    return responses.removeAt(0);
  }

  @override
  Future<void> clearSession() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loaded native floor wins without any request, unrelated pages ignored',
      () async {
    final client = _FloorClient();
    final wanted = _loaded(1, floor: 28);
    final found = await ForumRepository(client: client).findThreadFloor(
        _thread, 28, loaded: [
      _loaded(1, floor: 28, url: 'read.php?tid-9.html'),
      wanted,
      _loaded(2, floor: 31)
    ]);
    expect(found, same(wanted));
    expect(client.paths, isEmpty);
  });

  test('B31 to B28 and B41 to B2 cross-page references resolve exact floor',
      () async {
    for (final (currentFloor, target) in [(31, 28), (41, 2)]) {
      final client = _FloorClient()
        ..responses.add(_page(1, [target - 1, target, target + 1]));
      final found = await ForumRepository(client: client)
          .findThreadFloor(_thread, target, loaded: [
        _loaded(2,
            floor: currentFloor,
            favorite: const ThreadFavorite(
                tid: '3002979',
                verify: 'fixture',
                state: ThreadFavoriteState.favorite))
      ]);
      expect(found?.pagination.currentPage, 1);
      expect(found?.favorite?.state, ThreadFavoriteState.favorite);
      expect(
          found?.replies
              .where((reply) => reply.floor == 'B${target}F')
              .single
              .anchors,
          contains('fl-$target'));
      expect(client.paths, ['read.php?tid-3002979.html']);
    }
  });

  test(
      'variable page size is discovered from native pages instead of floor arithmetic',
      () async {
    final client = _FloorClient()..responses.add(_page(2, [17, 28], total: 3));
    final found = await ForumRepository(client: client).findThreadFloor(
        _thread, 28, loaded: [
      _loaded(1, total: 3, floor: 1),
      _loaded(3, total: 3, floor: 31)
    ]);
    expect(found?.pagination.currentPage, 2);
    expect(client.paths, ['read.php?tid-3002979-fpage-0-toread--page-2.html']);
  });

  test('deleted and author-filtered targets return missing, never a neighbor',
      () async {
    for (final filtered in [false, true]) {
      final source = filtered
          ? _thread.copyWith(url: 'read.php?tid-3002979-uid-2.html')
          : _thread;
      final client = _FloorClient()
        ..responses.add(_page(1, filtered ? [27, 28, 29] : [27, 29]));
      final found = await ForumRepository(client: client).findThreadFloor(
          source, 28,
          loaded: [_loaded(2, floor: 31, url: source.url)]);
      expect(found, isNull);
      expect(
          client.paths.single,
          filtered
              ? 'read.php?tid-3002979-uid-2.html'
              : 'read.php?tid-3002979.html');
    }
  });

  test('wrong thread and server fallback page cannot masquerade as success',
      () async {
    for (final html in [
      _page(1, [28], tid: '9'),
      _page(2, [28])
    ]) {
      final client = _FloorClient()..responses.add(html);
      await expectLater(
          ForumRepository(client: client)
              .findThreadFloor(_thread, 28, loaded: [_loaded(2, floor: 31)]),
          throwsA(isA<ForumRequestException>()));
      expect(client.paths, hasLength(1));
    }
  });

  test(
      'rate limit and network errors stop immediately and preserve classification',
      () async {
    for (final kind in [
      ForumRequestKind.network,
      ForumRequestKind.rateLimited
    ]) {
      final failure = ForumRequestException(kind, 'fixture');
      final client = _FloorClient()..failure = failure;
      await expectLater(
          ForumRepository(client: client)
              .findThreadFloor(_thread, 28, loaded: [_loaded(2, floor: 31)]),
          throwsA(same(failure)));
      expect(client.paths, hasLength(1));
    }
  });

  test(
      'route or account changes discard the in-flight page and stop further requests',
      () async {
    for (final accountChange in [false, true]) {
      final client = _FloorClient()..barrier = Completer<void>();
      final repository = ForumRepository(client: client);
      var current = true;
      final pending = repository.findThreadFloor(_thread, 28,
          loaded: [_loaded(2, floor: 31)], isCurrent: () => current);
      await client.entered.future;
      if (accountChange) {
        await repository.clearSession();
      } else {
        current = false;
      }
      client.barrier!.complete();
      await expectLater(pending, throwsA(isA<ForumRepositoryException>()));
      expect(client.paths, hasLength(1));
    }
  });

  test('large threads stop after twenty new page requests', () async {
    final client = _FloorClient()
      ..responses.addAll([
        for (var p = 1; p <= 20; p++) _page(p, [p], total: 100)
      ]);
    await expectLater(
        ForumRepository(client: client).findThreadFloor(_thread, 28,
            loaded: [_loaded(100, total: 100, floor: 100)]),
        throwsA(isA<ForumRequestException>()
            .having((error) => error.message, 'message', contains('20'))));
    expect(client.paths, hasLength(20));
  });
}
