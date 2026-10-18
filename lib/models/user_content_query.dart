import 'forum_models.dart';

enum UserContentArticleType { all, digest, poll, sale }

class UserContentQuery {
  const UserContentQuery({
    required this.uid,
    required this.tab,
    this.boardId,
    this.articleType = UserContentArticleType.all,
    this.classificationId,
    this.keyword = '',
  });

  final String uid;
  final UserProfileTab tab;
  final String? boardId;
  final UserContentArticleType articleType;
  final String? classificationId;
  final String keyword;

  String get cacheKey =>
      '$uid/${tab.name}/${boardId ?? ''}/${articleType.name}/${classificationId ?? ''}/${Uri.encodeComponent(keyword)}';
}

class UserContentClassification {
  const UserContentClassification({required this.id, required this.label});

  final String id;
  final String label;
}

class UserContentResult {
  const UserContentResult({
    required this.items,
    required this.unresolvedItems,
    required this.boards,
    required this.scannedPages,
    required this.totalPages,
    required this.checkedThreads,
    required this.pendingMetadataCount,
    required this.hasMore,
    this.lookupPagesScanned = 0,
    this.lookupPagesTotal = 0,
  });

  final List<UserListItem> items;
  // Rows whose required metadata could not be established remain visible here.
  final List<UserListItem> unresolvedItems;
  final List<ForumCategory> boards;
  final int scannedPages;
  final int totalPages;
  final int checkedThreads;
  final int pendingMetadataCount;
  final bool hasMore;
  final int lookupPagesScanned;
  final int lookupPagesTotal;
  bool get isComplete => !hasMore && unresolvedItems.isEmpty;
}

class UserContentPage {
  const UserContentPage(
      {required this.items,
      required this.totalPages,
      this.paginationKnown = true});

  final List<UserListItem> items;
  final int totalPages;
  final bool paginationKnown;
}

class UserContentThreadMetadata {
  const UserContentThreadMetadata({
    this.title,
    this.boardName,
    this.authorUid,
    this.boardId,
    this.classificationId,
    this.classificationKnown = false,
    this.digest,
    this.poll,
    this.sale,
  });

  final String? title;
  final String? boardName;
  final String? authorUid;
  final String? boardId;
  final String? classificationId;
  final bool classificationKnown;
  final bool? digest;
  final bool? poll;
  final bool? sale;

  bool? articleType(UserContentArticleType type) => switch (type) {
        UserContentArticleType.all => true,
        UserContentArticleType.digest => digest,
        UserContentArticleType.poll => poll,
        UserContentArticleType.sale => sale,
      };
}
