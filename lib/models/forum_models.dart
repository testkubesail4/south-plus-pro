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
  });

  final String title;
  final String url;
  final int replies;
  final String section;
  final String? bodyPreview;
  final String? lastPost;
  final String? author;
  final String? authorUrl;
}

class ThreadDetail {
  const ThreadDetail({
    required this.thread,
    required this.body,
    required this.replies,
    this.bodySaleBoxes = const [],
    this.bodySaleBoxesFirst = false,
    this.favorite,
  });

  final ForumThread thread;
  final String body;
  final List<ThreadReply> replies;
  final List<ThreadSaleBox> bodySaleBoxes;
  final bool bodySaleBoxesFirst;
  final ThreadFavorite? favorite;
}

class ThreadReply {
  const ThreadReply({
    required this.author,
    required this.content,
    this.postedAt,
    this.saleBoxes = const [],
    this.saleBoxesFirst = false,
  });

  final String author;
  final String content;
  final String? postedAt;
  final List<ThreadSaleBox> saleBoxes;
  final bool saleBoxesFirst;
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
  final List<ForumThread> items;
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
  final List<UserProfileField> info;
  final List<UserProfileField> stats;
  final String? signature;
  final List<UserActivityItem> homeActivities;
  final List<UserActivityItem> homeReplies;
  final List<UserListItem> topics;
  final List<UserListItem> posts;
  final List<UserListItem> favorites;
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
