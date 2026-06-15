import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/forum_models.dart';
import 'browsing_history_store.dart';
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
import 'parsers/thread_image_preview_parser.dart';
import 'parsers/user_profile_parser.dart';

class ForumRepository {
  ForumRepository({
    ForumClient? client,
    ForumNetworkConfig? config,
    UserProfileCache? profileCache,
    BrowsingHistoryStore? historyStore,
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
        _historyStore = historyStore ?? BrowsingHistoryStore();

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
  late ThreadImagePreviewParser _threadImagePreviewParser =
      ThreadImagePreviewParser(urls: _urls);
  late UserProfileParser _userProfileParser = UserProfileParser(urls: _urls);
  UserProfileCache _profileCache;
  final BrowsingHistoryStore _historyStore;
  final Map<String, Future<ThreadImagePreview>> _threadImagePreviewCache =
      <String, Future<ThreadImagePreview>>{};
  final Map<String, ThreadImagePreview> _completedThreadImagePreviewCache =
      <String, ThreadImagePreview>{};
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
    _threadImagePreviewParser = ThreadImagePreviewParser(urls: _urls);
    _userProfileParser = UserProfileParser(urls: _urls);
    _profileCache = UserProfileCache(urls: _urls);
    _threadImagePreviewCache.clear();
    _completedThreadImagePreviewCache.clear();
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
    var sections = _homePageParser.parseForumSections(document);
    try {
      final desktopDocument = html_parser.parse(await _client.get('index.php'));
      final desktopSections =
          _homePageParser.parseDesktopForumSections(desktopDocument);
      if (desktopSections.isNotEmpty) sections = desktopSections;
    } catch (_) {
      // Keep the mobile/simple directory if the desktop home is unavailable.
    }

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

  Future<ThreadImagePreview> fetchThreadImagePreview(
    ForumThread thread, {
    int maxDetailPages = ThreadImagePreviewParser.maxDetailPages,
    int targetMediaCount = ThreadImagePreviewParser.maxImages,
  }) {
    final cacheKey = _threadImagePreviewCacheKey(
      thread,
      maxDetailPages: maxDetailPages,
      targetMediaCount: targetMediaCount,
    );
    return _threadImagePreviewCache.putIfAbsent(
      cacheKey,
      () async {
        final preview = await _fetchThreadImagePreview(
          thread,
          maxDetailPages: maxDetailPages,
          targetMediaCount: targetMediaCount,
        );
        _completedThreadImagePreviewCache[cacheKey] = preview;
        return preview;
      },
    );
  }

  ThreadImagePreview? cachedThreadImagePreview(
    ForumThread thread, {
    int maxDetailPages = ThreadImagePreviewParser.maxDetailPages,
    int targetMediaCount = ThreadImagePreviewParser.maxImages,
  }) {
    return _completedThreadImagePreviewCache[_threadImagePreviewCacheKey(
      thread,
      maxDetailPages: maxDetailPages,
      targetMediaCount: targetMediaCount,
    )];
  }

  String _threadImagePreviewCacheKey(
    ForumThread thread, {
    required int maxDetailPages,
    required int targetMediaCount,
  }) {
    final tid = _urls.tidFromUrl(thread.url);
    return '${tid ?? thread.url}#$maxDetailPages#$targetMediaCount';
  }

  Future<ThreadImagePreview> _fetchThreadImagePreview(
    ForumThread thread, {
    required int maxDetailPages,
    required int targetMediaCount,
  }) async {
    final detailPath = _urls.threadDetailPath(thread.url);
    final html = await _client.get(detailPath);
    final pages = <({dom.Document document, String url})>[
      (document: html_parser.parse(html), url: _urls.absoluteUrl(detailPath)),
    ];
    var preview = _threadImagePreviewParser.parsePages(pages);

    final normalizedMaxDetailPages = maxDetailPages.clamp(
      1,
      ThreadImagePreviewParser.maxDetailPages,
    ).toInt();
    final normalizedTargetMediaCount = targetMediaCount.clamp(
      1,
      ThreadImagePreviewParser.maxImages,
    ).toInt();

    for (var page = 2;
        page <= normalizedMaxDetailPages &&
            preview.media.length < normalizedTargetMediaCount;
        page += 1) {
      try {
        final pagePath = _urls.threadDetailPath(thread.url, page: page);
        final pageHtml = await _client.get(pagePath);
        pages.add((
          document: html_parser.parse(pageHtml),
          url: _urls.absoluteUrl(pagePath),
        ));
        preview = _threadImagePreviewParser.parsePages(pages);
      } catch (_) {
        // Later detail pages are best-effort for list previews.
      }
    }

    if (preview.hostPages.isEmpty ||
        preview.media.length >= normalizedTargetMediaCount) {
      return _previewWithMediaLimit(preview, normalizedTargetMediaCount);
    }

    final media = preview.media.take(normalizedTargetMediaCount).toList();
    final resolvedHostMedia = await _resolveHostPagesMedia(
      preview.hostPages
          .take(math.min(
            ThreadImagePreviewParser.maxHostPages,
            normalizedTargetMediaCount,
          ))
          .toList(),
    );
    for (final item in resolvedHostMedia) {
      if (media.length >= normalizedTargetMediaCount) break;
      final key = item.type == ThreadPreviewMediaType.video
          ? item.videoUrl ?? item.openUrl
          : item.displayUrl;
      if (media.any((existing) {
        final existingKey = existing.type == ThreadPreviewMediaType.video
            ? existing.videoUrl ?? existing.openUrl
            : existing.displayUrl;
        return existingKey == key;
      })) {
        continue;
      }
      media.add(item);
    }

    final images = media
        .where((item) => item.type == ThreadPreviewMediaType.image)
        .map((item) => ThreadImage(url: item.url))
        .toList();
    return ThreadImagePreview(
      images: images,
      media: media,
      hostPages: preview.hostPages,
      hasBuyBlock: preview.hasBuyBlock,
      note: media.isNotEmpty ? null : preview.note,
    );
  }

  ThreadImagePreview _previewWithMediaLimit(
    ThreadImagePreview preview,
    int maxMedia,
  ) {
    final media = preview.media.take(maxMedia).toList();
    final images = media
        .where((item) => item.type == ThreadPreviewMediaType.image)
        .map((item) => ThreadImage(url: item.url))
        .toList();
    return ThreadImagePreview(
      images: images,
      media: media,
      hostPages: preview.hostPages,
      hasBuyBlock: preview.hasBuyBlock,
      note: media.isNotEmpty ? null : preview.note,
    );
  }

  Future<List<ThreadPreviewMedia>> _resolveHostPageMedia(String url) async {
    if (RegExp(r'gofile\.io/d/', caseSensitive: false).hasMatch(url)) {
      final gofileMedia = await _resolveGofileMediaList(url);
      if (gofileMedia.isNotEmpty) return gofileMedia;
    }

    final hostHtml = await _client.get(url);
    final hostDocument = html_parser.parse(hostHtml);
    return _threadImagePreviewParser.parseHostPageMedia(hostDocument, url);
  }

  Future<List<ThreadPreviewMedia>> _resolveHostPagesMedia(
    List<String> urls,
  ) async {
    const concurrency = 3;
    final output = <ThreadPreviewMedia>[];
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= urls.length) return;
        try {
          output.addAll(await _resolveHostPageMedia(urls[index]));
        } catch (_) {
          // Third-party preview pages are best-effort.
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        math.min(concurrency, urls.length),
        (_) => worker(),
      ),
    );
    return output;
  }

