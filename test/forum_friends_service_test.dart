import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:south_plus_rewrite/models/forum_friend_models.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_friends_service.dart';
import 'package:south_plus_rewrite/services/forum_request_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('friend mutation invalidates the warm self mixed-feed cache', () async {
    final client = _ProfileClient();
    final repository = ForumRepository(client: client);
    addTearDown(repository.clearSession);
    const overview = UserProfile(uid: '101', name: 'self', url: 'u.php');
    final before = await repository.fetchUserProfileDetails(overview);
    expect(before.homeActivities.map((item) => item.authorUid), ['101', '202']);
    await repository.fetchUserProfileDetails(overview);
    expect(client.homeReads, 1, reason: 'the second read is warm');
    final friends = await repository.fetchFriends();
    expect((await repository.deleteFriends(friends, friends.items)).confirmed,
        isTrue);
    final after = await repository.fetchUserProfileDetails(overview);
    expect(client.homeReads, 2);
    expect(after.homeActivities.map((item) => item.authorUid), ['101']);
  });
  test(
    'native verification popup preserves hidden fields and optional message once',
    () async {
      final client = _Client()..popup = true;
      final service = _service(client);
      final first = await service.addFriend('202');
      expect(first.status, ForumFriendAddStatus.verificationRequired);
      expect(first.request!.uid, '202');
      final result = await service.confirmFriendRequest(
        first.request!,
        message: '',
      );
      expect(result.status, ForumFriendAddStatus.pending);
      expect(
        _fields(client),
        containsAll([
          'verify=draft-token',
          'touid=202',
          'job=add',
          'step=2',
          'checkmsg=',
        ]),
      );
      await expectLater(
        service.confirmFriendRequest(first.request!, message: ''),
        throwsA(isA<ForumRequestException>()),
      );
      expect(client.posts, hasLength(1));
    },
  );

  test(
    'HTTP 200 XML body determines add success, wait and permission rejection',
    () async {
      for (final example in [
        ('成功将对方加为好友', ForumFriendAddStatus.added),
        ('请求添加为好友，正在等待好友验证。', ForumFriendAddStatus.pending),
        ('非法操作,请返回', ForumFriendAddStatus.rejected),
        ('该用户拒绝任何人加为好友', ForumFriendAddStatus.rejected),
        ('unrecognized', ForumFriendAddStatus.unknown),
      ]) {
        final client = _Client()..addMessage = example.$1;
        final result = await _service(client).addFriend('202');
        expect(result.status, example.$2);
        expect(client.adds, 1);
      }
    },
  );

  test(
    'friend list parses native rows and uses fresh form token for directional deletion',
    () async {
      final client = _Client();
      final service = _service(client);
      final page = await service.fetchFriends();
      final friend = page.items.single;
      expect(friend.uid, '202');
      expect(friend.name, 'friend');
      expect(friend.joinedAt, '2025-01-02 12:34');
      final result = await service.deleteFriends(page, [friend]);
      expect(result.confirmed, isTrue);
      expect(
        _fields(client),
        containsAll([
          'uid=101',
          'verify=list-token-2',
          'job=delete',
          'selid[]=202',
        ]),
      );
      await expectLater(
        service.deleteFriends(page, [friend]),
        throwsA(isA<ForumRequestException>()),
      );
      expect(client.posts, hasLength(1));
    },
  );

  test(
    'all three pending jobs preserve native semantics and refusal text',
    () async {
      for (final action in ForumFriendResponse.values) {
        final client = _Client()..friendPresent = false;
        final service = _service(client);
        final page = await service.fetchFriends(pending: true);
        expect(page.pending, isTrue);
        expect(page.items.single.verificationMessage, 'hello friend');
        final result = await service.respondToFriendRequests(
          page,
          page.items,
          action,
          refusalMessage: 'not now',
        );
        expect(result.confirmed, isTrue);
        expect(_fields(client), contains('job=${action.name}'));
        expect(client.friendPresent, action == ForumFriendResponse.acceptadd);
        expect(
          client.posts.single
              .where((entry) => entry.key == 'refusemsg')
              .map((entry) => entry.value),
          action == ForumFriendResponse.refuse ? ['not now'] : isEmpty,
        );
      }
    },
  );

  test(
    'native mutation rejection or unchanged list never reports success',
    () async {
      final client = _Client()..rejectWrite = true;
      final service = _service(client);
      final page = await service.fetchFriends();
      final result = await service.deleteFriends(page, page.items);
      expect(result.confirmed, isFalse);
      expect(result.message, contains('非法操作'));
    },
  );

  test(
    'a lost mutating response is unknown and consumed verification draft never replays',
    () async {
      final client = _Client()..loseResponse = true;
      final service = _service(client);
      expect(
        (await service.addFriend('202')).status,
        ForumFriendAddStatus.unknown,
      );
      expect(client.adds, 1);
      client
        ..loseResponse = false
        ..popup = true;
      final request = (await service.addFriend('202')).request!;
      client.loseResponse = true;
      expect(
        (await service.confirmFriendRequest(request, message: 'hello')).status,
        ForumFriendAddStatus.unknown,
      );
      await expectLater(
        service.confirmFriendRequest(request, message: 'hello'),
        throwsA(isA<ForumRequestException>()),
      );
      expect(client.posts, hasLength(1));
    },
  );

  test('unproven later-page clamping does not certify a mutation', () async {
    final client = _Client();
    final service = _service(client);
    final page = await service.fetchFriends(page: 2);
    expect((await service.deleteFriends(page, page.items)).confirmed, isFalse);
    expect(client.posts, hasLength(1));
  });

  test(
    'foreign, fabricated and stale snapshots cannot submit selected IDs',
    () async {
      final client = _Client();
      final service = _service(client);
      final page = await service.fetchFriends();
      final forged = ForumFriendPage(items: page.items, pending: false);
      await expectLater(
        service.deleteFriends(forged, forged.items),
        throwsA(isA<ForumRequestException>()),
      );
      await expectLater(
        service.deleteFriends(page, [
          const ForumFriend(
            uid: '303',
            name: 'other',
            url: 'u.php?uid-303.html',
          ),
        ]),
        throwsA(isA<ForumRequestException>()),
      );
      await expectLater(
        service.addFriend('101'),
        throwsA(isA<ForumRequestException>()),
      );
      expect(client.posts, isEmpty);
      expect(client.adds, 0);
    },
  );
}

