import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

const _overview = UserProfile(uid: '123', name: 'fixture-old', url: 'u.php');

class _DetailsClient extends ForumClient {
  final paths = <String>[];
  final gates = <String, Completer<void>>{};
  String? blockedTab;
  String? blockedResponse;
  bool failTransport = false;
  String mutationResponse = '操作完成 发表成功';

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    final response = await get(path);
    requireCurrentSession?.call();
    return response;
  }

  @override
  Future<String> get(String path) async {
    paths.add(path);
    if (failTransport) {
      throw const ForumRequestException(
          ForumRequestKind.network, 'fixture offline');
    }
    for (final entry in gates.entries) {
      if (path.contains('uid-${entry.key}.html')) await entry.value.future;
    }
    if (blockedTab != null && path.contains(blockedTab!)) {
      return blockedResponse!;
    }
    if (path.startsWith('post.php') || path.startsWith('read.php')) {
      return '<form name="FORM" action="post.php"><input name="verify" value="fixture"></form>';
    }
    if (path.startsWith('pw_ajax.php')) return mutationResponse;
    if (path.startsWith('job.php')) return mutationResponse;
    if (path.contains('action-topic')) return _table('fixture-topic');
    if (path.contains('action-post')) return _table('fixture-post');
    if (path.contains('action-favor')) return _table('fixture-favorite');
    return '<div class="u-box-wrap"><a href="read.php?tid-456.html">fixture-activity</a></div>'
        '<div class="u-box-wrap"><a href="job.php?action-topost-tid-456.html">fixture-reply</a></div>';
  }

  String _table(String title) => '<table class="u-table"><tr><td>'
      '<a href="read.php?tid-456.html">$title</a></td></tr></table>';

  @override
  Future<String> post(String path, Map<String, String> form) async =>
      mutationResponse;

  @override
  Future<void> clearSession() async {}
}

