import 'dart:convert';

import '../models/forum_models.dart';
import '../models/forum_pm_models.dart';
import 'forum_network_config.dart';
import 'parsers/forum_pm_parser.dart';

class ForumUrlResolver {
  ForumUrlResolver({
    Uri? baseUri,
  }) : baseUri = baseUri ?? ForumNetworkConfig.defaultSite.baseUri;

  static final RegExp _simpleBoardTokenPattern =
      RegExp(r'(?:^|[?&])([fp]\d+)(?:_\d+)?(?:\.html)?(?:$|[&#])');
  static final RegExp _slugSimpleBoardTokenPattern =
      RegExp(r'^([fp]\d+)(?:_\d+)?$');
  static final RegExp _fidPattern = RegExp(r'fid[-=](\d+)');

  final Uri baseUri;

  String get _origin => baseUri.origin;

  static bool isSafeExternalUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(value)) return false;
    if (uri.scheme == 'mailto') {
      return !uri.hasQuery &&
          !uri.hasFragment &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(uri.path) &&
          !RegExp(r'%0[ad]', caseSensitive: false).hasMatch(value);
    }
    if (uri.scheme == 'magnet') return uri.query.isNotEmpty;
    if (uri.scheme == 'ed2k') return value.startsWith('ed2k://|');
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        !RegExp(r'[\s\\]').hasMatch(value);
  }

  bool isForumHost(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return normalized ==
            baseUri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ||
        ForumNetworkConfig.sites.any((site) =>
            normalized == site.host || normalized.endsWith('.${site.host}'));
  }

  bool isForumUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.userInfo.isNotEmpty) return false;
    if (!uri.hasScheme && !uri.hasAuthority) return !value.contains('\\');
    final resolved = baseUri.resolveUri(uri);
    return (resolved.scheme == 'http' || resolved.scheme == 'https') &&
        isForumHost(resolved.host) &&
        (resolved.origin == baseUri.origin ||
            resolved.port == (resolved.scheme == 'https' ? 443 : 80));
  }

  ForumLinkTarget forumLinkTarget(String value) {
    final raw = value.trim();
    final parsed = Uri.tryParse(raw);
    if (raw.isEmpty ||
        parsed == null ||
        parsed.userInfo.isNotEmpty ||
        RegExp(r'[\s\\]').hasMatch(raw)) {
      return const ForumBlockedLinkTarget();
    }
    if (parsed.hasScheme &&
        parsed.scheme != 'http' &&
        parsed.scheme != 'https') {
      return isSafeExternalUrl(raw)
          ? ForumExternalLinkTarget(raw)
          : const ForumBlockedLinkTarget();
    }
    if (!isForumUrl(raw)) {
      final external = parsed.hasAuthority && !parsed.hasScheme
          ? '${baseUri.scheme}:$raw'
          : raw;
      return isSafeExternalUrl(external)
          ? ForumExternalLinkTarget(external)
          : const ForumBlockedLinkTarget();
    }
    final normalized = absoluteUrl(raw);
    final uri = Uri.parse(normalized);
    final legacyTask = uri.path == '/plugin.php' && !uri.hasFragment
        ? _legacyTaskStatus(uri.query)
        : null;
    if (legacyTask != null) {
      return ForumAppPageLinkTarget(ForumAppPage.forumTasks, normalized,
          taskStatus: legacyTask);
    }
    final fields = _queryFields(uri, rawQuery: _rawQuery(normalized));
    if (fields == null) return const ForumBlockedLinkTarget();
    if ({
      'del',
      'delete',
      'dellog',
      'clear',
      'clearlog',
      'buytopic',
      'buy',
      'send',
      'logout',
      'quit',
      'unread'
    }.contains(fields['action']?.toLowerCase())) {
      return const ForumBlockedLinkTarget();
    }
    if ({'/u.php', '/profile.php', '/message.php', '/plugin.php'}
            .contains(uri.path) &&
        fields.keys
            .any({'job', 'step', 'verify', 'delids', 'selid'}.contains)) {
      return const ForumBlockedLinkTarget();
    }
    final appPage = _appPageTarget(uri, normalized, fields);
    if (appPage != null) return appPage;
    final tid = tidFromUrl(normalized);
    if (tid != null) {
      var target = absoluteUrl(threadDetailPath(normalized));
      if (uri.path == '/job.php') {
        final pid = fields['pid'];
        if (pid == null || !RegExp(r'^[1-9]\d*$').hasMatch(pid)) {
          return ForumPageLinkTarget(normalized);
        }
        if (!uri.hasFragment) {
          target = _preserveRawQuery(
              Uri.parse(target).replace(fragment: pid).toString(), target);
        }
      }
      return ForumThreadLinkTarget(target);
    }
    if (uri.path == '/u.php') {
      final action = fields['action'];
      if (action == 'favor' && fields.containsKey('type')) {
        return ForumPageLinkTarget(normalized);
      }
      final tab = switch (action) {
        null || 'home' => UserProfileTab.home,
        'show' => UserProfileTab.profile,
        'topic' => UserProfileTab.topics,
        'post' => UserProfileTab.posts,
        'favor' => UserProfileTab.favorites,
        _ => null,
      };
      if (tab != null) {
        final uid = uidFromUrl(normalized);
        if (uid != null) return ForumUserLinkTarget(normalized, tab: tab);
        if (!uri.hasFragment &&
            (uri.query.isEmpty || fields.containsKey('action')) &&
            fields.keys.every({'action'}.contains)) {
          return ForumUserLinkTarget('$_origin/u.php', tab: tab, isSelf: true);
        }
      }
    }
    final fid = fidFromUrl(normalized);
    if (fid != null) {
      return ForumBoardLinkTarget(ForumCategory(
        name: '',
        slug: 'f$fid',
        url: normalized,
      ));
    }
    return ForumPageLinkTarget(normalized);
  }

  ForumLinkTarget? _appPageTarget(
      Uri uri, String normalized, Map<String, String> fields) {
    if (uri.hasFragment) return null;
    if (uri.query.isEmpty) {
      if ({'', '/', '/index.php', '/simple/index.php'}.contains(uri.path)) {
        return ForumAppPageLinkTarget(ForumAppPage.home, normalized);
      }
      if (uri.path == '/profile.php') {
        return ForumAppPageLinkTarget(ForumAppPage.account, normalized);
      }
    }
    if (uri.path == '/u.php' && fields['action'] == 'friend') {
      final pageNumber = int.tryParse(fields['page'] ?? '1');
      if (pageNumber == null || pageNumber < 1)
        return const ForumBlockedLinkTarget();
      if (!fields.keys.every({'action', 'uid', 'o', 'fuid', 'page'}.contains) ||
          !_optionalPositive(fields, 'uid') ||
          !_optionalPositive(fields, 'fuid') ||
          !_optionalPositive(fields, 'page') ||
          (fields.containsKey('o') && fields['o'] != 'check') ||
          (fields.containsKey('fuid') && fields['o'] != 'check')) return null;
      return ForumAppPageLinkTarget(
          fields['o'] == 'check'
              ? ForumAppPage.friendRequests
              : ForumAppPage.friends,
          normalized,
          ownerUid: fields['uid'],
          pageNumber: pageNumber);
    }
    if (uri.path == '/profile.php') {
      if (fields['action'] == 'modify' && fields.length == 1) {
        return ForumAppPageLinkTarget(ForumAppPage.profileEdit, normalized);
      }
      if (fields['action'] == 'bbsset' &&
          fields.keys.every({'action', 'info_type'}.contains) &&
          (!fields.containsKey('info_type') ||
              {'msg', 'friend', 'fancy'}.contains(fields['info_type']))) {
        return ForumAppPageLinkTarget(
            ForumAppPage.forumPreferences, normalized);
      }
    }
    if (uri.path == '/plugin.php' && fields['H_name'] == 'tasks') {
      if (fields.containsKey('action') ||
          {'job', 'ajax', 'claim'}.contains(fields['actions'])) {
        return const ForumBlockedLinkTarget();
      }
      if (!fields.keys.every({'H_name', 'actions'}.contains)) return null;
      final status = _taskStatus(fields['actions']);
      if (status != null) {
        return ForumAppPageLinkTarget(ForumAppPage.forumTasks, normalized,
            taskStatus: status);
      }
    }
    if (uri.path == '/message.php') {
      final route = ForumPmParser(baseUri: baseUri).route(normalized, {
        'receivebox',
        'sendbox',
        'scout',
        'write',
        'read',
        'readpub',
        'readsnd',
        'readscout',
        'chatlog',
      });
      if (route == null) return null;
      final page = switch (route.action) {
        'receivebox' => ForumAppPage.pmInbox,
        'sendbox' => ForumAppPage.pmSendbox,
        'scout' => ForumAppPage.pmScout,
        'write' => ForumAppPage.pmCompose,
        'chatlog' => ForumAppPage.pmChatlog,
        _ => ForumAppPage.pmDetail,
      };
      ForumPmSummary? message;
      if (page == ForumAppPage.pmDetail) {
        final type = switch (route.action) {
          'readpub' => ForumPmType.broadcast,
          'readsnd' => ForumPmType.sent,
          'readscout' => ForumPmType.tracked,
          _ => ForumPmType.personal,
        };
        final box = switch (type) {
          ForumPmType.sent => ForumPmBox.sendbox,
          ForumPmType.tracked => ForumPmBox.scout,
          _ => ForumPmBox.inbox,
        };
        message = ForumPmSummary(
            box: box,
            type: type,
            id: route.fields['mid']!,
            peer: '',
            title: '',
            time: '',
            detailPath: route.path);
      }
      return ForumAppPageLinkTarget(page, normalized, pmMessage: message);
    }
    return null;
  }

  bool _optionalPositive(Map<String, String> fields, String key) =>
      !fields.containsKey(key) || RegExp(r'^[1-9]\d*$').hasMatch(fields[key]!);

  ForumTaskStatus? _taskStatus(String? action) => switch (action) {
        null => ForumTaskStatus.available,
        'newtasks' => ForumTaskStatus.inProgress,
        'endtasks' => ForumTaskStatus.completed,
        'errotasks' => ForumTaskStatus.failed,
        _ => null,
      };

  ForumTaskStatus? _legacyTaskStatus(String query) {
    final match = RegExp(
            r'^H_name-tasks(?:-actions-(newtasks|endtasks|errotasks)\.html)?\.html$')
        .firstMatch(query);
    return match == null ? null : _taskStatus(match.group(1));
  }

  ForumSearchLinkPrefill? searchLinkPrefill(String raw) {
    if (raw.length > 8192 || forumLinkTarget(raw) is! ForumPageLinkTarget)
      return null;
    final uri = Uri.tryParse(absoluteUrl(raw));
    if (uri == null || uri.path != '/search.php') return null;
    final query = _queryFields(uri, rawQuery: _rawQuery(raw));
    if (query == null) return null;
    final fields = Map<String, String>.of(query);
    final hash = raw.indexOf('#');
    final fragment = hash < 0 ? '' : raw.substring(hash + 1);
    if (fragment.startsWith('prefill')) {
      if (!fragment.startsWith('prefill(') || !fragment.endsWith(')'))
        return null;
      try {
        final pairs = jsonDecode(
            '[${Uri.decodeComponent(fragment.substring(8, fragment.length - 1))}]');
        if (pairs is! List || pairs.length.isOdd) return null;
        final seen = <String>{};
        for (var index = 0; index < pairs.length; index += 2) {
          final key = pairs[index];
          final value = pairs[index + 1];
          if (key is! String ||
              !seen.add(key) ||
              (value is! String && !(key == 'fid' && value is int)))
            return null;
          if ({'keyword', 'pwuser', 'fid'}.contains(key)) {
            fields[key == 'fid' ? 'f_fid' : key] = value.toString();
          }
        }
      } on FormatException {
        return null;
      }
    }
    final board = fields['f_fid'];
    if (board != null &&
        board != 'all' &&
        !RegExp(r'^[1-9]\d*$').hasMatch(board)) return null;
    return ForumSearchLinkPrefill(
        keyword: fields['keyword'], username: fields['pwuser'], boardId: board);
  }

  String? fidFromUrl(String value) {
    if (!isForumUrl(value)) return null;
    final uri = baseUri.resolve(value);
    if (!{'/thread.php', '/thread_new.php', '/simple/index.php'}
        .contains(uri.path)) {
      return null;
    }
    final fid = _queryField(uri, 'fid', rawQuery: _rawQuery(value));
    return fid != null && RegExp(r'^[1-9]\d*$').hasMatch(fid)
        ? fid
        : _simpleBoardTokenFromUri(uri);
  }

  String? _simpleBoardTokenFromUri(Uri uri) =>
      RegExp(r'^[fp]([1-9]\d*)(?:_\d+)?\.html$')
          .firstMatch(uri.query)
          ?.group(1);

  String? _queryField(Uri uri, String key, {String? rawQuery}) =>
      _queryFields(uri, rawQuery: rawQuery)?[key];

  Map<String, String>? _queryFields(Uri uri, {String? rawQuery}) {
    final query = rawQuery ?? uri.query;
    if (query.isEmpty ||
        RegExp(r'^[tfp][1-9]\d*(?:_\d+)?\.html$').hasMatch(query)) {
      return const {};
    }
    final fields = <String, String>{};
    try {
      if (query.contains('=')) {
        for (final entry in uri.queryParametersAll.entries) {
          if (entry.value.length != 1 || !RegExp(r'^\w+$').hasMatch(entry.key))
            return null;
          fields[entry.key] = entry.value.single;
        }
      } else {
        final parts = query.replaceFirst(RegExp(r'\.html$'), '').split('-');
        if (parts.length.isOdd) return null;
        for (var index = 0; index + 1 < parts.length; index += 2) {
          final key = Uri.decodeComponent(parts[index]);
          if (!RegExp(r'^\w+$').hasMatch(key) || fields.containsKey(key))
            return null;
          fields[key] = Uri.decodeComponent(parts[index + 1]);
        }
      }
    } on FormatException {
      return null;
    }
    return fields;
  }

  String? _rawQuery(String value) {
    final start = value.indexOf('?');
    final fragment = value.indexOf('#');
    if (start < 0 || (fragment >= 0 && fragment < start)) return null;
    return value.substring(start + 1, fragment < 0 ? value.length : fragment);
  }

  String _preserveRawQuery(String normalized, String original) {
    final query = _rawQuery(original);
    final originalFragment = original.indexOf('#');
    if (query == null && originalFragment < 0) return normalized;
    final fragment = normalized.indexOf('#');
    var result = fragment < 0 ? normalized : normalized.substring(0, fragment);
    if (query != null) {
      final start = result.indexOf('?');
      result = '${start < 0 ? result : result.substring(0, start)}?$query';
    }
    return result +
        (originalFragment >= 0
            ? original.substring(originalFragment)
            : fragment < 0
                ? ''
                : normalized.substring(fragment));
  }

  String absoluteUrl(String href) {
    href = href.trim();
    final uri = Uri.tryParse(href);
    if (uri == null) return href;
    final resolved = baseUri.resolveUri(uri);
    if (isForumUrl(href)) {
      return _preserveRawQuery(
          resolved
              .replace(
                scheme: baseUri.scheme,
                host: baseUri.host,
                port: baseUri.port,
              )
              .toString(),
          href);
    }
    if (uri.hasScheme) return href.trim();
    if (uri.hasAuthority) return '${baseUri.scheme}:${href.trim()}';
    return _preserveRawQuery(resolved.toString(), href);
  }

  String relativePath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    if (!isForumUrl(url)) return url;
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final query = uri.hasQuery ? '?${_rawQuery(url) ?? uri.query}' : '';
    final fragment = uri.hasFragment ? url.substring(url.indexOf('#')) : '';
    return '$path$query$fragment';
  }

  String captchaPath(String src) {
    final path = relativePath(absoluteUrl(src));
    final separator = path.endsWith('?')
        ? ''
        : path.contains('?')
            ? '&'
            : '?';
    return '${path}${separator}nowtime=${DateTime.now().millisecondsSinceEpoch}';
  }

  String? tidFromUrl(String url) {
    if (!isForumUrl(url)) return null;
    final uri = baseUri.resolve(url);
    if (uri.path == '/simple/index.php') {
      return RegExp(r'^t([1-9]\d*)(?:_\d+)?\.html$')
          .firstMatch(uri.query)
          ?.group(1);
    }
    if (uri.path != '/read.php' && uri.path != '/job.php') return null;
    if (uri.path == '/job.php' &&
        _queryField(uri, 'action', rawQuery: _rawQuery(url)) != 'topost')
      return null;
    final tid = _queryField(uri, 'tid', rawQuery: _rawQuery(url));
    return tid != null && RegExp(r'^[1-9]\d*$').hasMatch(tid) ? tid : null;
  }

  String? uidFromUrl(String url) {
    if (!isForumUrl(url)) return null;
    final uri = baseUri.resolve(url);
    if (!{'/read.php', '/u.php'}.contains(uri.path)) return null;
    final uid = _queryField(uri, 'uid', rawQuery: _rawQuery(url));
    return uid != null && RegExp(r'^[1-9]\d*$').hasMatch(uid) ? uid : null;
  }

  String? fidFromCategory(ForumCategory category) {
    for (final value in [category.slug, category.url ?? '']) {
      final fid = _fidFromValue(value);
      if (fid != null) return fid;
    }
    return null;
  }

  ForumBoardFilter? boardFilterFromUrl(
    ForumCategory category, {
    required String label,
    required String url,
  }) {
    final parsed = _boardFilter(category, url);
    if (parsed == null) return null;
    return ForumBoardFilter(
      label: label,
      url: absoluteUrl(url),
      kind: parsed.kind,
    );
  }

  ({ForumBoardFilterKind kind, String suffix})? _boardFilter(
    ForumCategory category,
    String url,
  ) {
    final fid = fidFromCategory(category);
    if (fid == null || fidFromUrl(url) != fid) return null;
    final uri = baseUri.resolve(url);
    if (!{'/thread.php', '/thread_new.php'}.contains(uri.path)) return null;
    final fields = _queryFields(uri, rawQuery: _rawQuery(url));
    if (fields == null ||
        fields.keys.any(
          (key) => !{
            'fid',
            'search',
            'type',
            'special',
            'page',
            'orderway',
            'asc',
          }.contains(key),
        )) return null;
    final selectors = [
      'search',
      'type',
      'special',
    ].where((key) => fields.containsKey(key)).toList();
    if (selectors.isEmpty) return (kind: ForumBoardFilterKind.all, suffix: '');
    if (selectors.length != 1) return null;
    final key = selectors.single;
    final value = fields[key]!;
    if (key == 'search') {
      return value == 'digest'
          ? (kind: ForumBoardFilterKind.digest, suffix: '-search-digest')
          : null;
    }
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) return null;
    if (key == 'special' && !{'1', '2', '3', '4', '5'}.contains(value))
      return null;
    return (
      kind: key == 'type'
          ? ForumBoardFilterKind.topicType
          : ForumBoardFilterKind.special,
      suffix: '-$key-$value',
    );
  }

  String? boardDesktopPath(
    ForumCategory category, {
    int page = 1,
    ForumThreadOrder order = ForumThreadOrder.lastPost,
    ForumBoardFilter? filter,
  }) {
    final fid = fidFromCategory(category);
    if (fid == null) return null;
    var suffix = '';
    if (filter != null) {
      final parsed = _boardFilter(category, filter.url);
      if (parsed == null || parsed.kind != filter.kind) return null;
      suffix = parsed.suffix;
    }
    final normalizedPage = _normalizedPage(page);
    return 'thread_new.php?fid-$fid$suffix-orderway-${order.queryValue}-asc-DESC-page-$normalizedPage.html';
  }

  String? threadBoundaryUrl(String url, {required bool last}) {
    final tid = tidFromUrl(url);
    if (tid == null) return null;
    final uid = uidFromUrl(url);
    final filter = uid == null ? '' : '-uid-$uid';
    final page = last ? 'e' : '1';
    final anchor = last ? '' : '#tpc';
    return absoluteUrl('read.php?tid-$tid$filter-page-$page.html$anchor');
  }

  String threadDetailPath(String url, {int page = 1}) {
    final uri = Uri.tryParse(url);
    final isForum = isForumUrl(url);
    final tid = tidFromUrl(url);
    if (isForum && tid != null) {
      final uid = uidFromUrl(url);
      final uidPart = uid == null ? '' : '-uid-$uid';
      if (page <= 1) {
        if (uri?.path == '/simple/index.php' ||
            uri?.path == 'simple/index.php') {
          final simplePage =
              RegExp(r'^t\d+_(\d+)\.html$').firstMatch(uri!.query)?.group(1) ??
                  '1';
          final fragment =
              uri.hasFragment ? url.substring(url.indexOf('#')) : '';
          return 'read.php?tid=$tid&fpage=0&toread=&page=$simplePage$fragment';
        }
        if (uri?.path.endsWith('job.php') == true ||
            _hasExplicitThreadLocation(uri, url)) return relativePath(url);
        return 'read.php?tid-$tid$uidPart.html';
      }
      return 'read.php?tid-$tid$uidPart-fpage-0-toread--page-$page.html';
    }
    return relativePath(url);
  }

  String userTabUrl(String uid, UserProfileTab tab) {
    return switch (tab) {
      UserProfileTab.home => '$_origin/u.php?uid-$uid.html',
      UserProfileTab.profile => '$_origin/u.php?action-show-uid-$uid.html',
      UserProfileTab.topics => '$_origin/u.php?action-topic-uid-$uid.html',
      UserProfileTab.posts => '$_origin/u.php?action-post-uid-$uid.html',
      UserProfileTab.favorites => '$_origin/u.php?action-favor-uid-$uid.html',
    };
  }

  bool isThreadHref(String href) {
    final query = Uri.tryParse(href)?.query ?? '';
    return query.startsWith('t') && query.endsWith('.html');
  }

  bool isReadThreadHref(String href) {
    return href.contains('read.php') && tidFromUrl(href) != null;
  }

  bool isBoardHref(String href) {
    return _fidFromValue(href) != null;
  }

  String slugFromHref(String href) {
    final query = Uri.tryParse(href)?.query ?? href;
    return query.endsWith('.html')
        ? query.substring(0, query.length - '.html'.length)
        : query;
  }

  int _normalizedPage(int page) => page < 1 ? 1 : page;

  String? _fidFromValue(String value) {
    final token = _simpleBoardTokenFromValue(value);
    if (token != null) {
      return RegExp(r'\d+').firstMatch(token)?.group(0);
    }
    return _fidPattern.firstMatch(value)?.group(1);
  }

  String? _simpleBoardTokenFromValue(String value) {
    if (value.isEmpty) return null;
    return _simpleBoardTokenPattern.firstMatch(value)?.group(1) ??
        _slugSimpleBoardTokenPattern.firstMatch(value)?.group(1);
  }

  bool _hasExplicitThreadLocation(Uri? uri, String url) {
    if (uri?.hasFragment ?? false) return true;
    if (uri != null &&
        _queryField(uri, 'page', rawQuery: _rawQuery(url)) != null) return true;
    return RegExp(r'page-(?:\d+|e)\b').hasMatch(url);
  }
}
