import 'package:html/parser.dart' as html_parser;

import '../models/forum_models.dart';
import 'forum_client.dart';
import 'forum_network_config.dart';
import 'forum_url_resolver.dart';
import 'user_profile_cache.dart';
import 'parsers/board_thread_page_parser.dart';
import 'parsers/forum_form_parser.dart';
import 'parsers/forum_response_parser.dart';
import 'parsers/home_page_parser.dart';
import 'parsers/search_result_parser.dart';
import 'parsers/thread_content_parser.dart';
import 'parsers/thread_detail_parser.dart';
import 'parsers/user_profile_parser.dart';

class ForumRepository {
  ForumRepository({
    ForumClient? client,
    ForumNetworkConfig? config,
    UserProfileCache? profileCache,
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
            );

  ForumClient _client;
  ForumNetworkConfig _config;
  ForumUrlResolver _urls;
  late BoardThreadPageParser _boardThreadPageParser =
      BoardThreadPageParser(urls: _urls);
  final ForumFormParser _formParser = const ForumFormParser();
  final ForumResponseParser _responseParser = const ForumResponseParser();
  late HomePageParser _homePageParser = HomePageParser(urls: _urls);
  late SearchResultParser _searchResultParser = SearchResultParser(urls: _urls);
  late ThreadDetailParser _threadDetailParser = ThreadDetailParser(
    urls: _urls,
    contentParser: ThreadContentParser(urls: _urls),
  );
  late UserProfileParser _userProfileParser = UserProfileParser(urls: _urls);
  UserProfileCache _profileCache;
  String? _currentUsername;

  bool get isLoggedIn => _client.isLoggedIn;

  String? get currentUsername => _currentUsername;

  ForumNetworkConfig get networkConfig => _config;

  Future<void> updateNetworkConfig(ForumNetworkConfig config) async {
    if (config == _config) return;
    _client.close(force: true);
    _config = config;
    _urls = ForumUrlResolver(baseUri: config.baseUri);
    _boardThreadPageParser = BoardThreadPageParser(urls: _urls);
    _homePageParser = HomePageParser(urls: _urls);
    _searchResultParser = SearchResultParser(urls: _urls);
    _threadDetailParser = ThreadDetailParser(
      urls: _urls,
      contentParser: ThreadContentParser(urls: _urls),
    );
    _userProfileParser = UserProfileParser(urls: _urls);
    _profileCache = UserProfileCache(urls: _urls);
    _client = ForumClient(config: config);
    _currentUsername = null;
    await ForumNetworkSettings.save(config);
  }

  Future<bool> restoreSession() async {
    await _client.restoreCookies();
    if (!_client.isLoggedIn) return false;

    _currentUsername = await _fetchLoggedInUsername();
    if (_currentUsername == null) {
      await clearSession();
      return false;
    }
    return true;
  }

  Future<void> clearSession() async {
    _currentUsername = null;
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
    final form = document.querySelector('form[name="login"]');
    if (form == null) {
      throw const ForumRepositoryException('没有找到登录表单');
    }

    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = input.attributes['type'] ?? '';
      if (type == 'text' || type == 'password') continue;
      if (type == 'radio' && !input.attributes.containsKey('checked')) continue;
      fields[name] = input.attributes['value'] ?? '';
    }

    final captchaSrc = form.querySelector('#ckcode')?.attributes['src'];
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
      _currentUsername = _responseParser.loggedInUsername(response) ??
          await _fetchLoggedInUsername() ??
          username.trim();
      return const LoginResult(success: true, message: '登录成功');
    }

