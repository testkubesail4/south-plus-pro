import 'forum_models.dart';

enum ForumPmBox {
  inbox('receivebox'),
  sendbox('sendbox'),
  scout('scout');

  const ForumPmBox(this.wireName);
  final String wireName;
}

enum ForumPmType { personal, broadcast, sent, tracked }

class ForumPmSummary {
  const ForumPmSummary({
    required this.box,
    required this.type,
    required this.id,
    required this.peer,
    this.peerUid,
    required this.title,
    required this.time,
    this.unread = false,
    this.recipientRead,
    required this.detailPath,
    this.editPath,
    this.canDelete = false,
  });

  final ForumPmBox box;
  final ForumPmType type;
  final String id;
  final String peer;
  final String? peerUid;
  final String title;
  final String time;
  final bool unread;
  final bool? recipientRead;
  final String detailPath;
  final String? editPath;
  final bool canDelete;
}

class ForumPmPageLink {
  const ForumPmPageLink({required this.label, required this.path});
  final String label;
  final String path;
}

class ForumPmPage {
  const ForumPmPage({
    required this.box,
    required this.messages,
    this.pageLinks = const [],
    this.hasUnread,
    this.currentPage = 1,
    this.nextPagePath,
  });
  final ForumPmBox box;
  final List<ForumPmSummary> messages;
  final List<ForumPmPageLink> pageLinks;
  final bool? hasUnread;
  final int currentPage;
  final String? nextPagePath;
}

class ForumPmDetail {
  const ForumPmDetail({
    required this.summary,
    required this.sender,
    required this.title,
    required this.time,
    required this.content,
    this.segments = const [],
    this.replyPath,
    this.forwardPath,
    this.editPath,
    this.chatlogPath,
    this.markUnreadPath,
    this.deletePath,
    this.hasUnread,
  });
  final ForumPmSummary summary;
  final String sender;
  final String title;
  final String time;
  final String content;
  final List<ThreadContentSegment> segments;
  final String? replyPath;
  final String? forwardPath;
  final String? editPath;
  final String? chatlogPath;
  final String? markUnreadPath;
  final String? deletePath;
  final bool? hasUnread;
}

class ForumPmCompose {
  ForumPmCompose({
    required this.actionPath,
    required Map<String, String> fields,
    this.recipientUid = '',
    this.title = '',
    this.body = '',
    this.saveToSendbox = false,
    this.isEdit = false,
  }) : fields = Map.unmodifiable(fields);

  final String actionPath;
  final Map<String, String> fields;
  final String recipientUid;
  final String title;
  final String body;
  final bool saveToSendbox;
  final bool isEdit;
}

class ForumPmChatRecord {
  const ForumPmChatRecord({
    this.id,
    required this.sender,
    required this.title,
    required this.time,
    required this.content,
    this.segments = const [],
  });
  final String? id;
  final String sender;
  final String title;
  final String time;
  final String content;
  final List<ThreadContentSegment> segments;
}

class ForumPmChatlog {
  const ForumPmChatlog({
    required this.records,
    this.pageLinks = const [],
    this.composePath,
    this.currentPage = 1,
    this.nextPagePath,
  });
  final List<ForumPmChatRecord> records;
  final List<ForumPmPageLink> pageLinks;
  final String? composePath;
  final int currentPage;
  final String? nextPagePath;
}

class ForumPmActionResult {
  const ForumPmActionResult({required this.message, this.refreshPath});
  final String message;
  final String? refreshPath;
}
