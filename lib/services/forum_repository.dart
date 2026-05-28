import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/forum_models.dart';
import 'forum_client.dart';

class ForumRepository {
  ForumRepository({ForumClient? client}) : _client = client ?? ForumClient();

  final ForumClient _client;
  String? _currentUsername;

  bool get isLoggedIn => _client.isLoggedIn;

  String? get currentUsername => _currentUsername;

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
      captchaBytes: await _client.getBytes(_captchaPath(captchaSrc)),
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
      _currentUsername = _extractLoggedInUsername(response) ??
          await _fetchLoggedInUsername() ??
          username.trim();
      return const LoginResult(success: true, message: '登录成功');
    }

    return LoginResult(success: false, message: _extractPageMessage(response));
  }

  Future<ForumHomeSnapshot> fetchHome() async {
    final html = await _client.get('simple/index.php');
    final document = html_parser.parse(html);
    final latest = await _parseLatestThreads(document);
    final hot = _parseHotCategories(document);
    final sections = _parseForumSections(document);

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

    final fields = _formDefaults(form)
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
    final response =
        await _client.post(_relativePath(_absoluteUrl(action)), fields);
    return _parseSearchResults(html_parser.parse(response));
  }

  Future<List<ForumThread>> fetchBoardThreads(ForumCategory category) async {
    return (await fetchBoardThreadPage(category)).threads;
  }

  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final desktopPath = _boardDesktopPath(category, page: normalizedPage);
    if (desktopPath != null) {
      final desktopHtml = await _client.get(desktopPath);
      final desktopDocument = html_parser.parse(desktopHtml);
      final desktopThreads =
          _parseDesktopBoardThreads(desktopDocument, category);
      if (desktopThreads.isNotEmpty) {
        return ForumThreadPage(
          threads: desktopThreads,
          currentPage: _boardCurrentPage(desktopDocument) ?? normalizedPage,
          totalPages: _boardTotalPages(desktopDocument) ?? normalizedPage,
        );
      }
    }

    final url = category.url ??
        'https://south-plus.net/simple/index.php?${category.slug}.html';
    final html = await _client.get(_relativePath(url));
    final document = html_parser.parse(html);
    final threads = <ForumThread>[];
    final seen = <String>{};

    for (final link in document.querySelectorAll('li a[href*="?t"]')) {
      final parent = link.parent;
      if ((parent?.attributes['style'] ?? '').contains('display:none')) {
        continue;
      }
      final href = link.attributes['href'] ?? '';
      if (!_isThreadHref(href) || !seen.add(href)) continue;

      final meta = _cleanText(link.querySelector('.by')?.text ?? '');
      final title = _threadTitleFromBoardLink(link, meta);
      if (title.isEmpty) continue;

      final repliesText = _cleanText(parent?.querySelector('.num')?.text ?? '');
      threads.add(
        ForumThread(
          title: title,
          url: _absoluteUrl(href),
          replies: _firstInt(repliesText) ?? 0,
          section: category.name,
          author: _authorFromBoardMeta(meta),
          lastPost: _dateFromBoardMeta(meta),
        ),
      );
    }

    if (threads.isEmpty) {
      throw ForumRepositoryException('没有解析到${category.name}帖子列表');
    }
    return ForumThreadPage(
      threads: threads,
      currentPage: 1,
      totalPages: 1,
    );
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

    final fid = _fidFromCategory(category);
    if (fid == null) {
      return const ReplyResult(success: false, message: '没有找到版块 ID');
    }

    final html = await _client.get('post.php?fid=$fid');
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(success: false, message: _extractPageMessage(html));
    }

    final fields = _formDefaults(form)
      ..['atc_title'] = trimmedTitle
      ..['atc_content'] = trimmedContent
      ..['Submit'] = '提 交';

    final action = form.attributes['action'] ?? 'post.php?';
    final response =
        await _client.post(_relativePath(_absoluteUrl(action)), fields);
    final message = _extractPageMessage(response);
    final success = _isReplySuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '主题已发布' : message,
    );
  }

  Map<String, String> _formDefaults(dom.Element form) {
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (type == 'submit' || type == 'reset' || type == 'button') continue;
      if ((type == 'radio' || type == 'checkbox') &&
          !input.attributes.containsKey('checked')) {
        continue;
      }
      fields[name] = input.attributes['value'] ?? '';
    }

    for (final select in form.querySelectorAll('select[name]')) {
      final name = select.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final option = select.querySelector('option[selected]') ??
          select.querySelector('option');
      if (option == null) continue;
      fields[name] = option.attributes['value'] ?? _cleanText(option.text);
    }

    for (final textarea in form.querySelectorAll('textarea[name]')) {
      final name = textarea.attributes['name'];
      if (name == null || name.isEmpty) continue;
      fields[name] = textarea.text;
    }
    return fields;
  }

  List<ForumThread> _parseSearchResults(dom.Document document) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('tr')) {
      final threadLink = row.querySelector('a[href*="read.php?tid-"]');
      if (threadLink == null) continue;

      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;

      final cells = row.children
          .where((child) => child.localName == 'td' || child.localName == 'th')
          .toList();
      final sectionCell = cells.length > 2 ? cells[2] : row;
      final authorCell = cells.length > 3 ? cells[3] : row;
      final repliesCell = cells.length > 4 ? cells[4] : null;

      final section = _cleanText(
        sectionCell.querySelector('a[href*="thread.php"]')?.text ?? '',
      );
      final authorLink = authorCell.querySelector('a[href*="uid"]');
      final author = _cleanText(authorLink?.text ?? '');
      final authorHref = authorLink?.attributes['href'] ?? '';
      final date = RegExp(r'\d{4}-\d{2}-\d{2}')
          .firstMatch(_cleanText(authorCell.text))
          ?.group(0);

      threads.add(
        ForumThread(
          title: title,
          url: _absoluteUrl(href),
          replies: _firstInt(_cleanText(repliesCell?.text ?? '')) ?? 0,
          section: section.isEmpty ? '搜索结果' : section,
          author: author.isEmpty ? null : author,
          authorUrl: authorHref.isEmpty ? null : _absoluteUrl(authorHref),
          lastPost: date,
        ),
      );
      if (threads.length >= 60) break;
    }
    return threads;
  }

  List<ForumThread> _parseDesktopBoardThreads(
    dom.Document document,
    ForumCategory category,
  ) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('tr.tr3')) {
      final threadLink = row.querySelector('a[href*="read.php?tid-"]');
      if (threadLink == null) continue;
      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;

      final authorLink = row.querySelector('a.bl[href*="uid"]') ??
          row.querySelector('a[href*="action-show-uid"]');
      final authorHref = authorLink?.attributes['href'] ?? '';
      final text = _cleanText(row.text);
      final metrics = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(text);
      final date =
          RegExp(r'\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?').firstMatch(text);
      threads.add(
        ForumThread(
          title: title,
          url: _absoluteUrl(href),
          replies: metrics == null ? 0 : int.tryParse(metrics.group(1)!) ?? 0,
          section: category.name,
          author: _cleanText(authorLink?.text ?? '').isEmpty
              ? null
              : _cleanText(authorLink?.text ?? ''),
          authorUrl: authorHref.isEmpty ? null : _absoluteUrl(authorHref),
          lastPost: date?.group(0),
        ),
      );
      if (threads.length >= 60) break;
    }
    return threads;
  }

  String? _boardDesktopPath(ForumCategory category, {int page = 1}) {
    final fid = _fidFromCategory(category);
    if (fid != null) {
      final pagePart = page <= 1 ? '' : '-page-$page';
      return 'thread.php?fid-$fid$pagePart.html';
    }
    final slug = category.slug;
    if (slug.startsWith('fid-')) return 'thread.php?$slug.html';
    final href = category.url;
    if (href == null) return null;
    final hrefFid = RegExp(r'fid-\d+').firstMatch(href)?.group(0);
    return hrefFid == null ? null : 'thread.php?$hrefFid.html';
  }

  String? _fidFromCategory(ForumCategory category) {
    for (final value in [category.slug, category.url ?? '']) {
      final match = RegExp(r'(?:^f|fid-|[?&]f)(\d+)').firstMatch(value);
      if (match != null) return match.group(1);
    }
    return null;
  }

  int? _boardCurrentPage(dom.Document document) {
    final pages = _boardPages(document);
    return pages?.$1;
  }

  int? _boardTotalPages(dom.Document document) {
    final pages = _boardPages(document);
    return pages?.$2;
  }

  (int, int)? _boardPages(dom.Document document) {
    final text = _cleanText(document.body?.text ?? '');
    final match = RegExp(r'Pages:\s*(\d+)\s*/\s*(\d+)').firstMatch(text);
    if (match == null) return null;
    final current = int.tryParse(match.group(1)!);
    final total = int.tryParse(match.group(2)!);
    if (current == null || total == null || total < 1) return null;
    return (current, total);
  }

  Future<UserProfile> fetchUserProfile(String url) async {
    final profileUrl = _absoluteUrl(url);
    var uid = _uidFromUrl(profileUrl);
    if (uid == null) {
      final html = await _client.get(_relativePath(profileUrl));
      uid = _uidFromDocument(html_parser.parse(html));
    }
    if (uid == null) {
      throw const ForumRepositoryException('没有找到用户 UID');
    }

    final profileHtml = await _client
        .get(_relativePath(_userTabUrl(uid, UserProfileTab.profile)));
    final profileDocument = html_parser.parse(profileHtml);
    final shell = _parseUserProfileShell(uid, profileUrl, profileDocument);

    final homeDocument = html_parser.parse(
      await _client.get(_relativePath(_userTabUrl(uid, UserProfileTab.home))),
    );
    final topicsDocument = html_parser.parse(
      await _client.get(_relativePath(_userTabUrl(uid, UserProfileTab.topics))),
    );
    final postsDocument = html_parser.parse(
      await _client.get(_relativePath(_userTabUrl(uid, UserProfileTab.posts))),
    );
    final favoritesDocument = html_parser.parse(
      await _client
          .get(_relativePath(_userTabUrl(uid, UserProfileTab.favorites))),
    );

    return UserProfile(
      uid: uid,
      name: shell.name,
      url: profileUrl,
      tagline: shell.tagline,
      avatarUrl: shell.avatarUrl,
      level: shell.level,
      info: _parseUserFields(profileDocument.querySelector('#u-profile')),
      stats: _parseUserFields(profileDocument.querySelector('#u-profile-s')),
      signature: _cleanText(
        profileDocument.querySelector('.u-profile .u-table')?.text ?? '',
      ),
      homeActivities: _parseUserHomeActivities(homeDocument),
      homeReplies: _parseUserHomeReplies(homeDocument),
      topics: _parseUserThreadRows(topicsDocument, includeMetrics: true),
      posts: _parseUserThreadRows(postsDocument, includeAuthor: true),
      favorites: _parseUserFavorites(favoritesDocument),
    );
  }

  Future<ThreadDetail> fetchThreadDetail(ForumThread thread) async {
    final html = await _client.get(_threadDetailPath(thread.url));
    final document = html_parser.parse(html);
    final favorite = await _extractThreadFavorite(thread, html);
    final cards = _extractSimpleThreadCards(document);
    if (cards.isNotEmpty) {
      return ThreadDetail(
        thread: thread,
        body: cards.first.content,
        bodyImages: cards.first.images,
        bodyLinks: cards.first.links,
        bodySaleBoxes: cards.first.saleBoxes,
        bodySaleBoxesFirst: cards.first.saleBoxesFirst,
        replies: cards.skip(1).toList(),
        favorite: favorite,
      );
    }

    final body = _extractBodyText(document);
    final replies = _extractReplies(document);

    if (body.isEmpty && replies.isEmpty) {
      throw ForumRepositoryException(_extractPageMessage(html));
    }

    return ThreadDetail(
      thread: thread,
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

    final html = await _client.get(_relativePath(thread.url));
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(success: false, message: _extractPageMessage(html));
    }

    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = input.attributes['type'] ?? '';
      if (type == 'submit') continue;
      fields[name] = input.attributes['value'] ?? '';
    }

    fields['atc_title'] =
        title.trim().isEmpty ? 'Re:${thread.title}' : title.trim();
    fields['atc_content'] = content.trim();
    fields['Submit'] = ' 提 交 ';

    final action = form.attributes['action'] ?? 'post.php?';
    final response =
        await _client.post(_relativePath(_absoluteUrl(action)), fields);
    final message = _extractPageMessage(response);
    final success = _isReplySuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '回复已提交' : message,
    );
  }

  Future<ReplyResult> buySaleBox(ThreadSaleBox saleBox) async {
    if (saleBox.buyPath.trim().isEmpty) {
      return const ReplyResult(success: false, message: '没有找到购买链接');
    }

    final response =
        await _client.get(_relativePath(_absoluteUrl(saleBox.buyPath)));
    final message = _extractPageMessage(response);
    final success = _isPurchaseSuccess(response, message);
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
    final message = _extractAjaxMessage(response);
    final success = _isFavoriteAddSuccess(message);
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
    final message = _extractPageMessage(response);
    final success = _isFavoriteRemoveSuccess(response, message);
    return FavoriteResult(
      success: success,
      message: success ? '已取消收藏' : message,
      state: success ? ThreadFavoriteState.notFavorite : favorite.state,
    );
  }

  String _extractPageMessage(String html) {
    final document = html_parser.parse(html);
    final title = _cleanText(document.querySelector('title')?.text ?? '');
    if (title.isNotEmpty) {
      return title
          .replaceFirst(' - 南+ South Plus - powered by Pu!mdHd', '')
          .trim();
    }

    final text = _cleanText(document.body?.text ?? '');
    if (text.isEmpty) return '登录失败';
    final hints = ['认证码', '验证码', '密码', '用户名', '非法', '错误', '失败'];
    for (final hint in hints) {
      final index = text.indexOf(hint);
      if (index == -1) continue;
      final start = index - 24 < 0 ? 0 : index - 24;
      final end = index + 80 > text.length ? text.length : index + 80;
      return text.substring(start, end);
    }
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  bool _isReplySuccess(String html, String message) {
    if (message.contains('错误') ||
        message.contains('失败') ||
        message.contains('不能为空') ||
        message.contains('灌水') ||
        message.contains('权限') ||
        message.contains('认证码')) {
      return false;
    }
    return html.contains('发帖完毕') ||
        html.contains('回复成功') ||
        html.contains('发表成功') ||
        html.contains('顺利') ||
        message.contains('发帖完毕') ||
        message.contains('回复成功') ||
        message.contains('发表成功');
  }

  bool _isPurchaseSuccess(String html, String message) {
    if (message.contains('错误') ||
        message.contains('失败') ||
        message.contains('权限') ||
        message.contains('金币不足') ||
        message.contains('SP币不足') ||
        message.contains('认证码')) {
      return false;
    }
    return html.contains('操作完成') ||
        html.contains('购买成功') ||
        message.contains('操作完成') ||
        message.contains('购买成功');
  }

  bool _isFavoriteAddSuccess(String message) {
    if (message.contains('非法') ||
        message.contains('错误') ||
        message.contains('失败') ||
        message.contains('权限') ||
        message.contains('认证码')) {
      return false;
    }
    return message.contains('收藏');
  }

  bool _isFavoriteRemoveSuccess(String html, String message) {
    if (message.contains('错误') ||
        message.contains('失败') ||
        message.contains('权限') ||
        message.contains('认证码')) {
      return false;
    }
    return html.contains('操作完成') ||
        message.contains('操作完成') ||
        message.contains('删除') ||
        message.contains('取消');
  }

  String _extractAjaxMessage(String xml) {
    final cdata = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true)
        .firstMatch(xml)
        ?.group(1);
    if (cdata != null) return _cleanText(cdata);

    final document = html_parser.parse(xml);
    final ajax = _cleanText(document.querySelector('ajax')?.text ?? '');
    if (ajax.isNotEmpty) return ajax;

    final text = _cleanText(document.body?.text ?? xml);
    return text.isEmpty ? '操作失败' : text;
  }

  Future<String?> _fetchLoggedInUsername() async {
    try {
      return _extractLoggedInUsername(await _client.get('index.php')) ??
          _extractLoggedInUsername(await _client.get('simple/index.php'));
    } catch (_) {
      return null;
    }
  }

  String? _extractLoggedInUsername(String html) {
    final document = html_parser.parse(html);
    for (final link in document.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      final text = _cleanText(link.text);
      if ((href == 'u.php' || href.endsWith('/u.php')) &&
          text.isNotEmpty &&
          !{'个人首页', '查看个人资料'}.contains(text)) {
        return text;
      }
    }

    final logoutLink =
        document.querySelector('a[href*="login.php?action=quit"]') ??
            document.querySelector('a[href*="login.php?action-quit"]');
    if (logoutLink != null) {
      final nearbyText = _cleanText(logoutLink.parent?.text ?? '');
      final match = RegExp(r'([\w\u4e00-\u9fa5.-]{2,24})\s*(退出|注销|登出)')
          .firstMatch(nearbyText);
      if (match != null) return match.group(1);
    }

    for (final selector in [
      '#winduid',
      '.user-info',
      '.user-infoWraptwo',
      '.toptool',
      '#td_userinfomore',
      '#head_user',
    ]) {
      final text = _cleanText(document.querySelector(selector)?.text ?? '');
      final username = _usernameFromText(text);
      if (username != null) return username;
    }

    final bodyText = _cleanText(document.body?.text ?? '');
    return _usernameFromText(bodyText);
  }

  String? _usernameFromText(String text) {
    if (text.isEmpty) return null;
    for (final pattern in [
      RegExp(r'欢迎您?[，,\s]+([\w\u4e00-\u9fa5.-]{2,24})'),
      RegExp(r'用户[:：\s]+([\w\u4e00-\u9fa5.-]{2,24})'),
      RegExp(r'会员[:：\s]+([\w\u4e00-\u9fa5.-]{2,24})'),
      RegExp(r'([\w\u4e00-\u9fa5.-]{2,24})\s*(退出|注销|登出)'),
    ]) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  Future<List<ForumThread>> _parseLatestThreads(dom.Document document) async {
    final container =
        document.querySelector('.carousel-item.active') ?? document.body;
    if (container == null) return const [];

    final threads = _threadsFromLinks(container.querySelectorAll('a[href]'));
    if (threads.isNotEmpty) return threads;

    final scriptSrc = container.querySelector('script[src]')?.attributes['src'];
    if (scriptSrc == null || scriptSrc.isEmpty) return const [];

    final scriptUri = Uri.parse('https://south-plus.net/').resolve(scriptSrc);
    final script = await _client.get(_relativePath(scriptUri.toString()));
    final fragment = html_parser.parseFragment(_htmlFromDocumentWrites(script));
    return _threadsFromLinks(fragment.querySelectorAll('a[href]'));
  }

  List<ForumThread> _threadsFromLinks(List<dom.Element> links) {
    final threads = <ForumThread>[];
    final seen = <String>{};
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (title.isEmpty || !_isThreadHref(href) || !seen.add(href)) continue;
      threads.add(
        ForumThread(
          title: title,
          url: _absoluteUrl(href),
          replies: 0,
          section: '最新讨论',
          author: '匿名',
        ),
      );
      if (threads.length == 3) break;
    }
    return threads;
  }

  String _htmlFromDocumentWrites(String script) {
    final buffer = StringBuffer();
    for (final line in script.split('\n')) {
      final start = line.indexOf('document.write("');
      if (start == -1) continue;
      final contentStart = start + 'document.write("'.length;
      final contentEnd = line.lastIndexOf('");');
      if (contentEnd <= contentStart) continue;
      buffer.write(line.substring(contentStart, contentEnd));
    }
    return buffer.toString();
  }

  List<ForumCategory> _parseHotCategories(dom.Document document) {
    final hotList = _accordionListAfterToggle(document, '热门版块');
    if (hotList == null) return const [];

    return _parseSubtoggleLinks(hotList)
        .map(
          (link) => ForumCategory(
            name: link.title,
            slug: _slugFromHref(link.href),
            url: _absoluteUrl(link.href),
          ),
        )
        .toList();
  }

  List<ForumSection> _parseForumSections(dom.Document document) {
    final accordion = document.querySelector('ul.accordion');
    if (accordion == null) return const [];

    final sections = <ForumSection>[];
    for (var i = 0; i < accordion.children.length; i++) {
      final child = accordion.children[i];
      final toggle = _directToggle(child);
      if (toggle == null) continue;

      final title = _cleanText(toggle.text);
      if (title.isEmpty || title == '热门版块') continue;

      final list = _nextElement(accordion.children, i, 'ul');
      if (list == null) continue;

      final links = _parseSubtoggleLinks(list).take(12).toList();
      if (links.isEmpty) continue;

      sections.add(
        ForumSection(
          title: title,
          items: links
              .map(
                (link) => ForumThread(
                  title: link.title,
                  url: _absoluteUrl(link.href),
                  replies: 0,
                  section: title,
                  author: '版块',
                ),
              )
              .toList(),
        ),
      );
      if (sections.length == 8) break;
    }
    return sections;
  }

  dom.Element? _accordionListAfterToggle(dom.Document document, String title) {
    final accordion = document.querySelector('ul.accordion');
    if (accordion == null) return null;

    for (var i = 0; i < accordion.children.length; i++) {
      final toggle = _directToggle(accordion.children[i]);
      if (toggle == null || _cleanText(toggle.text) != title) continue;
      return _nextElement(accordion.children, i, 'ul');
    }
    return null;
  }

  dom.Element? _directToggle(dom.Element element) {
    if (element.localName != 'li') return null;
    return element.children
        .where((child) =>
            child.localName == 'a' && child.classes.contains('toggle'))
        .firstOrNull;
  }

  dom.Element? _nextElement(List<dom.Element> elements, int index, String tag) {
    for (var i = index + 1; i < elements.length; i++) {
      if (elements[i].localName == tag) return elements[i];
      if (_directToggle(elements[i]) != null) return null;
    }
    return null;
  }

  List<_ForumLinkData> _parseSubtoggleLinks(dom.Element element) {
    final seen = <String>{};
    final links = <_ForumLinkData>[];
    for (final link in element.querySelectorAll('a.subtoggle[href]')) {
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (href.isEmpty || title.isEmpty || !seen.add('$href$title')) continue;
      links.add(_ForumLinkData(title: title, href: href));
    }
    return links;
  }

  List<ThreadReply> _extractReplies(dom.Document document) {
    return document
        .querySelectorAll('.reply')
        .map((reply) {
          final author = _cleanText(reply.querySelector('b')?.text ?? '匿名');
          final content =
              _cleanText(reply.querySelector('.content')?.text ?? reply.text);
          return ThreadReply(author: author, content: content);
        })
        .where((reply) => reply.content.isNotEmpty)
        .toList();
  }

  _UserProfileShell _parseUserProfileShell(
    String uid,
    String url,
    dom.Document document,
  ) {
    final top = document.querySelector('#u-top');
    final name = _cleanText(top?.querySelector('.u-h1')?.text ?? '');
    final avatar = document.querySelector('#u-portrait img')?.attributes['src'];
    final levelRow = document
        .querySelectorAll('#u-sidebar tr')
        .where((row) => _cleanText(row.text).contains('等级'))
        .firstOrNull;
    final tagline = _userTagline(top);
    return _UserProfileShell(
      name: name.isEmpty ? '用户 $uid' : name,
      tagline: tagline,
      avatarUrl: avatar == null || avatar.isEmpty ? null : _absoluteUrl(avatar),
      level: _cleanText(levelRow?.children.lastOrNull?.text ?? ''),
    );
  }

  String? _userTagline(dom.Element? top) {
    if (top == null) return null;
    final row = top.querySelector('table tr');
    if (row == null || row.children.length < 2) return null;
    final tagline = _cleanText(row.children[1].text);
    return tagline.isEmpty ? null : tagline;
  }

  List<UserProfileField> _parseUserFields(dom.Element? section) {
    if (section == null) return const [];
    final fields = <UserProfileField>[];
    for (final row in section.querySelectorAll('tr')) {
      if (row.children.length < 2) continue;
      final label = _cleanText(row.children.first.text);
      final value = _cleanText(row.children[1].text);
      if (label.isEmpty || value.isEmpty) continue;
      fields.add(UserProfileField(label: label, value: value));
    }
    return fields;
  }

  List<UserActivityItem> _parseUserHomeActivities(dom.Document document) {
    final links = document.querySelectorAll(
      '.u-box-wrap a[href*="read.php"], .u-box-wrap a[href*="job.php?action-topost"]',
    );
    final activities = <UserActivityItem>[];
    final seen = <String>{};
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (href.isEmpty || title.isEmpty || !seen.add(href)) continue;
      final rowText = _cleanText(link.parent?.text ?? '');
      activities.add(
        UserActivityItem(
          title: title,
          url: _absoluteUrl(href),
          action: rowText.contains('回复') ? '回复了主题' : '发表了主题',
          author: _cleanText(
            link.parent?.querySelector('a[href*="uid"]')?.text ?? '',
          ),
        ),
      );
      if (activities.length >= 8) break;
    }
    return activities;
  }

  List<UserActivityItem> _parseUserHomeReplies(dom.Document document) {
    final container =
        document.querySelectorAll('.u-box-wrap').skip(1).firstOrNull;
    if (container == null) return const [];
    final replies = <UserActivityItem>[];
    for (final link
        in container.querySelectorAll('a[href*="job.php?action-topost"]')) {
      final title = _cleanText(link.text);
      final href = link.attributes['href'] ?? '';
      if (title.isEmpty || href.isEmpty) continue;
      final text = _cleanText(link.parent?.text ?? '');
      replies.add(
        UserActivityItem(
          title: title,
          url: _absoluteUrl(href),
          action: '回复',
          date: RegExp(r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}')
              .firstMatch(text)
              ?.group(0),
        ),
      );
      if (replies.length >= 8) break;
    }
    return replies;
  }

  List<UserListItem> _parseUserThreadRows(
    dom.Document document, {
    bool includeMetrics = false,
    bool includeAuthor = false,
  }) {
    final table = document.querySelector('.u-table');
    if (table == null) return const [];
    final items = <UserListItem>[];
    for (final row in table.querySelectorAll('tr')) {
      final threadLink = row.querySelector(
        'a[href*="read.php"], a[href*="job.php?action-topost"]',
      );
      if (threadLink == null) continue;
      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty) continue;

      final section =
          _cleanText(row.querySelector('a[href*="thread.php"]')?.text ?? '');
      final text = _cleanText(row.text);
      final date =
          RegExp(r'\[(\d{4}-\d{2}-\d{2})\]').firstMatch(text)?.group(1);
      final authorLink = row.querySelector('a[href*="uid"]');
      final author = includeAuthor ? _cleanText(authorLink?.text ?? '') : null;
      final authorHref = authorLink?.attributes['href'] ?? '';
      items.add(
        UserListItem(
          title: title,
          url: _absoluteUrl(href),
          section: section.isEmpty ? null : section,
          date: date,
          author: author == null || author.isEmpty ? null : author,
          authorUrl: authorHref.isEmpty ? null : _absoluteUrl(authorHref),
          replies: includeMetrics ? _valueAfterLabel(text, '回复') : null,
          views: includeMetrics ? _valueAfterLabel(text, '浏览') : null,
        ),
      );
    }
    return items;
  }

  List<UserListItem> _parseUserFavorites(dom.Document document) {
    final table = document.querySelector('.u-table');
    if (table == null) return const [];
    final items = <UserListItem>[];
    for (final row in table.querySelectorAll('tr')) {
      final link = row.querySelector('a[href*="read.php"]');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      if (href.isEmpty || title.isEmpty) continue;
      final authorLinks = row.querySelectorAll('a[href*="uid"]');
      final authorLink = authorLinks.isEmpty ? null : authorLinks.first;
      final authorHref = authorLink?.attributes['href'] ?? '';
      items.add(
        UserListItem(
          title: title,
          url: _absoluteUrl(href),
          author: authorLink == null ? null : _cleanText(authorLink.text),
          authorUrl: authorHref.isEmpty ? null : _absoluteUrl(authorHref),
        ),
      );
    }
    return items;
  }

  int? _valueAfterLabel(String text, String label) {
    final match = RegExp('$label:(\\d+)').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _userTabUrl(String uid, UserProfileTab tab) {
    return switch (tab) {
      UserProfileTab.home => 'https://south-plus.net/u.php?uid-$uid.html',
      UserProfileTab.profile =>
        'https://south-plus.net/u.php?action-show-uid-$uid.html',
      UserProfileTab.topics =>
        'https://south-plus.net/u.php?action-topic-uid-$uid.html',
      UserProfileTab.posts =>
        'https://south-plus.net/u.php?action-post-uid-$uid.html',
      UserProfileTab.favorites =>
        'https://south-plus.net/u.php?action-favor-uid-$uid.html',
    };
  }

  String? _uidFromUrl(String url) {
    for (final pattern in [
      RegExp(r'uid-(\d+)'),
      RegExp(r'[?&]uid=(\d+)'),
    ]) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? _uidFromDocument(dom.Document document) {
    for (final link in document.querySelectorAll('a[href]')) {
      final uid = _uidFromUrl(link.attributes['href'] ?? '');
      if (uid != null) return uid;
    }
    final textUid = RegExp(r'UID\s+(\d+)')
        .firstMatch(_cleanText(document.body?.text ?? ''));
    return textUid?.group(1);
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

    final tid = _tidFromUrl(thread.url);
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
    final tid = _tidFromUrl(thread.url);
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

  String? _tidFromUrl(String url) {
    for (final pattern in [
      RegExp(r'tid-(\d+)'),
      RegExp(r'[?&]t(\d+)'),
      RegExp(r'[?&]tid=(\d+)'),
    ]) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String _threadDetailPath(String url) {
    final uri = Uri.tryParse(url);
    final isSouthPlus =
        uri == null || uri.host.isEmpty || uri.host.endsWith('south-plus.net');
    final tid = _tidFromUrl(url);
    if (isSouthPlus &&
        tid != null &&
        !url.contains('/simple/') &&
        (url.contains('read.php') || url.contains('job.php?action-topost'))) {
      return 'simple/index.php?t$tid.html';
    }
    return _relativePath(url);
  }

  List<ThreadReply> _extractSimpleThreadCards(dom.Document document) {
    final replies = <ThreadReply>[];
    for (final card in document.querySelectorAll('.card .card-body')) {
      final header = card.querySelector('h6');
      final cardText = card.querySelector('.card-text');
      final saleBoxesFirst = cardText != null && _startsWithSaleBox(cardText);
      final saleBoxes = cardText == null
          ? const <ThreadSaleBox>[]
          : _extractSaleBoxes(cardText);
      final quote = cardText == null ? null : _extractQuote(cardText);
      final images =
          cardText == null ? const <ThreadImage>[] : _extractImages(cardText);
      final links =
          cardText == null ? const <ThreadLink>[] : _extractLinks(cardText);
      final content = _cleanText(cardText?.text ?? '');
      if (header == null ||
          (content.isEmpty &&
              saleBoxes.isEmpty &&
              images.isEmpty &&
              links.isEmpty)) {
        continue;
      }

      final author = _cleanText(header.querySelector('strong')?.text ?? '匿名');
      final headerText = _cleanText(header.text);
      final floor =
          _cleanText(header.querySelector('.float-right')?.text ?? '');
      final dateMatch =
          RegExp(r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}').firstMatch(headerText);
      final postedAt = [
        if (dateMatch != null) dateMatch.group(0)!,
        if (floor.isNotEmpty) floor,
      ].join(' ');
      replies.add(
        ThreadReply(
          author: author,
          content: content,
          postedAt: postedAt.isEmpty ? null : postedAt,
          floor: floor.isEmpty ? null : floor,
          quote: quote,
          images: images,
          links: links,
          saleBoxes: saleBoxes,
          saleBoxesFirst: saleBoxesFirst,
        ),
      );
    }
    return replies;
  }

  String? _extractQuote(dom.Element content) {
    final quoteElement = content.querySelector('blockquote') ??
        content.querySelector('.blockquote');
    if (quoteElement == null) return null;
    final quote = _cleanText(quoteElement.text);
    quoteElement.remove();
    return quote.isEmpty ? null : quote;
  }

  List<ThreadImage> _extractImages(dom.Element content) {
    final images = <ThreadImage>[];
    final seen = <String>{};
    for (final image in content.querySelectorAll('img[src]')) {
      final src = image.attributes['src'] ?? '';
      if (src.isEmpty) continue;
      final url = _absoluteUrl(src);
      if (!seen.add(url)) continue;
      final alt = _cleanText(image.attributes['alt'] ?? '');
      images.add(ThreadImage(url: url, alt: alt.isEmpty ? null : alt));
      if (images.length >= 12) break;
    }
    return images;
  }

  List<ThreadLink> _extractLinks(dom.Element content) {
    final links = <ThreadLink>[];
    final seen = <String>{};
    for (final link in content.querySelectorAll('a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty ||
          href == '#' ||
          href.startsWith('javascript:') ||
          href.startsWith('mailto:')) {
        continue;
      }
      final url = _absoluteUrl(href);
      if (!seen.add(url)) continue;
      final label = _cleanText(link.text);
      links.add(ThreadLink(label: label.isEmpty ? url : label, url: url));
      if (links.length >= 20) break;
    }
    return links;
  }

  bool _startsWithSaleBox(dom.Element content) {
    for (final node in content.nodes) {
      if (node is dom.Text && _cleanText(node.text).isEmpty) continue;
      if (node is dom.Element) {
        if (node.localName == 'h6' &&
            node.classes.contains('quote') &&
            node.classes.contains('jumbotron')) {
          return true;
        }
        if (_cleanText(node.text).isEmpty) continue;
      }
      return false;
    }
    return false;
  }

  List<ThreadSaleBox> _extractSaleBoxes(dom.Element content) {
    final saleBoxes = <ThreadSaleBox>[];
    for (final saleElement in content.querySelectorAll('h6.quote.jumbotron')) {
      final input = saleElement.querySelector('input[type="button"]');
      final onclick = input?.attributes['onclick'] ?? '';
      final buyPath = _buyPathFromOnclick(onclick);
      if (buyPath == null) continue;

      final summary = _cleanText(
        saleElement.querySelector('.s3')?.text ?? saleElement.text,
      );
      final warningElement = _saleWarningElement(saleElement);
      final warning = _cleanText(warningElement?.text ?? '');
      final priceMatch = RegExp(r'售价\s*(\d+)\s*SP币').firstMatch(summary);
      final buyersMatch = RegExp(r'已有\s*(\d+)\s*人购买').firstMatch(summary);

      saleBoxes.add(
        ThreadSaleBox(
          summary: summary.isEmpty ? '此帖需要购买后查看' : summary,
          buyPath: buyPath,
          warning: warning.isEmpty ? null : warning,
          price: priceMatch == null ? null : int.tryParse(priceMatch.group(1)!),
          buyers:
              buyersMatch == null ? null : int.tryParse(buyersMatch.group(1)!),
        ),
      );

      saleElement.remove();
      warningElement?.remove();
    }
    return saleBoxes;
  }

  String? _buyPathFromOnclick(String onclick) {
    final match = RegExp("location\\.href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]")
        .firstMatch(onclick);
    return match?.group(1);
  }

  dom.Element? _saleWarningElement(dom.Element saleElement) {
    final parent = saleElement.parent;
    if (parent == null) return null;
    final siblings = parent.children;
    final index = siblings.indexOf(saleElement);
    if (index == -1 || index + 1 >= siblings.length) return null;
    final sibling = siblings[index + 1];
    if (sibling.localName != 'blockquote') return null;
    return sibling.classes.contains('blockquote') ? sibling : null;
  }

  String _extractBodyText(dom.Document document) {
    final candidates = [
      document.querySelector('.body'),
      document.querySelector('.content'),
      document.querySelector('main'),
    ];
    for (final candidate in candidates) {
      final text = _cleanText(candidate?.text ?? '');
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  bool _isThreadHref(String href) {
    final query = Uri.tryParse(href)?.query ?? '';
    return query.startsWith('t') && query.endsWith('.html');
  }

  String _absoluteUrl(String href) {
    final uri = Uri.tryParse(href);
    if (uri != null && uri.hasScheme) return href;
    if (href.startsWith('//')) return 'https:$href';
    if (href.startsWith('/')) return 'https://south-plus.net$href';
    return 'https://south-plus.net/$href';
  }

  String _relativePath(String url) {
    if (!url.startsWith('https://south-plus.net/')) return url;
    return url.substring('https://south-plus.net/'.length);
  }

  String _captchaPath(String src) {
    final path = _relativePath(_absoluteUrl(src));
    final separator = path.endsWith('?')
        ? ''
        : path.contains('?')
            ? '&'
            : '?';
    return '${path}${separator}nowtime=${DateTime.now().millisecondsSinceEpoch}';
  }

  String _slugFromHref(String href) {
    final query = Uri.tryParse(href)?.query ?? href;
    return query.endsWith('.html')
        ? query.substring(0, query.length - '.html'.length)
        : query;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _threadTitleFromBoardLink(dom.Element link, String meta) {
    final text = _cleanText(link.text);
    if (meta.isEmpty) return text;
    return _cleanText(text.replaceFirst(meta, ''));
  }

  String? _authorFromBoardMeta(String meta) {
    if (meta.isEmpty) return null;
    final parts = meta.split(' - 发布于 ');
    return parts.first.trim().isEmpty ? null : parts.first.trim();
  }

  String? _dateFromBoardMeta(String meta) {
    final parts = meta.split(' - 发布于 ');
    return parts.length > 1 && parts.last.trim().isNotEmpty
        ? parts.last.trim()
        : null;
  }

  int? _firstInt(String input) {
    final match = RegExp(r'\d+').firstMatch(input);
    return match == null ? null : int.tryParse(match.group(0)!);
  }
}

class ForumRepositoryException implements Exception {
  const ForumRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ForumLinkData {
  const _ForumLinkData({required this.title, required this.href});

  final String title;
  final String href;
}

class _UserProfileShell {
  const _UserProfileShell({
    required this.name,
    this.tagline,
    this.avatarUrl,
    this.level,
  });

  final String name;
  final String? tagline;
  final String? avatarUrl;
  final String? level;
}
