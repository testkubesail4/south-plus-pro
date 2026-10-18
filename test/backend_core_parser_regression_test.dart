import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_task_state_store.dart';
import 'package:south_plus_rewrite/services/home_reading_preferences.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('opening metadata propagates without borrowing last-reply time',
      () async {
    final repository = ForumRepository(client: _CoreClient('''
      <table class="js-post"><tr>
        <th class="r_two"><a href="u.php?action-show-uid-12.html"><strong>Author</strong></a></th>
        <th class="r_one">
          <div class="tiptop"><span class="fl"><span class="s3">楼主</span></span>
            <div class="fl bianji">（Opening signature）</div>
          </div>
          <div class="tpc_content" id="read_tpc">Opening body</div>
        </th>
      </tr></table>
    '''));
    final detail = await repository.fetchThreadDetail(const ForumThread(
      title: 'Synthetic thread',
      url: 'https://south-plus.net/read.php?tid-701.html',
      replies: 0,
      section: '',
      lastPost: '2026-10-17 09:00',
    ));
    expect(detail.bodyPostedAt, isNull);
    expect(detail.personalSignature, 'Opening signature');
  });

  test(
      'local preferences share official mirrors and isolate custom accounts and guests',
      () async {
    final officialScopes = <String?>[];
    for (final site in ForumNetworkConfig.sites.take(2)) {
      final repository = ForumRepository(client: _ScopeClient(site));
      expect(repository.localPreferenceAccount, isNull);
      await repository.restoreSession();
      officialScopes.add(repository.localPreferenceAccount);
    }
    expect(officialScopes, ['fixture-account', 'fixture-account']);

    final customScopes = <String?>[];
    final guestScopes = <String?>[];
    for (final host in ['first.invalid', 'second.invalid']) {
      final repository = ForumRepository(client: _ScopeClient(ForumSite(host)));
      guestScopes.add(repository.localPreferenceAccount);
      await repository.restoreSession();
      customScopes.add(repository.localPreferenceAccount);
      expect(repository.currentUsername, 'fixture-account');
    }
    expect(guestScopes.toSet(), hasLength(2));
    expect(customScopes.toSet(), hasLength(2));
    expect(guestScopes.toSet().intersection(customScopes.toSet()), isEmpty);
    expect(customScopes, isNot(contains('fixture-account')));
    await HomeReadingPreferences.saveQuickRowCount(3,
        account: guestScopes.first);
    expect(
        (await HomeReadingPreferences.load(account: guestScopes.last))
            .quickRowCount,
        8);
    expect(
        (await HomeReadingPreferences.load(account: customScopes.first))
            .quickRowCount,
        8);
    final namedAnonymous = ForumRepository(
        client:
            _ScopeClient(const ForumSite('first.invalid'), name: 'anonymous'));
    await namedAnonymous.restoreSession();
    expect(namedAnonymous.localPreferenceAccount, isNot(guestScopes.first));
  });

  test(
      'an overview predating profile invalidation cannot restore stale identity',
      () async {
    final client = _GenerationClient();
    final cache = _MemoryProfileCache();
    final repository = ForumRepository(client: client, profileCache: cache);
    await repository.restoreSession();
    final oldOverview =
        repository.fetchUserProfileOverview('u.php?action-show-uid-42.html');
    await client.profileRequested.future;
    await repository.fetchUserProfileDetails(
        const UserProfile(
          uid: '42',
          name: 'fixture-account',
          url: 'u.php?action-show-uid-42.html',
        ),
        forceReload: true);
    client.profile.complete('''
      <div id="u-top"><h1 class="u-h1">fixture-account</h1></div>
      <div id="u-profile"><table><tr><td>昵称</td><th>Stale nickname</th></tr></table></div>
    ''');
    await oldOverview;
    expect(repository.accountIdentity.value?.nickname, isNull);
    expect(cache.saved, isEmpty);
    await repository.clearSession();
  });

  test('task threshold survives reentry without becoming a countdown',
      () async {
    const store = ForumTaskStateStore();
    final snapshot = ForumTaskSnapshot(
      updatedAt: DateTime.utc(2026, 10, 17),
      tasks: const [
        ForumTaskState(
          name: '周常',
          availability: ForumTaskAvailability.completed,
          completedAt: '2026-10-11 PM:21:43:38',
          cooldownThreshold: Duration(hours: 158),
        ),
      ],
    );
    await store.save(snapshot, scope: 'https://south-plus.net:account-a');
    final restored =
        await store.load(scope: 'https://south-plus.net:account-a');
    final task = restored!.taskNamed('周常')!;
    expect(task.cooldownThreshold, const Duration(hours: 158));
    expect(task.completedAt, '2026-10-11 PM:21:43:38');
    expect(task.cooldownRemainingFrom(DateTime.utc(2026, 10, 17)), isNull);
    expect(task.nextAvailableAt, isNull);
    expect(await store.load(scope: 'https://south-plus.net:account-b'), isNull);
    expect(await store.load(scope: 'https://other.invalid:account-a'), isNull);
  });

  test('successful board reads record recent visits, failed reads do not',
      () async {
    const category = ForumCategory(name: 'Synthetic parent', slug: 'f42');
    final repository = ForumRepository(client: _CoreClient('''
      <table>
        <tr><td>子版块</td></tr>
        <tr><td>论坛</td><td>文章</td></tr>
        <tr>
          <th><h2><a href="thread.php?fid-43.html" class="fnamecolor a1">Synthetic child</a></h2></th>
          <td>0</td><td>0</td>
        </tr>
      </table>
    '''));
    await repository.fetchBoardThreadPage(category);
    final recent = (await HomeReadingPreferences.load()).recentBoards;
    expect(recent.map((board) => board.id), ['42']);
    expect(recent.single.label, 'Synthetic parent');

    final failed = ForumRepository(client: _CoreClient('<html></html>'));
    await expectLater(
      failed.fetchBoardThreadPage(
          const ForumCategory(name: 'Unavailable board', slug: 'f44')),
      throwsA(isA<ForumRepositoryException>()),
    );
    expect(
        (await HomeReadingPreferences.load())
            .recentBoards
            .map((board) => board.id),
        ['42']);
  });

  test('off-home visits persist the immediate breadcrumb parent without extra reads', () async {
    final client = _CoreClient('''
      <div id="breadcrumbs"><a href="index.php">首页</a>
        <a href="thread.php?fid-13.html">资源区</a>
        <a href="thread.php?fid-14.html">直接父版</a>
        <a href="thread.php?fid-42.html">真实版名</a>
      </div>
      <table><tr><td>子版块</td></tr><tr><td>论坛</td><td>文章</td></tr>
        <tr><th><h2><a href="thread.php?fid-43.html" class="fnamecolor a1">Child</a></h2></th><td>0</td><td>0</td></tr>
      </table>
    ''');
    final repo = ForumRepository(client: client);
    await repo.fetchBoardThreadPage(const ForumCategory(name: '旧名', slug: 'f42'));
    final recent = (await HomeReadingPreferences.load()).recentBoards.single;
    expect(recent.id, '42');
    expect(recent.label, '直接父版 / 真实版名');
    expect(client.gets, hasLength(1));
  });

  test('task tab and concurrent snapshots share only in-flight reads',
      () async {
    final client = _PendingTaskClient();
    final repository = ForumRepository(client: client);
    final visible = repository.fetchForumTasks(ForumTaskStatus.available);
    final first = repository.refreshForumTaskSnapshot();
    final second = repository.refreshForumTaskSnapshot();
    expect(
        client.requests.map((request) => request.path).toSet(), hasLength(3));
    expect(client.requests, hasLength(3));
    for (final request in client.requests) {
      request.response.complete('<html></html>');
    }
    await Future.wait<Object>([visible, first, second]);

    final refreshed = repository.refreshForumTaskSnapshot();
    expect(client.requests, hasLength(6));
    for (final request in client.requests.skip(3)) {
      request.response.complete('<html></html>');
    }
    await refreshed;
  });

  test('failed task reads are evicted and can be retried', () async {
    final client = _PendingTaskClient();
    final repository = ForumRepository(client: client);
    final first = repository.fetchForumTasks(ForumTaskStatus.available);
    final duplicate = repository.fetchForumTasks(ForumTaskStatus.available);
    expect(client.requests, hasLength(1));
    final rejected = Future.wait([
      expectLater(first, throwsStateError),
      expectLater(duplicate, throwsStateError),
    ]);
    client.requests.single.response
        .completeError(StateError('Synthetic failure'));
    await rejected;
    final retried = repository.fetchForumTasks(ForumTaskStatus.available);
    expect(client.requests, hasLength(2));
    client.requests.last.response.complete('<html></html>');
    expect(await retried, isEmpty);
  });

  test('failed snapshot refreshes are evicted and can be retried', () async {
    final client = _PendingTaskClient();
    final repository = ForumRepository(client: client);
    final first = repository.refreshForumTaskSnapshot();
    final duplicate = repository.refreshForumTaskSnapshot();
    expect(client.requests, hasLength(3));
    final rejected = Future.wait([
      expectLater(first, throwsStateError),
      expectLater(duplicate, throwsStateError),
    ]);
    client.requests.first.response
        .completeError(StateError('Synthetic failure'));
    for (final request in client.requests.skip(1)) {
      request.response.complete('<html></html>');
    }
    await rejected;
    final retried = repository.refreshForumTaskSnapshot();
    expect(client.requests, hasLength(6));
    for (final request in client.requests.skip(3)) {
      request.response.complete('<html></html>');
    }
    expect((await retried).tasks, isEmpty);
  });

  test('old task read settlement never evicts a new-session request', () async {
    final client = _PendingTaskClient();
    final repository = ForumRepository(client: client);
    final old = repository.fetchForumTasks(ForumTaskStatus.available);
    final rejected = expectLater(old, throwsA(isA<ForumRepositoryException>()));
    await repository.clearSession();
    final fresh = repository.fetchForumTasks(ForumTaskStatus.available);
    expect(client.requests, hasLength(2));
    client.requests.first.response.complete('<html></html>');
    await rejected;
    final duplicate = repository.fetchForumTasks(ForumTaskStatus.available);
    expect(client.requests, hasLength(2));
    client.requests.last.response.complete('<html></html>');
    expect(await fresh, isEmpty);
    expect(await duplicate, isEmpty);
  });

  for (final mode in ['manual', 'automatic', 'single']) {
    test('$mode task action cannot continue after switching accounts',
        () async {
      final client = _GuardedActionClient();
      final repository = ForumRepository(client: client);
      await repository.restoreSession();
      final Future<Object?> action = switch (mode) {
        'manual' => repository.claimForumTaskRewards(),
        'automatic' => repository.autoClaimForumTaskRewardsIfDue(),
        _ => repository.runForumTask(const ForumTask(
            id: '15',
            name: '日常',
            status: ForumTaskStatus.available,
            actionLabel: '按这申请此任务',
          )),
      };
      final rejected =
          expectLater(action, throwsA(isA<ForumRepositoryException>()));
      await client.actionRequested.future;
      await repository.clearSession();
      client.name = 'account-b';
      await repository.restoreSession();
      client.pendingAction
          .complete('<ajax><![CDATA[success\t已经申请[日常]完成,请赶紧去完成任务吧!]]></ajax>');
      await rejected;
      expect(client.actions, hasLength(1));
      expect(client.followRedirects, [false]);
      expect(client.paths.where((path) => path.startsWith('plugin.php')),
          hasLength(mode == 'single' ? 1 : 3));
      expect(client.paths.where((path) => path.contains('actions-newtasks')),
          isEmpty);
      expect(await repository.loadCachedForumTaskSnapshot(), isNull);
      expect(
          await const ForumTaskStateStore()
              .load(scope: 'https://south-plus.net:account-b'),
          isNull);
    });
  }

  for (final pid in ['tpc', '42']) {
    test('native purchase pid=$pid is session-guarded without redirect replay',
        () async {
      final client = _GuardedActionClient();
      final repository = ForumRepository(client: client);
      await repository.restoreSession();
      final purchase = repository.buySaleBox(ThreadSaleBox(
        summary: 'Synthetic purchase',
        buyPath: 'job.php?action=buytopic&tid=701&pid=$pid&verify=fixture',
      ));
      final rejected =
          expectLater(purchase, throwsA(isA<ForumRepositoryException>()));
      await client.actionRequested.future;
      await repository.clearSession();
      client.name = 'account-b';
      await repository.restoreSession();
      client.pendingAction.complete('购买成功');
      await rejected;
      expect(client.actions, hasLength(1));
      expect(client.followRedirects, [false]);
    });
  }

  test(
      'purchase admission rejects foreign and malformed action URLs before transport',
      () async {
    final client = _GuardedActionClient();
    final repository = ForumRepository(client: client);
    for (final path in [
      'https://outside.invalid/job.php?action=buytopic&tid=701&pid=tpc&verify=fixture',
      'https://blue-plus.net/job.php?action=buytopic&tid=701&pid=tpc&verify=fixture',
      'javascript:buytopic',
      'job.php?action=buytopic&action=buytopic&tid=701&pid=tpc&verify=fixture',
      'job.php?action=buytopic&tid=701&pid=other&verify=fixture',
      'job.php?action=buytopic&tid=701&pid=tpc',
      'job.php?action=buytopic&tid=701&pid=tpc&verify=fixture&other=value',
      'other.php?action=buytopic&tid=701&pid=tpc&verify=fixture',
    ]) {
      final result = await repository
          .buySaleBox(ThreadSaleBox(summary: 'Synthetic', buyPath: path));
      expect(result.success, isFalse);
    }
    expect(client.paths, isEmpty);
    expect(client.actions, isEmpty);
  });

  test('task reads reject a response after a session change', () async {
    final pending = Completer<String>();
    final client = _CoreClient('', response: pending.future);
    final repository = ForumRepository(client: client);
    final read = repository.refreshForumTaskSnapshot();
    final rejected =
        expectLater(read, throwsA(isA<ForumRepositoryException>()));
    await repository.clearSession();
    pending.complete('<html><body>没有任务</body></html>');
    await rejected;
    expect(await repository.loadCachedForumTaskSnapshot(), isNull);
  });
}