class _CachedOverviewRepository extends ForumRepository {
  _CachedOverviewRepository(ForumClient client) : super(client: client);

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => _overview;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async => _overview;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reopening the recent profile reuses details with the fresh overview',
      () async {
    final client = _DetailsClient();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    await repository.fetchUserProfileDetails(_overview);
    expect(client.paths, hasLength(4));
    final result = await repository.fetchUserProfileDetails(
      _overview.copyWith(name: 'fixture-fresh'),
    );
    expect(client.paths, hasLength(4));
    expect(result.name, 'fixture-fresh');
    expect(result.homeActivities.map((item) => item.title),
        ['fixture-activity', 'fixture-reply']);
    expect(result.homeReplies.single.title, 'fixture-reply');
    expect(result.topics.single.title, 'fixture-topic');
    expect(result.posts.single.title, 'fixture-post');
    expect(result.favorites.single.title, 'fixture-favorite');
  });

  testWidgets(
      'warm profile paints details with its first cached overview frame',
      (tester) async {
    final client = _DetailsClient();
    final repository = _CachedOverviewRepository(client);
    await repository.fetchUserProfileDetails(_overview);
    final gate = Completer<void>();
    client.gates['123'] = gate;
    try {
      await tester.pumpWidget(MaterialApp(
          home: UserProfileScreen(
        userUrl: _overview.url,
        repository: repository,
      )));
      await tester.pump();
      expect(find.text('fixture-activity'), findsOneWidget);
      expect(client.paths, hasLength(4),
          reason: 'warm paint must not await new GETs');
    } finally {
      gate.complete();
      await repository.clearSession();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('concurrent same UID requests share one bundle', () async {
    final client = _DetailsClient()..gates['123'] = Completer<void>();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    final first = repository.fetchUserProfileDetails(_overview);
    final second = repository.fetchUserProfileDetails(_overview);
    expect(client.paths, hasLength(4));
    client.gates['123']!.complete();
    expect((await first).favorites.single.title, 'fixture-favorite');
    await second;
    expect(client.paths, hasLength(4));
  });

  test('replacing the recent UID does not invalidate a valid pending caller',
      () async {
    final client = _DetailsClient()..gates['123'] = Completer<void>();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    final first = repository.fetchUserProfileDetails(_overview);
    await repository.fetchUserProfileDetails(_overview.copyWith(uid: '789'));
    client.gates['123']!.complete();
    expect((await first).uid, '123');
    await repository.fetchUserProfileDetails(_overview.copyWith(uid: '789'));
    expect(client.paths, hasLength(8), reason: 'A completion must not evict B');
    await repository.fetchUserProfileDetails(_overview);
    expect(client.paths, hasLength(12),
        reason: 'only one recent UID is retained');
  });

  test('explicit refresh bypasses successful details', () async {
    final client = _DetailsClient();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    await repository.fetchUserProfileDetails(_overview);
    await repository.fetchUserProfileDetails(_overview, forceReload: true);
    expect(client.paths, hasLength(8));
  });

  testWidgets('details expire 60 seconds after success, not request start',
      (tester) async {
    final client = _DetailsClient()..gates['123'] = Completer<void>();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    final pending = repository.fetchUserProfileDetails(_overview);
    await tester.pump(const Duration(seconds: 61));
    client.gates['123']!.complete();
    await pending;
    await repository.fetchUserProfileDetails(_overview);
    expect(client.paths, hasLength(4));
    await tester.pump(const Duration(seconds: 59));
    await repository.fetchUserProfileDetails(_overview);
    expect(client.paths, hasLength(4));
    await tester.pump(const Duration(seconds: 1));
    await repository.fetchUserProfileDetails(_overview);
    expect(client.paths, hasLength(8));
    await repository.clearSession();
  });

  testWidgets('TTL eviction does not reject another valid pending UID',
      (tester) async {
    final client = _DetailsClient()..gates['123'] = Completer<void>();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    final pending = repository.fetchUserProfileDetails(_overview);
    await repository.fetchUserProfileDetails(_overview.copyWith(uid: '789'));
    await tester.pump(const Duration(seconds: 60));
    client.gates['123']!.complete();
    expect((await pending).uid, '123');
  });

  test('transport failures are not cached', () async {
    final client = _DetailsClient()..failTransport = true;
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    await expectLater(
        repository.fetchUserProfileDetails(_overview),
        throwsA(isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          ForumRequestKind.network,
        )));
    client.failTransport = false;
    expect(
        (await repository.fetchUserProfileDetails(_overview))
            .favorites
            .single
            .title,
        'fixture-favorite');
    expect(client.paths, hasLength(8));
  });

  for (final tab in ['?uid-', 'action-topic', 'action-post', 'action-favor']) {
    for (final failure in {
      '请先登录': ForumRequestKind.loginRequired,
      '没有权限': ForumRequestKind.forbidden,
      '请求过于频繁': ForumRequestKind.rateLimited,
    }.entries) {
      test('$tab ${failure.value.name} pages fail and are not cached',
          () async {
        final client = _DetailsClient()
          ..blockedTab = tab
          ..blockedResponse = '<body>${failure.key}</body>';
        final repository = ForumRepository(client: client);
        addTearDown(repository.clearSession);
        await expectLater(
          repository.fetchUserProfileDetails(_overview),
          throwsA(isA<ForumRequestException>().having(
            (error) => error.kind,
            'kind',
            failure.value,
          )),
        );
        client.blockedTab = null;
        expect(
            (await repository.fetchUserProfileDetails(_overview))
                .favorites
                .single
                .title,
            'fixture-favorite');
        expect(
            client.paths,
            hasLength(
              failure.value == ForumRequestKind.rateLimited ? 9 : 8,
            ));
      });
    }
  }

  for (final phrase in ['没有权限', '请先登录', '请求过于频繁']) {
    test('trusted thread title containing $phrase stays data', () async {
      final client = _DetailsClient()
        ..blockedTab = 'action-'
        ..blockedResponse = '<table class="u-table"><tr><td>'
            '<a href="read.php?tid-456.html">fixture <b>$phrase</b> title</a>'
            '</td></tr></table>';
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      final result = await repository.fetchUserProfileDetails(_overview);
      expect(result.topics.single.title, 'fixture $phrase title');
      expect(result.posts.single.title, 'fixture $phrase title');
      expect(result.favorites.single.title, 'fixture $phrase title');
    });
  }

  test('trusted home activity and reply titles keep their original markup text',
      () async {
    final client = _DetailsClient()
      ..blockedTab = '?uid-'
      ..blockedResponse = '<div class="u-box-wrap">'
          '<a href="read.php?tid-456.html"><b>没有权限</b> fixture activity</a>'
          '</div><div class="u-box-wrap">'
          '<a href="job.php?action-topost-tid-456-pid-789.html">请先登录 fixture reply</a>'
          '</div>';
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    final result = await repository.fetchUserProfileDetails(_overview);
    expect(result.homeActivities.first.title, '没有权限 fixture activity');
    expect(result.homeReplies.single.title, '请先登录 fixture reply');
  });

  for (final warning in [
    '<div>没有权限</div><table class="u-table"><tr><td>'
        '<a href="read.php?tid-456.html">fixture title</a></td></tr></table>',
    '<table class="u-table"><tr><td>没有权限 '
        '<a href="read.php?tid-456.html">fixture title</a></td></tr></table>',
    '<table class="u-table"><tr><td>没有权限</td></tr></table>',
    '<table class="u-table"><tr><td>'
        '<a href="https://outside.invalid/read.php?tid-456.html">没有权限</a>'
        '</td></tr></table>',
    '<table class="u-table"><tr><td>'
        '<a href="read.php?tid-bad.html">没有权限</a></td></tr></table>',
    '<table class="u-table"><tr><td>'
        '<a href="u.php?uid-123.html">没有权限</a></td></tr></table>',
    '<div class="u-box-wrap"><a href="job.php?action-topost-tid-456.html">没有权限</a></div>',
  ]) {
    test('warning outside a trusted title stays blocked (${warning.length})',
        () async {
      final client = _DetailsClient()
        ..blockedTab = 'action-topic'
        ..blockedResponse = warning;
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      await expectLater(
          repository.fetchUserProfileDetails(_overview),
          throwsA(isA<ForumRequestException>().having(
            (error) => error.kind,
            'kind',
            ForumRequestKind.forbidden,
          )));
      client.blockedTab = null;
      expect(
          (await repository.fetchUserProfileDetails(_overview))
              .topics
              .single
              .title,
          'fixture-topic');
      expect(client.paths, hasLength(8),
          reason: 'blocked data is never cached');
    });
  }

  for (final change in ['session', 'site']) {
    test('$change invalidation drops a pending old-scope result', () async {
      final client = _DetailsClient()..gates['123'] = Completer<void>();
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      final pending = repository.fetchUserProfileDetails(_overview);
      final rejected =
          expectLater(pending, throwsA(isA<ForumRequestException>()));
      if (change == 'session') {
        await repository.clearSession();
      } else {
        await repository.updateNetworkConfig(repository.networkConfig.copyWith(
          site: const ForumSite('blue-plus.net'),
        ));
      }
      client.gates['123']!.complete();
      await rejected;
      if (change == 'session') {
        await repository.fetchUserProfileDetails(_overview);
        expect(client.paths, hasLength(8));
      }
    });
  }

  for (final mutation in ['favorite', 'remove', 'reply', 'topic', 'purchase']) {
    test('successful $mutation invalidates reused and pending profile data',
        () async {
      final client = _DetailsClient();
      final repository = ForumRepository(client: client);
      addTearDown(repository.clearSession);
      await repository.fetchUserProfileDetails(_overview);
      const favorite = ThreadFavorite(tid: '456', verify: 'fixture');
      Future<void> write() async {
        switch (mutation) {
          case 'favorite':
            client.mutationResponse = '收藏成功';
            expect((await repository.addFavorite(favorite)).success, isTrue);
          case 'remove':
            client.mutationResponse = '操作完成';
            expect((await repository.removeFavorite(favorite)).success, isTrue);
          case 'reply':
            client.mutationResponse = '发表成功';
            expect(
                (await repository.submitReply(
                  thread: const ForumThread(
                      title: 'fixture',
                      url: 'read.php?tid-456.html',
                      replies: 0,
                      section: 'fixture'),
                  title: 'fixture reply title',
                  content: 'fixture reply',
                ))
                    .success,
                isTrue);
          case 'topic':
            client.mutationResponse = '发表成功';
            expect(
                (await repository.submitThread(
                  category: const ForumCategory(
                      name: 'fixture', slug: '9', url: 'thread.php?fid-9.html'),
                  title: 'fixture title',
                  content: 'fixture topic',
                ))
                    .success,
                isTrue);
          case 'purchase':
            client.mutationResponse = '购买成功';
            expect(
                (await repository.buySaleBox(
                  const ThreadSaleBox(
                      summary: 'fixture',
                      buyPath:
                          'job.php?action=buytopic&tid=456&pid=tpc&verify=fixture'),
                ))
                    .success,
                isTrue);
        }
      }

      await write();
      final before = client.paths.length;
      await repository.fetchUserProfileDetails(_overview);
      expect(client.paths.length - before, 4);
      client.gates['123'] = Completer<void>();
      final pending =
          repository.fetchUserProfileDetails(_overview, forceReload: true);
      final rejected =
          expectLater(pending, throwsA(isA<ForumRequestException>()));
      await write();
      client.gates['123']!.complete();
      await rejected;
    });
  }
}
