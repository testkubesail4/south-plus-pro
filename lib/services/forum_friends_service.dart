import '../models/forum_friend_models.dart';
import 'forum_client.dart';
import 'forum_request_exception.dart';
import 'forum_url_resolver.dart';
import 'parsers/forum_friends_parser.dart';
import 'parsers/forum_reply_notice_parser.dart';

class ForumFriendsService {
  ForumFriendsService({
    required ForumClient Function() client,
    required int Function() sessionEpoch,
    required bool Function() isLoggedIn,
    required String? Function() currentUsername,
    required Future<String> Function() ownerUid,
    required void Function() didWrite,
  })  : _client = client,
        _epoch = sessionEpoch,
        _loggedIn = isLoggedIn,
        _username = currentUsername,
        _ownerUid = ownerUid,
        _didWrite = didWrite;
  final ForumClient Function() _client;
  final int Function() _epoch;
  final bool Function() _loggedIn;
  final String? Function() _username;
  final Future<String> Function() _ownerUid;
  final void Function() _didWrite;
  final _pages = Expando<_FriendContext>();
  final _requests =
      Expando<({_FriendContext context, NativeFriendRequest form})>();
  bool _writing = false;
  int _revision = 0;

  Future<_FriendContext> _context() async {
    final client = _client();
    final epoch = _epoch();
    final username = _username();
    final credentialGeneration = client.credentialGeneration;
    _check(client, epoch, username, credentialGeneration);
    final uid = await _ownerUid();
    _check(client, epoch, username, credentialGeneration);
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) _invalid('无法识别当前账号');
    return _FriendContext(
        client, epoch, uid, _revision, username, credentialGeneration);
  }

  ForumFriendsParser _parser(_FriendContext context) => ForumFriendsParser(
        urls: ForumUrlResolver(baseUri: context.client.baseUri),
      );
  void _check(ForumClient client, int epoch, String? username,
      int credentialGeneration) {
    if (!_loggedIn() ||
        !identical(client, _client()) ||
        epoch != _epoch() ||
        username != _username() ||
        !client.isCredentialCurrent(credentialGeneration)) {
      throw const ForumRequestException(
        ForumRequestKind.loginRequired,
        '登录状态已改变，请重新加载',
      );
    }
  }

  void _current(_FriendContext context) => _check(context.client, context.epoch,
      context.username, context.credentialGeneration);

  Future<ForumFriendPage> fetchFriends({
    bool pending = false,
    int page = 1,
  }) async {
    if (page < 1) _invalid('页码无效');
    final context = await _context();
    final native = await _read(context, pending, page);
    _pages[native.page] = context;
    return native.page;
  }

  Future<NativeFriendPage> _read(
    _FriendContext context,
    bool pending,
    int page,
  ) async {
    _current(context);
    final response = await context.client.getForm(
      'u.php?action-friend-uid-${context.uid}${pending ? '-o-check' : ''}${page > 1 ? '-page-$page' : ''}.html',
      requireCurrentSession: () => _current(context),
      followRedirects: false,
    );
    _current(context);
    return _parser(
      context,
    ).parsePage(response, owner: context.uid, pending: pending, page: page);
  }

  Future<ForumFriendAddResult> addFriend(String uid) async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) _invalid('用户无效');
    if (_writing) _invalid('正在处理好友请求，请稍候');
    _writing = true;
    try {
      final context = await _context();
      if (uid == context.uid) _invalid('不能添加自己为好友');
      final profile = await context.client.getForm(
        'u.php?action-show-uid-$uid.html',
        requireCurrentSession: () => _current(context),
        followRedirects: false,
      );
      _current(context);
      final parser = _parser(context);
      final document = parser.document(profile);
      final token = ForumReplyNoticeParser(
        urls: ForumUrlResolver(baseUri: context.client.baseUri),
      ).verifyToken(document);
      final offered = document.querySelectorAll('#u-sidebar a').any((link) {
        final action =
            '${link.attributes['onclick'] ?? ''} ${link.attributes['href'] ?? ''}';
        return RegExp(
          r'pw_ajax\.php\?action=addfriend&touid=' + uid + r'(?:[\D]|$)',
        ).hasMatch(action);
      });
      if (token == null || !offered) {
        throw const ForumRequestException(
          ForumRequestKind.forbidden,
          '论坛未提供加好友操作，请刷新资料后重试',
        );
      }
      _invalidate();
      String response;
      try {
        response = await context.client.getForm(
          Uri(
            path: 'pw_ajax.php',
            queryParameters: {
              'action': 'addfriend',
              'touid': uid,
              'nowtime': '${DateTime.now().millisecondsSinceEpoch}',
              'verify': token,
            },
          ).toString(),
          requireCurrentSession: () => _current(context),
          followRedirects: false,
        );
      } catch (_) {
        _current(context);
        return _unknownAdd;
      }
      _current(context);
      final form = parser.parseRequest(response, uid);
      if (form != null) {
        _requests[form.request] = (context: context, form: form);
        return ForumFriendAddResult(
          status: ForumFriendAddStatus.verificationRequired,
          message: '可填写验证信息后发送好友请求',
          request: form.request,
        );
      }
      return parser.addResult(response);
    } finally {
      _writing = false;
    }
  }

  Future<ForumFriendAddResult> confirmFriendRequest(
    ForumFriendRequest request, {
    required String message,
  }) async {
    final loaded = _requests[request];
    if (loaded == null) _invalid('好友请求已失效，请重新添加');
    final context = loaded.context;
    _current(context);
    if (_writing) _invalid('正在处理好友请求，请稍候');
    if (request.maxLength != null && message.length > request.maxLength!) {
      _invalid('验证信息超过论坛长度限制');
    }
    if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(message)) {
      _invalid('验证信息包含无效字符');
    }
    _writing = true;
    _requests[request] = null;
    _invalidate();
    try {
      String response;
      try {
        response = await context.client.postForm(
          'pw_ajax.php?action=addfriend',
          [
            ...loaded.form.fields.where((field) => field.key != 'checkmsg'),
            MapEntry('checkmsg', message),
          ],
          requireCurrentSession: () => _current(context),
        );
      } catch (_) {
        _current(context);
        return _unknownAdd;
      }
      _current(context);
      return _parser(context).addResult(response);
    } finally {
      _writing = false;
    }
  }

  Future<ForumFriendMutationResult> deleteFriends(
    ForumFriendPage snapshot,
    List<ForumFriend> selected,
  ) =>
      _change(snapshot, selected, 'delete');
  Future<ForumFriendMutationResult> respondToFriendRequests(
    ForumFriendPage snapshot,
    List<ForumFriend> selected,
    ForumFriendResponse response, {
    String refusalMessage = '',
  }) =>
      _change(
        snapshot,
        selected,
        response.name,
        refusalMessage: refusalMessage,
      );

  Future<ForumFriendMutationResult> _change(
    ForumFriendPage snapshot,
    List<ForumFriend> selected,
    String job, {
    String refusalMessage = '',
  }) async {
    final context = _pages[snapshot];
    if (context == null) _invalid('请刷新好友列表后重试');
    _current(context);
    if (context.revision != _revision) _invalid('好友列表已更新，请刷新后重试');
    final selection = List<ForumFriend>.of(selected);
    if (selection.isEmpty ||
        selection.map((item) => item.uid).toSet().length != selection.length ||
        selection.any(
          (item) => !snapshot.items.any((row) => identical(row, item)),
        ) ||
        snapshot.pending != (job != 'delete')) _invalid('请选择当前列表中的好友');
    if (_writing) _invalid('正在处理好友请求，请稍候');
    if (RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(refusalMessage)) {
      _invalid('拒绝理由包含无效字符');
    }
    _writing = true;
    try {
      final fresh = await _read(context, snapshot.pending, snapshot.page);
      if (!fresh.jobs.contains(job) ||
          selection.any(
            (item) => !fresh.page.items.any((row) => row.uid == item.uid),
          )) _invalid('所选好友已变更，请刷新后重试');
      _invalidate();
      String? response;
      try {
        response = await context.client.postForm(
            'u.php?action=friend',
            [
              ...fresh.fields.where(
                (field) => !{'job', 'selid[]', 'refusemsg'}.contains(field.key),
              ),
              MapEntry('job', job),
              ...selection.map((item) => MapEntry('selid[]', item.uid)),
              if (job == 'refuse') MapEntry('refusemsg', refusalMessage),
            ],
            requireCurrentSession: () => _current(context));
      } catch (_) {
        _current(context);
        return const ForumFriendMutationResult(
          confirmed: false,
          message: '提交结果未确认，请刷新好友列表核对，勿重复提交',
        );
      }
      _current(context);
      final rejection = _parser(context).rejection(response);
      if (rejection != null)
        return ForumFriendMutationResult(confirmed: false, message: rejection);
      try {
        final after = await _read(context, snapshot.pending, snapshot.page);
        final gone = after.complete &&
            selection.every(
              (item) => !after.page.items.any((row) => row.uid == item.uid),
            );
        if (gone && job == 'acceptadd') {
          final friends = await _read(context, false, 1);
          final found = selection.every(
            (item) => friends.page.items.any((row) => row.uid == item.uid),
          );
          if (!found)
            return const ForumFriendMutationResult(
              confirmed: false,
              message: '请求已处理，好友关系未确认，请刷新核对',
            );
        }
        return ForumFriendMutationResult(
          confirmed: gone,
          message: gone ? '好友操作已完成' : '结果未确认，请刷新好友列表核对',
        );
      } catch (_) {
        _current(context);
        return const ForumFriendMutationResult(
          confirmed: false,
          message: '提交结果未确认，请刷新好友列表核对，勿重复提交',
        );
      }
    } finally {
      _writing = false;
    }
  }

  static const _unknownAdd = ForumFriendAddResult(
    status: ForumFriendAddStatus.unknown,
    message: '提交结果未确认，请刷新好友列表核对，勿重复提交',
  );
  void _invalidate() {
    _revision++;
    _didWrite();
  }

  Never _invalid(String message) =>
      throw ForumRequestException(ForumRequestKind.invalidInput, message);
}

class _FriendContext {
  const _FriendContext(this.client, this.epoch, this.uid, this.revision,
      this.username, this.credentialGeneration);
  final ForumClient client;
  final int epoch;
  final String uid;
  final int revision;
  final String? username;
  final int credentialGeneration;
}
