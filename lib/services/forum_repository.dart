import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import '../models/forum_models.dart';
import '../models/forum_account_models.dart';
import '../models/user_content_query.dart';
import '../models/forum_pm_models.dart';
import 'browsing_history_store.dart';
import 'forum_client.dart';
import 'full_scan.dart';
import 'thread_search.dart';
import 'forum_account_service.dart';
import 'forum_favorites_service.dart';
import 'home_reading_preferences.dart';
import 'user_content_query_service.dart';
import 'forum_blocking_settings.dart';
import 'forum_http_routing.dart';
import 'forum_network_config.dart';
import 'forum_request_exception.dart';
import 'forum_task_state_store.dart';
import 'forum_trace_logger.dart';
import 'forum_url_resolver.dart';
import 'user_profile_cache.dart';
import 'thread_read_position_store.dart';
import 'parsers/board_thread_page_parser.dart';
import 'parsers/forum_form_parser.dart';
import 'parsers/forum_pm_parser.dart';
import 'parsers/forum_reply_notice_parser.dart';
import 'parsers/forum_response_parser.dart';
import 'parsers/forum_tasks_parser.dart';
import 'parsers/home_page_parser.dart';
import 'parsers/search_result_parser.dart';
import 'parsers/thread_content_parser.dart';
import 'parsers/thread_detail_parser.dart';
import 'parsers/user_profile_parser.dart';

typedef _ProfileDetailsData = ({
  List<UserActivityItem> homeActivities,
  List<UserActivityItem> homeReplies,
  List<UserListItem> topics,
  List<UserListItem> posts,
  List<UserListItem> favorites,
});

class ForumRepository {
  ForumRepository({
    ForumClient? client,
    ForumNetworkConfig? config,
    UserProfileCache? profileCache,
    BrowsingHistoryStore? historyStore,
    ForumTaskStateStore? taskStateStore,
  })  : _client = client ??
            ForumClient(
              config: config ??
                  const ForumNetworkConfig(
                    site: ForumNetworkConfig.defaultSite,
                    dohEnabled: true,
                    dohProvider: ForumNetworkConfig.defaultProvider,
                  ),
            ),
        _config = config ??
            client?.config ??
            const ForumNetworkConfig(
              site: ForumNetworkConfig.defaultSite,
              dohEnabled: true,
              dohProvider: ForumNetworkConfig.defaultProvider,
            ),
        _urls = ForumUrlResolver(
          baseUri: (config ?? client?.config)?.baseUri ??
              ForumNetworkConfig.defaultSite.baseUri,
        ),
        _profileCache = profileCache ??
            UserProfileCache(
              urls: ForumUrlResolver(
                baseUri: (config ?? client?.config)?.baseUri ??
                    ForumNetworkConfig.defaultSite.baseUri,
              ),
            ),
        _historyStore = historyStore ?? BrowsingHistoryStore(),
        _taskStateStore = taskStateStore ?? const ForumTaskStateStore() {
    ForumHttpRouting.updateProxy(_config.proxy);
    _sessionEpoch.addListener(_clearProfileDetails);
    _sessionEpoch.addListener(() {
      _restoredDesktopHtml = null;
      _replyNoticeVerify = null;
      _blocking?.reset();
      _blockingLoadedEpoch = null;
      _noticeFlags.value = const ForumNoticeFlags();
      _accountIdentity.value = null;
      _accountNicknameFuture = null;
      _taskReadRequests.clear();
      _taskSnapshotRefreshes.clear();
      _invalidateQuickLists();
    });
    _sessionUser.addListener(() {
      final name = currentUsername;
      if (name == null) {
        _accountIdentity.value = null;
      } else if (_accountIdentity.value?.systemName != name) {
        _accountIdentity.value = ForumAccountIdentity(systemName: name);
      }
    });
  }

  ForumClient _client;
  String? _restoredDesktopHtml;
  ForumNetworkConfig _config;
  ForumUrlResolver _urls;
  late BoardThreadPageParser _boardThreadPageParser =
      BoardThreadPageParser(urls: _urls);
  final ForumFormParser _formParser = const ForumFormParser();
  final ForumResponseParser _responseParser = const ForumResponseParser();
  final ForumTasksParser _tasksParser = const ForumTasksParser();
  late HomePageParser _homePageParser = HomePageParser(urls: _urls);
  late SearchResultParser _searchResultParser = SearchResultParser(urls: _urls);
  late ThreadDetailParser _threadDetailParser = ThreadDetailParser(
    urls: _urls,
    contentParser: ThreadContentParser(urls: _urls),
  );
  late UserProfileParser _userProfileParser = UserProfileParser(urls: _urls);
  late final ForumAccountService _accountService = ForumAccountService(
    client: () => _client,
    sessionEpoch: () => _sessionEpoch.value,
    isLoggedIn: () => isLoggedIn,
  );
  late UserContentQueryService _userContentQueries = UserContentQueryService(
    getDocument: _fetchUserContentDocument,
    urls: _urls,
    sessionEpoch: () => _sessionEpoch.value,
  );
  UserProfileCache _profileCache;
  Future<_ProfileDetailsData>? _profileDetailsFuture;
  _ProfileDetailsData? _profileDetailsData;
  String? _profileDetailsUid;
  Timer? _profileDetailsTimer;
  int _profileDetailsGeneration = 0;
  late final ForumFavoritesService _favoritesService = ForumFavoritesService(
    client: () => _client,
    sessionEpoch: () => _sessionEpoch.value,
    isLoggedIn: () => isLoggedIn,
    didWrite: _clearProfileDetails,
  );
  final BrowsingHistoryStore _historyStore;
  final _readPositions = ThreadReadPositionStore();
  final ForumTaskStateStore _taskStateStore;
  final _taskReadRequests = <({
    ForumTaskStatus status,
    ForumClient client,
    int epoch
  }),
      Future<List<ForumTask>>>{};
  final _taskSnapshotRefreshes =
      <({ForumClient client, int epoch}), Future<ForumTaskSnapshot>>{};
  int _homeGeneration = 0;
  Set<ForumQuickList> _homeQuickLists = {};
  String? _homePreferenceAccount;
  int _homeSourcesRevision = 0;
  final _quickListRequests = <ForumQuickList, Future<List<ForumThread>>>{};

  ForumBlockingSettings? _blocking;
  int? _blockingLoadedEpoch;
  ForumBlockingSettings get blocking => _blocking ??= ForumBlockingSettings(
        accountUid: () => isLoggedIn ? _accountIdentity.value?.uid : null,
        request: _requestBlocking,
      );

  Future<void> ensureAccountIdentity() async {
    if (!isLoggedIn ||
        (_accountIdentity.value?.uid != null && _replyNoticeVerify != null))
      return;
    final client = _client;
    final epoch = _sessionEpoch.value;
    try {
      final response = await client.get('index.php');
      if (!isLoggedIn || client != _client || epoch != _sessionEpoch.value) {
        throw const ForumRequestException(
            ForumRequestKind.loginRequired, '登录状态已改变，请重试');
      }
      _throwIfBlockedPage(response);
      final document = html_parser.parse(response);
      _captureAccountIdentity(document);
      _captureIndexNotices(document);
      if (_accountIdentity.value?.uid == null) {
        throw const ForumRequestException(
            ForumRequestKind.server, '暂时无法识别当前账号，请重试');
      }
    } on ForumRequestException {
      rethrow;
    } catch (_) {
      throw const ForumRequestException(
          ForumRequestKind.network, '账号信息读取失败，请检查网络后重试');
    }
  }

  void _maybeLoadBlocking() {
    if (!isLoggedIn ||
        _accountIdentity.value?.uid == null ||
        _replyNoticeVerify == null ||
        _blockingLoadedEpoch == _sessionEpoch.value) return;
    _blockingLoadedEpoch = _sessionEpoch.value;
    unawaited(blocking.load().catchError((Object _) {}));
  }

  Future<String> _requestBlocking(
      String action, Map<String, String> fields) async {
    final epoch = _sessionEpoch.value;
    final client = _client;
    final owner = _accountIdentity.value?.uid;
    void requireCurrent() {
      if (!isLoggedIn ||
          owner == null ||
          epoch != _sessionEpoch.value ||
          client != _client ||
          owner != _accountIdentity.value?.uid) {
        throw const ForumRequestException(
            ForumRequestKind.loginRequired, '登录后可配置屏蔽规则');
      }
    }

    requireCurrent();
    try {
      if (_replyNoticeVerify == null) {
        await ensureAccountIdentity();
        requireCurrent();
      }
      final verify = _replyNoticeVerify;
      if (verify == null) {
        throw const ForumRequestException(
            ForumRequestKind.server, '无法取得屏蔽配置凭据，请重新登录');
      }
      final response = await client.post(
          Uri(path: 'pw_ajax.php', queryParameters: {
            'action': action,
            'verify': verify,
          }).toString(),
          fields);
      requireCurrent();
      return response;
    } on ForumRequestException catch (error) {
      throw ForumRequestException(error.kind, '屏蔽配置同步失败，请稍后重试');
    } catch (_) {
      throw const ForumRequestException(
          ForumRequestKind.network, '屏蔽配置同步失败，请检查网络后重试');
    }
  }

  final _accountIdentity = ValueNotifier<ForumAccountIdentity?>(null);
  Future<void>? _accountNicknameFuture;
  ValueListenable<ForumAccountIdentity?> get accountIdentity =>
      _accountIdentity;

  String? _replyNoticeVerify;
  Future<void> _replyNoticeQueue = Future.value();
  DateTime? _replyNoticeReadyAt;
  final _noticeFlags = ValueNotifier(const ForumNoticeFlags());
  ValueListenable<ForumNoticeFlags> get noticeFlags => _noticeFlags;
  final _sessionUser = ValueNotifier<String?>(null);
  final _sessionEpoch = ValueNotifier<int>(0);

  ValueListenable<String?> get sessionUser => _sessionUser;

  ValueListenable<int> get sessionEpoch => _sessionEpoch;

  bool get isLoggedIn => _client.isLoggedIn;

  String? get currentUsername => _sessionUser.value;

  String? get localPreferenceAccount {
    final account = currentUsername;
    if (ForumNetworkConfig.sites.contains(_config.site)) return account;
    final origin = _config.baseUri.origin;
    return account == null
        ? '$origin:anonymous'
        : '$origin:account:${Uri.encodeComponent(account)}';
  }

  ForumNetworkConfig get networkConfig => _config;

  bool isAttachmentUrl(String url) => _client.isAttachmentUrl(url);

  ForumLinkTarget forumLinkTarget(String url) => _urls.forumLinkTarget(url);

  ForumSearchLinkPrefill? searchLinkPrefill(String raw) =>
      _urls.searchLinkPrefill(raw);

  String? searchBoardId(ForumCategory category) =>
      _urls.fidFromCategory(category);

  String? userProfileUrl(String uid) => RegExp(r'^[1-9]\d*$').hasMatch(uid)
      ? _urls.userTabUrl(uid, UserProfileTab.profile)
      : null;

  String? originalPosterPostsUrl(ForumThread thread) {
    final tid = _urls.tidFromUrl(thread.url);
    if (tid == null) return null;
    final provided = thread.authorPostsUrl ?? '';
    final providedUid = _urls.uidFromUrl(provided);
    final authorUrl = thread.authorUrl ?? '';
    final authorUid = _urls.forumLinkTarget(authorUrl) is ForumUserLinkTarget
        ? _urls.uidFromUrl(authorUrl)
        : null;
    final uid = _urls.forumLinkTarget(provided) is ForumThreadLinkTarget &&
            providedUid != null &&
            _urls.tidFromUrl(provided) == tid &&
            (authorUid == null || providedUid == authorUid)
        ? providedUid
        : authorUid;
    return uid == null
        ? null
        : _urls.absoluteUrl('read.php?tid-$tid-uid-$uid.html');
  }

  bool isOriginalPosterFilter(ForumThread thread) {
    final activeUid = _urls.uidFromUrl(thread.url);
    final original = originalPosterPostsUrl(thread);
    return activeUid != null &&
        original != null &&
        activeUid == _urls.uidFromUrl(original);
  }

  String? unfilteredThreadUrl(ForumThread thread) {
    final tid = _urls.tidFromUrl(thread.url);
    return tid == null || _urls.uidFromUrl(thread.url) == null
        ? null
        : _urls.absoluteUrl('read.php?tid-$tid.html');
  }

  String? threadShareUrl(ForumThread thread) {
    if (_urls.forumLinkTarget(thread.url) is! ForumThreadLinkTarget)
      return null;
    final tid = _urls.tidFromUrl(thread.url);
    return tid == null ? null : _urls.absoluteUrl('read.php?tid-$tid.html');
  }

  Future<ForumAttachment> downloadAttachment(
    String url, {
    required Directory directory,
    String? suggestedName,
  }) =>
      _client.downloadAttachment(
        url,
        directory: directory,
        suggestedName: suggestedName,
      );

