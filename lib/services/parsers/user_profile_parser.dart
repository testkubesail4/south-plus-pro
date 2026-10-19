import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../../models/user_content_query.dart';
import 'board_thread_page_parser.dart';
import '../forum_url_resolver.dart';
import '../forum_request_exception.dart';

class UserProfileParser {
  UserProfileParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  ForumAccountIdentity? parseAccountIdentity(dom.Document document) {
    final name =
        document.querySelector('#user-login > a[href="u.php"]')?.text.trim();
    if (name == null || name.isEmpty) return null;
    String? uid;
    for (final link
        in document.querySelectorAll('#menu_profile .ul2 a[href]')) {
      final match = RegExp(r'^u\.php\?action-show-uid-([1-9]\d*)\.html$')
          .firstMatch(link.attributes['href']!);
      if (match != null) {
        uid = match.group(1);
        break;
      }
    }
    uid ??= RegExp(r'\bUID:\s*([1-9]\d*)\b')
        .firstMatch(
            document.querySelector('#showface .user-infoWraptwo')?.text ?? '')
        ?.group(1);
    final src = document
        .querySelector('#user_info > a[href="u.php"] > img')
        ?.attributes['src'];
    final avatar = src == null ? null : Uri.tryParse(urls.absoluteUrl(src));
    return ForumAccountIdentity(
      systemName: name,
      uid: uid,
      avatarUrl: avatar != null &&
              (avatar.scheme == 'https' || avatar.scheme == 'http')
          ? avatar.toString()
          : null,
    );
  }

  String parseLoginUsername(dom.Document document) {
    var name = document
            .querySelector('input[name="sendtoname"]')
            ?.attributes['value']
            ?.trim() ??
        '';
    if (name.isEmpty) {
      for (final candidate
          in document.querySelectorAll('#main .t .f_one center > b')) {
        if (candidate.parent?.text.contains('不接受邮件') ?? false) {
          name = candidate.text.trim();
          break;
        }
      }
    }
    if (name.isEmpty ||
        name.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const ForumRequestException(
        ForumRequestKind.server,
        '无法取得实际登录名称',
      );
    }
    return name;
  }

  UserProfile parseOverview({
    required String uid,
    required String profileUrl,
    required dom.Document profileDocument,
  }) {
    final shell = _parseShell(uid, profileDocument);
    return UserProfile(
      uid: uid,
      name: shell.name,
      url: profileUrl,
      nativeHashName: shell.nativeHashName,
      tagline: shell.tagline,
      avatarUrl: shell.avatarUrl,
      level: shell.level,
      isOnline: shell.isOnline,
      statusText: shell.statusText,
      messageUrl: shell.messageUrl,
      info: _parseFields(profileDocument.querySelector('#u-profile')),
      stats: _parseFields(profileDocument.querySelector('#u-profile-s')),
      signature: _profileSignature(profileDocument),
    );
  }

  UserProfile appendDetails({
    required UserProfile overview,
    required dom.Document homeDocument,
    required dom.Document topicsDocument,
    required dom.Document postsDocument,
    required dom.Document favoritesDocument,
  }) {
    final errors = <UserProfileTab, Object>{};
    UserContentPage read(dom.Document document, UserProfileTab tab) {
      try {
        return parseContentPage(document, uid: overview.uid, tab: tab, page: 1);
      } on ForumRequestException catch (error) {
        if (error.kind != ForumRequestKind.invalidInput) rethrow;
        errors[tab] = error;
        return const UserContentPage(
            items: [], totalPages: 1, paginationKnown: false);
      }
    }
    final topics = read(topicsDocument, UserProfileTab.topics);
    final posts = read(postsDocument, UserProfileTab.posts);
    final favorites = read(favoritesDocument, UserProfileTab.favorites);
    return overview.copyWith(
      contentErrors: Map.unmodifiable(errors),
      contentPagination: Map.unmodifiable({
        if (topics.paginationKnown)
          UserProfileTab.topics:
              ThreadPagination(currentPage: 1, totalPages: topics.totalPages),
        if (posts.paginationKnown)
          UserProfileTab.posts:
              ThreadPagination(currentPage: 1, totalPages: posts.totalPages),
        if (favorites.paginationKnown)
          UserProfileTab.favorites: ThreadPagination(
              currentPage: 1, totalPages: favorites.totalPages),
      }),
      homeActivities: _parseHomeActivities(homeDocument),
      homeReplies: _parseHomeReplies(homeDocument),
      topics: topics.items,
      posts: posts.items,
      favorites: favorites.items,
    );
  }