    return LoginResult(
      success: false,
      message: _responseParser.pageMessage(response),
    );
  }

  Future<ForumHomeSnapshot> fetchHome() async {
    final html = await _client.get('simple/index.php');
    final document = html_parser.parse(html);
    var latest = _homePageParser.parseLatestThreads(document);
    final latestScriptUrl = _homePageParser.latestThreadsScriptUrl(document);
    if (latest.isEmpty && latestScriptUrl != null) {
      final script = await _client.get(_urls.relativePath(latestScriptUrl));
      latest = _homePageParser.parseLatestThreadsFromScript(script);
    }
    final hot = _homePageParser.parseHotCategories(document);
    final sections = _homePageParser.parseForumSections(document);

    if (latest.isEmpty) {
      throw const ForumRepositoryException('没有解析到最新讨论');
    }
    if (hot.isEmpty && sections.isEmpty) {
      throw const ForumRepositoryException('没有解析到版块列表');
    }

    return ForumHomeSnapshot(latest: latest, hot: hot, sections: sections);
  }

  Future<List<ForumThread>> fetchLatestThreads() async {
    final home = await fetchHome();
    return home.latest;
  }

  Future<List<ForumCategory>> fetchHotCategories() async {
    final home = await fetchHome();
    return home.hot;
  }

  Future<List<ForumSection>> fetchForumSections() async {
    final home = await fetchHome();
    return home.sections;
  }

  Future<List<ForumThread>> searchThreads(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];

    final searchPage = html_parser.parse(await _client.get('search.php'));
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
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final simpleHtml = await _client.get(
      _urls.relativePath(_urls.boardSimplePath(category, page: normalizedPage)),
    );
    final simpleDocument = html_parser.parse(simpleHtml);
    final simpleThreads =
        _boardThreadPageParser.parseSimpleThreads(simpleDocument, category);
    if (simpleThreads.isNotEmpty) {
      final pages = _boardThreadPageParser.simplePages(simpleDocument) ??
          (current: normalizedPage, total: normalizedPage);
      return ForumThreadPage(
        threads: simpleThreads,
        currentPage: pages.current,
        totalPages: pages.total,
        ads: _boardThreadPageParser.parseSimpleAds(simpleDocument),
      );
    }

    final desktopPath = _urls.boardDesktopPath(category, page: normalizedPage);
    if (desktopPath != null) {
      final desktopHtml = await _client.get(desktopPath);
      final desktopDocument = html_parser.parse(desktopHtml);
      final desktopThreads =
          _boardThreadPageParser.parseDesktopThreads(desktopDocument, category);
      if (desktopThreads.isNotEmpty) {
        return ForumThreadPage(
          threads: desktopThreads,
          currentPage:
              _boardThreadPageParser.desktopCurrentPage(desktopDocument) ??
                  normalizedPage,
          totalPages:
              _boardThreadPageParser.desktopTotalPages(desktopDocument) ??
                  normalizedPage,
        );
      }
    }

    throw ForumRepositoryException('没有解析到${category.name}帖子列表');
  }

  Future<ReplyResult> submitThread({
    required ForumCategory category,
    required String title,
    required String content,
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
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(
          success: false, message: _responseParser.pageMessage(html));
    }

    final fields = _formParser.defaults(form)
      ..['atc_title'] = trimmedTitle
      ..['atc_content'] = trimmedContent
      ..['Submit'] = '提 交';

    final action = form.attributes['action'] ?? 'post.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isReplySuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '主题已发布' : message,
    );
  }

  Future<UserProfile> fetchUserProfile(String url) async {
    final overview = await fetchUserProfileOverview(url);
    return fetchUserProfileDetails(overview);
  }

  Future<UserProfile> fetchUserProfileOverview(String url) async {
    final profileUrl = _urls.absoluteUrl(url);
    final uid = await _uidFromProfileUrl(profileUrl);
    final profileDocument = html_parser.parse(
      await _client.get(
        _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.profile)),
      ),
    );
    final profile = _userProfileParser.parseOverview(
      uid: uid,
      profileUrl: profileUrl,
      profileDocument: profileDocument,
    );
    await _profileCache.saveOverview(url, profile);
    return profile;
  }

  Future<UserProfile?> cachedUserProfileOverview(String url) async {
    return _profileCache.loadOverview(url);
  }

  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) async {
    final uid = overview.uid;
    final documents = await Future.wait([
      _client
          .get(_urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.home))),
      _client.get(
          _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.topics))),
      _client
          .get(_urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.posts))),
      _client.get(
          _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.favorites))),
    ]);
    return _userProfileParser.appendDetails(
      overview: overview,
      homeDocument: html_parser.parse(documents[0]),
      topicsDocument: html_parser.parse(documents[1]),
      postsDocument: html_parser.parse(documents[2]),
      favoritesDocument: html_parser.parse(documents[3]),
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

  Future<ThreadDetail> fetchThreadDetail(ForumThread thread) async {
    final html = await _client.get(_urls.threadDetailPath(thread.url));
    final document = html_parser.parse(html);
    final favorite = await _extractThreadFavorite(thread, html);
    final section = _threadDetailParser.sectionTitle(document);
    final detailThread =
        section == null ? thread : thread.copyWith(section: section);
    final cards = _threadDetailParser.simpleThreadCards(document);
    if (cards.isNotEmpty) {
      return ThreadDetail(
        thread: detailThread,
        body: cards.first.content,
        bodyImages: cards.first.images,
        bodyLinks: cards.first.links,
        bodySegments: cards.first.segments,
        bodySaleBoxes: cards.first.saleBoxes,
        bodySaleBoxesFirst: cards.first.saleBoxesFirst,
        replies: cards.skip(1).toList(),
        favorite: favorite,
      );
    }

    final body = _threadDetailParser.bodyText(document);
    final replies = _threadDetailParser.legacyReplies(document);

    if (body.isEmpty && replies.isEmpty) {
      throw ForumRepositoryException(_responseParser.pageMessage(html));
    }

    return ThreadDetail(
      thread: detailThread,
      body: body,
      replies: replies,
      favorite: favorite,
    );
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
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isReplySuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '回复已提交' : message,
    );
  }

  Future<ReplyResult> buySaleBox(ThreadSaleBox saleBox) async {
    if (saleBox.buyPath.trim().isEmpty) {
      return const ReplyResult(success: false, message: '没有找到购买链接');
    }

    final response = await _client
        .get(_urls.relativePath(_urls.absoluteUrl(saleBox.buyPath)));
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isPurchaseSuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '购买完成' : message,
    );
  }

  Future<FavoriteResult> addFavorite(ThreadFavorite favorite) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final response = await _client.get(
      'pw_ajax.php?action=favor&tid=${favorite.tid}&nowtime=$now&verify=${favorite.verify}',
    );
    final message = _responseParser.ajaxMessage(response);
    final success = _responseParser.isFavoriteAddSuccess(message);
    return FavoriteResult(
      success: success,
      message: success ? '已收藏该主题' : message,
      state: success ? ThreadFavoriteState.favorite : favorite.state,
    );
  }

  Future<FavoriteResult> removeFavorite(ThreadFavorite favorite) async {
    final currentState = await _fetchFavoriteState(favorite.tid);
    if (currentState == ThreadFavoriteState.notFavorite) {
      return const FavoriteResult(
        success: true,
        message: '当前没有收藏该主题',
        state: ThreadFavoriteState.notFavorite,
      );
    }

    final response = await _client.post('u.php?action=favor&', {
      'verify': favorite.verify,
      'selid[]': favorite.tid,
      'job': 'clear',
      'type': '0',
    });
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isFavoriteRemoveSuccess(response, message);
    return FavoriteResult(
      success: success,
      message: success ? '已取消收藏' : message,
      state: success ? ThreadFavoriteState.notFavorite : favorite.state,
    );
  }

  Future<String?> _fetchLoggedInUsername() async {
    try {
      return _responseParser.loggedInUsername(await _client.get('index.php')) ??
          _responseParser
              .loggedInUsername(await _client.get('simple/index.php'));
    } catch (_) {
      return null;
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

    final tid = _urls.tidFromUrl(thread.url);
    if (tid == null || thread.url.contains('/read.php?')) return null;

    try {
      final readHtml = await _client.get('read.php?tid-$tid.html');
      favorite = _threadFavoriteFromHtml(thread, readHtml);
      if (favorite == null) return null;
      return favorite.copyWith(state: await _fetchFavoriteState(tid));
    } catch (_) {
      return null;
    }
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
}

class ForumRepositoryException implements Exception {
  const ForumRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
