import 'dart:typed_data';

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
    this.isSticky = false,
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
  final bool isSticky;

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
    bool? isSticky,
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
      isSticky: isSticky ?? this.isSticky,
    );
  }
}

class BrowsingHistoryEntry {
  const BrowsingHistoryEntry({
    required this.thread,
    required this.viewedAt,
  });

  final ForumThread thread;
  final DateTime viewedAt;
}

class ForumThreadPage {
  const ForumThreadPage({
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    this.ads = const [],
    this.subBoards = const [],
  });

  final List<ForumThread> threads;
  final int currentPage;
  final int totalPages;
  final List<ForumBoardAd> ads;
  final List<ForumBoard> subBoards;

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
    this.bodySaleBoxes = const [],
    this.bodySaleBoxesFirst = false,
    this.favorite,
    this.previousThread,
    this.nextThread,
    this.rssFeed,
  });

  final ForumThread thread;
  final String body;
  final List<ThreadReply> replies;
  final ThreadPagination pagination;
  final List<ThreadImage> bodyImages;
  final List<ThreadLink> bodyLinks;
  final List<ThreadContentSegment> bodySegments;
  final List<ThreadSaleBox> bodySaleBoxes;
  final bool bodySaleBoxesFirst;
  final ThreadFavorite? favorite;
  final ThreadActionLink? previousThread;
  final ThreadActionLink? nextThread;
  final ThreadActionLink? rssFeed;
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
    this.segments = const [],
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
  final List<ThreadContentSegment> segments;
  final List<ThreadImage> images;
  final List<ThreadLink> links;
  final List<ThreadSaleBox> saleBoxes;
  final bool saleBoxesFirst;
}

enum ThreadContentSegmentType {
  text,
  image,
  quote,
}

class ThreadContentSegment {
  const ThreadContentSegment.text(
    this.text, {
    this.colorValue,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.fontScale = 1,
    this.href,
    this.backgroundColorValue,
  })  : type = ThreadContentSegmentType.text,
        url = null,
        alt = null,
        children = const [],
        isEmoji = false;

  const ThreadContentSegment.image({
    required this.url,
    this.alt,
    this.isEmoji = false,
  })  : type = ThreadContentSegmentType.image,
        text = null,
        colorValue = null,
        isBold = false,
        isItalic = false,
        isUnderline = false,
        isStrike = false,
        fontScale = 1,
        href = null,
        backgroundColorValue = null,
        children = const [];

  const ThreadContentSegment.quote(this.children)
      : type = ThreadContentSegmentType.quote,
        text = null,
        url = null,
        alt = null,
        isEmoji = false,
        colorValue = null,
        isBold = false,
        isItalic = false,
        isUnderline = false,
        isStrike = false,
        fontScale = 1,
        href = null,
        backgroundColorValue = null;

  final ThreadContentSegmentType type;
  final String? text;
  final String? url;
  final String? alt;
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
    this.children = const [],
  });

  final String name;
  final String url;
  final String section;
  final String? subtitle;
  final int? topicCount;
  final int? postCount;
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

class ForumHomeSnapshot {
  const ForumHomeSnapshot({
    required this.latest,
    required this.hot,
    required this.sections,
  });

  final List<ForumThread> latest;
  final List<ForumCategory> hot;
  final List<ForumSection> sections;
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
  });

  final String title;
  final String url;
  final String? section;
  final String? date;
  final String? author;
  final String? authorUrl;
  final int? replies;
  final int? views;
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

class ForumTaskSnapshot {
  const ForumTaskSnapshot({
    required this.tasks,
    required this.updatedAt,
  });

  final List<ForumTaskState> tasks;
  final DateTime updatedAt;

  bool get hasCompletedReward => tasks.any((task) => task.isDoneToday);
  bool get hasClaimableReward =>
      tasks.any((task) => task.availability == ForumTaskAvailability.claimable);
  bool get hasAutoRewardState => tasks.any((task) => task.isAutoReward);

  ForumTaskState? taskNamed(String name) {
    for (final task in tasks) {
      if (task.name == name) return task;
    }
    return null;
  }

  bool shouldAutoClaimAt(DateTime now) {
    final autoTasks = tasks.where((task) => task.isAutoReward).toList();
    if (autoTasks.length < 2) return true;
    return autoTasks.any((task) => task.shouldAutoClaimAt(now));
  }

  DateTime? nextAutoClaimAt(DateTime now) {
    final autoTasks = tasks.where((task) => task.isAutoReward).toList();
    if (autoTasks.length < 2) return now.toUtc();
    DateTime? next;
    for (final task in autoTasks) {
      if (task.shouldAutoClaimAt(now)) return now.toUtc();
      final candidate = task.nextAutoClaimAt();
      if (candidate == null) continue;
      if (next == null || candidate.isBefore(next)) next = candidate;
    }
    return next;
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
    return next;
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
