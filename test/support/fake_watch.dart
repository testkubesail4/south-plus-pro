import 'package:south_plus_rewrite/models/watch_models.dart';
import 'package:south_plus_rewrite/services/watch_notifications.dart';
import 'package:south_plus_rewrite/services/watch_service.dart';

/// An in-memory [WatchService] for UI tests: no session, no requests, no
/// timers; it records what the UI asked for.
class FakeWatch extends WatchService {
  FakeWatch({
    List<WatchRule> rules = const [],
    List<WatchEvent> events = const [],
    Map<String, WatchStatus> statuses = const {},
    super.notifications,
  })  : _fakeRules = [...rules],
        _fakeEvents = [...events],
        _fakeStatuses = {...statuses},
        super(session: () => null);

  final List<WatchRule> _fakeRules;
  final List<WatchEvent> _fakeEvents;
  final Map<String, WatchStatus> _fakeStatuses;
  final seen = <(String, List<String>, bool)>[];
  final read = <String>[];
  int checks = 0;
  Object? markReadError;
  bool isRunning = false;
  bool grantOnRequest = true;

  @override
  List<WatchRule> get rules => List.unmodifiable(_fakeRules);

  @override
  List<WatchEvent> get events => List.unmodifiable(_fakeEvents);

  @override
  Map<String, WatchStatus> get statuses => Map.unmodifiable(_fakeStatuses);

  @override
  bool get running => isRunning;

  @override
  int get activeCount => _fakeRules.where((rule) => !rule.paused).length;

  @override
  int get unreadCount => _fakeEvents.where((event) => event.unread).length;

  @override
  Future<void> start() async {}

  @override
  Future<void> checkNow() async => checks++;

  @override
  Future<void> addRule(WatchRule rule) async {
    if (!rule.paused && activeCount >= WatchService.maxActiveRules) {
      throw const WatchLimitException('最多启用 10 条关注，请先暂停或删除一条');
    }
    _fakeRules.add(rule);
    notifyListeners();
  }

  @override
  Future<void> updateRule(WatchRule rule) async {
    final index = _fakeRules.indexWhere((r) => r.id == rule.id);
    _fakeRules[index] = rule;
    notifyListeners();
  }

  @override
  Future<void> setPaused(String id, bool paused) async {
    final index = _fakeRules.indexWhere((r) => r.id == id);
    _fakeRules[index] = _fakeRules[index].copyWith(paused: paused);
    notifyListeners();
  }

  @override
  Future<void> removeRule(String id) async {
    _fakeRules.removeWhere((r) => r.id == id);
    _fakeEvents.removeWhere((e) => e.ruleId == id);
    notifyListeners();
  }

  @override
  Future<void> markRead(String eventId) async {
    if (markReadError case final error?) throw error;
    read.add(eventId);
    final index = _fakeEvents.indexWhere((e) => e.id == eventId);
    if (index >= 0) _fakeEvents[index] = _fakeEvents[index].read();
    notifyListeners();
  }

  @override
  Future<void> markPostsSeen(
    String tid,
    Iterable<String> actualPositivePids, {
    bool openingSeen = false,
  }) async {
    seen.add((tid, [...actualPositivePids], openingSeen));
  }

  @override
  Future<void> requestNotifications() async {
    if (grantOnRequest) {
      notificationPermission = WatchNotificationPermission.granted;
    }
    notifyListeners();
  }

  /// As if a 短消息 or 回复提醒 system notification was tapped.
  void tapNotice(NoticeNotificationKind kind) {
    pendingNoticeOpen = kind;
    notifyListeners();
  }

  /// As if a system notification for [event] was tapped.
  void tap(WatchEvent event) {
    pendingOpen = event;
    notifyListeners();
  }
}