Iterable<String> _fields(_Client client) =>
    client.posts.single.map((entry) => '${entry.key}=${entry.value}');

ForumFriendsService _service(_Client client) => ForumFriendsService(
      client: () => client,
      sessionEpoch: () => 0,
      isLoggedIn: () => true,
      ownerUid: () async => '101',
      didWrite: () {},
    );

class _Client extends ForumClient {
  bool popup = false;
  bool friendPresent = true;
  bool pendingPresent = true;
  bool rejectWrite = false;
  bool loseResponse = false;
  String addMessage = '成功将对方加为好友';
  int reads = 0;
  int adds = 0;
  final posts = <List<MapEntry<String, String>>>[];

  @override
  Future<String> getForm(
    String path, {
    void Function()? requireCurrentSession,
    bool followRedirects = true,
  }) async {
    requireCurrentSession?.call();
    if (path.contains('action-show'))
      return '''
<head><script>var verifyhash='fxToken1';</script></head>
<div id="u-sidebar"><a onclick="ajax.send('pw_ajax.php?action=addfriend&touid=202','',ajax.get)">加为好友</a></div>''';
    if (path.startsWith('pw_ajax.php')) {
      adds++;
      if (loseResponse)
        throw const ForumRequestException(
          ForumRequestKind.network,
          'connection lost',
        );
      return popup
          ? _xml('''<form method="post" action="pw_ajax.php?action=addfriend">
<input type="hidden" name="verify" value="draft-token">
<input type="hidden" name="job" value="add"><input type="hidden" name="step" value="2">
<input type="hidden" name="touid" value="202"><input name="checkmsg" maxlength="100"></form>''')
          : _xml(addMessage);
    }
    reads++;
    final pending = path.contains('-o-check');
    final present = pending ? pendingPresent : friendPresent;
    return '''<form method="post" action="u.php?action=friend">
<input type="hidden" name="uid" value="101"><input type="hidden" name="verify" value="list-token-$reads">
<table class="u-table"><tr><td>头像</td><td>用户名</td><td>加入时间</td><td>操作</td></tr>
${present ? '''<tr><td><a href="u.php?action-show-uid-202.html"><img src="images/avatar.png"></a></td>
<td><a href="u.php?action-show-uid-202.html">friend</a> <b>在线</b>${pending ? '<br>hello friend' : ''}</td>
<td>2025-01-02 12:34</td><td><input type="checkbox" name="selid[]" value="202"></td></tr>''' : ''}</table>
${pending ? '''<input type="radio" name="job" value="acceptadd" checked>
<input type="radio" name="job" value="accept"><input type="radio" name="job" value="refuse"><textarea name="refusemsg"></textarea>''' : '<input type="hidden" name="job" value="delete">'}</form>''';
  }

  @override
  Future<String> postForm(
    String path,
    List<MapEntry<String, String>> fields, {
    bool multipart = false,
    List<ForumFormFile> files = const [],
    void Function()? requireCurrentSession,
  }) async {
    requireCurrentSession?.call();
    posts.add(List.of(fields));
    if (loseResponse)
      throw const ForumRequestException(
        ForumRequestKind.network,
        'connection lost',
      );
    if (rejectWrite) return '<div>非法操作,请返回</div>';
    if (path.startsWith('pw_ajax.php')) return _xml('请求添加为好友，正在等待好友验证。');
    final job = fields.firstWhere((entry) => entry.key == 'job').value;
    if (job == 'delete')
      friendPresent = false;
    else {
      pendingPresent = false;
      if (job == 'acceptadd') friendPresent = true;
    }
    return '<div>操作完成</div>';
  }
}

class _ProfileClient extends _Client {
  int homeReads = 0;

  @override
  bool get isLoggedIn => true;

  @override
  Future<String> getOnce(String path) => get(path);

  @override
  Future<String> get(String path) async {
    if (path == 'index.php')
      return '''
<head><script>var verifyhash='fxToken1';</script></head>
<div id="user-login"><a href="u.php">self</a></div>
<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-101.html">profile</a></div></div>''';
    if (path == 'u.php?uid-101.html') {
      homeReads++;
      return '''<div id="minifeed">
<dl class="feed-list"><dt><a href="u.php?uid-101.html">self</a> 发表了主题：<a href="read.php?tid-701.html">own topic</a></dt></dl>
${friendPresent ? '<dl class="feed-list"><dt><a href="u.php?uid-202.html">friend</a> 发表了主题：<a href="read.php?tid-702.html">friend topic</a></dt></dl>' : ''}
</div>''';
    }
    return '<table class="u-table"></table>';
  }

  @override
  Future<String> post(String path, Map<String, String> fields) async => '{}';
}

String _xml(String payload) =>
    '<?xml version="1.0"?><ajax><![CDATA[$payload]]></ajax>';
