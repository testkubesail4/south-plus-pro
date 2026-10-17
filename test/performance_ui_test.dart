import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/local_database.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

import 'support/native_favorite_fixture.dart';

const _profile = UserProfile(
  uid: '123',
  name: 'fixture-header',
  url: 'u.php?action-show-uid-123.html',
);

class _CachedRepository extends ForumRepository {
  final refresh = Completer<UserProfile>();
  final detailsUids = <String>[];

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async => _profile;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) => refresh.future;

  @override
  Future<UserProfile> fetchUserProfileDetails(UserProfile overview,
      {bool forceReload = false}) async {
    detailsUids.add(overview.uid);
    return overview;
  }
}

class _CountedClient extends ForumClient {
  _CountedClient({this.favoritesResponse});

  final String? favoritesResponse;
  final paths = <String>[];

  @override
  bool get isLoggedIn => true;

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    requireCurrentSession?.call();
    if (path != 'u.php?action=favor')
      throw StateError('Unexpected collection read: $path');
    paths.add(path);
    return nativeFavoriteHtml(
        categories: [], rows: [(id: '456', tid: '456', category: '')]);
  }

  @override
  Future<String> get(String path) async {
    paths.add(path);
    if (path == 'u.php') {
      return '<a href="u.php?action-show-uid-123.html">fixture</a>';
    }
    if (path.contains('action-show')) {
      return '<div id="u-top"><h1 class="u-h1">fixture-header</h1></div>';
    }
    if (path.contains('action-favor')) {
      return favoritesResponse ??
          '<table class="u-table"><tr><td>'
              '<a href="read.php?tid-456.html">fixture-favorite</a>'
              '</td></tr></table>';
    }
    throw StateError('Favorites must not depend on unrelated profile tabs');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in {
    '请先登录': ForumRequestKind.loginRequired,
    '没有权限': ForumRequestKind.forbidden,
    '请求过于频繁': ForumRequestKind.rateLimited,
  }.entries) {
    test('favorites preserves ${entry.value.name} response errors', () async {
      final db = LocalDatabase.openForTesting();
      addTearDown(db.close);
      final client =
          _CountedClient(favoritesResponse: '<body>${entry.key}</body>');
      final repository = ForumRepository(
        client: client,
        profileCache: UserProfileCache(databaseProvider: () async => db),
      );
      await expectLater(
        repository.fetchUserProfileFavorites('u.php'),
        throwsA(isA<ForumRequestException>().having(
          (error) => error.kind,
          'kind',
          entry.value,
        )),
      );
      expect(
          client.paths,
          hasLength(
            entry.value == ForumRequestKind.rateLimited ? 4 : 3,
          ));
    });
  }

  test('valid empty favorites remains empty', () async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final repository = ForumRepository(
      client:
          _CountedClient(favoritesResponse: '<table class="u-table"></table>'),
      profileCache: UserProfileCache(databaseProvider: () async => db),
    );
    expect((await repository.fetchUserProfileFavorites('u.php')).favorites,
        isEmpty);
  });

  test('favorites preserves a trusted title containing error-page phrases',
      () async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final repository = ForumRepository(
      client: _CountedClient(
          favoritesResponse: '<table class="u-table"><tr><td>'
              '<a href="read.php?tid-456.html">fixture 没有权限 请先登录 请求过于频繁</a>'
              '</td></tr></table>'),
      profileCache: UserProfileCache(databaseProvider: () async => db),
    );
    final result = await repository.fetchUserProfileFavorites('u.php');
    expect(result.favorites.single.title, 'fixture 没有权限 请先登录 请求过于频繁');
  });

  for (final uid in ['123', '789']) {
    testWidgets('cached profile revalidation loads details once per uid ($uid)',
        (tester) async {
      final repository = _CachedRepository();
      await tester.pumpWidget(MaterialApp(
        home: UserProfileScreen(
          userUrl: _profile.url,
          repository: repository,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('fixture-header'), findsWidgets);
      expect(repository.detailsUids, ['123']);

      repository.refresh.complete(
        _profile.copyWith(uid: uid, name: 'fresh-header'),
      );
      await tester.pumpAndSettle();
      expect(find.text('fresh-header'), findsWidgets);
      expect(repository.detailsUids, uid == '123' ? ['123'] : ['123', '789']);
    });
  }

  testWidgets('favorites only loads relevant pages and retains them on back',
      (tester) async {
    final db = LocalDatabase.openForTesting();
    addTearDown(db.close);
    final client = _CountedClient();
    final repository = ForumRepository(
      client: client,
      profileCache: UserProfileCache(databaseProvider: () async => db),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FavoriteThreadsPage(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic 456'), findsOneWidget);
    expect(find.text('已加载 1 个主题'), findsOneWidget);
    expect(find.textContaining('fixture-header'), findsNothing,
        reason: 'no account header card');
    expect(client.paths, ['u.php?action=favor'],
        reason:
            'one native read-only collection page, no unrelated account tabs');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('fixture-next-route')),
    )));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Synthetic 456'), findsOneWidget);
    expect(client.paths, hasLength(1),
        reason: 'back retains the loaded collection snapshot');

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(client.paths, hasLength(2),
        reason: 'explicit refresh fetches one fresh native collection page');
    expect(find.text('Synthetic 456'), findsOneWidget);
  });
}