  Future<void> updateNetworkConfig(ForumNetworkConfig config) async {
    if (config == _config) return;
    await ForumNetworkSettings.save(config);
    _sessionEpoch.value++;
    _client.close(force: true);
    _config = config;
    ForumHttpRouting.updateProxy(config.proxy);
    _urls = ForumUrlResolver(baseUri: config.baseUri);
    _boardThreadPageParser = BoardThreadPageParser(urls: _urls);
    _homePageParser = HomePageParser(urls: _urls);
    _searchResultParser = SearchResultParser(urls: _urls);
    _threadDetailParser = ThreadDetailParser(
      urls: _urls,
      contentParser: ThreadContentParser(urls: _urls),
    );
    _userProfileParser = UserProfileParser(urls: _urls);
    _userContentQueries = UserContentQueryService(
      getDocument: _fetchUserContentDocument,
      urls: _urls,
      sessionEpoch: () => _sessionEpoch.value,
    );
    _profileCache = UserProfileCache(urls: _urls);
    _client = ForumClient(config: config);
    _sessionUser.value = null;
  }

  ForumPmParser get _pmParser => ForumPmParser(baseUri: _config.baseUri);

  T _parsePm<T>(String response, T Function(dom.Document) parse) {
    try {
      return parse(html_parser.parse(response));
    } on ForumRequestException {
      // Private titles and quoted bodies can contain error-page phrases.
      _throwIfBlockedPage(response);
      rethrow;
    }
  }

  void _captureAccountIdentity(dom.Document document) {
    final identity = _userProfileParser.parseAccountIdentity(document);
    if (identity == null) return;
    final previous = _accountIdentity.value;
    _accountIdentity.value = ForumAccountIdentity(
      systemName: identity.systemName,
      uid: identity.uid,
      nickname: identity.uid != null && identity.uid == previous?.uid
          ? previous?.nickname
          : null,
      avatarUrl: identity.avatarUrl,
    );
    _maybeLoadBlocking();
  }

  Future<ForumAccountForm> fetchForumPreferences() =>
      _accountService.fetchForumPreferences();

  Future<ForumAccountForm> fetchAccountProfileForm() =>
      _accountService.fetchAccountProfileForm();

  Future<ForumAccountAvatarPage> fetchAccountSystemAvatars({int page = 1}) =>
      _accountService.fetchAccountSystemAvatars(page: page);

  Future<void> saveForumPreferences(
    ForumAccountForm form,
    Map<String, List<String>> changes,
  ) async {
    final epoch = _sessionEpoch.value;
    await _accountService.saveForumPreferences(form, changes);
    await _refreshEditedAccount(epoch);
  }

  Future<void> saveAccountProfileForm(
    ForumAccountForm form,
    Map<String, List<String>> changes, {
    ForumAccountUpload? avatar,
  }) async {
    final epoch = _sessionEpoch.value;
    await _accountService.saveAccountProfileForm(form, changes, avatar: avatar);
    await _refreshEditedAccount(epoch);
  }

