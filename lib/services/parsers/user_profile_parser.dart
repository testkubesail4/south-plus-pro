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
    return overview.copyWith(
      homeActivities: _parseHomeActivities(homeDocument),
      homeReplies: _parseHomeReplies(homeDocument),
      topics: _parseThreadRows(topicsDocument, includeMetrics: true),
      posts: _parseThreadRows(postsDocument, includeAuthor: true),
      favorites: _parseFavorites(favoritesDocument),
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
      throw const ForumRequestException(ForumRequestKind.server, '无法识别用户文章列表');
    }
    var totalPages = page;
    for (final link in document.querySelectorAll('.pages a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (!urls.isForumUrl(href) || urls.uidFromUrl(href) != uid) continue;
      final uri = Uri.parse(urls.absoluteUrl(href));
      if (uri.path != '/u.php') continue;
      final action = tab == UserProfileTab.topics ? 'topic' : 'post';
      if (!RegExp('(?:[?&]|^)action[-=]$action(?:[-&]|\$)').hasMatch(href))
        continue;
      final target = int.tryParse(
          RegExp(r'(?:[-?&])page[-=]([1-9]\d*)').firstMatch(href)?.group(1) ??
              '');
      if (target != null && target > totalPages) totalPages = target;
    }
    final count = RegExp(r'Pages:\s*\d+\s*/\s*(\d+)', caseSensitive: false)
        .firstMatch(document.querySelector('.pages')?.text ?? '');
    final total = int.tryParse(count?.group(1) ?? '');
    if (total != null && total > totalPages) totalPages = total;
    return UserContentPage(
      items: _parseThreadRows(document,
          includeMetrics: tab == UserProfileTab.topics,
          includeAuthor: tab == UserProfileTab.posts),
      totalPages: totalPages,
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
    for (final link in document.querySelectorAll(
        '#breadcrumbs a[href], #breadCrumb a[href], .breadcrumb a[href], .crumb a[href]')) {
      final href = link.attributes['href'] ?? '';
      if (urls.forumLinkTarget(href) is ForumBoardLinkTarget) {
        boardId = urls.fidFromUrl(href) ?? boardId;
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
  }) {
    final table = document.querySelector('.u-table');
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
      final text = _cleanText(row.text);
      final date =
          RegExp(r'\[(\d{4}-\d{2}-\d{2})\]').firstMatch(text)?.group(1);
      final authorLink = row.querySelector('a[href*="uid"]');
      final author = includeAuthor ? _cleanText(authorLink?.text ?? '') : null;
      final authorHref = authorLink?.attributes['href'] ?? '';
      items.add(
        UserListItem(
          title: title,
          url: urls.absoluteUrl(href),
          section: section.isEmpty ? null : section,
          boardId: boardId,
          boardUrl: boardId == null ? null : urls.absoluteUrl(boardHref),
          threadId: threadId,
          postId: postId,
          date: date,
          author: author == null || author.isEmpty ? null : author,
          authorUrl: authorHref.isEmpty ? null : urls.absoluteUrl(authorHref),
          replies: includeMetrics ? _valueAfterLabel(text, '回复') : null,
          views: includeMetrics ? _valueAfterLabel(text, '浏览') : null,
        ),
      );
    }
    return items;
  }

  List<UserListItem> _parseFavorites(dom.Document document) {
    final table =
        document.querySelector('form[action*="action=favor"] .u-table') ??
            document.querySelector('.u-table');
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
