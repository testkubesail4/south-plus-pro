import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/forum_models.dart';
import '../../services/external_link_launcher.dart';
import '../../services/forum_repository.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../home/home_shell.dart';
import '../messages/pm_box_screen.dart';
import '../messages/pm_compose_screen.dart';
import '../messages/pm_detail_screen.dart';
import '../profile/account_profile_edit_screen.dart';
import '../profile/forum_preferences_screen.dart';
import '../profile/forum_tasks_screen.dart';
import '../profile/friends_screen.dart';
import '../profile/user_profile_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';

/// Whether [url] belongs to a screen of this app; the rest go to a browser,
/// outside apps or nowhere.
bool forumLinkOpensInApp(ForumRepository repository, String url) =>
    repository.searchLinkPrefill(url) != null ||
    switch (repository.forumLinkTarget(url)) {
      ForumThreadLinkTarget() ||
      ForumUserLinkTarget() ||
      ForumBoardLinkTarget() ||
      ForumAppPageLinkTarget() =>
        true,
      ForumPageLinkTarget() ||
      ForumExternalLinkTarget() ||
      ForumBlockedLinkTarget() =>
        false,
    };

/// Opens a link: forum pages this app has a screen for (on any mirror)
/// in-app on the configured mirror, other forum pages in a browser after
/// asking, outside links externally, unsafe ones never. True when it
/// pushed an app page (not for a shell tab, which stays reselectable).
Future<bool> openForumLink(
  BuildContext context,
  ForumRepository repository,
  String url, {
  String label = '',
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  bool push(Widget screen) {
    navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
    return true;
  }

  // Search links prefill the form; the user still submits it.
  if (repository.searchLinkPrefill(url) case final prefill?) {
    final boardId = prefill.boardId;
    return push(SearchScreen(
      repository: repository,
      initialKeyword: prefill.keyword ?? '',
      initialUsername: prefill.username ?? '',
      initialBoard: boardId == null || boardId == 'all'
          ? null
          : ForumSearchBoard(id: boardId, name: ''),
    ));
  }
  final title = label.trim();
  switch (repository.forumLinkTarget(url)) {
    case ForumThreadLinkTarget(:final url):
      return push(ThreadDetailScreen(
        thread: ForumThread(
          title: title.isEmpty || title == url ? '帖子' : title,
          url: url,
          replies: 0,
          section: '',
        ),
        repository: repository,
      ));
    case ForumUserLinkTarget(:final userUrl, :final tab, :final isSelf):
      // A link to one's own page means nothing without an account.
      if (isSelf && !repository.isLoggedIn) {
        _showAccountNotice(context, repository);
        return false;
      }
      return push(UserProfileScreen(
        userUrl: userUrl,
        repository: repository,
        initialTab: tab,
      ));
    case ForumBoardLinkTarget(:final category):
      // Link text can say anything; the board page names the board.
      return push(BoardThreadListScreen(category: category, repository: repository));
    case final ForumAppPageLinkTarget target:
      // An account page stays in the app even when it cannot open: the
      // browser would show it with that browser's account, or reopen here.
      if (!repository.canOpenForumAppPage(target)) {
        _showAccountNotice(context, repository);
        return false;
      }
      switch (target.page) {
        // The shell's own tabs: back to the root, not a second copy.
        case ForumAppPage.home:
          HomeShell.showTab(context, HomeShell.homeTab);
          return false;
        case ForumAppPage.account:
          HomeShell.showTab(context, HomeShell.accountTab);
          return false;
        case final page:
          return push(_appPage(repository, page, target));
      }
    case ForumPageLinkTarget(:final url):
      // Forum pages without a screen here may perform account actions, so
      // the browser hand-off is explicit.
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
      if (open != true) return false;
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
  return false;
}

Widget _appPage(
  ForumRepository repository,
  ForumAppPage page,
  ForumAppPageLinkTarget target,
) =>
    switch (page) {
      ForumAppPage.friends => FriendsScreen(
          repository: repository, initialPage: target.pageNumber),
      ForumAppPage.friendRequests => FriendsScreen(
          repository: repository,
          initialPending: true,
          initialPage: target.pageNumber,
        ),
      // The native path keeps the box and page it names.
      ForumAppPage.pmInbox ||
      ForumAppPage.pmSendbox ||
      ForumAppPage.pmScout =>
        PmBoxScreen(repository: repository, initialPath: target.url),
      ForumAppPage.pmDetail =>
        PmDetailScreen(repository: repository, message: target.pmMessage!),
      ForumAppPage.pmChatlog =>
        PmChatlogScreen(repository: repository, path: target.url),
      ForumAppPage.pmCompose =>
        PmComposeScreen(repository: repository, path: target.url),
      ForumAppPage.forumPreferences =>
        ForumPreferencesScreen(repository: repository),
      ForumAppPage.profileEdit =>
        AccountProfileEditScreen(repository: repository),
      ForumAppPage.forumTasks => ForumTasksScreen(
          repository: repository,
          initialStatus: target.taskStatus ?? ForumTaskStatus.inProgress,
        ),
      // Shown as shell tabs by the caller.
      ForumAppPage.home || ForumAppPage.account => const SizedBox.shrink(),
    };

void _showAccountNotice(BuildContext context, ForumRepository repository) {
  final signedIn = repository.isLoggedIn;
  // The page under the snack bar may be gone when 登录 is tapped.
  final rootContext = Navigator.of(context, rootNavigator: true).context;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(signedIn ? '无法确认这是当前账号的页面' : '登录后才能打开这个页面'),
      action: signedIn
          ? null
          : SnackBarAction(
              label: '登录',
              onPressed: () => openLogin(rootContext, repository),
            ),
    ));
}
