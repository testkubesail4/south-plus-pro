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
  final bool isSticky;
}

class ForumThreadPage {
  const ForumThreadPage({
    required this.threads,
    required this.currentPage,
    required this.totalPages,
    this.ads = const [],
  });

  final List<ForumThread> threads;
  final int currentPage;
  final int totalPages;
  final List<ForumBoardAd> ads;

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
    this.bodyImages = const [],
    this.bodyLinks = const [],
    this.bodySegments = const [],
    this.bodySaleBoxes = const [],
    this.bodySaleBoxesFirst = false,
    this.favorite,
  });

  final ForumThread thread;
  final String body;
  final List<ThreadReply> replies;
  final List<ThreadImage> bodyImages;
  final List<ThreadLink> bodyLinks;
  final List<ThreadContentSegment> bodySegments;
  final List<ThreadSaleBox> bodySaleBoxes;
  final bool bodySaleBoxesFirst;
  final ThreadFavorite? favorite;
}

class ThreadReply {
  const ThreadReply({
    required this.author,
    required this.content,
    this.postedAt,
    this.floor,
    this.quote,
    this.segments = const [],
    this.images = const [],
    this.links = const [],
    this.saleBoxes = const [],
    this.saleBoxesFirst = false,
  });

  final String author;
  final String content;
  final String? postedAt;
  final String? floor;
  final String? quote;
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