  Future<void> _refreshEditedAccount(int epoch) async {
    if (epoch != _sessionEpoch.value) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变，请重试');
    }
    final uid = _accountIdentity.value?.uid;
    _clearProfileDetails();
    _accountNicknameFuture = null;
    if (uid == null) return;
    try {
      await fetchUserProfileOverview(
          _urls.userTabUrl(uid, UserProfileTab.profile));
    } catch (_) {
      // The native save succeeded; an optional header refresh must not retry it.
    }
    if (epoch != _sessionEpoch.value) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变，请重试');
    }
  }

  Future<UserContentResult> fetchUserContent(
    UserContentQuery query, {
    bool refresh = false,
  }) =>
      _userContentQueries.fetch(query, refresh: refresh);

  Future<List<UserContentClassification>> fetchUserContentBoardFilters(
    String boardId,
  ) =>
      _userContentQueries.fetchBoardFilters(boardId);

  Future<dom.Document> _fetchUserContentDocument(String path) async {
    final client = _client;
    final epoch = _sessionEpoch.value;
    final response = await client.get(path);
    if (!identical(client, _client) || epoch != _sessionEpoch.value) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变，请重试');
    }
    return html_parser.parse(response);
  }

  Future<void> loadAccountNickname() {
    final uid = _accountIdentity.value?.uid;
    if (!isLoggedIn || uid == null) return SynchronousFuture(null);
    return _accountNicknameFuture ??= _loadAccountNickname(uid);
  }

  Future<void> _loadAccountNickname(String uid) async {
    final epoch = _sessionEpoch.value;
    final generation = _profileDetailsGeneration;
    final profileUrl = _urls.userTabUrl(uid, UserProfileTab.profile);
    try {
      var profile = await _profileCache.loadOverview(profileUrl);
      if (epoch != _sessionEpoch.value) return;
      if (profile?.uid != uid) profile = null;
      profile ??= await fetchUserProfileOverview(profileUrl);
      if (epoch != _sessionEpoch.value ||
          generation != _profileDetailsGeneration) return;
      _applyAccountProfile(profile);
    } catch (_) {
      // Optional nickname loading keeps the verified header identity on failure.
    }
  }

  void _applyAccountProfile(UserProfile profile) {
    final identity = _accountIdentity.value;
    if (identity == null || identity.uid != profile.uid) return;
    final nickname = profile.nickname;
    _accountIdentity.value = ForumAccountIdentity(
      systemName: identity.systemName,
      uid: identity.uid,
      nickname: nickname == null || nickname.isEmpty ? null : nickname,
      avatarUrl: profile.avatarUrl ?? identity.avatarUrl,
    );
  }

  ForumReplyNoticeParser get _replyNoticeParser =>
      ForumReplyNoticeParser(urls: _urls);

  void _captureIndexNotices(dom.Document document) {
    _replyNoticeVerify = _replyNoticeParser.verifyToken(document);
    _noticeFlags.value = ForumNoticeFlags(
      replyNotice: _replyNoticeParser.hasReplyNotice(document),
      unreadPm: _replyNoticeParser.hasUnreadPm(document),
    );
    _maybeLoadBlocking();
  }

  Future<String> _postReplyNotice(Map<String, String> fields) async {
    final epoch = _sessionEpoch.value;
    final client = _client;
    void requireCurrentSession() {
      if (epoch != _sessionEpoch.value || client != _client) {
        throw const ForumRequestException(
            ForumRequestKind.loginRequired, '登录状态已改变');
      }
    }

    final previous = _replyNoticeQueue;
    final completed = Completer<void>();
    _replyNoticeQueue = completed.future;
    try {
      await previous;
      requireCurrentSession();
      var wait = _replyNoticeReadyAt?.difference(DateTime.now());
      while (wait != null && wait > Duration.zero) {
        await Future<void>.delayed(wait);
        wait = _replyNoticeReadyAt?.difference(DateTime.now());
      }
      requireCurrentSession();
      if (_replyNoticeVerify == null) {
        final response = await client.get('index.php');
        requireCurrentSession();
        _throwIfBlockedPage(response);
        _captureIndexNotices(html_parser.parse(response));
      }
      final verify = _replyNoticeVerify;
      if (verify == null) {
        throw const ForumRequestException(
            ForumRequestKind.server, '没有找到操作验证码，请刷新首页后重试');
      }
      final response = await client.post(
        'pw_ajax.php?nowtime=${DateTime.now().millisecondsSinceEpoch}&verify=$verify',
        fields,
      );
      requireCurrentSession();
      return _responseParser.ajaxPayload(response) ?? response;
    } finally {
      _replyNoticeReadyAt =
          DateTime.now().add(const Duration(milliseconds: 1500));
      completed.complete();
    }
  }

  Future<List<ForumReplyNotice>> fetchReplyNotices() async {
    final response = await _postReplyNotice({'action': 'newrp'});
    final List<ForumReplyNotice> notices;
    if (response.trim() == '您的回复列表为空') {
      notices = const [];
    } else {
      try {
        notices = _replyNoticeParser.parse(html_parser.parse(response));
      } on ForumRequestException {
        _throwIfBlockedPage(response);
        rethrow;
      }
    }
    _noticeFlags.value = ForumNoticeFlags(
      replyNotice: notices.isNotEmpty,
      unreadPm: _noticeFlags.value.unreadPm,
    );
    return notices;
  }

  Future<void> deleteReplyNotice(ForumReplyNotice notice) async {
    if (notice.tid <= 0) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '回复提醒编号无效');
    }
    final response = await _postReplyNotice({
      'action': 'delnewrp',
      'tid': '${notice.tid}',
    });
    _throwIfBlockedPage(response);
    final remaining = await fetchReplyNotices();
    if (remaining.any((item) => item.tid == notice.tid)) {
      throw const ForumRequestException(ForumRequestKind.server, '回复提醒未删除，请重试');
    }
  }

  Future<ForumPmPage> fetchPmBox(ForumPmBox box, {String? pagePath}) async {
    final path = _pmParser.requireRoute(
      pagePath ?? 'message.php?action-${box.wireName}.html',
      {box.wireName},
    ).path;
    final response = await _client.getOnce(path);
    return _parsePm(response, (document) => _pmParser.parseBox(document, box));
  }

  Future<ForumPmDetail> fetchPmDetail(ForumPmSummary message) async {
    final target = _pmParser.requireDetail(message);
    final response = await _client.getOnce(target.path);
    return _parsePm(
        response, (document) => _pmParser.parseDetail(document, message));
  }

  Future<ForumPmCompose> fetchPmCompose({String? path}) async {
    final source = _pmParser
        .requireRoute(path ?? 'message.php?action-write.html', {'write'});
    final response = await _client.getOnce(source.path);
    return _parsePm(
        response, (document) => _pmParser.parseCompose(document, source));
  }

  Future<ForumPmActionResult> submitPm({
    required ForumPmCompose compose,
    required String recipientUid,
    required String title,
    required String body,
    bool saveToSendbox = false,
  }) async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(recipientUid.trim())) {
      throw const ForumRepositoryException('请输入正整数收件人 UID');
    }
    if (title.trim().isEmpty || body.trim().isEmpty) {
      throw const ForumRepositoryException('标题和内容不能为空');
    }
    _pmParser.validateCompose(compose);
    final fields = <String, String>{
      'font': '',
      'size': '',
      'color': '',
      ...compose.fields,
      'action': 'write',
      'step': '2',
      'touidmsg': recipientUid.trim(),
      'msg_title': title.trim(),
      'atc_content': body,
    }..remove('ifsave');
    if (saveToSendbox) fields['ifsave'] = 'Y';
    final response = await _client.post(compose.actionPath, fields);
    _throwIfBlockedPage(response);
    return _pmParser.parseActionResult(html_parser.parse(response));
  }

  Future<ForumPmActionResult> markPmUnread(ForumPmDetail detail) async {
    final message = detail.summary;
    _pmParser.requireDetail(message);
    final target =
        _pmParser.requireRoute(detail.markUnreadPath ?? '', {'unread'});
    if (message.type != ForumPmType.personal ||
        target.fields['mid'] != message.id) {
      throw const ForumRepositoryException('服务器未提供此消息的标记未读入口');
    }
    final response = await _client.getOnce(target.path);
    return _parsePm(
        response, (document) => _pmParser.parseUnreadResult(document, message));
  }

  Future<ForumPmActionResult> deletePm(ForumPmSummary message,
      {ForumPmDetail? detail}) async {
    _pmParser.requireDetail(message);
    // shortcut: broadcast pdelid deletion is unverified, add it after protocol evidence.
    if (message.type == ForumPmType.broadcast) {
      throw const ForumRepositoryException('群发消息不能使用个人消息的删除入口');
    }
    if (detail != null &&
        (detail.summary.box != message.box ||
            detail.summary.type != message.type ||
            detail.summary.id != message.id)) {
      throw const ForumRepositoryException('私讯详情与删除目标不一致');
    }
    final link = detail?.deletePath;
    String response;
    if (link != null) {
      final target = _pmParser.requireRoute(link, {'del'});
      if (target.fields['towhere'] != message.box.wireName ||
          target.fields['delids'] != message.id) {
        throw const ForumRepositoryException('私讯删除入口与所属箱不一致');
      }
      response = await _client.getOnce(target.path);
    } else {
      if (!message.canDelete) {
        throw const ForumRepositoryException('服务器未提供此消息的删除入口');
      }
      final fresh = await _client
          .getOnce('message.php?action-${message.box.wireName}.html');
      final fields = _parsePm(
          fresh, (document) => _pmParser.singleDeleteFields(document, message));
      response = await _client.post('message.php', fields);
    }
    _throwIfBlockedPage(response);
    return _pmParser.parseActionResult(html_parser.parse(response));
  }

  Future<ForumPmChatlog> fetchPmChatlog(String path) async {
    final target = _pmParser.requireRoute(path, {'chatlog'});
    final response = await _client.getOnce(target.path);
    return _parsePm(
        response,
        (document) =>
            _pmParser.parseChatlog(document, target.fields['withuid']!));
  }

  Future<bool> restoreSession() async {
    await _client.restoreCookies();
    if (!_client.isLoggedIn) {
      _sessionEpoch.value++;
      _sessionUser.value = null;
      return false;
    }

    final client = _client;
    final epoch = _sessionEpoch.value;
    final header = await _fetchSessionHeader();
    if (!identical(client, _client) || epoch != _sessionEpoch.value)
      return false;
    final username = header.username;
    if (username == null) {
      await clearSession();
      return false;
    }
    if (username != currentUsername) _sessionEpoch.value++;
    _sessionUser.value = username;
    _restoredDesktopHtml = header.desktopHtml;
    if (header.desktopHtml != null) {
      final document = html_parser.parse(header.desktopHtml!);
      _captureAccountIdentity(document);
      _captureIndexNotices(document);
    }
    return true;
  }

  Future<void> clearSession() async {
    _sessionEpoch.value++;
    _sessionUser.value = null;
    await _client.clearSession();
  }

  Future<bool> login({
    required String username,
    required String password,
    String captcha = '',
    Map<String, String> fields = const {},
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return false;
    }

    final result = await submitLogin(
      username: username,
      password: password,
      captcha: captcha,
      fields: fields,
    );
    return result.success;
  }

  Future<LoginChallenge> fetchLoginChallenge() async {
    final html = await _client.get('login.php');
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="login"]') ??
        document.querySelector('form[action*="login.php"]') ??
        _loginFormFromFields(document);
    if (form == null) {
      throw ForumRepositoryException(
        _responseParser.pageMessage(html) == '登录失败'
            ? '没有找到登录表单'
            : _responseParser.pageMessage(html),
      );
    }

    final fields = _formParser.defaults(form)
      ..remove('pwuser')
      ..remove('pwpwd')
      ..remove('gdcode');

    final captchaSrc = form.querySelector('#ckcode')?.attributes['src'] ??
        form.querySelector('img[src*="ck.php"]')?.attributes['src'] ??
        form.querySelector('img[src*="gdcode"]')?.attributes['src'] ??
        form.querySelector('img[src*="captcha"]')?.attributes['src'];
    if (captchaSrc == null || captchaSrc.isEmpty) {
      throw const ForumRepositoryException('没有找到验证码图片');
    }

    return LoginChallenge(
      fields: fields,
      captchaBytes: await _client.getBytes(_urls.captchaPath(captchaSrc)),
    );
  }

  Future<LoginResult> submitLogin({
    required String username,
    required String password,
    required String captcha,
    required Map<String, String> fields,
  }) async {
    if (username.trim().isEmpty) {
      return const LoginResult(success: false, message: '用户名不能为空');
    }
    if (password.isEmpty) {
      return const LoginResult(success: false, message: '密码不能为空');
    }
    if (captcha.trim().isEmpty) {
      return const LoginResult(success: false, message: '验证码不能为空');
    }

    _sessionEpoch.value++;
    final response = await _client.post('login.php', {
      ...fields,
      'step': fields['step'] ?? '2',
      'lgt': fields['lgt'] ?? '0',
      'hideid': fields['hideid'] ?? '0',
      'cktime': fields['cktime'] ?? '31536000',
      'pwuser': username.trim(),
      'pwpwd': password,
      'gdcode': captcha.trim(),
      'submit': '登 录',
    });

    if (_client.isLoggedIn || response.contains('登录成功')) {
      _sessionUser.value = _responseParser.loggedInUsername(response) ??
          await _fetchLoggedInUsername() ??
          username.trim();
      _captureAccountIdentity(html_parser.parse(response));
      return const LoginResult(success: true, message: '登录成功');
    }

    return LoginResult(
      success: false,
      message: _responseParser.pageMessage(response),
    );
  }

  void _invalidateQuickLists() {
    _homeGeneration++;
    _homeQuickLists = {};
    _quickListRequests.clear();
  }

  void _requireHome(ForumClient client, int epoch, int generation,
      String? account, int sourcesRevision) {
    if (!identical(client, _client) ||
        epoch != _sessionEpoch.value ||
        generation != _homeGeneration ||
        account != localPreferenceAccount ||
        sourcesRevision !=
            HomeReadingPreferences.quickSourcesRevision(account: account)) {
      throw const ForumRepositoryException('首页已更新，请重新打开列表');
    }
  }

  Future<List<ForumThread>> fetchQuickList(ForumQuickList list) async {
    if (!_homeQuickLists.contains(list)) {
      throw const ForumRepositoryException('首页已更新，请重新打开列表');
    }
    final generation = _homeGeneration;
    final client = _client;
    final epoch = _sessionEpoch.value;
    final account = _homePreferenceAccount;
    final sourcesRevision = _homeSourcesRevision;
    void requireCurrent() =>
        _requireHome(client, epoch, generation, account, sourcesRevision);
    requireCurrent();
    if (list.threads != null) return list.threads!;
    final cached = _quickListRequests[list];
    if (cached != null) return cached;
    final script = list.scriptUrl;
    if (script == null || !_urls.isForumUrl(script)) {
      throw const ForumRepositoryException('没有找到讨论列表');
    }
    final request = (list.source.kind == HomeQuickSourceKind.board
            ? _readBoardQuickList(list, client, requireCurrent)
            : client
                .getOnceGuarded(_urls.relativePath(script),
                    requireCurrentSession: requireCurrent)
                .then((response) {
                requireCurrent();
                final threads =
                    _homePageParser.parseLatestThreadsFromScript(response);
                if (threads.isEmpty)
                  throw const ForumRepositoryException('没有解析到讨论列表');
                return threads;
              }))
        .catchError((Object error, StackTrace stack) {
      requireCurrent();
      if (list.source.kind == HomeQuickSourceKind.site &&
          list.fallbackThreads.isNotEmpty) return list.fallbackThreads;
      Error.throwWithStackTrace(error, stack);
    });
    _quickListRequests[list] = request;
    try {
      return await request;
    } catch (_) {
      if (identical(_quickListRequests[list], request))
        _quickListRequests.remove(list);
      rethrow;
    }
  }

  Future<List<ForumThread>> _readBoardQuickList(ForumQuickList list,
      ForumClient client, void Function() requireCurrent) async {
    final feed = await client.getOnceGuarded(
        _urls.relativePath(list.scriptUrl!),
        requireCurrentSession: requireCurrent);
    requireCurrent();
    final threads = _homePageParser.parseLatestThreadsFromScript(feed);
    if (threads.isNotEmpty) return threads.take(8).toList(growable: false);
    _throwIfBlockedPage(feed);
    var fid = list.source.fid!;
    final order = list.source.order == QuickOrder.posted
        ? ForumThreadOrder.postedAt
        : ForumThreadOrder.lastPost;
    for (var attempt = 0; attempt < 2; attempt++) {
      final category = ForumCategory(name: '版块 $fid', slug: 'fid-$fid');
      final path = _urls.boardDesktopPath(category, order: order)!;
      final response = await client.getOnceGuarded(path,
          requireCurrentSession: requireCurrent,
          redirectPolicy: ForumReadRedirectPolicy.board);
      requireCurrent();
      final document = _boardDocument(response, category);
      final links = document.querySelectorAll('#breadcrumbs a[href]');
      final boardIds = [
        for (final link in links)
          if (_urls.fidFromUrl(link.attributes['href']!) case final fid?) fid
      ];
      final listIds = [
        for (final link in links)
          if (link.text.contains('列表模式'))
            if (_urls.fidFromUrl(link.attributes['href']!) case final fid?) fid
      ];
      final canonical = listIds.lastOrNull ?? boardIds.lastOrNull;
      final validPage = document.querySelector('ul.stream') != null ||
          (canonical != fid && listIds.isNotEmpty);
      if (canonical == null || !validPage) {
        throw ForumRequestException(
            canonical == null
                ? ForumRequestKind.invalidInput
                : ForumRequestKind.server,
            canonical == null ? '来源版块不存在' : '没有解析到版块列表');
      }
      if (canonical != fid) {
        // A picture-wall redirect drops the requested order; apply it to the real board.
        fid = canonical;
        continue;
      }
      final name = _boardThreadPageParser.parseBoardName(document, category) ??
          category.name;
      return _boardThreadPageParser
          .parseWallThreads(
              document, ForumCategory(name: name, slug: category.slug))
          .take(8)
          .toList(growable: false);
    }
    throw const ForumRequestException(
        ForumRequestKind.invalidInput, '来源版块已变更，请重新选择');
  }

  List<ForumQuickList> _configuredQuickLists(List<ForumQuickList> native,
      List<HomeQuickSource> sources, List<ForumSection> sections) {
    String? boardName(List<ForumBoard> boards, String fid) {
      for (final board in boards) {
        if (_urls.fidFromUrl(board.url) == fid) return board.name;
        final child = boardName(board.children, fid);
        if (child != null) return child;
      }
      return null;
    }

    final lists = <ForumQuickList>[];
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      if (source.kind == HomeQuickSourceKind.site) {
        if (index < native.length) lists.add(native[index]);
      } else if (source.kind == HomeQuickSourceKind.board) {
        final name = boardName(
                [for (final section in sections) ...section.items],
                source.fid!) ??
            source.boardPath?.split(' / ').last ??
            '版块 ${source.fid}';
        final script = Uri(path: 'new.php', queryParameters: {
          'action': 'article',
          'fidin': source.fid!,
          'order': source.order == QuickOrder.posted ? '2' : '1',
          'num': '8',
          'length': '120',
          'postdate': '1',
          'author': '1',
          'replies': '1',
          'fname': '1',
          'simple': '1',
        });
        lists.add(ForumQuickList(
            title: '$name ${source.order == QuickOrder.posted ? '新帖' : '回复'}',
            source: source,
            scriptUrl: _urls.baseUri.resolveUri(script).toString()));
      }
    }
    return List.unmodifiable(lists);
  }

  Future<ForumHomeSnapshot> fetchHome() async {
    _invalidateQuickLists();
    final generation = _homeGeneration;
    // Consume session verification once; refreshes still fetch a fresh directory.
    final restoredDesktopHtml = _restoredDesktopHtml;
    _restoredDesktopHtml = null;
    final client = _client;
    final epoch = _sessionEpoch.value;
    final account = localPreferenceAccount;
    final sourcesRevision =
        HomeReadingPreferences.quickSourcesRevision(account: account);
    void requireCurrent() =>
        _requireHome(client, epoch, generation, account, sourcesRevision);
    final sources =
        (await HomeReadingPreferences.load(account: account)).quickSources;
    requireCurrent();
    final html = await client.getOnceGuarded('simple/index.php',
        requireCurrentSession: requireCurrent);
    if (!identical(client, _client) || epoch != _sessionEpoch.value) {
      throw const ForumRepositoryException('网络或登录状态已改变，请重试');
    }
    final document = html_parser.parse(html);
    var latest = _homePageParser.parseLatestThreads(document);
    final latestScriptUrl = _homePageParser.latestThreadsScriptUrl(document);
    if (latestScriptUrl != null &&
        sources.first.kind == HomeQuickSourceKind.site) {
      try {
        final script = await client.getOnceGuarded(
            _urls.relativePath(latestScriptUrl),
            requireCurrentSession: requireCurrent);
        requireCurrent();
        final fetched = _homePageParser.parseLatestThreadsFromScript(script);
        if (fetched.isNotEmpty) latest = fetched;
      } catch (_) {
        if (latest.isEmpty) rethrow;
      }
    }
    final hot = _homePageParser.parseHotCategories(document);
    var sections = _homePageParser.parseForumSections(document);
    dom.Document? indexDocument;
    try {
      final desktopDocument = html_parser.parse(restoredDesktopHtml ??
          await client.getOnceGuarded('index.php',
              requireCurrentSession: requireCurrent));
      final desktopSections =
          _homePageParser.parseDesktopForumSections(desktopDocument);
      if (desktopSections.isNotEmpty) sections = desktopSections;
      indexDocument = desktopDocument;
    } catch (_) {
      // Keep the mobile/simple directory if the desktop home is unavailable.
    }

    if (!identical(client, _client) || epoch != _sessionEpoch.value) {
      throw const ForumRepositoryException('网络或登录状态已改变，请重试');
    }
    requireCurrent();
    if (latest.isEmpty && sources.first.kind == HomeQuickSourceKind.site) {
      throw const ForumRepositoryException('没有解析到最新讨论');
    }
    if (hot.isEmpty && sections.isEmpty) {
      throw const ForumRepositoryException('没有解析到版块列表');
    }

    if (generation != _homeGeneration) {
      throw const ForumRepositoryException('首页已更新，请重试');
    }
    final quickLists = _configuredQuickLists(
        _homePageParser.parseQuickLists(document, latest), sources, sections);
    if (quickLists.isEmpty) {
      throw const ForumRequestException(ForumRequestKind.server, '没有找到速览栏目');
    }
    _homeQuickLists = quickLists.toSet();
    _homePreferenceAccount = account;
    _homeSourcesRevision = sourcesRevision;
    if (indexDocument != null) {
      _captureIndexNotices(indexDocument);
      _captureAccountIdentity(indexDocument);
    }
    return ForumHomeSnapshot(
      latest: latest,
      hot: hot,
      sections: sections,
      hasReplyNotice: _noticeFlags.value.replyNotice,
      hasUnreadPm: _noticeFlags.value.unreadPm,
      quickLists: quickLists,
    );
  }

  Future<List<ForumThread>> fetchLatestThreads() async {
    final home = await fetchHome();
    return home.latest;
  }

  Future<List<ForumTask>> fetchForumTasks(ForumTaskStatus status) {
    final key = (status: status, client: _client, epoch: _sessionEpoch.value);
    final pending = _taskReadRequests[key];
    if (pending != null) return pending;
    late Future<List<ForumTask>> request;
    request = _readForumTasks(status, key.client, key.epoch).whenComplete(() {
      if (identical(_taskReadRequests[key], request)) {
        _taskReadRequests.remove(key);
      }
    });
    _taskReadRequests[key] = request;
    return request;
  }

  Future<List<ForumTask>> _readForumTasks(
      ForumTaskStatus status, ForumClient client, int epoch) async {
    final path = switch (status) {
      ForumTaskStatus.available => 'plugin.php?H_name-tasks.html',
      ForumTaskStatus.inProgress =>
        'plugin.php?H_name-tasks-actions-newtasks.html.html',
      ForumTaskStatus.completed =>
        'plugin.php?H_name-tasks-actions-endtasks.html.html',
      ForumTaskStatus.failed =>
        'plugin.php?H_name-tasks-actions-errotasks.html.html',
    };
    final html = await client.get(path);
    if (!identical(client, _client) || epoch != _sessionEpoch.value) {
      throw const ForumRepositoryException('网络或登录状态已改变，请重试');
    }
    _throwIfBlockedPage(html);
    final tasks = _tasksParser.parse(html_parser.parse(html), status);
    ForumTraceLogger.log(
      'Tasks',
      'fetchForumTasks status=$status path=$path count=${tasks.length}',
    );
    for (final task in tasks) {
      ForumTraceLogger.log('Tasks', '  ${_describeTask(task)}');
    }
    return tasks;
  }

  void _requireTaskSession(ForumClient client, int epoch) {
    if (!identical(client, _client) || epoch != _sessionEpoch.value) {
      throw const ForumRepositoryException('网络或登录状态已改变，请重试');
    }
  }

  Future<ForumTaskActionResult> runForumTask(
    ForumTask task, {
    bool claimReward = false,
  }) async {
    final id = task.id;
    if (id == null || id.isEmpty) {
      return const ForumTaskActionResult(
        success: false,
        message: '没有找到任务 ID',
      );
    }

    final client = _client;
    final epoch = _sessionEpoch.value;
    final expectation = claimReward
        ? _ForumTaskActionExpectation.claimReward
        : _ForumTaskActionExpectation.start;
    final action = claimReward ? 'job2' : 'job';
    ForumTraceLogger.log(
      'Action',
      'runForumTask task=${_describeTask(task)} expectation=$expectation action=$action',
    );
    final response = await client.getForm(
      'plugin.php?H_name=tasks&action=ajax&actions=$action&cid=$id',
      followRedirects: false,
      requireCurrentSession: () => _requireTaskSession(client, epoch),
    );
    _requireTaskSession(client, epoch);
    final payload = _responseParser.ajaxPayload(response);
    final parts = payload?.split('\t') ?? const <String>[];
    final status = parts.isEmpty ? '' : parts.first.trim().toLowerCase();
    final message = parts.length > 1
        ? _cleanText(parts[1])
        : _responseParser.ajaxMessage(response);
    final success = parts.length > 1 && status == 'success';
    ForumTraceLogger.log(
      'Action',
      'runForumTask response task=${task.name} expectation=$expectation action=$action rawStatus=$status success=$success message=$message raw=$response',
    );
    return ForumTaskActionResult(
      success: success,
      message: message.isEmpty
          ? success
              ? expectation == _ForumTaskActionExpectation.claimReward
                  ? '任务奖励领取完成'
                  : '任务领取完成'
              : '任务操作失败'
          : message,
    );
  }

  Future<ForumTaskQuickClaimResult> claimForumTaskRewards() async {
    ForumTraceLogger.log('Claim', 'claimForumTaskRewards BEGIN');
    final client = _client;
    final epoch = _sessionEpoch.value;
    final now = _nowUtc();
    final failures = <String>[];
    final skipped = <String>[];
    var appliedCount = 0;
    final claimedRewards = <ForumTaskClaimItem>[];
    final handledNames = <String>{};
    var shouldRefresh = false;
    var checkedRecovery = false;
    var pages = await _fetchTaskPages();
    _requireTaskSession(client, epoch);
    _logTaskPages('Claim', 'initial pages', pages);

    final baselineDecisions = _buildTaskDecisions(
      pages,
      now: now,
      mode: _ForumTaskDecisionMode.baseline,
      handledNames: handledNames,
    );
    _logDecisions('Claim', 'baseline decisions', baselineDecisions);
    final recoveryNames = <String>{};

    for (final decision in baselineDecisions) {
      ForumTraceLogger.log(
        'Claim',
        'baseline decision name=${decision.name} kind=${decision.kind}',
      );
      switch (decision.kind) {
        case _ForumTaskDecisionKind.startThenClaim:
          _requireTaskSession(client, epoch);
          final outcome = await _startAutoTask(
            decision.task!,
            claimedRewards: claimedRewards,
            failures: failures,
          );
          _requireTaskSession(client, epoch);
          appliedCount += outcome.appliedCount;
          shouldRefresh = shouldRefresh || outcome.shouldRefresh;
          if (outcome.handled) handledNames.add(decision.name);
          if (outcome.needsRecovery) recoveryNames.add(decision.name);
          ForumTraceLogger.log(
            'Claim',
            'start outcome name=${decision.name} applied=${outcome.appliedCount} handled=${outcome.handled} shouldRefresh=${outcome.shouldRefresh} needsRecovery=${outcome.needsRecovery}',
          );
          break;
        case _ForumTaskDecisionKind.unknown:
          recoveryNames.add(decision.name);
          ForumTraceLogger.log(
            'Claim',
            'baseline unknown name=${decision.name} recoveryNames=${recoveryNames.toList()}',
          );
          break;
        case _ForumTaskDecisionKind.claimInProgress:
        case _ForumTaskDecisionKind.inProgress:
        case _ForumTaskDecisionKind.handled:
          ForumTraceLogger.log(
            'Claim',
            'baseline no-op name=${decision.name} kind=${decision.kind}',
          );
          break;
      }
    }

    if (recoveryNames.isNotEmpty) {
      ForumTraceLogger.log(
        'Claim',
        'recovery BEGIN names=${recoveryNames.toList()..sort()}',
      );
      checkedRecovery = true;
      pages = _ForumTaskPages(
        completed: pages.completed,
        available: pages.available,
        inProgress: await fetchForumTasks(ForumTaskStatus.inProgress),
      );
      _requireTaskSession(client, epoch);
      _logTaskPages('Claim', 'recovery pages', pages);
      final recoveryDecisions = _buildTaskDecisions(
        pages,
        now: now,
        mode: _ForumTaskDecisionMode.recovery,
        handledNames: handledNames,
      );
      _logDecisions('Claim', 'recovery decisions', recoveryDecisions);

      for (final decision in recoveryDecisions) {
        ForumTraceLogger.log(
          'Claim',
          'recovery decision name=${decision.name} kind=${decision.kind}',
        );
        if (!recoveryNames.contains(decision.name)) continue;
        if (decision.kind != _ForumTaskDecisionKind.claimInProgress) continue;
        _requireTaskSession(client, epoch);
        final outcome = await _claimTaskReward(
          decision.task!,
          claimedRewards: claimedRewards,
          failures: failures,
        );
        _requireTaskSession(client, epoch);
        shouldRefresh = shouldRefresh || outcome.shouldRefresh;
        if (outcome.handled) handledNames.add(decision.name);
        ForumTraceLogger.log(
          'Claim',
          'claim outcome name=${decision.name} handled=${outcome.handled} shouldRefresh=${outcome.shouldRefresh} needsRecovery=${outcome.needsRecovery}',
        );
      }
    }

    if (shouldRefresh) {
      ForumTraceLogger.log('Claim', 'refresh pages after actions');
      pages = await _refreshTaskPages();
      _requireTaskSession(client, epoch);
      _logTaskPages('Claim', 'refreshed pages', pages);
    }

    final finalDecisions = _buildTaskDecisions(
      pages,
      now: now,
      mode: checkedRecovery
          ? _ForumTaskDecisionMode.recovery
          : _ForumTaskDecisionMode.baseline,
      handledNames: handledNames,
    );
    _logDecisions('Claim', 'final decisions', finalDecisions);
    _requireTaskSession(client, epoch);
    final snapshot = await _saveTaskSnapshotFromPages(
      inProgress: pages.inProgress,
      available: pages.available,
      completed: pages.completed,
    );
    _requireTaskSession(client, epoch);
    ForumTraceLogger.log(
      'Claim',
      'snapshot saved ${_describeSnapshot(snapshot)}',
    );
    final targetNames = finalDecisions.map((decision) => decision.name).toSet();
    final inProgressNames = finalDecisions
        .where((decision) =>
            decision.kind == _ForumTaskDecisionKind.inProgress ||
            decision.kind == _ForumTaskDecisionKind.claimInProgress)
        .map((decision) => decision.name)
        .toSet();
    final snapshotHandledNames = snapshot.tasks
        .where((task) =>
            task.availability == ForumTaskAvailability.completed ||
            task.availability == ForumTaskAvailability.coolingDown)
        .map((task) => task.name)
        .toSet();
    final alreadyHandled = claimedRewards.isEmpty &&
        appliedCount == 0 &&
        failures.isEmpty &&
        inProgressNames.isEmpty &&
        targetNames.isNotEmpty &&
        finalDecisions.every(
          (decision) => decision.kind == _ForumTaskDecisionKind.handled,
        ) &&
        targetNames.every(
          (name) =>
              handledNames.contains(name) ||
              snapshotHandledNames.contains(name),
        );
    ForumTraceLogger.log(
      'Claim',
      'claimForumTaskRewards END appliedCount=$appliedCount claimed=${claimedRewards.map((item) => item.name).toList()} failures=$failures inProgress=${inProgressNames.toList()} alreadyHandled=$alreadyHandled handledNames=${handledNames.toList()} recoveryChecked=$checkedRecovery recoveryNames=${recoveryNames.toList()}',
    );

    return ForumTaskQuickClaimResult(
      appliedCount: appliedCount,
      claimedRewards: claimedRewards,
      failures: failures,
      skipped: skipped,
      inProgress: inProgressNames.toList(),
      alreadyHandled: alreadyHandled,
    );
  }

  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async {
    final client = _client;
    final epoch = _sessionEpoch.value;
    ForumTraceLogger.log(
      'AutoClaim',
      'autoClaimForumTaskRewardsIfDue BEGIN isLoggedIn=$isLoggedIn',
    );
    if (!isLoggedIn) {
      ForumTraceLogger.log('AutoClaim', 'skip because not logged in');
      return null;
    }

    final cached = await loadCachedForumTaskSnapshot();
    _requireTaskSession(client, epoch);
    ForumTraceLogger.log(
      'AutoClaim',
      'cached snapshot=${cached == null ? 'null' : _describeSnapshot(cached)}',
    );
    if (cached != null && !cached.shouldAutoClaimAt(_nowUtc())) {
      ForumTraceLogger.log('AutoClaim', 'skip because shouldAutoClaimAt=false');
      return null;
    }

    ForumTraceLogger.log('AutoClaim', 'proceed to claimForumTaskRewards');
    return claimForumTaskRewards();
  }

  Future<_StartTaskOutcome> _startAutoTask(
    ForumTask task, {
    required List<ForumTaskClaimItem> claimedRewards,
    required List<String> failures,
  }) async {
    ForumTraceLogger.log('Start', '_startAutoTask task=${_describeTask(task)}');
    final startResult = await runForumTask(
      task,
      claimReward: false,
    );
    final startDecision = _classifyTaskAction(
      startResult,
      expectation: _ForumTaskActionExpectation.start,
    );
    ForumTraceLogger.log(
      'Start',
      '_startAutoTask decision task=${task.name} kind=${startDecision.kind} message=${startDecision.message}',
    );
    switch (startDecision.kind) {
      case _ForumTaskActionKind.started:
        return const _StartTaskOutcome(
          appliedCount: 1,
          shouldRefresh: true,
          needsRecovery: true,
        );
      case _ForumTaskActionKind.alreadyStarted:
        return const _StartTaskOutcome(needsRecovery: true);
      case _ForumTaskActionKind.rewardClaimed:
        claimedRewards.add(_claimItemFromTask(task, startResult.message));
        return const _StartTaskOutcome(
          appliedCount: 1,
          shouldRefresh: true,
          handled: true,
        );
      case _ForumTaskActionKind.alreadyCompleted:
      case _ForumTaskActionKind.coolingDown:
        return const _StartTaskOutcome(handled: true);
      case _ForumTaskActionKind.loginRequired:
      case _ForumTaskActionKind.failure:
        failures.add('${task.name}：${startDecision.message}');
        return const _StartTaskOutcome();
    }
  }

  Future<_ClaimTaskOutcome> _claimTaskReward(
    ForumTask task, {
    required List<ForumTaskClaimItem> claimedRewards,
    required List<String> failures,
  }) async {
    ForumTraceLogger.log(
        'Reward', '_claimTaskReward task=${_describeTask(task)}');
    final claimedNames = claimedRewards.map((item) => item.name).toSet();
    if (claimedNames.contains(task.name)) {
      ForumTraceLogger.log(
        'Reward',
        '_claimTaskReward skip duplicate task=${task.name}',
      );
      return const _ClaimTaskOutcome();
    }

    final result = await runForumTask(
      task,
      claimReward: true,
    );
    final decision = _classifyTaskAction(
      result,
      expectation: _ForumTaskActionExpectation.claimReward,
    );
    ForumTraceLogger.log(
      'Reward',
      '_claimTaskReward decision task=${task.name} kind=${decision.kind} message=${decision.message}',
    );
    switch (decision.kind) {
      case _ForumTaskActionKind.rewardClaimed:
        claimedRewards.add(_claimItemFromTask(task, result.message));
        return const _ClaimTaskOutcome(
          shouldRefresh: true,
          handled: true,
        );
      case _ForumTaskActionKind.alreadyCompleted:
        return const _ClaimTaskOutcome(
          shouldRefresh: true,
          handled: true,
        );
      case _ForumTaskActionKind.coolingDown:
        return const _ClaimTaskOutcome(shouldRefresh: true);
      case _ForumTaskActionKind.started:
      case _ForumTaskActionKind.alreadyStarted:
        return const _ClaimTaskOutcome(needsRecovery: true);
      case _ForumTaskActionKind.loginRequired:
      case _ForumTaskActionKind.failure:
        failures.add('${task.name}：${decision.message}');
        return const _ClaimTaskOutcome();
    }
  }

  ForumTaskClaimItem _claimItemFromTask(ForumTask task, String message) {
    return ForumTaskClaimItem(
      name: task.name,
      reward: task.reward,
      spAmount: _spAmount(task.reward),
      message: message,
    );
  }

  bool _isClaimableForumTask(ForumTask task) {
    if (!task.canRun) return false;
    final label = task.actionLabel ?? '';
    if (label.contains('领取')) return true;
    return task.progressPercent != null && task.progressPercent! >= 100;
  }

  bool _isStartableForumTask(ForumTask task) {
    if (!task.canRun) return false;
    final label = task.actionLabel ?? '';
    return label.contains('申请');
  }

  _ForumTaskActionDecision _classifyTaskAction(
    ForumTaskActionResult result, {
    required _ForumTaskActionExpectation expectation,
  }) {
    final message = _cleanText(result.message);
    final text = message.replaceAll(RegExp(r'\s+'), '');
    if (_looksLikeLoginRequired(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.loginRequired,
        message.isEmpty ? '登录状态已失效' : message,
      );
    }
    if (result.success &&
        expectation == _ForumTaskActionExpectation.claimReward) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.rewardClaimed,
        message.isEmpty ? '任务奖励领取完成' : message,
      );
    }
    if (_alreadyCompletedTask(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.alreadyCompleted,
        message.isEmpty ? '奖励已领取' : message,
      );
    }
    if (_taskCooldownMessage(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.coolingDown,
        message.isEmpty ? '任务处于冷却中' : message,
      );
    }
    if (_alreadyStartedTask(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.alreadyStarted,
        message.isEmpty ? '任务已领取，等待完成' : message,
      );
    }
    if (result.success) {
      if (text.contains('奖励')) {
        return _ForumTaskActionDecision(
          _ForumTaskActionKind.rewardClaimed,
          message.isEmpty ? '任务奖励领取完成' : message,
        );
      }
      if (text.contains('任务') && text.contains('领取')) {
        return _ForumTaskActionDecision(
          _ForumTaskActionKind.started,
          message.isEmpty ? '任务领取完成' : message,
        );
      }
      return _ForumTaskActionDecision(
        expectation == _ForumTaskActionExpectation.claimReward
            ? _ForumTaskActionKind.rewardClaimed
            : _ForumTaskActionKind.started,
        message.isEmpty ? '任务操作完成' : message,
      );
    }
    return _ForumTaskActionDecision(
      _ForumTaskActionKind.failure,
      message.isEmpty ? '任务操作失败' : message,
    );
  }

  int? _spAmount(String? reward) {
    final text = reward ?? '';
    final match =
        RegExp(r'SP\s*币?\s*(\d+)', caseSensitive: false).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  bool _alreadyStartedTask(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('任务已领取') ||
        text.contains('已经领取任务') ||
        text.contains('已申领') ||
        text.contains('已经申领');
  }

  bool _alreadyCompletedTask(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('奖励已领取') ||
        text.contains('已经领取奖励') ||
        text.contains('已经完成') ||
        text.contains('已完成任务');
  }

  bool _taskCooldownMessage(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('距离上次') ||
        text.contains('上次领取未超过') ||
        text.contains('没超过') ||
        text.contains('冷却');
  }

  bool _looksLikeLoginRequired(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('登录') ||
        text.contains('登陆') ||
        text.contains('请先登录') ||
        text.contains('login.php');
  }

  String? get _taskSnapshotScope => currentUsername == null
      ? null
      : '${_urls.baseUri.origin}:$currentUsername';

  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() async {
    final epoch = _sessionEpoch.value;
    final snapshot = await _taskStateStore.load(scope: _taskSnapshotScope);
    return epoch == _sessionEpoch.value ? snapshot : null;
  }

  Future<ForumTaskSnapshot> refreshForumTaskSnapshot() {
    final key = (client: _client, epoch: _sessionEpoch.value);
    final pending = _taskSnapshotRefreshes[key];
    if (pending != null) return pending;
    late Future<ForumTaskSnapshot> request;
    request = _refreshForumTaskSnapshot(key.client, key.epoch).whenComplete(() {
      if (identical(_taskSnapshotRefreshes[key], request)) {
        _taskSnapshotRefreshes.remove(key);
      }
    });
    _taskSnapshotRefreshes[key] = request;
    return request;
  }

  Future<ForumTaskSnapshot> _refreshForumTaskSnapshot(
      ForumClient client, int epoch) async {
    ForumTraceLogger.log('Snapshot', 'refreshForumTaskSnapshot BEGIN');
    final pages = await Future.wait([
      fetchForumTasks(ForumTaskStatus.inProgress),
      fetchForumTasks(ForumTaskStatus.completed),
      fetchForumTasks(ForumTaskStatus.available),
    ]);
    if (!identical(client, _client) || epoch != _sessionEpoch.value) {
      throw const ForumRepositoryException('网络或登录状态已改变，请重试');
    }
    return _saveTaskSnapshotFromPages(
      inProgress: pages[0],
      completed: pages[1],
      available: pages[2],
    );
  }

  Future<ForumTaskSnapshot> _saveTaskSnapshotFromPages({
    required List<ForumTask> inProgress,
    required List<ForumTask> completed,
    required List<ForumTask> available,
  }) async {
    final epoch = _sessionEpoch.value;
    final scope = _taskSnapshotScope;
    final now = _nowUtc();
    final currentCycleCompletedNames =
        _currentCycleCompletedNames(completed, now: now);
    final cooldownsByName = {
      for (final task in available)
        if (task.cooldownRemaining != null) task.name: task.cooldownRemaining!,
    };
    final snapshot = ForumTaskSnapshot(tasks: const [], updatedAt: now).merge([
      ...inProgress.map(
        (task) => _taskStateFromTask(
          task,
          now: now,
          preferCompleted: currentCycleCompletedNames.contains(task.name),
        ),
      ),
      ...completed.map(
        (task) => _taskStateFromTask(
          task,
          now: now,
          cooldownRemaining: cooldownsByName[task.name],
        ),
      ),
      ...available.map((task) => _taskStateFromTask(task, now: now)),
    ]);
    await _taskStateStore.save(snapshot, scope: scope);
    if (epoch != _sessionEpoch.value) {
      throw const ForumRepositoryException('网络或登录状态已改变，请重试');
    }
    ForumTraceLogger.log(
      'Snapshot',
      '_saveTaskSnapshotFromPages ${_describeSnapshot(snapshot)}',
    );
    return snapshot;
  }

  ForumTaskState _taskStateFromTask(
    ForumTask task, {
    required DateTime now,
    Duration? cooldownRemaining,
    bool preferCompleted = false,
  }) {
    final cooldown = cooldownRemaining ?? task.cooldownRemaining;
    return ForumTaskState(
      id: task.id,
      name: task.name,
      availability:
          _availabilityFromTask(task, preferCompleted: preferCompleted),
      reward: task.reward,
      spAmount: _spAmount(task.reward),
      progressPercent: task.progressPercent,
      completedAt: task.completedAt,
      cooldownRemaining: cooldown,
      cooldownThreshold: task.cooldownThreshold,
      nextAvailableAt:
          cooldown == null ? null : now.toUtc().add(cooldown).toUtc(),
    );
  }

  ForumTaskAvailability _availabilityFromTask(
    ForumTask task, {
    bool preferCompleted = false,
  }) {
    if (task.status == ForumTaskStatus.completed) {
      return ForumTaskAvailability.completed;
    }
    if (task.status == ForumTaskStatus.inProgress) {
      if (preferCompleted) return ForumTaskAvailability.completed;
      return _isClaimableForumTask(task)
          ? ForumTaskAvailability.claimable
          : ForumTaskAvailability.inProgress;
    }
    if (task.isCoolingDown) {
      return ForumTaskAvailability.coolingDown;
    }
    if (task.canRun) return ForumTaskAvailability.available;
    return ForumTaskAvailability.unknown;
  }

  DateTime _nowUtc() => DateTime.now().toUtc();

  Future<_ForumTaskPages> _fetchTaskPages({
    bool includeInProgress = false,
  }) async {
    ForumTraceLogger.log(
      'Pages',
      '_fetchTaskPages includeInProgress=$includeInProgress',
    );
    final client = _client;
    final epoch = _sessionEpoch.value;
    final completed = await fetchForumTasks(ForumTaskStatus.completed);
    _requireTaskSession(client, epoch);
    final available = await fetchForumTasks(ForumTaskStatus.available);
    _requireTaskSession(client, epoch);
    final inProgress = includeInProgress
        ? await fetchForumTasks(ForumTaskStatus.inProgress)
        : const <ForumTask>[];
    _requireTaskSession(client, epoch);
    return _ForumTaskPages(
      completed: completed,
      available: available,
      inProgress: inProgress,
    );
  }

  Future<_ForumTaskPages> _refreshTaskPages() async {
    ForumTraceLogger.log('Pages', '_refreshTaskPages includeInProgress=true');
    return _fetchTaskPages(includeInProgress: true);
  }

  Set<String> _currentCycleCompletedNames(
    Iterable<ForumTask> tasks, {
    required DateTime now,
  }) {
    final names = <String>{};
    for (final task in tasks) {
      if (_isCurrentCycleCompletion(task, now: now)) names.add(task.name);
    }
    return names;
  }

  List<_ForumTaskDecision> _buildTaskDecisions(
    _ForumTaskPages pages, {
    required DateTime now,
    required _ForumTaskDecisionMode mode,
    required Set<String> handledNames,
  }) {
    final names = _targetTaskNames(pages.allTasks).toList()
      ..sort(_compareTaskNames);
    final currentCycleCompletedNames =
        _currentCycleCompletedNames(pages.completed, now: now);
    return [
      for (final name in names)
        _buildTaskDecision(
          name,
          pages: pages,
          currentCycleCompletedNames: currentCycleCompletedNames,
          mode: mode,
          handledNames: handledNames,
        ),
    ];
  }

  _ForumTaskDecision _buildTaskDecision(
    String name, {
    required _ForumTaskPages pages,
    required Set<String> currentCycleCompletedNames,
    required _ForumTaskDecisionMode mode,
    required Set<String> handledNames,
  }) {
    if (handledNames.contains(name)) {
      return _ForumTaskDecision(name, _ForumTaskDecisionKind.handled);
    }

    if (mode == _ForumTaskDecisionMode.recovery) {
      final claimable = _firstMatchingTask(
        pages.inProgress,
        name,
        predicate: _isClaimableForumTask,
      );
      if (claimable != null) {
        return _ForumTaskDecision(
          name,
          _ForumTaskDecisionKind.claimInProgress,
          task: claimable,
        );
      }

      final inProgress = _firstTaskNamed(pages.inProgress, name);
      if (inProgress != null) {
        return _ForumTaskDecision(
          name,
          _ForumTaskDecisionKind.inProgress,
          task: inProgress,
        );
      }
      if (currentCycleCompletedNames.contains(name)) {
        return _ForumTaskDecision(name, _ForumTaskDecisionKind.handled);
      }
      final coolingDown = _firstMatchingTask(
        pages.available,
        name,
        predicate: (task) => task.isCoolingDown,
      );
      if (coolingDown != null) {
        return _ForumTaskDecision(name, _ForumTaskDecisionKind.handled);
      }
      return _ForumTaskDecision(name, _ForumTaskDecisionKind.unknown);
    }

    final startable = _firstMatchingTask(
      pages.available,
      name,
      predicate: _isStartableForumTask,
    );
    if (startable != null) {
      return _ForumTaskDecision(
        name,
        _ForumTaskDecisionKind.startThenClaim,
        task: startable,
      );
    }

    if (currentCycleCompletedNames.contains(name)) {
      return _ForumTaskDecision(name, _ForumTaskDecisionKind.handled);
    }

    return _ForumTaskDecision(name, _ForumTaskDecisionKind.unknown);
  }

  bool _isCurrentCycleCompletion(
    ForumTask task, {
    required DateTime now,
  }) {
    final cycle = _taskCycle(task.name);
    final completedAt = _parseForumTaskCompletedAt(task.completedAt);
    if (cycle == null || completedAt == null) return true;
    return completedAt.add(cycle).isAfter(now.toUtc());
  }

  Set<String> _targetTaskNames(Iterable<ForumTask> tasks) {
    final names = <String>{'日常', '周常'};
    for (final task in tasks) {
      if (task.name.contains('日常') || task.name.contains('周常')) {
        names.add(task.name);
      }
    }
    return names;
  }

  ForumTask? _firstTaskNamed(Iterable<ForumTask> tasks, String name) {
    for (final task in tasks) {
      if (task.name == name) return task;
    }
    return null;
  }

  ForumTask? _firstMatchingTask(
    Iterable<ForumTask> tasks,
    String name, {
    required bool Function(ForumTask task) predicate,
  }) {
    for (final task in tasks) {
      if (task.name == name && predicate(task)) return task;
    }
    return null;
  }

  int _compareTaskNames(String a, String b) {
    return _taskNamePriority(a).compareTo(_taskNamePriority(b));
  }

  int _taskNamePriority(String name) {
    if (name.contains('周常')) return 0;
    if (name.contains('日常')) return 1;
    return 2;
  }

  Future<List<BrowsingHistoryEntry>> browsingHistory(
      {int limit = browsingHistoryLimit}) {
    return _historyStore.recent(limit: limit);
  }

  Future<void> clearBrowsingHistory() async {
    await _historyStore.clear();
    await _readPositions.clear();
  }

  String? firstThreadPageUrl(ForumThread thread) =>
      _urls.threadBoundaryUrl(thread.url, last: false);

  String? latestThreadPageUrl(ForumThread thread) =>
      _urls.threadBoundaryUrl(thread.url, last: true);

  String? _threadReadKey(ForumThread thread) {
    final tid = _urls.tidFromUrl(thread.url);
    if (tid == null) return null;
    return '$tid:${_urls.uidFromUrl(thread.url) ?? ''}';
  }

  Future<ThreadReadPosition?> loadThreadReadPosition(ForumThread thread) {
    final key = _threadReadKey(thread);
    return key == null ? SynchronousFuture(null) : _readPositions.load(key);
  }

  Future<void> saveThreadReadPosition(
      ForumThread thread, ThreadReadPosition position) {
    final key = _threadReadKey(thread);
    if (key == null) return Future.error(ArgumentError('Invalid thread URL'));
    return _readPositions.save(key, position);
  }

  Future<List<ForumCategory>> fetchHotCategories() async {
    final home = await fetchHome();
    return home.hot;
  }

  Future<List<ForumSection>> fetchForumSections() async {
    final response = await _client.get('index.php');
    _throwIfBlockedPage(response);
    return _homePageParser
        .parseDesktopForumSections(html_parser.parse(response));
  }

  Future<dom.Element> _fetchSearchForm() async {
    final response = await _client.get('search.php');
    _throwIfBlockedPage(response);
    final document = html_parser.parse(response);
    final form = document.querySelector('form[action*="search.php"]') ??
        document.querySelector('form');
    if (form == null) {
      throw const ForumRequestException(
        ForumRequestKind.server,
        '没有找到搜索表单',
      );
    }
    return form;
  }

  Future<List<ForumSearchBoard>> fetchSearchBoards() async =>
      _searchBoards(await _fetchSearchForm());

  List<ForumSearchBoard> _searchBoards(dom.Element form) => [
        for (final option
            in form.querySelectorAll('select[name="f_fid"] option'))
          ForumSearchBoard(
            id: option.attributes['value'] ?? '',
            name: option.text.trim(),
            depth: RegExp(r'\|-').allMatches(option.text).length,
            selectable: !option.attributes.containsKey('disabled') &&
                (option.attributes['value'] == 'all' ||
                    RegExp(r'^[1-9]\d*$')
                        .hasMatch(option.attributes['value'] ?? '')),
          ),
      ];

  void _validateSearchQuery(ForumSearchQuery query) {
    if (query.keyword.trim().isEmpty && query.username.trim().isEmpty) {
      throw const ForumRepositoryException('请输入关键词或用户名');
    }
  }

  Future<ForumSearchPage> searchForum(ForumSearchQuery query) async {
    _validateSearchQuery(query);
    final form = await _fetchSearchForm();
    if (!_searchBoards(form)
        .any((board) => board.id == query.boardId && board.selectable)) {
      throw const ForumRepositoryException('搜索版块已不可用，请重新选择');
    }
    final fields = _formParser.defaults(form)
      ..remove('digest')
      ..['sch_area'] = '0'
      ..['step'] = '2'
      ..['keyword'] = query.keyword.trim()
      ..['pwuser'] = query.username.trim()
      ..['method'] = query.match.queryValue
      ..['f_fid'] = query.boardId
      ..['sch_time'] = query.time.queryValue
      ..['orderway'] = query.order.queryValue
      ..['asc'] = query.ascending ? 'ASC' : 'DESC'
      ..['submit'] = '提 交';
    if (query.digest) fields['digest'] = '1';
    final action = form.attributes['action'] ?? 'search.php?';
    if (!_urls.isForumUrl(action) ||
        Uri.tryParse(_urls.absoluteUrl(action))?.path != '/search.php') {
      throw const ForumRepositoryException('搜索表单入口无效');
    }
    final response = await _client.post(
      _urls.relativePath(_urls.absoluteUrl(action)),
      fields,
    );
    return _searchResultParser.parsePage(html_parser.parse(response));
  }

  Future<ForumSearchPage> searchForumPage(
    ForumSearchQuery query,
    String pagePath,
  ) async {
    _validateSearchQuery(query);
    final uri = Uri.tryParse(pagePath);
    if (uri == null ||
        uri.hasAuthority ||
        uri.hasScheme ||
        uri.path != 'search.php') {
      throw const ForumRepositoryException('搜索分页链接无效');
    }
    final response = await _client.get(pagePath);
    return _searchResultParser.parsePage(html_parser.parse(response));
  }

  Future<List<ForumThread>> searchThreads(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];

    final searchHtml = await _client.get('search.php');
    _throwIfBlockedPage(searchHtml);
    final searchPage = html_parser.parse(searchHtml);
    final form = searchPage.querySelector('form[action*="search.php"]') ??
        searchPage.querySelector('form');
    if (form == null) {
      throw const ForumRepositoryException('没有找到搜索表单');
    }

    final fields = _formParser.defaults(form)
      ..['step'] = '2'
      ..['keyword'] = query
      ..putIfAbsent('method', () => 'OR')
      ..putIfAbsent('sch_area', () => '0')
      ..putIfAbsent('f_fid', () => 'all')
      ..putIfAbsent('sch_time', () => '31536000')
      ..putIfAbsent('orderway', () => 'postdate')
      ..putIfAbsent('asc', () => 'DESC')
      ..['submit'] = '提 交';

    final action = form.attributes['action'] ?? 'search.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    return _searchResultParser.parse(html_parser.parse(response));
  }

  Future<List<ForumThread>> fetchBoardThreads(ForumCategory category) async {
    return (await fetchBoardThreadPage(category)).threads;
  }

  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) async {
    final account = localPreferenceAccount;
    final client = _client;
    final epoch = _sessionEpoch.value;
    filter ??= _urls.boardFilterFromUrl(
      category,
      label: '',
      url: category.url ?? '',
    );
    final normalizedPage = page < 1 ? 1 : page;
    final desktopPath = _urls.boardDesktopPath(
      category,
      page: normalizedPage,
      order: order,
      filter: filter,
    );
    if (desktopPath == null) {
      throw ForumRepositoryException('没有解析到${category.name}帖子列表');
    }
    final desktopDocument = await _fetchStructuredDocument(
      desktopPath,
      (response) => _boardDocument(response, category),
    );
    final boardName =
        _boardThreadPageParser.parseBoardName(desktopDocument, category);
    if (boardName != null) {
      category = ForumCategory(
          name: boardName, slug: category.slug, url: category.url);
    }
    final subBoards = _boardThreadPageParser.parseDesktopSubBoards(
      desktopDocument,
      category,
    );
    // thread_new.php uses the wall stream for ordinary topics, while the table
    // above it still carries board-level sticky topics and ads. Do not parse the
    // whole table as threads, because it also contains broader sticky levels
    // that simple mode intentionally hides.
    final threads = _mergeThreadNewThreads(
      _boardThreadPageParser.parseDesktopStickyThreads(
        desktopDocument,
        category,
      ),
      _boardThreadPageParser.parseWallThreads(desktopDocument, category),
    );
    final hasPictureWall = _boardThreadPageParser.hasPictureWall(
      desktopDocument,
      category,
    );
    final parents = _boardThreadPageParser.parseParents(
      desktopDocument,
      category,
    );
    final filters = _boardThreadPageParser.parseFilters(
      desktopDocument,
      category,
    );
    final activeFilter = _boardThreadPageParser.parseActiveFilter(
      desktopDocument,
      category,
      filters,
      requested: filter,
    );
    if (threads.isNotEmpty ||
        subBoards.isNotEmpty ||
        hasPictureWall ||
        filters.isNotEmpty) {
      final pages = _boardThreadPageParser.wallPages(desktopDocument) ??
          (current: normalizedPage, total: normalizedPage);
      if (!identical(client, _client) || epoch != _sessionEpoch.value) {
        throw const ForumRepositoryException('网络或登录状态已改变，请重试');
      }
      try {
        final parentName = parents.lastOrNull?.name.trim();
        await HomeReadingPreferences.recordBoardVisit(category,
            account: account,
            label: parentName != null && parentName.isNotEmpty
                ? '$parentName / ${category.name}'
                : boardName != null
                    ? category.name
                    : null);
      } catch (_) {
        // A local history failure must not discard the fetched board.
      }
      if (!identical(client, _client) || epoch != _sessionEpoch.value) {
        throw const ForumRepositoryException('网络或登录状态已改变，请重试');
      }
      return ForumThreadPage(
        threads: threads,
        currentPage: pages.current,
        totalPages: pages.total,
        ads: _boardThreadPageParser.parseDesktopAds(desktopDocument),
        subBoards: subBoards,
        boardName: boardName,
        hasPictureWall: hasPictureWall,
        parents: parents,
        filters: filters,
        activeFilter: activeFilter,
      );
    }

    throw ForumRepositoryException('没有解析到${category.name}帖子列表');
  }

  List<ForumThread> _mergeThreadNewThreads(
    List<ForumThread> stickyThreads,
    List<ForumThread> wallThreads,
  ) {
    final seen = <String>{};
    return [
      for (final thread in [...stickyThreads, ...wallThreads])
        if (seen.add(thread.url)) thread,
    ];
  }

  Future<ReplyResult> submitThread({
    required ForumCategory category,
    required String title,
    required String content,
    bool enableReplyNotice = false,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedContent = content.trim();
    if (trimmedTitle.isEmpty) {
      return const ReplyResult(success: false, message: '标题不能为空');
    }
    if (trimmedContent.isEmpty) {
      return const ReplyResult(success: false, message: '正文不能为空');
    }

    final fid = _urls.fidFromCategory(category);
    if (fid == null) {
      return const ReplyResult(success: false, message: '没有找到版块 ID');
    }

    final html = await _client.get('post.php?fid=$fid');
    _throwIfBlockedPage(html);
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(
          success: false, message: _responseParser.pageMessage(html));
    }

    final fields = _formParser.defaults(form)
      ..remove('atc_newrp')
      ..['atc_title'] = trimmedTitle
      ..['atc_content'] = trimmedContent
      ..['Submit'] = '提 交';
    if (enableReplyNotice) fields['atc_newrp'] = '1';

    final action = form.attributes['action'] ?? 'post.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    return _replyResult(response, '主题已发布');
  }

  Future<String> fetchLoginUsername(String numericUid) async {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(numericUid)) {
      throw const ForumRepositoryException('用户 UID 无效');
    }
    if (!isLoggedIn) {
      throw const ForumRequestException(
        ForumRequestKind.loginRequired,
        '需要登录',
      );
    }
    final client = _client;
    final epoch = _sessionEpoch.value;
    final owner = currentUsername;
    final response = await client.getOnce('sendemail.php?uid-$numericUid.html');
    if (epoch != _sessionEpoch.value ||
        !identical(client, _client) ||
        owner != currentUsername ||
        !isLoggedIn) {
      throw const ForumRequestException(
        ForumRequestKind.loginRequired,
        '登录状态已变更，请重新查询',
      );
    }
    _throwIfBlockedPage(response);
    return _userProfileParser.parseLoginUsername(html_parser.parse(response));
  }

  Future<UserProfile> fetchUserProfile(String url) async {
    final overview = await fetchUserProfileOverview(url);
    return fetchUserProfileDetails(overview);
  }

  Future<UserProfile> fetchUserProfileOverview(String url) async {
    final epoch = _sessionEpoch.value;
    final generation = _profileDetailsGeneration;
    final client = _client;
    final profileUrl = _urls.absoluteUrl(url);
    final uid = await _uidFromProfileUrl(profileUrl);
    if (epoch != _sessionEpoch.value) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变');
    }
    final profileDocument = html_parser.parse(
      await client.get(
        _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.profile)),
      ),
    );
    if (epoch != _sessionEpoch.value) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已改变');
    }
    final profile = _userProfileParser.parseOverview(
      uid: uid,
      profileUrl: profileUrl,
      profileDocument: profileDocument,
    );
    if (generation == _profileDetailsGeneration) {
      await _profileCache.saveOverview(url, profile);
      if (epoch == _sessionEpoch.value &&
          generation == _profileDetailsGeneration)
        _applyAccountProfile(profile);
    }
    return profile;
  }

  Future<UserProfile?> cachedUserProfileOverview(String url) async {
    return _profileCache.loadOverview(url);
  }

  Future<FavoriteCollections> fetchFavoriteCollections({String? categoryId}) =>
      _favoritesService.fetchFavoriteCollections(categoryId: categoryId);

  Future<FavoriteCollectionMutation> createFavoriteCategory(
          FavoriteCollections snapshot, String name) =>
      _favoritesService.createFavoriteCategory(snapshot, name);

  Future<FavoriteCollectionMutation> deleteFavoriteCategory(
          FavoriteCollections snapshot, String categoryId) =>
      _favoritesService.deleteFavoriteCategory(snapshot, categoryId);

  Future<FavoriteCollectionMutation> moveFavorites(FavoriteCollections snapshot,
          List<FavoriteCollectionEntry> entries, String categoryId) =>
      _favoritesService.moveFavorites(snapshot, entries, categoryId);

  Future<FavoriteCollectionMutation> removeFavorites(
          FavoriteCollections snapshot,
          List<FavoriteCollectionEntry> entries) =>
      _favoritesService.removeFavorites(snapshot, entries);

  Future<FavoriteCollectionMutation> addFavoriteToCollection(
          FavoriteCollections snapshot,
          ThreadFavorite favorite,
          String categoryId) =>
      _favoritesService.addFavoriteToCollection(snapshot, favorite, categoryId);

  void _evictProfileDetails() {
    _profileDetailsTimer?.cancel();
    _profileDetailsTimer = null;
    _profileDetailsFuture = null;
    _profileDetailsData = null;
    _profileDetailsUid = null;
  }

  void _clearProfileDetails() {
    _profileDetailsGeneration++;
    _evictProfileDetails();
  }

  UserProfile _withProfileDetails(
    UserProfile overview,
    _ProfileDetailsData details,
  ) =>
      overview.copyWith(
        homeActivities: details.homeActivities,
        homeReplies: details.homeReplies,
        topics: details.topics,
        posts: details.posts,
        favorites: details.favorites,
      );

  Future<UserProfile> fetchUserProfileDetails(
    UserProfile overview, {
    bool forceReload = false,
  }) {
    if (forceReload) _clearProfileDetails();
    if (_profileDetailsUid != overview.uid) _evictProfileDetails();
    final data = _profileDetailsData;
    if (data != null) {
      return SynchronousFuture(_withProfileDetails(overview, data));
    }
    var pending = _profileDetailsFuture;
    if (pending == null) {
      final generation = _profileDetailsGeneration;
      final epoch = _sessionEpoch.value;
      final client = _client;
      final origin = _config.baseUri.origin;
      late Future<_ProfileDetailsData> next;
      next = _readUserProfileDetails(overview).then((details) {
        if (epoch != _sessionEpoch.value ||
            !identical(client, _client) ||
            origin != _config.baseUri.origin) {
          throw const ForumRequestException(
            ForumRequestKind.loginRequired,
            '登录状态已变更，请重新加载',
          );
        }
        if (generation != _profileDetailsGeneration) {
          throw const ForumRequestException(
            ForumRequestKind.server,
            '用户资料已变更，请重新加载',
          );
        }
        if (identical(_profileDetailsFuture, next)) {
          _profileDetailsData = details;
          // Reuse one UID's details for 60s; refresh, session changes and writes clear it.
          _profileDetailsTimer = Timer(const Duration(seconds: 60), () {
            if (identical(_profileDetailsFuture, next)) _evictProfileDetails();
          });
        }
        return details;
      }).catchError((Object error, StackTrace stack) {
        if (identical(_profileDetailsFuture, next)) _evictProfileDetails();
        Error.throwWithStackTrace(error, stack);
      });
      _profileDetailsUid = overview.uid;
      _profileDetailsFuture = pending = next;
    }
    return pending.then((details) => _withProfileDetails(overview, details));
  }

  Future<_ProfileDetailsData> _readUserProfileDetails(
      UserProfile overview) async {
    final uid = overview.uid;
    final parsed = await Future.wait([
      for (final tab in [
        UserProfileTab.home,
        UserProfileTab.topics,
        UserProfileTab.posts,
        UserProfileTab.favorites
      ])
        _fetchStructuredDocument(
          _urls.relativePath(_urls.userTabUrl(uid, tab)),
          _profileDetailsDocument,
        ),
    ]);
    final profile = _userProfileParser.appendDetails(
      overview: overview,
      homeDocument: parsed[0],
      topicsDocument: parsed[1],
      postsDocument: parsed[2],
      favoritesDocument: parsed[3],
    );
    return (
      homeActivities: profile.homeActivities,
      homeReplies: profile.homeReplies,
      topics: profile.topics,
      posts: profile.posts,
      favorites: profile.favorites,
    );
  }

  Future<String> _uidFromProfileUrl(String profileUrl) async {
    var uid = _urls.uidFromUrl(profileUrl);
    if (uid == null) {
      final html = await _client.get(_urls.relativePath(profileUrl));
      uid = _userProfileParser.uidFromDocument(html_parser.parse(html));
    }
    if (uid == null) {
      throw const ForumRepositoryException('没有找到用户 UID');
    }
    return uid;
  }

  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final detailPath = _urls.threadDetailPath(thread.url, page: normalizedPage);
    final html =
        await _client.get(Uri.parse(detailPath).removeFragment().toString());
    final favorite = await _extractThreadFavorite(thread, html);
    final detail = _parseThreadPage(thread, html_parser.parse(html), html,
        page: normalizedPage, detailPath: detailPath, favorite: favorite);
    await _recordThreadView(detail.thread);
    return detail;
  }

  ThreadDetail _parseThreadPage(
      ForumThread thread, dom.Document document, String html,
      {required int page,
      required String detailPath,
      ThreadFavorite? favorite}) {
    final posts = _threadDetailParser.desktopThreadCards(document);
    final pagination = _threadDetailParser.desktopPagination(
      document,
      requestedPage: page,
      threadUrl: thread.url,
    );
    final board = _threadDetailParser.board(document);
    final section = board?.name ?? _threadDetailParser.sectionTitle(document);

    if (posts.isEmpty) {
      throw ForumRepositoryException(_responseParser.pageMessage(html));
    }

    final authorFilterUid = _urls.uidFromUrl(thread.url);
    final originalUid = _urls.uidFromUrl(originalPosterPostsUrl(thread) ?? '');
    final openingFloor = posts.first.floor == '楼主' ||
        RegExp(r'^B?0F?$', caseSensitive: false)
            .hasMatch(posts.first.floor ?? '') ||
        posts.first.anchors.any({'tpc', 'read_tpc', 'td_tpc'}.contains);
    final isOpeningPage = pagination.currentPage == 1 &&
        openingFloor &&
        (authorFilterUid == null || authorFilterUid == originalUid);
    final first = isOpeningPage ? posts.first : null;
    final updateOriginalAuthor = authorFilterUid == null;
    final detailThread = thread.copyWith(
      title: _threadDetailParser.threadTitle(document) ?? thread.title,
      url: _canonicalThreadUrl(
        parserUrl: _threadDetailParser.threadUrl(document),
        sourceUrl: thread.url,
        detailPath: detailPath,
      ),
      section: section ?? thread.section,
      author: updateOriginalAuthor ? first?.author : null,
      authorUrl: updateOriginalAuthor ? first?.authorUrl : null,
      authorAvatarUrl: updateOriginalAuthor ? first?.authorAvatarUrl : null,
      authorPostsUrl: updateOriginalAuthor ? first?.authorPostsUrl : null,
      lastPost: first?.postedAt ?? thread.lastPost,
    );

    return ThreadDetail(
      thread: detailThread,
      board: board,
      body: first?.content ?? '',
      bodyImages: first?.images ?? const [],
      bodyLinks: first?.links ?? const [],
      bodySegments: first?.segments ?? const [],
      bodyAnchors: first?.anchors ?? const [],
      bodySaleBoxes: first?.saleBoxes ?? const [],
      bodySaleBoxesFirst: first?.saleBoxesFirst ?? false,
      bodyReplyTitle: first?.replyTitle,
      bodyReplyUrl: first?.replyUrl,
      bodyQuoteUrl: first?.quoteUrl,
      bodyContentKey: first?.blockContentKey,
      personalSignature: first?.personalSignature,
      bodyPostedAt: first?.postedAt,
      replies: isOpeningPage ? posts.skip(1).toList() : posts,
      pagination: pagination,
      favorite: favorite,
      previousThread: _threadDetailParser.previousThread(document),
      nextThread: _threadDetailParser.nextThread(document),
      rssFeed: _threadDetailParser.rssFeed(document),
    );
  }

  FullScan<ThreadSearchHit> scanThread(
    ForumThread current,
    String keyword, {
    required List<ThreadDetail> loaded,
    required BlockingRules rules,
  }) {
    final client = _client;
    final epoch = _sessionEpoch.value;
    final tid = _urls.tidFromUrl(current.url);
    if (tid == null) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '帖子链接无效');
    }
    final uid = _urls.uidFromUrl(current.url);
    final source = current.copyWith(
        url: _urls.absoluteUrl(
            'read.php?tid-$tid${uid == null ? '' : '-uid-$uid'}.html'));
    final seed = loaded.where((detail) =>
        _urls.tidFromUrl(detail.thread.url) == tid &&
        _urls.uidFromUrl(detail.thread.url) == uid);
    final total = seed.fold<int>(
        1,
        (count, detail) => detail.pagination.totalPages > count
            ? detail.pagination.totalPages
            : count);
    return PageFullScan<ThreadSearchHit>(
      client: client,
      isCurrentSession: () =>
          identical(client, _client) && epoch == _sessionEpoch.value,
      totalPages: seed.isEmpty ? null : total,
      loaded: seed.map((detail) => ScanPage(
          page: detail.pagination.currentPage,
          totalPages: total,
          hasMore: detail.pagination.currentPage < total,
          hits: searchLoadedThread([detail], keyword, rules))),
      readPage: (page, request) async {
        final path = _urls.threadDetailPath(source.url, page: page);
        final html = await request.getOnce(path);
        final document = html_parser.parse(html);
        ThreadDetail detail;
        try {
          detail = _parseThreadPage(source, document, html,
              page: page, detailPath: path);
        } on ForumRepositoryException {
          _throwIfBlockedPage(html);
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '未读到可搜索的帖子页面');
        }
        final pager = document.querySelectorAll('.pages, .pagesone');
        if (pager.isNotEmpty &&
            !RegExp(r'Pages:\s*[1-9]\d*\s*/\s*[1-9]\d*')
                .hasMatch(pager.map((element) => element.text).join(' '))) {
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '无法确认帖子的分页');
        }
        final linked = _threadDetailParser.threadUrl(document);
        if (linked != null && _urls.tidFromUrl(linked) != tid) {
          throw const ForumRequestException(
              ForumRequestKind.invalidInput, '响应不是所选帖子');
        }
        return ScanPage(
            page: detail.pagination.currentPage,
            totalPages: detail.pagination.totalPages,
            hasMore: detail.pagination.hasNext,
            hits: searchLoadedThread([detail], keyword, rules));
      },
    );
  }

  Future<String?> fetchQuoteDraft(ThreadReply reply) async {
    final quoteUrl = reply.quoteUrl;
    if (quoteUrl == null || quoteUrl.isEmpty) return null;

    final html = await _client.get(
      _urls.relativePath(_urls.absoluteUrl(quoteUrl)),
    );
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]') ??
        document.querySelector('form[action*="post.php"]');
    final textarea = form?.querySelector('textarea[name="atc_content"]') ??
        document.querySelector('textarea[name="atc_content"]');
    final content = textarea?.text.trim();
    if (content != null && content.isNotEmpty) return content;

    final input = form?.querySelector('input[name="atc_content"]') ??
        document.querySelector('input[name="atc_content"]');
    final value = input?.attributes['value']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<ReplyResult> submitReply({
    required ForumThread thread,
    required String title,
    required String content,
  }) async {
    if (content.trim().isEmpty) {
      return const ReplyResult(success: false, message: '回复内容不能为空');
    }

    final html = await _client.get(_urls.relativePath(thread.url));
    _throwIfBlockedPage(html);
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(
          success: false, message: _responseParser.pageMessage(html));
    }

    final fields = _formParser.defaults(form)
      ..['atc_title'] =
          title.trim().isEmpty ? 'Re:${thread.title}' : title.trim()
      ..['atc_content'] = content.trim()
      ..['Submit'] = ' 提 交 ';

    final action = form.attributes['action'] ?? 'post.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    return _replyResult(response, '回复已提交');
  }

  ReplyResult _replyResult(String response, String successMessage) {
    final message = _responseParser.pageMessage(response);
    if (_responseParser.isReplySuccess(response, message)) {
      _clearProfileDetails();
      return ReplyResult(success: true, message: successMessage);
    }
    _throwIfBlockedPage(response);
    return ReplyResult(success: false, message: message);
  }

  Future<dom.Document> _fetchStructuredDocument(
      String path, dom.Document Function(String) parse) async {
    final client = _client;
    try {
      return parse(await client.getOnce(path));
    } on ForumRequestException catch (error) {
      if (error.kind != ForumRequestKind.rateLimited) rethrow;
    }
    // Retry one actual cooldown, never an error phrase inside admitted user data.
    return parse(await client.getOnce(path));
  }

  dom.Document _boardDocument(String response, ForumCategory category) {
    final document = html_parser.parse(response);
    _throwIfBlockedText(
        _boardThreadPageParser.validationText(document, category));
    return document;
  }

  dom.Document _profileDetailsDocument(String response) {
    final document = html_parser.parse(response);
    final validation = document.clone(true);
    for (final link in validation
        .querySelectorAll('.u-table a[href], .u-box-wrap a[href]')) {
      if (_urls.forumLinkTarget(link.attributes['href']!)
          is ForumThreadLinkTarget) {
        // Thread titles are user data; warnings outside the title still count.
        link.nodes.clear();
      }
    }
    _throwIfBlockedText('${validation.querySelector('title')?.text ?? ''}\n'
        '${validation.body?.text ?? ''}');
    return document;
  }

  void _throwIfBlockedPage(String html) {
    final document = html_parser.parse(html);
    _throwIfBlockedText('${document.querySelector('title')?.text ?? ''}\n'
        '${document.body?.text ?? ''}');
  }

  void _throwIfBlockedText(String text) {
    if (forumTextIsRateLimited(text)) {
      throw const ForumRequestException(
        ForumRequestKind.rateLimited,
        '请求过于频繁',
      );
    }
    if (forumTextNeedsLogin(text)) {
      throw const ForumRequestException(
        ForumRequestKind.loginRequired,
        '需要登录',
      );
    }
    if (forumTextIsForbidden(text)) {
      throw const ForumRequestException(
        ForumRequestKind.forbidden,
        '没有权限',
      );
    }
  }

  Future<ReplyResult> buySaleBox(ThreadSaleBox saleBox) async {
    if (saleBox.buyPath.trim().isEmpty) {
      return const ReplyResult(success: false, message: '没有找到购买链接');
    }

    final client = _client;
    final epoch = _sessionEpoch.value;
    final raw = saleBox.buyPath.trim();
    final parsed = Uri.tryParse(raw);
    final uri = parsed == null ? null : _urls.baseUri.resolveUri(parsed);
    if (uri == null ||
        RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(raw) ||
        !_isNativePurchaseUri(uri)) {
      return const ReplyResult(success: false, message: '购买链接无效，请刷新帖子');
    }
    void requireCurrentSession() {
      if (!identical(client, _client) || epoch != _sessionEpoch.value) {
        throw const ForumRepositoryException('网络或登录状态已改变，请重试');
      }
    }

    final response = await client.getForm(
      _urls.relativePath(uri.toString()),
      followRedirects: false,
      requireCurrentSession: requireCurrentSession,
    );
    requireCurrentSession();
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isPurchaseSuccess(response, message);
    if (success) _clearProfileDetails();
    return ReplyResult(
      success: success,
      message: success ? '购买完成' : message,
    );
  }

  bool _isNativePurchaseUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.origin != _urls.baseUri.origin ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/job.php' ||
        uri.hasFragment) return false;
    try {
      final fields = uri.queryParametersAll;
      if (fields.length != 4 ||
          fields.values.any((values) => values.length != 1)) {
        return false;
      }
      final tid = fields['tid']?.single ?? '';
      final pid = fields['pid']?.single ?? '';
      final verify = fields['verify']?.single ?? '';
      return fields['action']?.single == 'buytopic' &&
          RegExp(r'^[1-9]\d*$').hasMatch(tid) &&
          (pid == 'tpc' || RegExp(r'^[1-9]\d*$').hasMatch(pid)) &&
          verify.isNotEmpty &&
          !RegExp(r'[\x00-\x1f\x7f]').hasMatch(verify);
    } on FormatException {
      return false;
    }
  }

  Future<FavoriteResult> removeFavorite(ThreadFavorite favorite) async {
    final result = await _favoritesService.removeFavorite(favorite);
    if (result.success) _clearProfileDetails();
    return result;
  }

  Future<String?> _fetchLoggedInUsername() async {
    final epoch = _sessionEpoch.value;
    final header = await _fetchSessionHeader();
    if (epoch != _sessionEpoch.value) return null;
    if (header.desktopHtml != null) {
      _captureAccountIdentity(html_parser.parse(header.desktopHtml!));
    }
    return header.username;
  }

  Future<({String? username, String? desktopHtml})>
      _fetchSessionHeader() async {
    final client = _client;
    try {
      final desktopHtml = await client.get('index.php');
      final username = _responseParser.loggedInUsername(desktopHtml);
      if (username != null)
        return (username: username, desktopHtml: desktopHtml);
      return (
        username: _responseParser
            .loggedInUsername(await client.get('simple/index.php')),
        desktopHtml: null,
      );
    } catch (_) {
      return (username: null, desktopHtml: null);
    }
  }

  Future<ThreadFavorite?> _extractThreadFavorite(
    ForumThread thread,
    String html,
  ) async {
    var favorite = _threadFavoriteFromHtml(thread, html);
    if (favorite != null) {
      if (favorite.state == ThreadFavoriteState.unknown) {
        return favorite.copyWith(
          state: await _fetchFavoriteState(favorite.tid),
        );
      }
      return favorite;
    }
    return null;
  }

  ThreadFavorite? _threadFavoriteFromHtml(ForumThread thread, String html) {
    final tid = _urls.tidFromUrl(thread.url);
    if (tid == null) return null;

    final verify =
        RegExp(r"verifyhash\s*=\s*'([^']+)'").firstMatch(html)?.group(1);
    if (verify == null || verify.isEmpty) return null;

    final document = html_parser.parse(html);
    final favoriteButton = document.querySelector('#favor');
    final text = _cleanText(favoriteButton?.text ?? '');
    final state = text.contains('取消收藏')
        ? ThreadFavoriteState.favorite
        : ThreadFavoriteState.unknown;
    return ThreadFavorite(
      tid: tid,
      verify: verify,
      state: state,
    );
  }

  Future<ThreadFavoriteState> _fetchFavoriteState(String tid) async {
    try {
      final html = await _client.get('u.php?action-favor.html');
      final document = html_parser.parse(html);
      final favoriteForm =
          document.querySelector('form[action*="action=favor"]');
      if (favoriteForm == null) return ThreadFavoriteState.unknown;

      final escapedTid = RegExp.escape(tid);
      final item = favoriteForm.querySelector(
        'input[type="checkbox"][name="selid[]"][value="$escapedTid"]',
      );
      if (item != null) return ThreadFavoriteState.favorite;

      return ThreadFavoriteState.unknown;
    } catch (_) {
      return ThreadFavoriteState.unknown;
    }
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Duration? _taskCycle(String name) {
    if (name.contains('日常')) return const Duration(hours: 24);
    if (name.contains('周常')) return const Duration(hours: 168);
    return null;
  }

  DateTime? _parseForumTaskCompletedAt(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})\s+(AM|PM):(\d{1,2}):(\d{2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return DateTime.tryParse(text)?.toUtc();
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    var hour = int.tryParse(match.group(5) ?? '');
    final minute = int.tryParse(match.group(6) ?? '');
    final second = int.tryParse(match.group(7) ?? '');
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    final marker = (match.group(4) ?? '').toUpperCase();
    if (marker == 'PM' && hour < 12) hour += 12;
    if (marker == 'AM' && hour == 12) hour = 0;
    return DateTime(year, month, day, hour, minute, second).toUtc();
  }

  String _canonicalThreadUrl({
    required String? parserUrl,
    required String sourceUrl,
    required String detailPath,
  }) {
    final authorUid = _urls.uidFromUrl(sourceUrl);
    final sourceTid = _urls.tidFromUrl(sourceUrl);
    if (authorUid != null && sourceTid != null) {
      return _urls.absoluteUrl('read.php?tid-$sourceTid-uid-$authorUid.html');
    }
    final parsed = parserUrl;
    if (parsed != null && parsed.isNotEmpty) return parsed;

    final tid = _urls.tidFromUrl(sourceUrl);
    if (tid != null) {
      return _urls.absoluteUrl('read.php?tid-$tid.html');
    }
    return _urls.absoluteUrl(detailPath);
  }

  Future<void> _recordThreadView(ForumThread thread) async {
    try {
      await _historyStore.recordThread(thread);
    } catch (_) {
      // Browsing must keep working even if local history persistence fails.
    }
  }

  dom.Element? _loginFormFromFields(dom.Document document) {
    for (final form in document.querySelectorAll('form')) {
      if (form.querySelector('input[name="pwuser"]') != null &&
          form.querySelector('input[name="pwpwd"]') != null) {
        return form;
      }
    }
    return null;
  }

  void _logTaskPages(String scope, String label, _ForumTaskPages pages) {
    ForumTraceLogger.log(
      scope,
      '$label completed=${pages.completed.length} available=${pages.available.length} inProgress=${pages.inProgress.length}',
    );
    for (final task in pages.completed) {
      ForumTraceLogger.log(scope, '  completed ${_describeTask(task)}');
    }
    for (final task in pages.available) {
      ForumTraceLogger.log(scope, '  available ${_describeTask(task)}');
    }
    for (final task in pages.inProgress) {
      ForumTraceLogger.log(scope, '  inProgress ${_describeTask(task)}');
    }
  }

  void _logDecisions(
    String scope,
    String label,
    List<_ForumTaskDecision> decisions,
  ) {
    ForumTraceLogger.log(scope, '$label count=${decisions.length}');
    for (final decision in decisions) {
      ForumTraceLogger.log(
        scope,
        '  decision name=${decision.name} kind=${decision.kind} task=${decision.task == null ? 'null' : _describeTask(decision.task!)}',
      );
    }
  }

  String _describeTask(ForumTask task) {
    return 'name=${task.name} status=${task.status} id=${task.id} actionLabel=${task.actionLabel} canRun=${task.canRun} progress=${task.progressPercent} completedAt=${task.completedAt} cooldown=${task.cooldownRemaining} reward=${task.reward}';
  }

  String _describeSnapshot(ForumTaskSnapshot snapshot) {
    final parts = <String>[];
    for (final task in snapshot.tasks) {
      parts.add(
        '${task.name}:${task.availability}(id=${task.id},progress=${task.progressPercent},completedAt=${task.completedAt},cooldown=${task.cooldownRemaining})',
      );
    }
    return 'updatedAt=${snapshot.updatedAt.toIso8601String()} tasks=[${parts.join(', ')}]';
  }
}

