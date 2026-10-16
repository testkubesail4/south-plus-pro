import 'dart:typed_data';

sealed class ForumLinkTarget {
  const ForumLinkTarget();
}

class ForumThreadLinkTarget extends ForumLinkTarget {
  const ForumThreadLinkTarget(this.url);
  final String url;
}

class ForumUserLinkTarget extends ForumLinkTarget {
  const ForumUserLinkTarget(this.userUrl, {this.tab = UserProfileTab.home});
  final String userUrl;
  final UserProfileTab tab;
}

class ForumBoardLinkTarget extends ForumLinkTarget {
  const ForumBoardLinkTarget(this.category);
  final ForumCategory category;
}

class ForumPageLinkTarget extends ForumLinkTarget {
  const ForumPageLinkTarget(this.url);
  final String url;
}

class ForumExternalLinkTarget extends ForumLinkTarget {
  const ForumExternalLinkTarget(this.url);
  final String url;
}

class ForumBlockedLinkTarget extends ForumLinkTarget {
  const ForumBlockedLinkTarget();
}

enum ForumThreadOrder {
  lastPost('lastpost'),
  postedAt('postdate'),
  hits('hits'),
  replies('replies');

  const ForumThreadOrder(this.queryValue);

  final String queryValue;
}

enum ForumSearchMatch {
  partial('OR'),
  exact('AND');

  const ForumSearchMatch(this.queryValue);

  final String queryValue;
}

enum ForumSearchTime {
  all('all'),
  newTopics('newatc'),
  day('86400'),
  twoDays('172800'),
  week('604800'),
  month('2592000'),
  twoMonths('5184000'),
  threeMonths('7776000'),
  halfYear('15552000'),
  year('31536000');

  const ForumSearchTime(this.queryValue);

  final String queryValue;
}

class ForumSearchLinkPrefill {
  const ForumSearchLinkPrefill({this.keyword, this.username, this.boardId});

  final String? keyword;
  final String? username;
  final String? boardId;
}

class ForumSearchQuery {
  const ForumSearchQuery({
    this.keyword = '',
    this.username = '',
    this.match = ForumSearchMatch.partial,
    this.boardId = 'all',
    this.time = ForumSearchTime.year,
    this.order = ForumThreadOrder.postedAt,
    this.ascending = false,
    this.digest = false,
  });

  final String keyword;
  final String username;
  final ForumSearchMatch match;
  final String boardId;
  final ForumSearchTime time;
  final ForumThreadOrder order;
  final bool ascending;
  final bool digest;
}

class ForumSearchBoard {
  const ForumSearchBoard(
      {required this.id,
      required this.name,
      this.depth = 0,
      this.selectable = true});

  final String id;
  final String name;
  final int depth;
  final bool selectable;
}

class ForumSearchPage {
  const ForumSearchPage({
    required this.threads,
    this.total,
    this.nextPagePath,
    this.previousPagePath,
    this.currentPage = 1,
    this.pageLinks = const [],
  });

  final List<ForumThread> threads;
  final int? total;
  final String? nextPagePath;
  final String? previousPagePath;
  final int currentPage;
  final List<ForumSearchPageLink> pageLinks;
}

class ForumSearchPageLink {
  const ForumSearchPageLink(
      {required this.label, required this.path, required this.page});
  final String label;
  final String path;
  final int page;
}

class ForumTitleStyle {
  const ForumTitleStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.colorValue,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final int? colorValue;
}

class ForumThread {
  const ForumThread({
    required this.title,
    required this.url,
    required this.replies,
    required this.section,
    this.bodyPreview,
    this.lastPost,
    this.author,
    this.authorUrl,
    this.authorAvatarUrl,
    this.authorPostsUrl,
    this.previewImageUrl,
    this.isSticky = false,
    this.titleStyle,
  });

  final String title;
  final String url;
  final int replies;
  final String section;
  final String? bodyPreview;
  final String? lastPost;
  final String? author;
  final String? authorUrl;
  final String? authorAvatarUrl;
  final String? authorPostsUrl;
  String? get authorUid => _profileUid(authorUrl);
  final String? previewImageUrl;
  final bool isSticky;
  final ForumTitleStyle? titleStyle;

