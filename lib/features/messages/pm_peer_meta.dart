import 'package:flutter/material.dart';

import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../profile/user_profile_screen.dart';

/// `peer · time ...` for a message. The peer opens TA's 用户中心 only with a
/// positive native UID; SYSTEM, broadcasts and unknown peers stay plain.
class PmPeerMeta extends StatelessWidget {
  const PmPeerMeta({
    super.key,
    required this.repository,
    required this.peer,
    required this.peerUid,
    this.rest = const [],
  });

  final ForumRepository repository;
  final String peer;
  final String? peerUid;
  final List<String> rest;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final url = peer.isEmpty || peerUid == null
        ? null
        : repository.userProfileUrl(peerUid!);
    final tail = rest.where((part) => part.isNotEmpty).join(' · ');
    final Widget name;
    if (url == null) {
      name = Text(
        peer,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    } else {
      void open() => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                UserProfileScreen(userUrl: url, repository: repository),
          ));
      name = Semantics(
        button: true,
        label: '查看 $peer 的用户中心',
        // The label replaces the InkWell's node, so the tap is kept here.
        onTap: open,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: open,
          // A finger-sized target around a one-line name.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                peer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(
                  color: AppColors.link,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Plain meta keeps its usual one-line height.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: url == null ? 0 : 40),
      child: Row(
        children: [
          if (peer.isNotEmpty) Flexible(child: name),
          if (tail.isNotEmpty)
            Flexible(
              child: Text(
                peer.isEmpty ? tail : ' · $tail',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}
