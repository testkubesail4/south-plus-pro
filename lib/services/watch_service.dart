import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/forum_models.dart';
import '../models/watch_models.dart';
import 'forum_client.dart';
import 'forum_url_resolver.dart';
import 'local_state_preferences.dart';
import 'watch_notifications.dart';
import 'watch_reader.dart';

class WatchLimitException implements Exception {
  const WatchLimitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WatchBudgetExhausted implements Exception {
  const WatchBudgetExhausted();
}

class _WatchStorageFailure implements Exception {}

class WatchSession {
  const WatchSession({
    required this.owner,
    required this.uid,
    required this.epoch,
    required this.client,
    required this.urls,
    required this.requireCurrent,
  });
  final String owner;
  final String uid;
  final int epoch;
  final ForumClient client;
  final ForumUrlResolver urls;
  final void Function() requireCurrent;
}

class WatchService extends ChangeNotifier with WidgetsBindingObserver {
  WatchService({
    required this.session,
    WatchNotifications? notifications,
    DateTime Function()? clock,
    this.checkNativeNotices,
    this.acceptNativeNoticeTap,
  }) : notifications = notifications ?? WatchNotifications(),
       clock = clock ?? DateTime.now;

  static const maxActiveRules = 10;
  static const maxStoredRules = 30;
  static const maxSends = 20;
  static const interval = Duration(minutes: 15);
  static const budgetWindow = Duration(minutes: 5);
  final WatchSession? Function() session;
  final WatchNotifications notifications;
  final DateTime Function() clock;
  final Future<DateTime?> Function(
    WatchSession,
    void Function(),
    void Function(),
  )?
  checkNativeNotices;
  final Future<bool> Function(Map<String, dynamic>)? acceptNativeNoticeTap;
  final _rules = <WatchRule>[];
  final _events = <WatchEvent>[];
  final _states = <String, Map<String, dynamic>>{};
  final _statuses = <String, WatchStatus>{};
  final _sends = <DateTime>[];
  String? _owner;
  int? _epoch;
  int _generation = 0;
  int _runGeneration = 0;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _nativeReset = Future.value();
  Future<void>? _checking;
  Future<void> _writes = Future.value();
  Future<void> _mutations = Future.value();
  final _sourceStatuses = <String, WatchStatus>{};
  WatchEvent? pendingOpen;
  NoticeNotificationKind? pendingNoticeOpen;
  DateTime? _nativePendingUntil;
  WatchNotificationPermission notificationPermission =
      WatchNotificationPermission.unsupported;
  DateTime? nextCheckAt;
  DateTime? pendingUntil;
  int progressDone = 0;
  int progressTotal = 0;

  List<WatchRule> get rules => List.unmodifiable(_rules);
  List<WatchEvent> get events => List.unmodifiable(_events.reversed);
  Map<String, WatchStatus> get statuses => Map.unmodifiable(_statuses);
  bool get running => _checking != null;
  int get activeCount => _rules.where((r) => !r.paused).length;
  int get unreadCount => _events.where((e) => e.unread).length;
  WatchRule? ruleFor(WatchScope scope, String subjectId) => _rules
      .where((r) => r.scope == scope && r.subjectId == subjectId)
      .firstOrNull;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    notifications.listen(() => _consumeTap().catchError((_) {}));
    if (_disposed || !_started) return;
    await _resumeCheck();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _foreground = false;
    _runGeneration++;
    _timer?.cancel();
    nextCheckAt = null;
    WidgetsBinding.instance.removeObserver(this);
    notifications.listen(null);
  }

  void sessionChanged() {
    if (_disposed) return;
    final current = session();
    if (current?.owner == _owner && current?.epoch == _epoch) return;
    final previousOwner = _owner;
    _generation++;
    _owner = current?.owner;
    _epoch = current?.epoch;
    _rules.clear();
    _events.clear();
    _states.clear();
    _statuses.clear();
    _sourceStatuses.clear();
    pendingOpen = null;
    pendingNoticeOpen = null;
    _nativePendingUntil = null;
    // The rolling budget is deliberately not reset by account/mirror changes.
    if (previousOwner != null)
      _nativeReset = _nativeReset.then((_) => notifications.cancelAll());
    final generation = _generation;
    _loading = current == null ? Future.value() : _load(current, generation);
    if (current == null) {
      _timer?.cancel();
      nextCheckAt = null;
    } else if (_started && _foreground) {
      final checking = _checking;
      if (checking == null || previousOwner != null) {
        unawaited(
          (checking ?? Future<void>.value()).catchError((_) {}).then((_) async {
            if (!_disposed && generation == _generation && _foreground)
              await checkNow().catchError((_) {});
          }),
        );
      }
    }
    notifyListeners();
  }