  ForumThread copyWith({
    String? title,
    String? url,
    int? replies,
    String? section,
    String? bodyPreview,
    String? lastPost,
    String? author,
    String? authorUrl,
    String? authorAvatarUrl,
    String? authorPostsUrl,
    String? previewImageUrl,
    bool? isSticky,
    ForumTitleStyle? titleStyle,
  }) {
    return ForumThread(
      title: title ?? this.title,
      url: url ?? this.url,
      replies: replies ?? this.replies,
      section: section ?? this.section,
      bodyPreview: bodyPreview ?? this.bodyPreview,
      lastPost: lastPost ?? this.lastPost,
      author: author ?? this.author,
      authorUrl: authorUrl ?? this.authorUrl,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorPostsUrl: authorPostsUrl ?? this.authorPostsUrl,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
      isSticky: isSticky ?? this.isSticky,
      titleStyle: titleStyle ?? this.titleStyle,
    );
  }
}

String? _profileUid(String? url) {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null || !uri.path.endsWith('/u.php')) return null;
  return RegExp(
    r'(?:^|[&-])uid[-=]([1-9]\d*)(?:\.html)?(?:$|[&-])',
  ).firstMatch(uri.query)?.group(1);
}

class ThreadReadPosition {
  const ThreadReadPosition({required this.page, this.anchor});

  final int page;
  final String? anchor;
}

class BrowsingHistoryEntry {
  const BrowsingHistoryEntry({
    required this.thread,
    required this.viewedAt,
  });

  final ForumThread thread;
  final DateTime viewedAt;
}

enum ForumBoardFilterKind { all, digest, topicType, special }

class ForumBoardFilter {
  const ForumBoardFilter({
    required this.label,
    required this.url,
    required this.kind,
  });

  final String label;
  final String url;
  final ForumBoardFilterKind kind;
}

class ForumThreadPage {
  const ForumThreadPage({
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    this.ads = const [],
    this.subBoards = const [],
    this.boardName,
    this.hasPictureWall = false,
    this.filters = const [],
    this.activeFilter,
    this.parents = const [],
  });

  final List<ForumThread> threads;
  final int currentPage;
  final int totalPages;
  final List<ForumBoardAd> ads;
  final List<ForumBoard> subBoards;
  final String? boardName;
  final bool hasPictureWall;
  final List<ForumBoardFilter> filters;
  final ForumBoardFilter? activeFilter;
  final List<ForumCategory> parents;

  bool get hasPrevious => currentPage > 1;
  bool get hasNext => currentPage < totalPages;
}

class ForumBoardAd {
  const ForumBoardAd({
    required this.title,
    required this.url,
    this.imageUrl,
    this.subtitle,
  });

  final String title;
  final String url;
  final String? imageUrl;
  final String? subtitle;
}

class ThreadDetail {
  const ThreadDetail({
    required this.thread,
    required this.body,
    required this.replies,
    this.pagination = const ThreadPagination(currentPage: 1, totalPages: 1),
    this.bodyImages = const [],
    this.bodyLinks = const [],
    this.bodySegments = const [],
    this.bodyAnchors = const [],
    this.bodySaleBoxes = const [],
    this.bodySaleBoxesFirst = false,
    this.bodyReplyTitle,
    this.bodyReplyUrl,
    this.bodyQuoteUrl,
    this.bodyContentKey,
    this.favorite,
    this.previousThread,
    this.nextThread,
    this.rssFeed,
    this.board,
  });

  final ForumThread thread;
  final String body;
  final List<ThreadReply> replies;
  final ThreadPagination pagination;
  final List<ThreadImage> bodyImages;
  final List<ThreadLink> bodyLinks;
  final List<ThreadContentSegment> bodySegments;
  final List<String> bodyAnchors;
  final List<ThreadSaleBox> bodySaleBoxes;
  final bool bodySaleBoxesFirst;
  final String? bodyReplyTitle;
  final String? bodyReplyUrl;
  final String? bodyQuoteUrl;
  final String? bodyContentKey;
  final ThreadFavorite? favorite;
  final ThreadActionLink? previousThread;
  final ThreadActionLink? nextThread;
  final ThreadActionLink? rssFeed;
  final ForumCategory? board;
}

