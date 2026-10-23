import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import 'async_state_view.dart';

/// A pushed page holding one account's private content (a message, a draft).
///
/// When the signed-in account changes while it is open, [child] is removed
/// in that frame: nothing of it is painted, read aloud or tapped again, its
/// drafts go with it, and answers still on their way land nowhere. Sheets and
/// dialogs opened from it close too. The page then says why it is empty.
class SessionBound extends StatefulWidget {
  const SessionBound({
    super.key,
    required this.repository,
    required this.title,
    required this.child,
  });

  final ForumRepository repository;

  /// The app bar title kept on the emptied page.
  final String title;
  final Widget child;

  @override
  State<SessionBound> createState() => _SessionBoundState();
}

class _SessionBoundState extends State<SessionBound> {
  // Read when the page opens, before any change can be heard.
  late final String? _user;
  late final int _epoch;
  late final Listenable _signals;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    _user = repository.sessionUser.value;
    _epoch = repository.sessionEpoch.value;
    _signals =
        Listenable.merge([repository.sessionUser, repository.sessionEpoch]);
    _signals.addListener(_onSession);
  }

  void _onSession() {
    if (_ended ||
        (widget.repository.sessionUser.value == _user &&
            widget.repository.sessionEpoch.value == _epoch)) {
      return;
    }
    setState(() => _ended = true);
    // Only from a page still in the history: one already leaving (closed by
    // a private page below it) has nothing above it to close.
    final route = ModalRoute.of(context);
    if (route != null && route.isActive && !route.isCurrent) {
      Navigator.of(context).popUntil((r) => r == route);
    }
  }

  @override
  void dispose() {
    _signals.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ended) return widget.child;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: EmptyStateView(
        icon: Icons.lock_outline,
        title: '账号已切换',
        action: FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('返回'),
        ),
      ),
    );
  }
}