  String? uidFromDocument(dom.Document document) {
    for (final link in document.querySelectorAll('a[href]')) {
      final uid = urls.uidFromUrl(link.attributes['href'] ?? '');
      if (uid != null) return uid;
    }
    final textUid = RegExp(r'UID\s+(\d+)')
        .firstMatch(_cleanText(document.body?.text ?? ''));
    return textUid?.group(1);
  }

  _UserProfileShell _parseShell(String uid, dom.Document document) {
    final top = document.querySelector('#u-top');
    final name = _cleanText(top?.querySelector('.u-h1')?.text ?? '');
    final avatar = document.querySelector('#u-portrait img')?.attributes['src'];
    final levelRow = document
        .querySelectorAll('#u-sidebar tr')
        .where((row) => _cleanText(row.text).contains('等级'))
        .firstOrNull;
    final tagline = _userTagline(top);
    final messageHref = document
            .querySelector('#u-sidebar a[href*="message.php?action-write"]')
            ?.attributes['href'] ??
        '';
    final statusText = _onlineStatusText(document);
    return _UserProfileShell(
      name: name.isEmpty ? '用户 $uid' : name,
      nativeHashName: name.isEmpty ? null : name,
      tagline: tagline,
      avatarUrl:
          avatar == null || avatar.isEmpty ? null : urls.absoluteUrl(avatar),
      level: _cleanText(levelRow?.children.lastOrNull?.text ?? ''),
      isOnline: statusText == null ? null : statusText == '在线',
      statusText: statusText,
      messageUrl: messageHref.isEmpty ? null : urls.absoluteUrl(messageHref),
    );
  }

  String? _userTagline(dom.Element? top) {
    if (top == null) return null;
    final tagline = _cleanText(top.querySelector('#honor')?.text ?? '');
    return tagline.isEmpty ? null : tagline;
  }

  String? _profileSignature(dom.Document document) {
    final signaturePanel = document
        .querySelectorAll('.u-h5, h5')
        .where((heading) => _cleanText(heading.text).contains('帖间签名'))
        .firstOrNull
        ?.nextElementSibling;
    final signature = _cleanText(signaturePanel?.text ?? '');
    return signature.isEmpty ? null : signature;
  }

  String? _onlineStatusText(dom.Document document) {
    final statusImage = document.querySelector(
      '#u-sidebar img[title="在线"], #u-sidebar img[title="离线"]',
    );
    final imageStatus = _cleanText(statusImage?.attributes['title'] ?? '');
    if (imageStatus == '在线' || imageStatus == '离线') return imageStatus;

    final friendAction = document.querySelector('#u-sidebar a[title]');
    final actionStatus = _cleanText(friendAction?.attributes['title'] ?? '');
    if (actionStatus == '在线' || actionStatus == '离线') return actionStatus;
    return null;
  }