class ThreadPagination {
  const ThreadPagination({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  bool get hasPrevious => currentPage > 1;
  bool get hasNext => currentPage < totalPages;
}

class ThreadReply {
  const ThreadReply({
    required this.author,
    required this.content,
    this.authorUrl,
    this.authorAvatarUrl,
    this.authorPostsUrl,
    this.postedAt,
    this.floor,
    this.quote,
    this.quoteUrl,
    this.replyTitle,
    this.replyUrl,
    this.blockContentKey,
    this.segments = const [],
    this.anchors = const [],
    this.images = const [],
    this.links = const [],
    this.saleBoxes = const [],
    this.saleBoxesFirst = false,
  });

  final String author;
  final String content;
  final String? authorUrl;
  final String? authorAvatarUrl;
  final String? authorPostsUrl;
  final String? postedAt;
  final String? floor;
  final String? quote;
  final String? quoteUrl;
  final String? replyTitle;
  final String? replyUrl;
  final String? blockContentKey;
  String? get authorUid => _profileUid(authorUrl);
  final List<ThreadContentSegment> segments;
  final List<String> anchors;
  final List<ThreadImage> images;
  final List<ThreadLink> links;
  final List<ThreadSaleBox> saleBoxes;
  final bool saleBoxesFirst;
}

enum ThreadContentSegmentType {
  text,
  image,
  quote,
  saleBox,
  block,
  code,
  list,
  table,
  media
}

const forumWindCodeColors = {
  'black': 0xff000000,
  'red': 0xffff0000,
  'blue': 0xff0000ff,
  'green': 0xff008000,
  'white': 0xffffffff,
  'gray': 0xff808080,
  'grey': 0xff808080,
  'purple': 0xff800080,
  'skyblue': 0xff87ceeb,
  'royalblue': 0xff4169e1,
  'darkblue': 0xff00008b,
  'orange': 0xffffa500,
  'orangered': 0xffff4500,
  'crimson': 0xffdc143c,
  'firebrick': 0xffb22222,
  'darkred': 0xff8b0000,
  'limegreen': 0xff32cd32,
  'seagreen': 0xff2e8b57,
  'teal': 0xff008080,
  'deeppink': 0xffff1493,
  'tomato': 0xffff6347,
  'coral': 0xffff7f50,
  'indigo': 0xff4b0082,
  'burlywood': 0xffdeb887,
  'sandybrown': 0xfff4a460,
  'sienna': 0xffa0522d,
  'chocolate': 0xffd2691e,
  'silver': 0xffc0c0c0,
};

enum ThreadContentAlignment { start, center, end, justify }

class ThreadContentTableCell {
  const ThreadContentTableCell(this.segments, {this.isHeader = false});
  final List<ThreadContentSegment> segments;
  final bool isHeader;
}

class ThreadContentSegment {
  const ThreadContentSegment._({
    required this.type,
    this.text,
    this.url,
    this.alt,
    this.saleBox,
    this.isEmoji = false,
    this.children = const [],
    this.colorValue,
    this.backgroundColorValue,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.fontScale = 1,
    this.href,
    this.fontFamily,
    this.alignment = ThreadContentAlignment.start,
    this.isOrdered = false,
    this.listStyle = '1',
    this.tableRows = const [],
  });

  const ThreadContentSegment.text(
    String? text, {
    int? colorValue,
    bool isBold = false,
    bool isItalic = false,
    bool isUnderline = false,
    bool isStrike = false,
    double fontScale = 1,
    String? href,
    int? backgroundColorValue,
    String? fontFamily,
  }) : this._(
            type: ThreadContentSegmentType.text,
            text: text,
            colorValue: colorValue,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            isStrike: isStrike,
            fontScale: fontScale,
            href: href,
            backgroundColorValue: backgroundColorValue,
            fontFamily: fontFamily);

  const ThreadContentSegment.image(
      {required String? url, String? alt, bool isEmoji = false, String? href})
      : this._(
            type: ThreadContentSegmentType.image,
            url: url,
            alt: alt,
            isEmoji: isEmoji,
            href: href);
  const ThreadContentSegment.quote(List<ThreadContentSegment> children)
      : this._(type: ThreadContentSegmentType.quote, children: children);
  const ThreadContentSegment.saleBox(ThreadSaleBox? saleBox)
      : this._(type: ThreadContentSegmentType.saleBox, saleBox: saleBox);
  const ThreadContentSegment.block(List<ThreadContentSegment> children,
      {ThreadContentAlignment alignment = ThreadContentAlignment.start})
      : this._(
            type: ThreadContentSegmentType.block,
            children: children,
            alignment: alignment);
  const ThreadContentSegment.code(String text)
      : this._(type: ThreadContentSegmentType.code, text: text);
  const ThreadContentSegment.list(List<ThreadContentSegment> children,
      {bool isOrdered = false, String listStyle = '1'})
      : this._(
            type: ThreadContentSegmentType.list,
            children: children,
            isOrdered: isOrdered,
            listStyle: listStyle);
  const ThreadContentSegment.table(List<List<ThreadContentTableCell>> rows)
      : this._(type: ThreadContentSegmentType.table, tableRows: rows);
  const ThreadContentSegment.media({String? url, required String text})
      : this._(type: ThreadContentSegmentType.media, url: url, text: text);

  final ThreadContentSegmentType type;
  final String? text;
  final String? url;
  final String? alt;
  final ThreadSaleBox? saleBox;
  final bool isEmoji;
  final List<ThreadContentSegment> children;
  final int? colorValue;
  final int? backgroundColorValue;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final double fontScale;
  final String? href;
  final String? fontFamily;
  final ThreadContentAlignment alignment;
  final bool isOrdered;
  final String listStyle;
  final List<List<ThreadContentTableCell>> tableRows;
}

class ThreadImage {
  const ThreadImage({
    required this.url,
    this.alt,
  });

  final String url;
  final String? alt;
}

class ThreadLink {
  const ThreadLink({
    required this.url,
    required this.label,
  });

  final String url;
  final String label;
}

class ThreadSaleBox {
  const ThreadSaleBox({
    required this.summary,
    required this.buyPath,
    this.warning,
    this.price,
    this.buyers,
  });

  final String summary;
  final String buyPath;
  final String? warning;
  final int? price;
  final int? buyers;
}

class ThreadActionLink {
  const ThreadActionLink({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;
}

enum ThreadFavoriteState {
  unknown,
  notFavorite,
  favorite,
}

class ThreadFavorite {
  const ThreadFavorite({
    required this.tid,
    required this.verify,
    this.state = ThreadFavoriteState.unknown,
  });

  final String tid;
  final String verify;
  final ThreadFavoriteState state;

  bool get canRemove => state == ThreadFavoriteState.favorite;

  ThreadFavorite copyWith({ThreadFavoriteState? state}) {
    return ThreadFavorite(
      tid: tid,
      verify: verify,
      state: state ?? this.state,
    );
  }
}

class FavoriteResult {
  const FavoriteResult({
    required this.success,
    required this.message,
    required this.state,
  });

  final bool success;
  final String message;
  final ThreadFavoriteState state;
}

class ForumSection {
  const ForumSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<ForumBoard> items;
}

class ForumBoard {
  const ForumBoard({
    required this.name,
    required this.url,
    required this.section,
    this.subtitle,
    this.topicCount,
    this.postCount,
    this.todayCount,
    this.lastPostTitle,
    this.lastPostTime,
    this.hasNew = false,
    this.hasPictureWall = false,
    this.children = const [],
  });

  final String name;
  final String url;
  final String section;
  final String? subtitle;
  final int? topicCount;
  final int? postCount;
  final int? todayCount;
  final String? lastPostTitle;
  final String? lastPostTime;
  final bool hasNew;
  final bool hasPictureWall;
  final List<ForumBoard> children;

  String get slug {
    final query = Uri.tryParse(url)?.query ?? url;
    return query.endsWith('.html')
        ? query.substring(0, query.length - '.html'.length)
        : query;
  }
}

class ForumCategory {
  const ForumCategory({
    required this.name,
    required this.slug,
    this.url,
  });

  final String name;
  final String slug;
  final String? url;
}

class ForumAccountIdentity {
  const ForumAccountIdentity({
    required this.systemName,
    this.uid,
    this.nickname,
    this.avatarUrl,
  });

  final String systemName;
  final String? uid;
  final String? nickname;
  final String? avatarUrl;
}

class ForumNoticeFlags {
  const ForumNoticeFlags({this.replyNotice = false, this.unreadPm = false});

  final bool replyNotice;
  final bool unreadPm;
}

class ForumReplyNotice {
  const ForumReplyNotice({
    required this.tid,
    required this.board,
    required this.boardUrl,
    required this.title,
    required this.threadUrl,
    required this.date,
  });

  final int tid;
  final String board;
  final String boardUrl;
  final String title;
  final String threadUrl;
  final String date;
}

class ForumQuickList {
  const ForumQuickList({
    required this.title,
    this.threads,
    this.scriptUrl,
    this.fallbackThreads = const [],
  });

  final String title;
  final List<ForumThread>? threads;
  final String? scriptUrl;
  final List<ForumThread> fallbackThreads;
}

class ForumHomeSnapshot {
  const ForumHomeSnapshot({
    required this.latest,
    required this.hot,
    required this.sections,
    this.hasReplyNotice = false,
    this.hasUnreadPm = false,
    this.quickLists = const [],
  });

  final List<ForumThread> latest;
  final List<ForumCategory> hot;
  final List<ForumSection> sections;
  final bool hasReplyNotice;
  final bool hasUnreadPm;
  final List<ForumQuickList> quickLists;
}

enum UserProfileTab {
  home,
  profile,
  topics,
  posts,
  favorites,
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.url,
    this.tagline,
    this.avatarUrl,
    this.level,
    this.isOnline,
    this.statusText,
    this.messageUrl,
    this.info = const [],
    this.stats = const [],
    this.signature,
    this.homeActivities = const [],
    this.homeReplies = const [],
    this.topics = const [],
    this.posts = const [],
    this.favorites = const [],
  });

  final String uid;
  final String name;
  final String url;
  final String? tagline;
  final String? avatarUrl;
  final String? level;
  final bool? isOnline;
  final String? statusText;
  final String? messageUrl;
  final List<UserProfileField> info;
  final List<UserProfileField> stats;
  final String? signature;
  final List<UserActivityItem> homeActivities;
  final List<UserActivityItem> homeReplies;
  final List<UserListItem> topics;
  final List<UserListItem> posts;
  final List<UserListItem> favorites;

  UserProfile copyWith({
    String? uid,
    String? name,
    String? url,
    String? tagline,
    String? avatarUrl,
    String? level,
    bool? isOnline,
    String? statusText,
    String? messageUrl,
    List<UserProfileField>? info,
    List<UserProfileField>? stats,
    String? signature,
    List<UserActivityItem>? homeActivities,
    List<UserActivityItem>? homeReplies,
    List<UserListItem>? topics,
    List<UserListItem>? posts,
    List<UserListItem>? favorites,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      url: url ?? this.url,
      tagline: tagline ?? this.tagline,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      isOnline: isOnline ?? this.isOnline,
      statusText: statusText ?? this.statusText,
      messageUrl: messageUrl ?? this.messageUrl,
      info: info ?? this.info,
      stats: stats ?? this.stats,
      signature: signature ?? this.signature,
      homeActivities: homeActivities ?? this.homeActivities,
      homeReplies: homeReplies ?? this.homeReplies,
      topics: topics ?? this.topics,
      posts: posts ?? this.posts,
      favorites: favorites ?? this.favorites,
    );
  }
}

class UserProfileField {
  const UserProfileField({required this.label, required this.value});

  final String label;
  final String value;
}

class UserActivityItem {
  const UserActivityItem({
    required this.title,
    required this.url,
    this.action,
    this.author,
    this.date,
  });

  final String title;
  final String url;
  final String? action;
  final String? author;
  final String? date;
}

class FavoriteListRemoval {
  const FavoriteListRemoval({required this.id, required this.verify});

  final String id;
  final String verify;
}

class UserListItem {
  const UserListItem({
    required this.title,
    required this.url,
    this.section,
    this.date,
    this.author,
    this.authorUrl,
    this.replies,
    this.views,
    this.favoriteRemoval,
  });

  final String title;
  final String url;
  final String? section;
  final String? date;
  final String? author;
  final String? authorUrl;
  final int? replies;
  final int? views;
  final FavoriteListRemoval? favoriteRemoval;
}

class LoginChallenge {
  const LoginChallenge({
    required this.captchaBytes,
    required this.fields,
  });

  final Uint8List captchaBytes;
  final Map<String, String> fields;
}

class LoginResult {
  const LoginResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class ReplyResult {
  const ReplyResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

enum ForumTaskStatus {
  available,
  inProgress,
  completed,
  failed,
}

class ForumTask {
  const ForumTask({
    required this.name,
    required this.status,
    this.id,
    this.description,
    this.reward,
    this.popularity,
    this.startedAt,
    this.endsAt,
    this.progressPercent,
    this.completedAt,
    this.actionLabel,
    this.cooldownRemaining,
  });

  final String? id;
  final String name;
  final ForumTaskStatus status;
  final String? description;
  final String? reward;
  final int? popularity;
  final String? startedAt;
  final String? endsAt;
  final int? progressPercent;
  final String? completedAt;
  final String? actionLabel;
  final Duration? cooldownRemaining;

  bool get canRun => id != null && actionLabel != null;
}

class ForumTaskActionResult {
  const ForumTaskActionResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class ForumTaskClaimItem {
  const ForumTaskClaimItem({
    required this.name,
    required this.message,
    this.reward,
    this.spAmount,
  });

  final String name;
  final String message;
  final String? reward;
  final int? spAmount;

  String get completionMessage {
    final amount = spAmount;
    if (amount != null) return '$name奖励领取完成SP+$amount';
    final fallback = reward?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      return '$name奖励领取完成$fallback';
    }
    return '$name奖励领取完成';
  }
}

class ForumTaskQuickClaimResult {
  const ForumTaskQuickClaimResult({
    required this.appliedCount,
    required this.claimedRewards,
    required this.failures,
    this.skipped = const [],
    this.cooldowns = const [],
    this.inProgress = const [],
    this.alreadyHandled = false,
  });

  final int appliedCount;
  final List<ForumTaskClaimItem> claimedRewards;
  final List<String> failures;
  final List<String> skipped;
  final List<String> cooldowns;
  final List<String> inProgress;
  final bool alreadyHandled;

  bool get hasClaims => claimedRewards.isNotEmpty;
  bool get hasFailures => failures.isNotEmpty;
}

enum ForumTaskAvailability {
  unknown,
  available,
  inProgress,
  claimable,
  coolingDown,
  completed,
}

class ForumTaskState {
  const ForumTaskState({
    required this.name,
    required this.availability,
    this.id,
    this.reward,
    this.spAmount,
    this.progressPercent,
    this.completedAt,
    this.cooldownRemaining,
    this.nextAvailableAt,
  });

  final String name;
  final String? id;
  final ForumTaskAvailability availability;
  final String? reward;
  final int? spAmount;
  final int? progressPercent;
  final String? completedAt;
  final Duration? cooldownRemaining;
  final DateTime? nextAvailableAt;

  bool get isDoneToday =>
      availability == ForumTaskAvailability.completed ||
      availability == ForumTaskAvailability.coolingDown;
  bool get canClaim => availability == ForumTaskAvailability.claimable;
  bool get isDailyReward => name.contains('日常');
  bool get isWeeklyReward => name.contains('周常');
  bool get isAutoReward => isDailyReward || isWeeklyReward;

  Duration? get autoRewardCycle {
    if (isDailyReward) return const Duration(hours: 24);
    if (isWeeklyReward) return const Duration(hours: 168);
    return null;
  }

  Duration? cooldownRemainingFrom(DateTime now) {
    final next = nextAvailableAt;
    if (next == null) return cooldownRemaining;
    final remaining = next.difference(now.toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  DateTime? nextAutoClaimAt() {
    final next = nextAvailableAt;
    if (next != null) return next.toUtc();
    final cycle = autoRewardCycle;
    final completed = _parseForumTaskCompletedAt(completedAt);
    if (cycle == null || completed == null) return null;
    return completed.add(cycle).toUtc();
  }

  bool shouldAutoClaimAt(DateTime now) {
    if (!isAutoReward) return false;
    if (availability == ForumTaskAvailability.available ||
        availability == ForumTaskAvailability.claimable ||
        availability == ForumTaskAvailability.inProgress) {
      return true;
    }
    final next = nextAutoClaimAt();
    if (next == null) return true;
    return !next.isAfter(now.toUtc());
  }

  ForumTaskState merge(ForumTaskState other) {
    final preferred = _preferredTaskState(this, other);
    final fallback = identical(preferred, other) ? this : other;
    final cooldownRemaining = this.cooldownRemaining ?? other.cooldownRemaining;
    final nextAvailableAt = this.nextAvailableAt ?? other.nextAvailableAt;
    return ForumTaskState(
      name: preferred.name,
      id: preferred.id ?? fallback.id,
      availability: preferred.availability,
      reward: preferred.reward ?? fallback.reward,
      spAmount: preferred.spAmount ?? fallback.spAmount,
      progressPercent: preferred.progressPercent ?? fallback.progressPercent,
      completedAt: preferred.completedAt ?? fallback.completedAt,
      cooldownRemaining: cooldownRemaining,
      nextAvailableAt: nextAvailableAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'id': id,
      'availability': availability.name,
      'reward': reward,
      'spAmount': spAmount,
      'progressPercent': progressPercent,
      'completedAt': completedAt,
      'cooldownRemainingMinutes': cooldownRemaining?.inMinutes,
      'nextAvailableAt': nextAvailableAt?.toIso8601String(),
    };
  }

  static ForumTaskState? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final availabilityName = json['availability'];
    final availability = ForumTaskAvailability.values.firstWhere(
      (value) => value.name == availabilityName,
      orElse: () => ForumTaskAvailability.unknown,
    );
    final cooldownMinutes = json['cooldownRemainingMinutes'];
    final nextAvailableAtValue = json['nextAvailableAt'];
    return ForumTaskState(
      name: name,
      id: json['id'] is String ? json['id'] as String : null,
      availability: availability,
      reward: json['reward'] is String ? json['reward'] as String : null,
      spAmount: json['spAmount'] is int ? json['spAmount'] as int : null,
      progressPercent: json['progressPercent'] is int
          ? json['progressPercent'] as int
          : null,
      completedAt:
          json['completedAt'] is String ? json['completedAt'] as String : null,
      cooldownRemaining:
          cooldownMinutes is int ? Duration(minutes: cooldownMinutes) : null,
      nextAvailableAt: nextAvailableAtValue is String
          ? DateTime.tryParse(nextAvailableAtValue)?.toUtc()
          : null,
    );
  }
}

class ForumAutoTaskSummary {
  const ForumAutoTaskSummary({
    this.daily,
    this.weekly,
  });

  factory ForumAutoTaskSummary.fromTasks(Iterable<ForumTaskState> tasks) {
    ForumTaskState? daily;
    ForumTaskState? weekly;
    for (final task in tasks) {
      if (daily == null && task.isDailyReward) {
        daily = task;
      } else if (weekly == null && task.isWeeklyReward) {
        weekly = task;
      }
    }
    return ForumAutoTaskSummary(daily: daily, weekly: weekly);
  }

  final ForumTaskState? daily;
  final ForumTaskState? weekly;

  Iterable<ForumTaskState> get tasks sync* {
    if (daily != null) yield daily!;
    if (weekly != null) yield weekly!;
  }

  bool get hasAnyTask => daily != null || weekly != null;
  bool get hasAllTasks => daily != null && weekly != null;
  bool get hasClaimable => tasks.any((task) => task.canClaim);
  bool get hasInProgress => tasks
      .any((task) => task.availability == ForumTaskAvailability.inProgress);
  bool get hasAvailable =>
      tasks.any((task) => task.availability == ForumTaskAvailability.available);
  bool get hasPending => hasClaimable || hasInProgress || hasAvailable;
  bool get isFullyHandled =>
      hasAllTasks && tasks.every((task) => task.isDoneToday);

  Iterable<Duration> cooldownsFrom(DateTime now) sync* {
    for (final task in tasks) {
      final remaining = task.cooldownRemainingFrom(now);
      if (remaining != null) yield remaining;
    }
  }

  bool shouldAutoClaimAt(DateTime now) {
    if (!hasAllTasks) return true;
    return tasks.any((task) => task.shouldAutoClaimAt(now));
  }

  DateTime? nextAutoClaimAt(DateTime now) {
    if (!hasAllTasks) return now.toUtc();
    DateTime? next;
    for (final task in tasks) {
      if (task.shouldAutoClaimAt(now)) return now.toUtc();
      final candidate = task.nextAutoClaimAt();
      if (candidate == null) continue;
      if (next == null || candidate.isBefore(next)) next = candidate;
    }
    return next;
  }
}

class ForumTaskSnapshot {
  const ForumTaskSnapshot({
    required this.tasks,
    required this.updatedAt,
  });

  final List<ForumTaskState> tasks;
  final DateTime updatedAt;

  ForumAutoTaskSummary get autoTaskSummary =>
      ForumAutoTaskSummary.fromTasks(tasks);

  ForumTaskState? taskNamed(String name) {
    for (final task in tasks) {
      if (task.name == name) return task;
    }
    return null;
  }

  bool shouldAutoClaimAt(DateTime now) {
    return autoTaskSummary.shouldAutoClaimAt(now);
  }

  DateTime? nextAutoClaimAt(DateTime now) {
    return autoTaskSummary.nextAutoClaimAt(now);
  }

  ForumTaskSnapshot merge(Iterable<ForumTaskState> updates) {
    final byName = {for (final task in tasks) task.name: task};
    for (final update in updates) {
      byName[update.name] = byName[update.name]?.merge(update) ?? update;
    }
    return ForumTaskSnapshot(
      tasks: byName.values.toList()
        ..sort((a, b) => _taskSort(a.name).compareTo(_taskSort(b.name))),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'updatedAt': updatedAt.toIso8601String(),
      'tasks': tasks.map((task) => task.toJson()).toList(),
    };
  }

  static ForumTaskSnapshot? fromJson(Map<String, dynamic> json) {
    final updatedAtValue = json['updatedAt'];
    final updatedAt = updatedAtValue is String
        ? DateTime.tryParse(updatedAtValue)?.toUtc()
        : null;
    final taskValues = json['tasks'];
    if (updatedAt == null || taskValues is! List) return null;
    final tasks = <ForumTaskState>[];
    for (final value in taskValues) {
      if (value is! Map<String, dynamic>) continue;
      final task = ForumTaskState.fromJson(value);
      if (task != null) tasks.add(task);
    }
    return ForumTaskSnapshot(tasks: tasks, updatedAt: updatedAt);
  }
}

int _taskSort(String name) {
  if (name.contains('日常')) return 0;
  if (name.contains('周常')) return 1;
  return 2;
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

int _availabilityRank(ForumTaskAvailability availability) {
  return switch (availability) {
    ForumTaskAvailability.unknown => 0,
    ForumTaskAvailability.coolingDown => 1,
    ForumTaskAvailability.completed => 2,
    ForumTaskAvailability.inProgress => 3,
    ForumTaskAvailability.available => 4,
    ForumTaskAvailability.claimable => 5,
  };
}

ForumTaskState _preferredTaskState(
    ForumTaskState current, ForumTaskState next) {
  final currentAvailability = current.availability;
  final nextAvailability = next.availability;

  if (nextAvailability == ForumTaskAvailability.available &&
      (currentAvailability == ForumTaskAvailability.completed ||
          currentAvailability == ForumTaskAvailability.coolingDown)) {
    return next;
  }

  if (nextAvailability == ForumTaskAvailability.completed &&
      currentAvailability == ForumTaskAvailability.claimable) {
    return current;
  }

  if (nextAvailability == ForumTaskAvailability.coolingDown &&
      (currentAvailability == ForumTaskAvailability.completed ||
          currentAvailability == ForumTaskAvailability.claimable)) {
    return current;
  }

  if (currentAvailability == ForumTaskAvailability.coolingDown &&
      nextAvailability == ForumTaskAvailability.completed) {
    return next;
  }

  return _availabilityRank(nextAvailability) >=
          _availabilityRank(currentAvailability)
      ? next
      : current;
}