class _ScopeClient extends ForumClient {
  _ScopeClient(ForumSite site, {this.name = 'fixture-account'})
      : super(
            config: ForumNetworkConfig(
          site: site,
          dohEnabled: false,
          dohProvider: ForumNetworkConfig.defaultProvider,
        ));

  final String name;

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> restoreCookies() async {}

  @override
  Future<String> get(String path) async =>
      '<div id="user-login"><a href="u.php">$name</a></div>'
      '<a href="login.php?action-quit">退出</a>'
      '<div id="menu_profile"><ul class="ul2"><li>'
      '<a href="u.php?action-show-uid-42.html">查看个人资料</a></li></ul></div>';
}

class _GenerationClient extends _ScopeClient {
  _GenerationClient() : super(ForumNetworkConfig.defaultSite);
  final profile = Completer<String>();
  final profileRequested = Completer<void>();

  @override
  Future<String> get(String path) {
    if (path.contains('action-show-uid-42')) {
      profileRequested.complete();
      return profile.future;
    }
    return super.get(path);
  }

  @override
  Future<String> getOnce(String path) async => '<html></html>';

  @override
  Future<void> clearSession() async {}
}

class _MemoryProfileCache extends UserProfileCache {
  final saved = <UserProfile>[];

  @override
  Future<void> saveOverview(String requestedUrl, UserProfile profile) async {
    saved.add(profile);
  }
}

