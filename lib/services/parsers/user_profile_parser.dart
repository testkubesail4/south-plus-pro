import 'package:html/dom.dart' as dom;

import '../../models/forum_models.dart';
import '../forum_url_resolver.dart';

class UserProfileParser {
  UserProfileParser({ForumUrlResolver? urls})
      : urls = urls ?? ForumUrlResolver();

  final ForumUrlResolver urls;

  UserProfile parse({
    required String uid,
    required String profileUrl,
    required dom.Document profileDocument,
    required dom.Document homeDocument,
    required dom.Document topicsDocument,
    required dom.Document postsDocument,
    required dom.Document favoritesDocument,
  }) {
    final shell = _parseShell(uid, profileDocument);
    return UserProfile(
      uid: uid,
      name: shell.name,
      url: profileUrl,
      tagline: shell.tagline,
      avatarUrl: shell.avatarUrl,
      level: shell.level,
      info: _parseFields(profileDocument.querySelector('#u-profile')),
      stats: _parseFields(profileDocument.querySelector('#u-profile-s')),
      signature: _cleanText(
        profileDocument.querySelector('.u-profile .u-table')?.text ?? '',
      ),
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
    return _UserProfileShell(
      name: name.isEmpty ? '用户 $uid' : name,
      tagline: tagline,
      avatarUrl:
          avatar == null || avatar.isEmpty ? null : urls.absoluteUrl(avatar),
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
          url: urls.absoluteUrl(href),
          section: section.isEmpty ? null : section,
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
    this.tagline,
    this.avatarUrl,
    this.level,
  });

  final String name;
  final String? tagline;
  final String? avatarUrl;
  final String? level;
}
