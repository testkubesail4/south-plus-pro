import 'dart:convert';

import '../models/forum_models.dart';
import '../models/forum_pm_models.dart';
import 'local_state_preferences.dart';
import 'parsers/forum_pm_parser.dart';
import 'watch_notifications.dart';
import 'watch_service.dart';

class _NativeSliceExhausted implements Exception {}

/// Native lists are read without opening a message or clearing a server reminder.
class NativeNoticeNotifications {
  NativeNoticeNotifications({
    required this.session,
    required this.refreshFlags,
    required this.loadInbox,
    required this.loadReplies,
    required this.notifications,
    this.onNotice,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final WatchSession? Function() session;
  final Future<ForumNoticeFlags> Function(WatchSession) refreshFlags;
  final Future<ForumPmPage> Function(String? path) loadInbox;
  final Future<List<ForumReplyNotice>> Function() loadReplies;
  final WatchNotifications notifications;
  final void Function(NoticeNotificationKind kind, int count, String? title)?
      onNotice;
  (int, String?)? _pmEventDetails;
  (int, String?)? _replyEventDetails;
  final DateTime Function() clock;
  static const maxSends = 8;
  static const window = Duration(minutes: 5);
  final _sends = <DateTime>[];
  String? _owner;
  int? _epoch;
  int _generation = 0;
  Map<String, dynamic> _state = {};
  Future<void>? _loading;
  bool _loadFailed = false;
  Object? lastError;

  String _key(String owner) =>
      'account/${Uri.encodeComponent(owner)}/native_notice_notifications_v1';

  void sessionChanged() {
    final current = session();
    if (current?.owner == _owner && current?.epoch == _epoch) return;
    _owner = current?.owner;
    _epoch = current?.epoch;
    _generation++;
    _state = {};
    _loadFailed = false;
    final generation = _generation;
    _loading = current == null ? Future.value() : _load(current, generation);
    // Do not reset the rolling reservation when accounts or mirrors change.
  }

  Future<void> _load(WatchSession scope, int generation) async {
    try {
      final raw = await LocalStatePreferences.read(
        (prefs) => prefs.getString(_key(scope.owner)),
      );
      scope.requireCurrent();
      if (generation != _generation) return;
      final state = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      for (final key in ['pmSeen', 'replyCurrent', 'pmSignatures']) {
        if (state[key] != null) (state[key] as List).cast<String>();
      }
      if (state['issued'] != null) {
        for (final record in state['issued'] as List) {
          if (record is! Map ||
              record['id'] is! String ||
              !NoticeNotificationKind.values.any(
                (kind) => kind.name == record['kind'],
              )) {
            throw const FormatException('Invalid native notice record');
          }
        }
      }
      _state = state;
      _loadFailed = false;
    } catch (_) {
      if (generation == _generation) _loadFailed = true;
    }
  }

  Future<void> _ready(WatchSession scope) async {
    scope.requireCurrent();
    sessionChanged();
    await _loading;
    scope.requireCurrent();
    if (_owner != scope.owner || _epoch != scope.epoch)
      throw StateError('登录状态已改变');
    if (_loadFailed) {
      await _load(scope, _generation);
      scope.requireCurrent();
      if (_loadFailed) throw StateError('无法读取通知去重记录');
    }
  }

  Map<String, dynamic> _copy() =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_state)) as Map);

  Future<void> _save(
    WatchSession scope,
    Map<String, dynamic> next,
    void Function() guard,
  ) async {
    guard();
    final generation = _generation;
    final previous = _state;
    final payload = jsonEncode(next);
    _state = next;
    try {
      await LocalStatePreferences.write((prefs) {
        guard();
        return prefs.setString(_key(scope.owner), payload);
      });
      guard();
    } catch (_) {
      if (generation == _generation) _state = previous;
      rethrow;
    }
  }

  String _issue(
    Map<String, dynamic> next,
    NoticeNotificationKind kind,
    List<String> sources,
  ) {
    final serial = (next['serial'] as int? ?? 0) + 1;
    next['serial'] = serial;
    final id = 'notice_${kind.name}_$serial';
    final issued = (next['issued'] ??= <Map<String, dynamic>>[]) as List;
    issued.add({'id': id, 'kind': kind.name, 'sources': sources});
    if (issued.length > 64) {
      final latest = <String, String>{};
      for (final record in issued) {
        latest[record['kind'] as String] = record['id'] as String;
      }
      final remove = issued.indexWhere(
        (record) => latest[record['kind']] != record['id'],
      );
      if (remove >= 0) issued.removeAt(remove);
    }
    return id;
  }

  int _page(String? path) {
    if (path == null) return 1;
    return int.tryParse(
          RegExp(r'(?:[?&-])page[-=]([1-9]\d*)').firstMatch(path)?.group(1) ??
              '',
        ) ??
        1;
  }

  Future<String?> _readPmPage(WatchSession scope, void Function() guard) async {
    final path = _state['pmNext'] as String?;
    final pageNumber = _page(path);
    final page = await loadInbox(path);
    guard();
    final parser = ForumPmParser(baseUri: scope.urls.baseUri);
    final nextPath = page.nextPagePath;
    if (page.box != ForumPmBox.inbox ||
        page.currentPage != pageNumber ||
        !page.paginationKnown ||
        (nextPath == null &&
            page.pageLinks.any((link) => _page(link.path) > pageNumber))) {
      throw const FormatException('Unconfirmed inbox pagination');
    }
    if (nextPath != null &&
        (parser.route(nextPath, {'receivebox'}) == null ||
            _page(nextPath) != pageNumber + 1)) {
      throw const FormatException('Invalid inbox continuation');
    }
    final keys = <String>[];
    for (final message in page.messages) {
      if (message.box != ForumPmBox.inbox ||
          !{
            ForumPmType.personal,
            ForumPmType.broadcast,
          }.contains(message.type) ||
          !RegExp(r'^[1-9]\d*$').hasMatch(message.id)) {
        throw const FormatException('Invalid native message identity');
      }
      keys.add('${message.type.name}:${message.id}');
    }
    final next = _copy();
    final baseline = next['pmInitialized'] != true;
    final signatures = path == null
        ? <String>[]
        : ((next['pmSignatures'] as List?) ?? const []).cast<String>().toList();
    final signature = keys.join(',');
    if (signature.isNotEmpty && signatures.contains(signature))
      throw const FormatException('Repeated inbox page');
    if (signature.isNotEmpty) signatures.add(signature);
    final seen = ((next['pmSeen'] as List?) ?? const []).cast<String>().toSet();
    final fresh = <String>[];
    for (var i = 0; i < page.messages.length; i++) {
      if (!baseline && !seen.contains(keys[i]) && page.messages[i].unread)
        fresh.add(keys[i]);
      seen.add(keys[i]);
    }
    next['pmSeen'] = seen.toList();
    next['pmNext'] = nextPath;
    next['pmSignatures'] = nextPath == null ? <String>[] : signatures;
    if (nextPath == null) next['pmInitialized'] = true;
    final id =
        fresh.isEmpty ? null : _issue(next, NoticeNotificationKind.pm, fresh);
    await _save(scope, next, guard);
    if (id != null) {
      _pmEventDetails = (
        fresh.length,
        page.messages[keys.indexOf(fresh.first)].title,
      );
    }
    return id;
  }

  String _replyKey(ForumReplyNotice notice) {
    if (notice.tid <= 0)
      throw const FormatException('Invalid reminder identity');
    final date = notice.date.trim().replaceAll(RegExp(r'\s+'), ' ');
    // A relative date is not a stable server event identity.
    final absolute = RegExp(
      r'^\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2}(?::\d{2})?)?$',
    ).hasMatch(date);
    return '${notice.tid}|${absolute ? date : ''}';
  }

  Future<String?> _readReplies(
    WatchSession scope,
    bool hasNotice,
    void Function() guard,
  ) async {
    final rows = hasNotice ? await loadReplies() : const <ForumReplyNotice>[];
    guard();
    final current = rows.map<String>(_replyKey).toSet();
    final next = _copy();
    final previous =
        ((next['replyCurrent'] as List?) ?? const []).cast<String>().toSet();
    final fresh = next['replyInitialized'] == true
        ? current.difference(previous).toList()
        : <String>[];
    next['replyCurrent'] =
        hasNotice ? previous.union(current).toList() : <String>[];
    next['replyInitialized'] = true;
    final id = fresh.isEmpty
        ? null
        : _issue(next, NoticeNotificationKind.reply, fresh);
    await _save(scope, next, guard);
    if (id != null) {
      _replyEventDetails = (
        fresh.length,
        rows.firstWhere((row) => _replyKey(row) == fresh.first).title,
      );
    }
    if (!hasNotice) {
      await notifications.cancelKind(scope.owner, NoticeNotificationKind.reply);
      guard();
    }
    return id;
  }

  /// Returns the earliest continuation time, leaving twelve sends for watch rules.
  Future<DateTime?> check(
    WatchSession scope,
    void Function() beforeSend,
    void Function() guard, {
    bool refreshInbox = false,
  }) async {
    lastError = null;
    String? pmEvent;
    String? replyEvent;
    _pmEventDetails = null;
    _replyEventDetails = null;
    var hasMore = false;
    DateTime? pendingUntil;
    try {
      await _ready(scope);
      guard();
      _sends.removeWhere((time) => !time.add(window).isAfter(clock()));
      if (_sends.length >= maxSends) return _sends.first.add(window);
      void reserve() {
        guard();
        _sends.removeWhere((time) => !time.add(window).isAfter(clock()));
        if (_sends.length >= maxSends) throw _NativeSliceExhausted();
        beforeSend();
        _sends.add(clock());
      }

      await scope.client.runNativeNoticeReads(
        () async {
          final flags = await refreshFlags(scope);
          guard();
          final needsPm = refreshInbox ||
              flags.unreadPm ||
              _state['pmInitialized'] != true ||
              _state['pmNext'] != null;
          if (needsPm) {
            try {
              pmEvent = await _readPmPage(scope, guard);
            } on _NativeSliceExhausted {
              rethrow;
            } on WatchBudgetExhausted {
              rethrow;
            } catch (error) {
              guard();
              lastError = error;
              hasMore = true;
            }
          }
          if (!flags.unreadPm) {
            await notifications.cancelKind(
              scope.owner,
              NoticeNotificationKind.pm,
            );
            guard();
          }
          // Both kinds get a turn before an inbox backlog consumes its reservation.
          try {
            replyEvent = await _readReplies(scope, flags.replyNotice, guard);
          } on _NativeSliceExhausted {
            rethrow;
          } on WatchBudgetExhausted {
            rethrow;
          } catch (error) {
            guard();
            lastError = error;
            hasMore = true;
          }
          while (_state['pmNext'] != null) {
            pmEvent = await _readPmPage(scope, guard) ?? pmEvent;
          }
        },
        requireCurrentSession: guard,
        beforeSend: reserve,
      );
    } on _NativeSliceExhausted {
      guard();
      hasMore = true;
      pendingUntil = _sends.first.add(window);
    } on WatchBudgetExhausted {
      rethrow;
    } catch (error) {
      guard();
      lastError = error;
      hasMore = true;
    } finally {
      guard();
      if (pmEvent != null && _pmEventDetails != null) {
        final details = _pmEventDetails!;
        onNotice?.call(NoticeNotificationKind.pm, details.$1, details.$2);
        guard();
      }
      if (replyEvent != null && _replyEventDetails != null) {
        final details = _replyEventDetails!;
        onNotice?.call(NoticeNotificationKind.reply, details.$1, details.$2);
        guard();
      }
      final permission = await notifications.permission();
      guard();
      if (permission == WatchNotificationPermission.granted) {
        if (pmEvent != null) {
          await notifications.showNotice(
            scope.owner,
            pmEvent!,
            NoticeNotificationKind.pm,
          );
          guard();
        }
        if (replyEvent != null) {
          await notifications.showNotice(
            scope.owner,
            replyEvent!,
            NoticeNotificationKind.reply,
          );
          guard();
        }
      }
    }
    return pendingUntil ??
        (hasMore || _state['pmNext'] != null ? clock().add(window) : null);
  }

  Future<bool> acceptTap(Map<String, dynamic> tap) async {
    final scope = session();
    if (scope == null || tap['owner'] != scope.owner) return false;
    await _ready(scope);
    scope.requireCurrent();
    final issued = (_state['issued'] as List?) ?? const [];
    return issued.any(
      (record) =>
          record['id'] == tap['eventId'] && record['kind'] == tap['kind'],
    );
  }

  Future<void> cancelKind(NoticeNotificationKind kind) async {
    final scope = session();
    if (scope == null) return;
    scope.requireCurrent();
    await _ready(scope);
    scope.requireCurrent();
    await notifications.cancelKind(scope.owner, kind);
    scope.requireCurrent();
  }
}