  Future<List<ThreadPreviewMedia>> _resolveGofileMediaList(String url) async {
    final idMatch =
        RegExp(r'gofile\.io/d/([a-z0-9]+)', caseSensitive: false)
            .firstMatch(url);
    final contentId = idMatch?.group(1);
    if (contentId == null || contentId.isEmpty) return const [];

    final token = await _createGofileGuestToken();
    final uri = Uri.https('api.gofile.io', '/contents/$contentId', {
      'contentFilter': '',
      'page': '1',
      'pageSize': '1000',
      'sortField': 'createTime',
      'sortDirection': '-1',
    });
    final response = await _getExternalJson(uri, headers: {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      'X-Website-Token': _generateGofileWebsiteToken(token),
      'X-BL': 'zh-CN',
      HttpHeaders.userAgentHeader: _gofileUserAgent,
    });
    final data = response['data'];
    final children = data is Map<String, dynamic> ? data['children'] : null;
    final files = _flattenGofileChildren(children);
    return files
        .map(
          (file) => _gofileFileToPreviewMedia(
            file,
            sourceUrl: url,
            accountToken: token,
          ),
        )
        .nonNulls
        .take(ThreadImagePreviewParser.maxImages)
        .toList();
  }

  Future<String> _createGofileGuestToken() async {
    final response = await _postExternalJson(
      Uri.https('api.gofile.io', '/accounts'),
      headers: {
        HttpHeaders.userAgentHeader: _gofileUserAgent,
      },
    );
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      final token = data['token'];
      if (token is String && token.isNotEmpty) return token;
    }
    throw const FormatException('Gofile token missing');
  }

  Future<Map<String, dynamic>> _getExternalJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    return _externalJson(uri, method: 'GET', headers: headers);
  }

  Future<Map<String, dynamic>> _postExternalJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) {
    return _externalJson(uri, method: 'POST', headers: headers);
  }

  Future<Map<String, dynamic>> _externalJson(
    Uri uri, {
    required String method,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = method == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final preview = body.length > 400 ? body.substring(0, 400) : body;
        throw HttpException(
          'HTTP ${response.statusCode}: $preview',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Expected JSON object');
    } finally {
      client.close(force: true);
    }
  }

  String _generateGofileWebsiteToken(String accountToken) {
    final bucket =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 14400).toString();
    final input = '$_gofileUserAgent::zh-CN::$accountToken::$bucket::9844d94d963d30';
    return crypto.sha256.convert(utf8.encode(input)).toString();
  }

  List<Map<String, dynamic>> _flattenGofileChildren(Object? children) {
    final values = switch (children) {
      List<Object?> list => list,
      Map<Object?, Object?> map => map.values.toList(),
      _ => const <Object?>[],
    };
    final files = <Map<String, dynamic>>[];
    for (final child in values) {
      if (child is! Map) continue;
      final normalized = child.cast<String, dynamic>();
      final nested = normalized['children'];
      if (nested != null) {
        files.addAll(_flattenGofileChildren(nested));
      } else {
        files.add(normalized);
      }
    }
    return files;
  }

  ThreadPreviewMedia? _gofileFileToPreviewMedia(
    Map<String, dynamic> file, {
    required String sourceUrl,
    required String accountToken,
  }) {
    final mime = _stringValue(file, ['mimetype', 'mimeType', 'contentType']);
    final name = _stringValue(file, ['name']);
    final url = _stringValue(file, ['directLink', 'link', 'downloadPage']);
    final poster = _stringValue(file, ['thumbnail', 'preview']);
    if (url.isEmpty && poster.isEmpty) return null;

    if (_isVideoMedia(mime, name, url)) {
      final videoUrl = url.isNotEmpty ? url : poster;
      return ThreadPreviewMedia.video(
        url: poster.isNotEmpty ? poster : videoUrl,
        videoUrl: videoUrl,
        poster: poster.isNotEmpty ? poster : null,
        videoHeaders: _gofileVideoHeaders(accountToken: accountToken),
        source: sourceUrl,
        name: name.isNotEmpty ? name : null,
      );
    }

    if (_isImageMedia(mime, name, url, poster)) {
      final imageUrl = poster.isNotEmpty ? poster : url;
      return ThreadPreviewMedia.image(
        url: imageUrl,
        source: url.isNotEmpty ? url : imageUrl,
        name: name.isNotEmpty ? name : null,
      );
    }

    return null;
  }

  String _stringValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return '';
  }

  bool _isVideoMedia(String mime, String name, String url) {
    return mime.toLowerCase().startsWith('video/') ||
        _videoExtensionPattern.hasMatch(name) ||
        _videoExtensionPattern.hasMatch(url);
  }

  bool _isImageMedia(String mime, String name, String url, String poster) {
    return mime.toLowerCase().startsWith('image/') ||
        _imageExtensionPattern.hasMatch(name) ||
        _imageExtensionPattern.hasMatch(url) ||
        _imageExtensionPattern.hasMatch(poster);
  }

  Map<String, String> _gofileVideoHeaders({required String accountToken}) {
    return {
      HttpHeaders.authorizationHeader: 'Bearer $accountToken',
      HttpHeaders.cookieHeader: 'accountToken=$accountToken',
      HttpHeaders.refererHeader: 'https://gofile.io/',
      HttpHeaders.userAgentHeader: _gofileUserAgent,
    };
  }

  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) {
    return _historyStore.recent(limit: limit);
  }

  Future<void> clearBrowsingHistory() {
    return _historyStore.clear();
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
    final desktopPath = _urls.boardDesktopPath(category, page: normalizedPage);
    var desktopSubBoards = const <ForumBoard>[];
    if (desktopPath != null) {
      try {
        final desktopHtml = await _client.get(desktopPath);
        final desktopDocument = html_parser.parse(desktopHtml);
        desktopSubBoards = _boardThreadPageParser.parseDesktopSubBoards(
            desktopDocument, category);
      } catch (_) {
        // The simple/mobile thread list should still render if desktop fails.
      }
    }
    if (simpleThreads.isNotEmpty) {
      final pages = _boardThreadPageParser.simplePages(simpleDocument) ??
          (current: normalizedPage, total: normalizedPage);
      return ForumThreadPage(
        threads: simpleThreads,
        currentPage: pages.current,
        totalPages: pages.total,
        ads: _boardThreadPageParser.parseSimpleAds(simpleDocument),
        subBoards: desktopSubBoards,
      );
    }

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
          subBoards: _boardThreadPageParser.parseDesktopSubBoards(
              desktopDocument, category),
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

  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final detailPath = _urls.threadDetailPath(thread.url, page: normalizedPage);
    final html = await _client.get(detailPath);
    final document = html_parser.parse(html);
    final favorite = await _extractThreadFavorite(thread, html);
    final posts = _threadDetailParser.desktopThreadCards(document);
    final pagination = _threadDetailParser.desktopPagination(
      document,
      requestedPage: normalizedPage,
    );
    final section = _threadDetailParser.sectionTitle(document);

    if (posts.isEmpty) {
      throw ForumRepositoryException(_responseParser.pageMessage(html));
    }

    final isOpeningPage = pagination.currentPage == 1;
    final first = isOpeningPage ? posts.first : null;
    final detailThread = thread.copyWith(
      title: _threadDetailParser.threadTitle(document) ?? thread.title,
      url: _canonicalThreadUrl(
        parserUrl: _threadDetailParser.threadUrl(document),
        sourceUrl: thread.url,
        detailPath: detailPath,
      ),
      section: section ?? thread.section,
      author: first?.author,
      authorUrl: first?.authorUrl,
      authorAvatarUrl: first?.authorAvatarUrl,
      authorPostsUrl: first?.authorPostsUrl,
      lastPost: first?.postedAt ?? thread.lastPost,
    );

    final detail = ThreadDetail(
      thread: detailThread,
      body: first?.content ?? '',
      bodyImages: first?.images ?? const [],
      bodyLinks: first?.links ?? const [],
      bodySegments: first?.segments ?? const [],
      bodySaleBoxes: first?.saleBoxes ?? const [],
      bodySaleBoxesFirst: first?.saleBoxesFirst ?? false,
      replies: isOpeningPage ? posts.skip(1).toList() : posts,
      pagination: pagination,
      favorite: favorite,
      previousThread: _threadDetailParser.previousThread(document),
      nextThread: _threadDetailParser.nextThread(document),
      rssFeed: _threadDetailParser.rssFeed(document),
    );
    await _recordThreadView(detail.thread);
    return detail;
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

  String _canonicalThreadUrl({
    required String? parserUrl,
    required String sourceUrl,
    required String detailPath,
  }) {
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
}

const _gofileUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

final _videoExtensionPattern = RegExp(
  r'\.(?:mp4|webm|mov|m4v)(?:[?#].*)?$',
  caseSensitive: false,
);

final _imageExtensionPattern = RegExp(
  r'\.(?:jpg|jpeg|png|webp|gif|bmp)(?:[?#].*)?$',
  caseSensitive: false,
);

class ForumRepositoryException implements Exception {
  const ForumRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