  List<UserProfileField> _parseFields(dom.Element? section) {
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

  List<UserActivityItem> _parseHomeActivities(dom.Document document) {
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
          url: urls.absoluteUrl(href),
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

  List<UserActivityItem> _parseHomeReplies(dom.Document document) {
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
          url: urls.absoluteUrl(href),
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

  UserContentPage parseContentPage(
    dom.Document document, {
    required String uid,
    required UserProfileTab tab,
    required int page,
    UserContentArticleType articleType = UserContentArticleType.all,
  }) {
    if (document.querySelector('.u-table') == null) {
      throw const ForumRequestException(
          ForumRequestKind.invalidInput, '无法识别用户文章列表');
    }
    final pagination = _contentPagination(document,
        uid: uid, tab: tab, page: page, articleType: articleType);
    final items = tab == UserProfileTab.favorites
        ? _parseFavorites(document, sourcePage: pagination.current)
        : _parseThreadRows(document,
            includeMetrics: tab == UserProfileTab.topics,
            includeAuthor: tab == UserProfileTab.posts,
            sourcePage: pagination.current);
    return UserContentPage(
      items: items,
      totalPages: pagination.total,
      paginationKnown: pagination.known &&
          (items.isNotEmpty || pagination.current == pagination.total),
    );
  }

  ({int current, int total, bool known}) _contentPagination(
      dom.Document document,
      {required String uid,
      required UserProfileTab tab,
      int page = 1,
      UserContentArticleType articleType = UserContentArticleType.all}) {
    if (!{UserProfileTab.topics, UserProfileTab.posts, UserProfileTab.favorites}
        .contains(tab)) throw ArgumentError('Unsupported content tab');
    var totalFromLinks = page;
    var hasLast = false;
    var hasPagerLinks = false;
    var compatibleRoute = false;
    var conflictingType = false;
    var matchingType = false;
    final expectedType = tab == UserProfileTab.topics ? articleType.name : null;
    for (final link in document.querySelectorAll('.pages a[href]')) {
      final href = link.attributes['href'] ?? '';
      final target = int.tryParse(
          RegExp(r'(?:[-?&])page[-=]([1-9]\d*)').firstMatch(href)?.group(1) ??
              '');
      if (target == null) continue;
      hasPagerLinks = true;
      final route = urls.forumLinkTarget(href);
      if (route is! ForumUserLinkTarget ||
          route.tab != tab ||
          urls.uidFromUrl(route.userUrl) != uid) continue;
      final uri = Uri.parse(route.userUrl);
      final type = uri.query.contains('=')
          ? uri.queryParameters['type']
          : RegExp(r'(?:^|-)type-(.*?)(?:-|\.html$)')
              .firstMatch(uri.query)
              ?.group(1);
      final claimed = type == null
          ? null
          : uri.query.contains('=')
              ? type
              : Uri.decodeComponent(type);
      if (claimed != null && claimed != expectedType) {
        conflictingType = true;
        continue;
      }
      compatibleRoute = true;
      if (claimed == expectedType ||
          (claimed == null && expectedType == 'all')) {
        matchingType = true;
      }
      if (target > totalFromLinks) totalFromLinks = target;
      if ({'»', '>>', 'last', '末页', '尾页'}
          .contains(link.text.trim().toLowerCase())) {
        hasLast = true;
      }
    }
    final pager = document.querySelector('.pages');
    final counter = RegExp(r'Pages:\s*(\d+)\s*/\s*(\d+)', caseSensitive: false)
        .firstMatch(pager?.text ?? '');
    final current = int.tryParse(counter?.group(1) ?? '') ?? page;
    final declared = int.tryParse(counter?.group(2) ?? '');
    final total = declared ?? totalFromLinks;
    final known = current == page &&
        (!hasPagerLinks || compatibleRoute) &&
        (!conflictingType || matchingType) &&
        current >= 1 &&
        total >= current &&
        (declared == null || totalFromLinks <= total) &&
        (counter != null || hasLast || (pager == null && page == 1));
    return (
      current: current < 1 ? page : current,
      total: total < page ? page : total,
      known: known
    );
  }

  List<UserContentClassification> parseContentClassifications(
      dom.Document document, String boardId) {
    final category = ForumCategory(name: '', slug: 'f$boardId');
    return [
      for (final filter
          in BoardThreadPageParser(urls: urls).parseFilters(document, category))
        if (filter.kind == ForumBoardFilterKind.topicType)
          UserContentClassification(
            id: RegExp(r'(?:[-?&])type[-=]([1-9]\d*)')
                .firstMatch(filter.url)!
                .group(1)!,
            label: filter.label,
          ),
    ];
  }

  Map<String, UserContentThreadMetadata> parseContentBoardMetadata(
    dom.Document document, {
    required String boardId,
    required List<UserContentClassification> classifications,
  }) {
    final result = <String, UserContentThreadMetadata>{};
    for (final row in document.querySelectorAll('#ajaxtable tr.tr3')) {
      if (row.querySelector(
              'img[src*="headtopic_2"], img[src*="headtopic_3"]') !=
          null) {
        continue;
      }
      final threadLink =
          row.querySelector('a[id^="a_ajax_"][href], h3 a[href*="read.php"]');
      final tid = urls.tidFromUrl(threadLink?.attributes['href'] ?? '');
      if (tid == null) continue;
      String? classificationId;
      var unknownClassification = false;
      for (final link in row.querySelectorAll('a[href*="thread.php"]')) {
        final href = link.attributes['href'] ?? '';
        if (urls.fidFromUrl(href) != boardId) continue;
        final filter = urls.boardFilterFromUrl(
            ForumCategory(name: '', slug: 'f$boardId'),
            label: '',
            url: href);
        if (filter?.kind != ForumBoardFilterKind.topicType) continue;
        final id =
            RegExp(r'(?:[-?&])type[-=]([1-9]\d*)').firstMatch(href)?.group(1);
        if (classifications.any((item) => item.id == id)) {
          classificationId = id;
        } else {
          unknownClassification = true;
        }
      }
      result[tid] = UserContentThreadMetadata(
        boardId: boardId,
        classificationId: classificationId,
        classificationKnown:
            classifications.isNotEmpty && !unknownClassification,
        digest: row.querySelector('img[src*="/file/digest_"]') != null,
      );
    }
    return result;
  }

  UserContentThreadMetadata parseContentThreadMetadata(
    dom.Document document, {
    required List<UserContentClassification> classifications,
    String? profileTitle,
    String? threadId,
  }) {
    final subject = document.querySelector('#subject_tpc');
    if (subject == null) return const UserContentThreadMetadata();
    String? boardId;
    String? boardName;
    for (final link in document.querySelectorAll(
        '#breadcrumbs a[href], #breadCrumb a[href], .breadcrumb a[href], .crumb a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (urls.forumLinkTarget(href) is ForumBoardLinkTarget) {
        boardId = urls.fidFromUrl(href) ?? boardId;
        final name = _cleanText(link.text);
        boardName = name.isEmpty ? null : name;
      }
    }
    final title = _cleanText(subject.text);
    final original = _cleanText(profileTitle ?? '');
    final classification = classifications.where((item) {
      final prefix = '[${item.label}]';
      return original.isNotEmpty &&
          !original.startsWith('[') &&
          !original.contains('…') &&
          !original.contains('...') &&
          title.startsWith(prefix) &&
          _cleanText(title.substring(prefix.length)) == original;
    }).firstOrNull;
    final openingPost = document.querySelector('table.js-post');
    final authorCell = openingPost?.querySelector('th.r_two');
    final authorLink =
        authorCell?.querySelector('a[href*="uid"] strong')?.parent ??
            authorCell?.querySelector('a[href*="action-show-uid"]');
    final authorUid = openingPost?.querySelector('#read_tpc') == null
        ? null
        : urls.uidFromUrl(authorLink?.attributes['href'] ?? '');
    final poll = document.querySelectorAll('form[action]').any((form) {
      final action = form.attributes['action'] ?? '';
      return urls.isForumUrl(action) &&
          Uri.parse(urls.absoluteUrl(action)).path == '/job.php' &&
          RegExp(r'(?:[?&]|-)action[-=]vote(?:[&-]|$)').hasMatch(action) &&
          form.querySelector('input[name="voteid[]"]') != null &&
          (threadId == null ||
              form.querySelector('input[name="tid"]')?.attributes['value'] ==
                  threadId);
    });
    return UserContentThreadMetadata(
      title: title,
      boardName: boardName,
      authorUid: authorUid,
      boardId: boardId,
      classificationId: classification?.id,
      classificationKnown: boardId != null && classification != null,
      poll: poll ? true : null,
    );
  }

  List<UserListItem> _parseThreadRows(
    dom.Document document, {
    bool includeMetrics = false,
    bool includeAuthor = false,
    int sourcePage = 1,
  }) {
    final table = document.querySelector('#u-contentmain .u-table') ??
        document.querySelector('.u-table');
    if (table == null) return const [];
    final items = <UserListItem>[];
    for (final row in table.querySelectorAll('tr')) {
      final threadLink = row.querySelector(
        'a[href*="read.php"], a[href*="job.php"]',
      );
      if (threadLink == null) continue;
      final href = threadLink.attributes['href'] ?? '';
      final title = _cleanText(threadLink.text);
      if (href.isEmpty || title.isEmpty || urls.tidFromUrl(href) == null)
        continue;

      final boardLink = row.querySelector('a[href*="thread.php"]');
      final boardHref = boardLink?.attributes['href'] ?? '';
      final section = _cleanText(boardLink?.text ?? '');
      final boardId = urls.forumLinkTarget(boardHref) is ForumBoardLinkTarget
          ? urls.fidFromUrl(boardHref)
          : null;
      final threadId = urls.tidFromUrl(href);
      final postId = urls.isForumUrl(href)
          ? RegExp(r'(?:[-?&])pid[-=]([1-9]\d*)').firstMatch(href)?.group(1)
          : null;
      final metadataRow = row.clone(true);
      metadataRow
          .querySelector('a[href*="read.php"], a[href*="job.php"]')
          ?.remove();
      final dateText = metadataRow.querySelector('th span.gray.f9')?.text ?? '';
      final metricsText = _cleanText(metadataRow.querySelectorAll('td')
          .map((cell) => cell.text).join(' '));
      final date =
          RegExp(r'\[(\d{4}-\d{2}-\d{2})\]').firstMatch(dateText)?.group(1);
      final authorLink = row.querySelector('a[href*="uid"]');
      final author = includeAuthor ? _cleanText(authorLink?.text ?? '') : null;
      final authorHref = authorLink?.attributes['href'] ?? '';
      items.add(
        UserListItem(
          title: title,
          titleTruncated: title.endsWith('..'),
          sourcePage: sourcePage,
          url: urls.absoluteUrl(href),
          section: section.isEmpty ? null : section,
          boardId: boardId,
          boardUrl: boardId == null ? null : urls.absoluteUrl(boardHref),
          threadId: threadId,
          postId: postId,
          date: date,
          author: author == null || author.isEmpty ? null : author,
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
          replies: includeMetrics ? _valueAfterLabel(metricsText, '回复') : null,
          views: includeMetrics ? _valueAfterLabel(metricsText, '浏览') : null,
        ),
      );
    }
    return items;
  }

  List<UserListItem> _parseFavorites(dom.Document document,
      {int sourcePage = 1}) {
    final table = document.querySelector('#u-contentmain .u-table') ??
        document.querySelector('form[action*="action=favor"] .u-table') ??
        document.querySelector('.u-table');
    if (table == null) return const [];
    final items = <UserListItem>[];
    for (final row in table.querySelectorAll('tr')) {
      final link = row.querySelector('a[href*="read.php"]');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      final title = _cleanText(link.text);
      final tid = urls.tidFromUrl(href);
      if (href.isEmpty || title.isEmpty || tid == null) continue;
      final authorLinks = row.querySelectorAll('a[href*="uid"]');
      final authorLink = authorLinks.isEmpty ? null : authorLinks.first;
      final authorHref = authorLink?.attributes['href'] ?? '';
      items.add(
        UserListItem(
          title: title,
          titleTruncated: title.endsWith('..'),
          sourcePage: sourcePage,
          threadId: tid,
          url: urls.absoluteUrl(href),
          author: authorLink == null ? null : _cleanText(authorLink.text),
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
        ),
      );
    }
    return items;
  }

  int? _valueAfterLabel(String text, String label) {
    final match = RegExp('$label:(\\d+)').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _UserProfileShell {
  const _UserProfileShell({
    required this.name,
    this.nativeHashName,
    this.tagline,
    this.avatarUrl,
    this.level,
    this.isOnline,
    this.statusText,
    this.messageUrl,
  });

  final String name;
  final String? nativeHashName;
  final String? tagline;
  final String? avatarUrl;
  final String? level;
  final bool? isOnline;
  final String? statusText;
  final String? messageUrl;
}
