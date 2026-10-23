import 'package:flutter/material.dart';

import '../../services/watch_notifications.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';

/// One line while system notifications are off. 开启 asks; once asking has
/// been refused, 去设置 opens the system settings, and only when tapped.
class NotificationPermissionRow extends StatefulWidget {
  const NotificationPermissionRow({super.key, required this.watch});

  final WatchService watch;

  @override
  State<NotificationPermissionRow> createState() =>
      _NotificationPermissionRowState();
}

class _NotificationPermissionRowState extends State<NotificationPermissionRow> {
  // Android may stop showing its prompt; a refusal is all the app can see.
  bool _refused = false;

  Future<void> _enable() async {
    final watch = widget.watch;
    if (_refused) {
      await watch.notifications.openSettings();
      return;
    }
    await watch.requestNotifications();
    if (mounted &&
        watch.notificationPermission == WatchNotificationPermission.denied) {
      setState(() => _refused = true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.watch,
        builder: (context, _) {
          if (widget.watch.notificationPermission !=
              WatchNotificationPermission.denied) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding:
                const EdgeInsets.only(left: AppSpace.lg, right: AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '系统通知未开启',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _enable,
                  child: Text(_refused ? '去设置' : '开启'),
                ),
              ],
            ),
          );
        },
      );
}