  String _key(String owner) => 'account/${Uri.encodeComponent(owner)}/watch_v1';

  Future<void> _load(WatchSession current, int generation) async {
    try {
      final raw = await LocalStatePreferences.read(
        (prefs) => prefs.getString(_key(current.owner)),
      );
      current.requireCurrent();
      if (generation != _generation || _disposed || raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rules = (decoded['rules'] as List)
          .map((r) => WatchRule.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
      if (rules.length > maxStoredRules ||
          rules.where((r) => !r.paused).length > maxActiveRules ||
          rules.map((r) => r.id).toSet().length != rules.length)
        throw const FormatException('Invalid rules');
      final events = (decoded['events'] as List)
          .map((e) => WatchEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .where(
            (e) =>
                rules.any((r) => r.id == e.ruleId) &&
                current.urls.forumLinkTarget(e.url) is ForumThreadLinkTarget,
          )
          .toList();
      final states = Map<String, dynamic>.from(decoded['states'] as Map);
      _rules.addAll(rules);
      _events.addAll(events);
      for (final entry in states.entries) {
        if (rules.any((r) => entry.key.startsWith('${r.id}/'))) {
          _states[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
    } catch (_) {
      if (generation != _generation || _disposed) return;
      // Keep malformed local state visible as a failure instead of replacing it.
      _statuses['storage'] = const WatchStatus(
        WatchPhase.unavailable,
        '关注数据无法读取，请重试或检查本机存储',
      );
    }
    if (generation == _generation && !_disposed) notifyListeners();
  }

  Future<WatchSession> _ready() async {
    sessionChanged();
    var pending = _loading;
    await pending;
    while (!_disposed && !identical(pending, _loading)) {
      pending = _loading;
      await pending;
    }
    final generation = _generation;
    await _nativeReset;
    if (!_disposed && generation != _generation) return _ready();
    final current = session();
    if (_disposed || current == null) throw StateError('登录后可使用本机关注');
    current.requireCurrent();
    if (_statuses.containsKey('storage'))
      throw StateError(_statuses['storage']!.reason);
    return current;
  }

  Future<void> _save(WatchSession current) {
    final generation = _generation;
    final payload = jsonEncode({
      'rules': _rules.map((r) => r.toJson()).toList(),
      'events': _events.map((e) => e.toJson()).toList(),
      'states': _states,
    });
    final operation = _writes.catchError((_) {}).then((_) async {
      current.requireCurrent();
      if (generation != _generation || _disposed) throw StateError('登录状态已改变');
      await LocalStatePreferences.write((prefs) {
        current.requireCurrent();
        return prefs.setString(_key(current.owner), payload);
      });
      current.requireCurrent();
    });
    _writes = operation;
    return operation;
  }

  Future<void> _mutate(void Function() change, {bool scheduleCheck = false}) {
    final initiating = session();
    if (initiating == null) return Future.error(StateError('登录后可使用本机关注'));
    final checking = _checking;
    final pending = _mutations.catchError((_) {}).then((_) async {
      initiating.requireCurrent();
      await checking?.catchError((_) {});
      initiating.requireCurrent();
      await _ready();
      initiating.requireCurrent();
      final current = initiating;
      final generation = _generation;
      final oldRules = List<WatchRule>.from(_rules);
      final oldEvents = List<WatchEvent>.from(_events);
      final oldStates = Map<String, Map<String, dynamic>>.from(_states);
      final oldStatuses = Map<String, WatchStatus>.from(_statuses);
      try {
        change();
        await _save(current);
      } catch (_) {
        if (generation == _generation && !_disposed) {
          _rules
            ..clear()
            ..addAll(oldRules);
          _events
            ..clear()
            ..addAll(oldEvents);
          _states
            ..clear()
            ..addAll(oldStates);
          _statuses
            ..clear()
            ..addAll(oldStatuses);
        }
        rethrow;
      }
      if (!_disposed) {
        notifyListeners();
        if (scheduleCheck) _schedule(Duration.zero);
      }
    });
    _mutations = pending;
    return pending;
  }

  Future<void> addRule(WatchRule rule) => _mutate(() {
    if (_rules.any((r) => r.id == rule.id)) throw ArgumentError('关注 ID 已存在');
    if (_rules.length >= maxStoredRules)
      throw const WatchLimitException('最多保存 30 条关注，请先删除一条');
    if (!rule.paused && activeCount >= maxActiveRules)
      throw const WatchLimitException('最多启用 10 条关注，请先暂停或删除一条');
    _rules.add(rule);
    _statuses[rule.id] = WatchStatus(
      rule.paused ? WatchPhase.paused : WatchPhase.baseline,
      rule.paused ? '已暂停，保留检查进度' : '等待建立可见快照，不发送历史动态',
    );
  }, scheduleCheck: true);

  void _replaceRule(WatchRule rule) {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index < 0) throw ArgumentError('关注不存在');
    final old = _rules[index];
    if (old.paused && !rule.paused && activeCount >= maxActiveRules)
      throw const WatchLimitException('最多启用 10 条关注');
    _rules[index] = rule;
    final before = Map<String, dynamic>.from(old.toJson())
      ..remove('paused')
      ..remove('notificationsEnabled');
    final after = Map<String, dynamic>.from(rule.toJson())
      ..remove('paused')
      ..remove('notificationsEnabled');
    if (jsonEncode(before) != jsonEncode(after))
      _states.removeWhere((k, _) => k.startsWith('${rule.id}/'));
    _statuses[rule.id] = WatchStatus(
      rule.paused ? WatchPhase.paused : WatchPhase.pending,
      rule.paused ? '已暂停，保留检查进度' : '等待继续检查',
    );
  }

  Future<void> updateRule(WatchRule rule) =>
      _mutate(() => _replaceRule(rule), scheduleCheck: true);

  Future<void> setPaused(String id, bool paused) => _mutate(() {
    final rule = _rules.where((r) => r.id == id).firstOrNull;
    if (rule != null) _replaceRule(rule.copyWith(paused: paused));
  }, scheduleCheck: true);

  Future<void> removeRule(String id) => _mutate(() {
    _rules.removeWhere((r) => r.id == id);
    _events.removeWhere((e) => e.ruleId == id);
    _states.removeWhere((k, _) => k.startsWith('$id/'));
    _statuses.remove(id);
  }, scheduleCheck: true);

  Future<void> markRead(String eventId) => _mutate(() {
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index >= 0 && _events[index].unread)
      _events[index] = _events[index].read();
  });

  Future<void> markPostsSeen(
    String tid,
    Iterable<String> actualPositivePids, {
    bool openingSeen = false,
  }) => _mutate(() {
    final pids = actualPositivePids
        .where((p) => RegExp(r'^[1-9]\d*$').hasMatch(p))
        .toSet();
    for (var i = 0; i < _events.length; i++) {
      final event = _events[i];
      if (event.unread &&
          event.tid == tid &&
          (event.kind == WatchContentKind.replies
              ? pids.contains(event.pid)
              : openingSeen)) {
        _events[i] = event.read();
      }
    }
  });

  Future<void> requestNotifications() async {
    notificationPermission = await notifications.permission(request: true);
    if (!_disposed) notifyListeners();
  }

  void _charge() {
    final now = clock();
    _sends.removeWhere((t) => !t.add(budgetWindow).isAfter(now));
    if (_sends.length >= maxSends) {
      pendingUntil = _sends.first.add(budgetWindow);
      throw const WatchBudgetExhausted();
    }
    _sends.add(now);
  }

  Future<void> checkNow() {
    final existing = _checking;
    if (existing != null) return existing;
    if (_disposed || !_foreground) return Future.value();
    late Future<void> pending;
    pending = _check().whenComplete(() {
      if (identical(_checking, pending)) _checking = null;
      if (!_disposed) {
        notifyListeners();
        var next = clock().add(interval);
        for (final deadline in [pendingUntil, _nativePendingUntil]) {
          if (deadline != null && deadline.isBefore(next)) next = deadline;
        }
        _schedule(next.difference(clock()));
      }
    });
    _checking = pending;
    notifyListeners();
    return pending;
  }

  Future<void> _persistStep(
    WatchSession current,
    String key,
    Map<String, dynamic> state, {
    WatchEvent? event,
  }) async {
    final generation = _generation;
    final previous = _states[key];
    final fresh = event != null && !_events.any((e) => e.id == event.id);
    _states[key] = state;
    if (fresh) _events.add(event);
    try {
      await _save(current);
    } catch (_) {
      if (generation == _generation && !_disposed) {
        if (previous == null) {
          _states.remove(key);
        } else {
          _states[key] = previous;
        }
        if (fresh) _events.removeWhere((e) => e.id == event.id);
      }
      throw _WatchStorageFailure();
    }
  }

  Future<void> _resumeCheck() async {
    final permission = await notifications.permission();
    if (_disposed || !_started || !_foreground) return;
    if (permission != notificationPermission) {
      notificationPermission = permission;
      notifyListeners();
    }
    await _checking?.catchError((_) {});
    if (_disposed || !_started || !_foreground) return;
    await checkNow().catchError((_) {});
  }

  Future<void> _check() async {
    final runGeneration = _runGeneration;
    await _mutations.catchError((_) {});
    if (session() == null) {
      sessionChanged();
      return;
    }
    final current = await _ready();
    final generation = _generation;
    final cache = <String, Future<dom.Document>>{};
    void requireCurrent() {
      current.requireCurrent();
      if (_disposed ||
          !_foreground ||
          generation != _generation ||
          runGeneration != _runGeneration)
        throw StateError('关注检查已暂停');
    }

    Future<dom.Document> document(String path) {
      requireCurrent();
      final key = current.urls.baseUri
          .resolve(path)
          .removeFragment()
          .toString();
      return cache.putIfAbsent(key, () async {
        final response = await current.client.getWatch(
          path,
          requireCurrentSession: requireCurrent,
          beforeSend: _charge,
        );
        requireCurrent();
        return html.parse(response);
      });
    }

    final reader = WatchReader(
      urls: current.urls,
      getDocument: document,
      now: clock,
    );
    final jobs = [
      for (final r in _rules.where((r) => !r.paused))
        for (final k in r.kinds) (r, k),
    ];
    final done = <String>{};
    final failures = <String>{};
    void status(WatchRule rule, String key, WatchStatus value) {
      _sourceStatuses[key] = value;
      const severity = {
        WatchPhase.current: 0,
        WatchPhase.baseline: 1,
        WatchPhase.pending: 2,
        WatchPhase.incomplete: 3,
        WatchPhase.unavailable: 4,
        WatchPhase.paused: 5,
      };
      final sources = [
        for (final kind in rule.kinds)
          _sourceStatuses['${rule.id}/${kind.name}'] ??
              const WatchStatus(WatchPhase.pending, '仍有来源待检查，下次继续'),
      ];
      sources.sort((a, b) => severity[b.phase]!.compareTo(severity[a.phase]!));
      _statuses[rule.id] = sources.first;
    }

    progressDone = 0;
    progressTotal = jobs.length;
    pendingUntil = null;
    // Resume the least recently checked source first to avoid starving later rules.
    jobs.sort(
      (a, b) => ((_states['${a.$1.id}/${a.$2.name}']?['checked'] as int?) ?? 0)
          .compareTo(
            (_states['${b.$1.id}/${b.$2.name}']?['checked'] as int?) ?? 0,
          ),
    );
    await _consumeTap();
    requireCurrent();
    try {
      if (checkNativeNotices != null) {
        try {
          final deadline = await checkNativeNotices!(
            current,
            _charge,
            requireCurrent,
          );
          requireCurrent();
          _nativePendingUntil = deadline;
        } on WatchBudgetExhausted {
          rethrow;
        } catch (_) {
          requireCurrent();
          _nativePendingUntil = clock().add(budgetWindow);
        }
      }
      while (done.length + failures.length < jobs.length) {
        for (final (rule, kind) in jobs) {
          final key = '${rule.id}/${kind.name}';
          if (done.contains(key) || failures.contains(key)) continue;
          requireCurrent();
          if (!_rules.any((r) => identical(r, rule) && !r.paused)) {
            failures.add(key);
            continue;
          }
          final state = Map<String, dynamic>.from(
            jsonDecode(jsonEncode(_states[key] ?? {})) as Map,
          );
          try {
            final result = await reader.step(rule, kind, state);
            requireCurrent();
            if (!_rules.any((r) => identical(r, rule) && !r.paused)) {
              failures.add(key);
              continue;
            }
            state['checked'] = clock().millisecondsSinceEpoch;
            if (result.done) {
              done.add(key);
              progressDone++;
            }
            status(
              rule,
              key,
              WatchStatus(
                result.done
                    ? WatchPhase.current
                    : result.baseline
                    ? WatchPhase.baseline
                    : WatchPhase.pending,
                result.done
                    ? '已检查当前可见内容'
                    : result.baseline
                    ? '正在建立可见快照，期间不发送历史动态'
                    : '仍有页面或回复待检查，下次继续',
                checkedAt: clock(),
              ),
            );
            final event = result.event;
            final fresh =
                event != null && !_events.any((e) => e.id == event.id);
            await _persistStep(current, key, state, event: event);
            requireCurrent();
            if (fresh &&
                rule.notificationsEnabled &&
                event.confidence == WatchConfidence.certain &&
                event.authorUid != null &&
                event.authorUid != current.uid &&
                notificationPermission == WatchNotificationPermission.granted) {
              await notifications.show(current.owner, event);
              requireCurrent();
            }
          } on WatchBudgetExhausted {
            requireCurrent();
            status(
              rule,
              key,
              WatchStatus(
                WatchPhase.pending,
                '待继续（已达请求上限），保留未检查进度',
                checkedAt: clock(),
              ),
            );
            await _persistStep(current, key, state);
            rethrow;
          } on WatchIncomplete catch (error) {
            requireCurrent();
            status(
              rule,
              key,
              WatchStatus(
                WatchPhase.incomplete,
                error.reason,
                checkedAt: clock(),
              ),
            );
            failures.add(key);
            await _persistStep(current, key, state);
          } on _WatchStorageFailure {
            requireCurrent();
            status(
              rule,
              key,
              WatchStatus(
                WatchPhase.unavailable,
                '无法保存检查进度，请检查本机存储后重试',
                checkedAt: clock(),
              ),
            );
            rethrow;
          } catch (_) {
            requireCurrent();
            status(
              rule,
              key,
              WatchStatus(
                WatchPhase.unavailable,
                '页面暂时不可用，保留进度稍后重试',
                checkedAt: clock(),
              ),
            );
            failures.add(key);
            await _persistStep(current, key, state);
          }
          requireCurrent();
          notifyListeners();
        }
      }
    } on WatchBudgetExhausted {
      // A budget stop is pending, never an empty result or a new baseline.
    }
    requireCurrent();
    for (final r in _rules.where((r) => r.paused)) {
      _statuses[r.id] = const WatchStatus(WatchPhase.paused, '已暂停，保留检查进度');
    }
    await _consumeTap();
  }

  Future<void> _consumeTap() async {
    if (session() == null) return;
    final current = await _ready();
    final generation = _generation;
    final tap = await notifications.takeTap();
    current.requireCurrent();
    if (generation != _generation || _disposed) return;
    if (tap == null || tap['owner'] != current.owner) return;
    final kind = tap['kind'] ?? 'watch';
    if (kind == 'watch') {
      pendingOpen = _events.where((e) => e.id == tap['eventId']).firstOrNull;
      notifyListeners();
    } else if (NoticeNotificationKind.values.any(
          (value) => value.name == kind,
        ) &&
        acceptNativeNoticeTap != null) {
      final accepted = await acceptNativeNoticeTap!(tap);
      current.requireCurrent();
      if (generation != _generation || _disposed || !accepted) return;
      pendingNoticeOpen = NoticeNotificationKind.values.byName(kind as String);
      notifyListeners();
    }
  }

  WatchEvent? takePendingOpen() {
    final event = pendingOpen;
    pendingOpen = null;
    return event;
  }

  NoticeNotificationKind? takePendingNoticeOpen() {
    final kind = pendingNoticeOpen;
    pendingNoticeOpen = null;
    return kind;
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_started ||
        !_foreground ||
        _disposed ||
        session() == null ||
        (activeCount == 0 && checkNativeNotices == null)) {
      nextCheckAt = null;
      return;
    }
    final safe = delay < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : delay;
    nextCheckAt = clock().add(safe);
    _timer = Timer(safe, () {
      unawaited(checkNow().catchError((_) {}));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_resumeCheck());
    } else {
      _runGeneration++;
      _timer?.cancel();
      nextCheckAt = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      notifications.listen(null);
    }
    super.dispose();
  }
}
