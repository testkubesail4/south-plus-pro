import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../services/watch_notifications.dart';
import '../../theme/app_theme.dart';
import '../common/app_tab_header.dart';
import '../common/content_width.dart';
import '../profile/forum_preferences_screen.dart';
import '../watch/watch_tab.dart';
import 'notification_permission_row.dart';
import 'pm_box_screen.dart';
import 'reply_notices_screen.dart';

/// The 消息 tab: the one home of 短消息, 回复提醒 and 关注, swipeable, each
/// tab dotted while it has something unread.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.repository});

  final ForumRepository repository;

  /// The 关注 tab's index.
  static const watchTab = 2;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with SingleTickerProviderStateMixin {
  ForumRepository get repository => widget.repository;
  late final _tabs = TabController(length: 3, vsync: this);
  // Bumped by a tapped notification, which reloads that list from the top.
  var _pmLoads = 0;
  var _replyLoads = 0;
  bool? _shown;

  @override
  void initState() {
    super.initState();
    repository.watch.addListener(_onWatch);
    _tabs.addListener(_cancelShownKind);
    _onWatch(building: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.of(context);
    if (shown == _shown) return;
    _shown = shown;
    _cancelShownKind();
  }

  @override
  void dispose() {
    repository.watch.removeListener(_onWatch);
    _tabs.dispose();
    super.dispose();
  }

  // A tapped system notification turns to its tab: 关注 opens the 动态;
  // 短消息 and 回复提醒 reload their lists, opening and reading nothing.
  void _onWatch({bool building = false}) {
    final watch = repository.watch;
    if (watch.pendingOpen != null) {
      _tabs.animateTo(MessagesScreen.watchTab);
    }
    if (watch.pendingNoticeOpen == null) return;
    final kind = watch.takePendingNoticeOpen();
    if (kind == null) return;
    void reload() =>
        kind == NoticeNotificationKind.pm ? _pmLoads++ : _replyLoads++;
    building ? reload() : setState(reload);
    _tabs.animateTo(kind == NoticeNotificationKind.pm ? 0 : 1);
  }

  // A list on screen is seen: its system notification has done its job.
  void _cancelShownKind() {
    if (_shown != true || _tabs.indexIsChanging) return;
    final kind = switch (_tabs.index) {
      0 => NoticeNotificationKind.pm,
      1 => NoticeNotificationKind.reply,
      _ => null,
    };
    if (kind != null) {
      // Best effort: a stale account or unreadable ledger leaves the shade as
      // it is, and the tap or the next visit clears it.
      unawaited(
        repository.nativeNotifications.cancelKind(kind).catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The dot follows the label instead of sitting on its last character.
    // The dot is announced too, since the Badge itself has no semantics.
    Widget tab(String label, bool unread) => Tab(
          child: Semantics(
            label: unread ? '$label，有未读' : label,
            child: ExcludeSemantics(
              // Very large text shrinks the label to its share of the bar.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    const SizedBox(width: 2),
                    Badge(isLabelVisible: unread),
                  ],
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      body: Column(
        children: [
          AppTabHeader(
            title: '消息',
            actions: [
              if (repository.isLoggedIn)
                IconButton(
                  tooltip: '短消息设置',
                  icon: const Icon(Icons.tune_outlined),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ForumPreferencesScreen(repository: repository),
                  )),
                ),
            ],
          ),
          // The tabs line up with the lists below them.
          AppContentWidth(
            maxWidth: AppWidths.list,
            child: ListenableBuilder(
              listenable:
                  Listenable.merge([repository.noticeFlags, repository.watch]),
              builder: (context, _) {
                final flags = repository.noticeFlags.value;
                return TabBar(
                  controller: _tabs,
                  tabs: [
                    tab('短消息', flags.unreadPm),
                    tab('回复提醒', flags.replyNotice),
                    tab('关注', repository.watch.unreadCount > 0),
                  ],
                );
              },
            ),
          ),
          AppContentWidth(
            maxWidth: AppWidths.list,
            child: NotificationPermissionRow(watch: repository.watch),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _KeepAlive(
                  key: ValueKey(('pm', _pmLoads)),
                  PmBoxScreen(repository: repository, embedded: true),
                ),
                _KeepAlive(
                  key: ValueKey(('reply', _replyLoads)),
                  ReplyNoticesScreen(repository: repository, embedded: true),
                ),
                _KeepAlive(WatchTab(repository: repository)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Swiping back shows the list as left, without a reload.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child, {super.key});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