class ForumRepositoryException implements Exception {
  const ForumRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _ForumTaskActionExpectation {
  start,
  claimReward,
}

enum _ForumTaskActionKind {
  started,
  rewardClaimed,
  alreadyStarted,
  alreadyCompleted,
  coolingDown,
  loginRequired,
  failure,
}

class _ForumTaskActionDecision {
  const _ForumTaskActionDecision(this.kind, this.message);

  final _ForumTaskActionKind kind;
  final String message;
}

class _ForumTaskPages {
  const _ForumTaskPages({
    required this.completed,
    required this.available,
    required this.inProgress,
  });

  final List<ForumTask> completed;
  final List<ForumTask> available;
  final List<ForumTask> inProgress;

  Iterable<ForumTask> get allTasks sync* {
    yield* completed;
    yield* available;
    yield* inProgress;
  }
}

enum _ForumTaskDecisionMode {
  baseline,
  recovery,
}

enum _ForumTaskDecisionKind {
  startThenClaim,
  claimInProgress,
  inProgress,
  handled,
  unknown,
}

class _ForumTaskDecision {
  const _ForumTaskDecision(this.name, this.kind, {this.task});

  final String name;
  final _ForumTaskDecisionKind kind;
  final ForumTask? task;
}

class _StartTaskOutcome {
  const _StartTaskOutcome({
    this.appliedCount = 0,
    this.shouldRefresh = false,
    this.handled = false,
    this.needsRecovery = false,
  });

  final int appliedCount;
  final bool shouldRefresh;
  final bool handled;
  final bool needsRecovery;
}

class _ClaimTaskOutcome {
  const _ClaimTaskOutcome({
    this.shouldRefresh = false,
    this.handled = false,
    this.needsRecovery = false,
  });

  final bool shouldRefresh;
  final bool handled;
  final bool needsRecovery;
}
