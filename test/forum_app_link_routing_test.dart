import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/forum_pm_models.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';
import 'package:south_plus_rewrite/services/forum_url_resolver.dart';
import 'package:south_plus_rewrite/services/user_profile_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final urls = ForumUrlResolver(baseUri: Uri.parse('https://blue-plus.net/'));

  test('native PM pending link names requester fuid, never account owner', () {
    for (final path in [
      'u.php?action-friend-o-check-fuid-202.html',
      'u.php?action=friend&o=check&fuid=202',
    ]) {
      final target = urls.forumLinkTarget('https://south-plus.net/$path')
          as ForumAppPageLinkTarget;
      expect(target.page, ForumAppPage.friendRequests);
      expect(target.ownerUid, isNull);
      expect(target.url, 'https://blue-plus.net/$path');
    }
    final own =
        urls.forumLinkTarget('u.php?action-friend-uid-101-o-check-page-2.html')
            as ForumAppPageLinkTarget;
    expect(own.ownerUid, '101');
    expect(own.pageNumber, 2);
  });

  test('all supported management views use typed current-mirror destinations',
      () {
    final examples = <String, ForumAppPage>{
      '/': ForumAppPage.home,
      'index.php': ForumAppPage.home,
      'simple/index.php': ForumAppPage.home,
      'profile.php': ForumAppPage.account,
      'profile.php?action-modify.html': ForumAppPage.profileEdit,
      'profile.php?action=modify': ForumAppPage.profileEdit,
      'profile.php?action-bbsset-info_type-friend.html':
          ForumAppPage.forumPreferences,
      'profile.php?action=bbsset&info_type=msg': ForumAppPage.forumPreferences,
      'profile.php?action-bbsset-info_type-fancy.html':
          ForumAppPage.forumPreferences,
      'profile.php?action=bbsset&info_type=fancy':
          ForumAppPage.forumPreferences,
      'u.php?action-friend.html': ForumAppPage.friends,
      'u.php?action=friend&uid=101': ForumAppPage.friends,
      'message.php': ForumAppPage.pmInbox,
      'message.php?action-receivebox-page-2.html': ForumAppPage.pmInbox,
      'message.php?action=sendbox&page=3': ForumAppPage.pmSendbox,
      'message.php?action-scout.html': ForumAppPage.pmScout,
      'message.php?action-write-touid-202.html': ForumAppPage.pmCompose,
      'message.php?action=write&remid=701': ForumAppPage.pmCompose,
      'message.php?action-write-transmit-701.html': ForumAppPage.pmCompose,
      'message.php?action-write-edmid-701.html': ForumAppPage.pmCompose,
      'message.php?action-chatlog-withuid-202-page-2.html':
          ForumAppPage.pmChatlog,
      'message.php?action=chatlog&withuid=202&page=2': ForumAppPage.pmChatlog,
    };
    for (final example in examples.entries) {
      final target = urls.forumLinkTarget(
              '//south-plus.net/${example.key.replaceFirst(RegExp(r'^/'), '')}')
          as ForumAppPageLinkTarget;
      expect(target.page, example.value, reason: example.key);
      expect(Uri.parse(target.url).origin, 'https://blue-plus.net');
    }
  });

  test(
      'bare homepage aliases never swallow existing simple thread or board queries',
      () {
    expect(urls.forumLinkTarget('https://south-plus.net'),
        isA<ForumAppPageLinkTarget>());
    expect(urls.forumLinkTarget('simple/index.php?t701_2.html'),
        isA<ForumThreadLinkTarget>());
    expect(urls.forumLinkTarget('simple/index.php?f42.html'),
        isA<ForumBoardLinkTarget>());
    expect(urls.forumLinkTarget('simple/index.php?p42.html'),
        isA<ForumBoardLinkTarget>());
    final thread = urls.forumLinkTarget('simple/index.php?t701_2.html#fixture')
        as ForumThreadLinkTarget;
    expect(thread.url, contains('page=2#fixture'));
  });

  test('PM detail destinations retain native box, type and message identity',
      () {
    final examples = [
      ('read', ForumPmBox.inbox, ForumPmType.personal),
      ('readpub', ForumPmBox.inbox, ForumPmType.broadcast),
      ('readsnd', ForumPmBox.sendbox, ForumPmType.sent),
      ('readscout', ForumPmBox.scout, ForumPmType.tracked),
    ];
    for (final example in examples) {
      for (final query in [
        'action-${example.$1}-mid-701.html',
        'action=${example.$1}&mid=701'
      ]) {
        final target = urls.forumLinkTarget('message.php?$query')
            as ForumAppPageLinkTarget;
        expect(target.page, ForumAppPage.pmDetail);
        expect(target.pmMessage!.box, example.$2);
        expect(target.pmMessage!.type, example.$3);
        expect(target.pmMessage!.id, '701');
        expect(target.pmMessage!.detailPath, 'message.php?$query');
        expect(target.pmMessage!.canDelete, isFalse);
      }
    }
  });

  test(
      'all existing native task view modes stay distinct without loosening URL grammar',
      () {
    for (final example in [
      ('', ForumTaskStatus.available),
      ('newtasks', ForumTaskStatus.inProgress),
      ('endtasks', ForumTaskStatus.completed),
      ('errotasks', ForumTaskStatus.failed),
    ]) {
      final action = example.$1;
      for (final query in [
        'H_name-tasks${action.isEmpty ? '' : '-actions-$action.html'}.html',
        'H_name=tasks${action.isEmpty ? '' : '&actions=$action'}',
      ]) {
        final target =
            urls.forumLinkTarget('plugin.php?$query') as ForumAppPageLinkTarget;
        expect(target.page, ForumAppPage.forumTasks);
        expect(target.taskStatus, example.$2);
      }
    }
  });

  test(
      'self profile aliases preserve tabs without fetching untrusted first-user links',
      () async {
    for (final example in [
      ('u.php', UserProfileTab.home),
      ('u.php?action-home.html', UserProfileTab.home),
      ('u.php?action=show', UserProfileTab.profile),
      ('u.php?action-topic.html', UserProfileTab.topics),
      ('u.php?action=post', UserProfileTab.posts),
      ('u.php?action-favor.html', UserProfileTab.favorites),
    ]) {
      final target = urls.forumLinkTarget(example.$1) as ForumUserLinkTarget;
      expect(target.isSelf, isTrue);
      expect(target.userUrl, 'https://blue-plus.net/u.php');
      expect(target.tab, example.$2);
    }
    final client = _IdentityClient();
    final cache = _Cache();
    final repository = ForumRepository(client: client, profileCache: cache);
    addTearDown(repository.clearSession);
    final profile = await repository.fetchUserProfileOverview('u.php');
    expect(profile.uid, '101');
    expect(client.reads, ['index.php', 'u.php?action-show-uid-101.html']);
    await repository.cachedUserProfileOverview('u.php?action-favor.html');
    expect(cache.loadedUrl,
        'https://south-plus.net/u.php?action-show-uid-101.html');
  });

  test(
      'an explicit owner link fails closed when identity provenance is unknown',
      () {
    final repository = _UnknownIdentityRepository(_IdentityClient());
    final target =
        repository.forumLinkTarget('u.php?action-friend-uid-101.html')
            as ForumAppPageLinkTarget;
    expect(repository.isLoggedIn, isTrue);
    expect(repository.accountIdentity.value?.uid, '101');
    expect(repository.canOpenForumAppPage(target), isFalse);
  });

  test(
      'cached own identity cannot authorize an old owner after credentials change',
      () async {
    final client = _IdentityClient();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    await repository.ensureAccountIdentity();
    final old = repository.forumLinkTarget('u.php?action-friend-uid-101.html')
        as ForumAppPageLinkTarget;
    expect(repository.canOpenForumAppPage(old), isTrue);
    client.credentialOverride = client.credentialGeneration + 1;
    client.indexUid = '202';
    expect(repository.canOpenForumAppPage(old), isFalse);
    await repository.ensureAccountIdentity();
    expect(client.reads, ['index.php', 'index.php']);
    expect(repository.accountIdentity.value?.uid, '202');
    final fresh = repository.forumLinkTarget('u.php?action-friend-uid-202.html')
        as ForumAppPageLinkTarget;
    expect(repository.canOpenForumAppPage(fresh), isTrue);
  });

  test('a self-profile cache reply cannot cross a session switch', () async {
    final client = _IdentityClient();
    final cache = _Cache()..gate = Completer<UserProfile?>();
    final repository = ForumRepository(client: client, profileCache: cache);
    addTearDown(repository.clearSession);
    final pending = repository.cachedUserProfileOverview('u.php');
    await cache.started.future;
    await repository.clearSession();
    cache.gate!
        .complete(const UserProfile(uid: '101', name: 'self', url: 'u.php'));
    await expectLater(pending, throwsA(isA<ForumRequestException>()));
  });

  test('an index read begun during login cannot replace the new route owner',
      () async {
    final client = _IdentityClient();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    await repository.submitLogin(
        username: 'synthetic-A',
        password: 'synthetic-password',
        captcha: 'synthetic-captcha',
        fields: {});
    client.loginGate = Completer<void>();
    client.indexGate = Completer<void>();
    final login = repository.submitLogin(
        username: 'synthetic-B',
        password: 'synthetic-password',
        captcha: 'synthetic-captcha',
        fields: {});
    await client.loginReached.future;
    final pending = repository.ensureAccountIdentity();
    await client.indexReached.future;
    client.loginGate!.complete();
    await login;
    expect(repository.accountIdentity.value?.uid, '202');
    client.indexGate!.complete();
    await expectLater(
        pending,
        throwsA(isA<ForumRequestException>().having(
            (error) => error.kind, 'kind', ForumRequestKind.loginRequired)));
    expect(repository.accountIdentity.value?.uid, '202');
    final own = repository.forumLinkTarget('u.php?action-friend-uid-202.html')
        as ForumAppPageLinkTarget;
    final old = repository.forumLinkTarget('u.php?action-friend-uid-101.html')
        as ForumAppPageLinkTarget;
    expect(repository.canOpenForumAppPage(own), isTrue);
    expect(repository.canOpenForumAppPage(old), isFalse);
  });

  test(
      'known account destinations are admitted only for current session owner and origin',
      () async {
    final client = _IdentityClient()..loggedIn = false;
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    ForumAppPageLinkTarget target(String path) =>
        repository.forumLinkTarget(path) as ForumAppPageLinkTarget;
    final home = target('/');
    final account = target('profile.php');
    final pending = target('u.php?action-friend-o-check-fuid-202.html');
    final own = target('u.php?action-friend-uid-101.html');
    final other = target('u.php?action-friend-uid-202.html');
    expect(repository.canOpenForumAppPage(home), isTrue);
    expect(repository.canOpenForumAppPage(account), isTrue);
    expect(repository.canOpenForumAppPage(pending), isFalse);
    client.loggedIn = true;
    expect(repository.canOpenForumAppPage(pending), isTrue);
    expect(repository.canOpenForumAppPage(own), isFalse,
        reason: 'unknown current UID is not owner authority');
    await repository.ensureAccountIdentity();
    expect(repository.canOpenForumAppPage(own), isTrue);
    expect(repository.canOpenForumAppPage(other), isFalse);
    expect(
        repository.canOpenForumAppPage(const ForumAppPageLinkTarget(
            ForumAppPage.friends,
            'https://blue-plus.net/u.php?action-friend.html')),
        isFalse,
        reason:
            'a previously issued target is not valid after changing mirrors');
    expect(
        repository.canOpenForumAppPage(const ForumAppPageLinkTarget(
            ForumAppPage.home, 'https://external.invalid/')),
        isFalse);
    expect(
        repository.canOpenForumAppPage(
            const ForumAppPageLinkTarget(ForumAppPage.home, '/')),
        isFalse);
    await repository.clearSession();
    expect(repository.canOpenForumAppPage(own), isFalse);
  });

  test(
      'write-shaped, malformed and duplicate native fields never become view authority',
      () {
    for (final value in [
      'u.php?action=friend&job=delete',
      'u.php?action-friend-uid-101-verify-synthetic.html',
      'profile.php?action=bbsset&step=2',
      'message.php?action=write&step=2',
      'message.php?action-unread-mid-701-verify-synthetic.html',
      'message.php?action=del&delids=701',
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=14',
      'plugin.php?H_name-tasks-actions-claim.html',
      'u.php?action=friend&action=friend',
      'u.php?action-friend-uid-101-%75id-202.html',
      'u.php?action=friend&uid=101&%75id=202',
      'u.php?action-friend-o-check-fuid-202-fuid-303.html',
      'u.php?action=friend&page=99999999999999999999999999999999999',
    ]) {
      expect(urls.forumLinkTarget(value), isA<ForumBlockedLinkTarget>(),
          reason: value);
    }
  });

  test(
      'unsupported harmless filters/pages and external origins retain honest fallback',
      () {
    for (final value in [
      'index.php?cateid=5',
      'index.php?cateid-5.html',
      'profile.php?action=permission',
      'profile.php?action=bbsset&info_type=unknown',
      'u.php?action=favor&type=1',
      'u.php?action=favor&uid=101&type=1',
      'u.php?action-favor-uid-101-type-1.html',
      'u.php?action=friend&o=unknown',
      'u.php?t701.html',
      'message.php?action=write&touid=202&remid=701',
      'post.php?fid=42',
      'pw_ajax.php?action=newrp',
    ]) {
      expect(urls.forumLinkTarget(value), isA<ForumPageLinkTarget>(),
          reason: value);
    }
    for (final value in [
      'https://south-plus.net.evil.invalid/profile.php?action=modify',
      'https://south-plus.net:444/u.php?action-friend.html',
      'https://external.invalid/message.php?action=receivebox',
    ]) {
      expect(urls.forumLinkTarget(value), isA<ForumExternalLinkTarget>(),
          reason: value);
    }
  });
}

