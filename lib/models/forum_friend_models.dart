enum ForumFriendResponse { acceptadd, accept, refuse }

enum ForumFriendAddStatus {
  added,
  pending,
  verificationRequired,
  rejected,
  unknown,
}

class ForumFriend {
  const ForumFriend({
    required this.uid,
    required this.name,
    required this.url,
    this.avatarUrl,
    this.joinedAt,
    this.verificationMessage,
  });
  final String uid;
  final String name;
  final String url;
  final String? avatarUrl;
  final String? joinedAt;
  final String? verificationMessage;
}

class ForumFriendPage {
  const ForumFriendPage({
    required this.items,
    required this.pending,
    this.page = 1,
    this.pageCount = 1,
  });
  final List<ForumFriend> items;
  final bool pending;
  final int page;
  final int pageCount;
}

// The service binds this handle to the native form and the originating session.
class ForumFriendRequest {
  const ForumFriendRequest({required this.uid, this.maxLength, this.prompt});
  final String uid;
  final int? maxLength;
  final String? prompt;
}

class ForumFriendAddResult {
  const ForumFriendAddResult({
    required this.status,
    required this.message,
    this.request,
  });
  final ForumFriendAddStatus status;
  final String message;
  final ForumFriendRequest? request;
}

class ForumFriendMutationResult {
  const ForumFriendMutationResult({
    required this.confirmed,
    required this.message,
  });
  final bool confirmed;
  final String message;
}