class _GuardedActionClient extends ForumClient {
  String name = 'account-a';
  final paths = <String>[];
  final actions = <String>[];
  final followRedirects = <bool>[];
  final actionRequested = Completer<void>();
  final pendingAction = Completer<String>();

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> restoreCookies() async {}

  @override
  Future<void> clearSession() async {}

  @override
  Future<String> getForm(String path,
      {void Function()? requireCurrentSession,
      bool followRedirects = true}) async {
    this.followRedirects.add(followRedirects);
    requireCurrentSession?.call();
    final response = await get(path);
    requireCurrentSession?.call();
    return response;
  }

  @override
  Future<String> get(String path) async {
    paths.add(path);
    if (path == 'index.php') {
      return '<div id="user-login"><a href="u.php">$name</a></div>'
          '<a href="login.php?action-quit">退出</a>';
    }
    if (path.contains('action=ajax') || path.startsWith('job.php')) {
      actions.add(path);
      if (!actionRequested.isCompleted) {
        actionRequested.complete();
        return pendingAction.future;
      }
      return '<ajax><![CDATA[success\t你[日常]已经完成!]]></ajax>';
    }
    if (path == 'plugin.php?H_name-tasks.html') {
      return '''<table><tr>
        <td><b>日常</b> (人气 : 1) 任务时效2011-12-03~2028-12-31</td>
        <td>奖励 : SP币 2 G</td>
        <td><a onclick="startjob('15');" title="按这申请此任务"></a></td>
      </tr><tr><td>每日SP+2的日常。</td></tr></table>''';
    }
    return '<html></html>';
  }
}

class _PendingTaskClient extends ForumClient {
  final requests = <({String path, Completer<String> response})>[];

  @override
  Future<String> get(String path) {
    final response = Completer<String>();
    requests.add((path: path, response: response));
    return response.future;
  }

  @override
  Future<void> clearSession() async {}
}

class _CoreClient extends ForumClient {
  _CoreClient(this.html, {this.response});
  final String html;
  final Future<String>? response;
  final gets = <String>[];

  @override
  Future<String> get(String path) async {
    gets.add(path);
    return response == null ? html : await response!;
  }

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<void> clearSession() async {}
}