class _UnknownIdentityRepository extends ForumRepository {
  _UnknownIdentityRepository(ForumClient client) : super(client: client);
  final identity = ValueNotifier<ForumAccountIdentity?>(
      const ForumAccountIdentity(systemName: 'unverified', uid: '101'));
  @override
  ValueListenable<ForumAccountIdentity?> get accountIdentity => identity;
}

class _IdentityClient extends ForumClient {
  bool loggedIn = true;
  String indexUid = '101';
  int? credentialOverride;
  @override
  int get credentialGeneration =>
      credentialOverride ?? super.credentialGeneration;
  @override
  bool isCredentialCurrent(int generation) => credentialOverride == null
      ? super.isCredentialCurrent(generation)
      : generation == credentialOverride;
  final reads = <String>[];
  Completer<void>? indexGate;
  final indexReached = Completer<void>();
  Completer<void>? loginGate;
  final loginReached = Completer<void>();
  @override
  bool get isLoggedIn => loggedIn;
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
    reads.add(path);
    if (path == 'index.php') {
      if (indexGate != null) {
        indexReached.complete();
        await indexGate!.future;
      }
      return '''
<head><script>var verifyhash='fxToken1';</script></head>
<a href="u.php?uid-999.html">unrelated first user</a>
<div id="user-login"><a href="u.php">self</a></div>
<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-$indexUid.html">profile</a></div></div>''';
    }
    return '<div id="u-top"><div class="u-h1">self</div></div>';
  }

  @override
  Future<
      ({
        String response,
        int credentialGeneration,
        bool installedCredentials
      })> postLogin(Map<String, String> form) async {
    final response = await post('login.php', form);
    return (
      response: response,
      credentialGeneration: credentialGeneration,
      installedCredentials: isLoggedIn
    );
  }

  @override
  Future<String> post(String path, Map<String, String> fields) async {
    if (path != 'login.php') return '{}';
    if (loginGate != null) {
      loginReached.complete();
      await loginGate!.future;
    }
    final uid = fields['pwuser'] == 'synthetic-A' ? '101' : '202';
    return '<div id="user-login"><a href="u.php">${fields['pwuser']}</a></div>'
        '<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-$uid.html">profile</a></div></div>';
  }

  @override
  Future<void> clearSession() async {
    loggedIn = false;
  }
}

class _Cache extends UserProfileCache {
  String? loadedUrl;
  Completer<UserProfile?>? gate;
  final started = Completer<void>();
  @override
  Future<UserProfile?> loadOverview(String url) async {
    loadedUrl = url;
    if (!started.isCompleted) started.complete();
    return gate?.future;
  }

  @override
  Future<void> saveOverview(String requestedUrl, UserProfile profile) async {}
}
