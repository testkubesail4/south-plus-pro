import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../board/board_thread_list_screen.dart';
import '../profile/user_profile_screen.dart';
import '../thread/thread_detail_screen.dart';

/// Opens a content link: forum threads, profiles and boards (on any mirror)
/// in-app on the configured mirror, other pages externally, unsafe ones never.
Future<void> openForumLink(
  BuildContext context,
  ForumRepository repository,
  String url, {
  String label = '',
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final title = label.trim();
  switch (repository.forumLinkTarget(url)) {
    case ForumThreadLinkTarget(:final url):
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => ThreadDetailScreen(
          thread: ForumThread(
            title: title.isEmpty || title == url ? '帖子' : title,
            url: url,
            replies: 0,
            section: '',
          ),
          repository: repository,
        ),
      ));
    case ForumUserLinkTarget(:final userUrl, :final tab):
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          userUrl: userUrl,
          repository: repository,
          initialTab: tab,
        ),
      ));
    case ForumBoardLinkTarget(:final category):
      // Link text can say anything; the board page names the board.
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => BoardThreadListScreen(
          category: category,
          repository: repository,
        ),
      ));
    case ForumPageLinkTarget(:final url):
      // Forum pages without a native screen may perform account actions,
      // so the browser hand-off is explicit.
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('在浏览器中打开'),
          content: SelectableText(url),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('打开'),
            ),
          ],
        ),
      );
      if (open != true) return;
      try {
        // A real browser, never an app intent that could reopen this app.
        await ExternalLinkLauncher.openInBrowser(url);
      } on ExternalLinkLaunchException catch (error) {
        messenger.showSnackBar(SnackBar(
          content: Text(error.message),
          action: SnackBarAction(
            label: '复制链接',
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        ));
      }
    case ForumExternalLinkTarget(:final url):
      try {
        await ExternalLinkLauncher.open(url);
      } catch (error) {
        messenger.showSnackBar(SnackBar(content: Text('$error')));
      }
    case ForumBlockedLinkTarget():
      messenger.showSnackBar(
        const SnackBar(content: Text('已阻止不安全链接')),
      );
  }
}
