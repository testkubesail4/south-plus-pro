import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../common/app_tab_header.dart';
import '../common/content_width.dart';
import '../profile/forum_preferences_screen.dart';
import 'pm_box_screen.dart';
import 'reply_notices_screen.dart';

/// The 消息 tab: the one home of 短消息 and 回复提醒, swipeable, each tab
/// dotted while it has something unread.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key, required this.repository});

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    // The dot follows the label instead of sitting on its last character.
    // The dot is announced too, since the Badge itself has no semantics.
    Widget tab(String label, bool unread) => Tab(
          child: Semantics(
            label: unread ? '$label，有未读' : label,
            child: ExcludeSemantics(
              // Very large text shrinks the label to its half of the bar.
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            AppTabHeader(
              title: '消息',
              actions: [
                if (repository.isLoggedIn)
                  IconButton(
                    tooltip: '短消息设置',
                    icon: const Icon(Icons.tune_outlined),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          ForumPreferencesScreen(repository: repository),
                    )),
                  ),
              ],
            ),
            // The tabs line up with the lists below them.
            AppContentWidth(
              maxWidth: AppWidths.list,
              child: ValueListenableBuilder<ForumNoticeFlags>(
                valueListenable: repository.noticeFlags,
                builder: (context, flags, _) => TabBar(
                  tabs: [
                    tab('短消息', flags.unreadPm),
                    tab('回复提醒', flags.replyNotice),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _KeepAlive(
                      PmBoxScreen(repository: repository, embedded: true)),
                  _KeepAlive(
                    ReplyNoticesScreen(repository: repository, embedded: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Swiping back shows the list as left, without a reload.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive(this.child);

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
