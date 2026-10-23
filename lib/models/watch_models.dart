enum WatchScope { thread, user, board }

enum WatchContentKind { topics, replies, favorites }

enum WatchKeywordField { title, body }

enum WatchConfidence { certain, probable, incomplete, unavailable }

enum WatchPhase { baseline, pending, current, incomplete, unavailable, paused }

class WatchRule {
  WatchRule({
    required this.id,
    required this.scope,
    required this.subjectId,
    required this.label,
    Set<WatchContentKind> kinds = const {WatchContentKind.replies},
    this.involvingUid,
    this.keyword = '',
    this.keywordField = WatchKeywordField.title,
    this.paused = false,
    this.notificationsEnabled = true,
  }) : kinds = Set.unmodifiable(kinds) {
    final positive = RegExp(r'^[1-9]\d*$');
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        !positive.hasMatch(subjectId) ||
        (involvingUid != null && !positive.hasMatch(involvingUid!)) ||
        kinds.isEmpty ||
        label.length > 500 ||
        keyword.length > 200 ||
        (scope == WatchScope.thread &&
            (kinds.length != 1 || !kinds.contains(WatchContentKind.replies))) ||
        (scope == WatchScope.board &&
            (kinds.length != 1 ||
                !kinds.contains(WatchContentKind.topics) ||
                keyword.trim().isEmpty ||
                keywordField != WatchKeywordField.title ||
                involvingUid != null)) ||
        (scope == WatchScope.user &&
            involvingUid != null &&
            (kinds.length != 1 || !kinds.contains(WatchContentKind.replies)))) {
      throw ArgumentError('无效的关注条件');
    }
  }

  final String id;
  final WatchScope scope;
  final String subjectId;
  final String label;
  final Set<WatchContentKind> kinds;
  final String? involvingUid;
  final String keyword;
  final WatchKeywordField keywordField;
  final bool paused;
  final bool notificationsEnabled;

  WatchRule copyWith({bool? paused}) => WatchRule(
        id: id,
        scope: scope,
        subjectId: subjectId,
        label: label,
        kinds: kinds,
        involvingUid: involvingUid,
        keyword: keyword,
        keywordField: keywordField,
        paused: paused ?? this.paused,
        notificationsEnabled: notificationsEnabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'scope': scope.name,
        'subjectId': subjectId,
        'label': label,
        'kinds': kinds.map((k) => k.name).toList(),
        'involvingUid': involvingUid,
        'keyword': keyword,
        'keywordField': keywordField.name,
        'paused': paused,
        'notificationsEnabled': notificationsEnabled,
      };

  factory WatchRule.fromJson(Map<String, dynamic> json) => WatchRule(
        id: json['id'] as String,
        scope: WatchScope.values.byName(json['scope'] as String),
        subjectId: json['subjectId'] as String,
        label: json['label'] as String,
        kinds: (json['kinds'] as List)
            .map((k) => WatchContentKind.values.byName(k as String))
            .toSet(),
        involvingUid: json['involvingUid'] as String?,
        keyword: json['keyword'] as String,
        keywordField: WatchKeywordField.values.byName(
          json['keywordField'] as String,
        ),
        paused: json['paused'] as bool,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      );
}

class WatchEvent {
  const WatchEvent({
    required this.id,
    required this.ruleId,
    required this.title,
    required this.url,
    required this.kind,
    required this.confidence,
    required this.reason,
    required this.detectedAt,
    this.authorUid,
    this.unread = true,
  });

  final String id;
  final String ruleId;
  final String title;
  final String url;
  final WatchContentKind kind;
  final WatchConfidence confidence;
  final String reason;
  final DateTime detectedAt;
  final String? authorUid;
  final bool unread;
  String get tid =>
      RegExp(r'(?:[?&-])tid[-=]([1-9]\d*)').firstMatch(url)?.group(1) ?? '';
  String? get pid => Uri.tryParse(url)?.fragment.isNotEmpty == true
      ? Uri.parse(url).fragment
      : RegExp(r'(?:[?&-])pid[-=]([1-9]\d*)').firstMatch(url)?.group(1);

  WatchEvent read() => WatchEvent(
        id: id,
        ruleId: ruleId,
        title: title,
        url: url,
        kind: kind,
        confidence: confidence,
        reason: reason,
        detectedAt: detectedAt,
        authorUid: authorUid,
        unread: false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleId': ruleId,
        'title': title,
        'url': url,
        'kind': kind.name,
        'confidence': confidence.name,
        'reason': reason,
        'detectedAt': detectedAt.toIso8601String(),
        'authorUid': authorUid,
        'unread': unread,
      };

  factory WatchEvent.fromJson(Map<String, dynamic> json) => WatchEvent(
        id: json['id'] as String,
        ruleId: json['ruleId'] as String,
        title: json['title'] as String,
        url: json['url'] as String,
        kind: WatchContentKind.values.byName(json['kind'] as String),
        confidence: WatchConfidence.values.byName(json['confidence'] as String),
        reason: json['reason'] as String,
        detectedAt: DateTime.parse(json['detectedAt'] as String),
        authorUid: json['authorUid'] as String?,
        unread: json['unread'] as bool,
      );
}

class WatchStatus {
  const WatchStatus(this.phase, this.reason, {this.checkedAt});
  final WatchPhase phase;
  final String reason;
  final DateTime? checkedAt;
}
