import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/features/profile/favorite_threads_page.dart';
import 'package:south_plus_rewrite/features/profile/user_profile_screen.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

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
  final paths = <String>[];

  @override
  bool get isLoggedIn => true;

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    final client = _CountedClient();
    final repository = ForumRepository(client: client);
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
