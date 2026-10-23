import 'package:flutter/material.dart';

import '../../models/forum_friend_models.dart';
import '../../services/forum_repository.dart';
import '../../services/loading_preferences.dart';
import '../../theme/app_theme.dart';
import '../common/app_switcher.dart';
import '../common/async_state_view.dart';
import '../common/cached_forum_image.dart';
import '../common/content_width.dart';
import '../common/forum_pager.dart';
import '../common/grouped_list.dart';
import '../common/more_pages.dart';
import '../common/page_end.dart';
import '../common/sub_tabs.dart';
import 'forum_preferences_screen.dart';
import 'user_profile_screen.dart';

/// The signed-in user's 好友 and 待验证 lists, as the forum's 好友 tab.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.repository,
    this.initialPending = false,
    this.initialPage = 1,
  });

  final ForumRepository repository;
  final bool initialPending;

  /// The page of the initial list (a forum link can name one).
  final int initialPage;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late bool _pending = widget.initialPending;
  late final _pages = {
    false: widget.initialPending ? 1 : widget.initialPage,
    true: widget.initialPending ? widget.initialPage : 1,
  };
  // Each list's first page once read, the pages 自动接续 appended after it,
  // and its scroll.
  final _first = <bool, ForumFriendPage?>{false: null, true: null};
  final _reads = {false: 0, true: 0};
  late final _more = {
    for (final pending in [false, true]) pending: _pagesAfter(pending)
  };
  final _scrolls = {false: ScrollController(), true: ScrollController()};
  late final _futures = {
    false: _fetch(false),
    true: _fetch(true),
  };
  // Rows with a request in flight; their actions stay disabled.
  final Set<String> _busy = {};
  // The session changed: the lists may be another account's, so they stay
  // hidden until the user reloads in the settled session.
  bool _sessionChanged = false;

  @override
  void initState() {
    super.initState();
    widget.repository.sessionEpoch.addListener(_onSessionChanged);
    for (final pending in [false, true]) {
      _scrolls[pending]!.addListener(() => _maybeLoadMore(pending));
    }
    LoadingPreferences.notifier.addListener(_onLoadingModeChanged);
    if (!LoadingPreferences.isReady) LoadingPreferences.load().ignore();
  }

  @override
  void dispose() {
    widget.repository.sessionEpoch.removeListener(_onSessionChanged);
    LoadingPreferences.notifier.removeListener(_onLoadingModeChanged);
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  MorePages<ForumFriendPage> _pagesAfter(bool pending) => MorePages(
        domain: LoadingDomain.friends,
        fetch: (page) => widget.repository
            .fetchFriends(pending: pending, page: int.parse(page)),
        nextOf: (page) =>
            page.page < page.pageCount ? '${page.page + 1}' : null,
        idsOf: (page) => [for (final friend in page.items) friend.uid],
        changed: () {
          if (mounted) setState(() {});
        },
      );

  // Not while a write runs: its reload starts the lists over.
  void _maybeLoadMore(bool pending) {
    if (_busy.isEmpty) {
      _more[pending]!.maybeLoad(_first[pending], _scrolls[pending]!);
    }
  }

  // The footer follows the mode; a page already on its way still lands.
  // 自动接续 starts at the next scroll to the end, never by itself.
  void _onLoadingModeChanged() {
    if (mounted) setState(() {});
  }

  Future<ForumFriendPage> _fetch(bool pending) {
    final read = _reads[pending] = _reads[pending]! + 1;
    _first[pending] = null;
    _more[pending]!.reset();
    return widget.repository
        .fetchFriends(pending: pending, page: _pages[pending]!)
        .then((page) {
      if (mounted && read == _reads[pending]) {
        _first[pending] = page;
        // A page too short to scroll reads on by itself.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeLoadMore(pending));
      }
      return page;
    });
  }

  // No automatic reload: the session may still be switching cookies.
  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {
      _sessionChanged = true;
      _busy.clear();
      _pages.updateAll((_, __) => 1);
      for (final more in _more.values) {
        more.reset();
      }
    });
  }

  bool _current(int epoch) =>
      mounted && epoch == widget.repository.sessionEpoch.value;

  /// Reloads both lists: a reply to a request can change the friend list.
  Future<void> _reloadAll() async {
    setState(() {
      _sessionChanged = false;
      _futures.updateAll((pending, _) => _fetch(pending));
    });
    try {
      await _futures[_pending];
    } catch (_) {
      // The FutureBuilder shows the failure.
    }
  }

  void _openPage(int page) {
    setState(() {
      _pages[_pending] = page;
      _futures[_pending] = _fetch(_pending);
    });
  }

  Widget _footer(ForumFriendPage first, MorePages<ForumFriendPage> more) {
    final last = more.pages.isEmpty ? first : more.pages.last;
    final next = last.page < last.pageCount ? last.page + 1 : null;
    return PageEndFooter(
      next: next,
      manual: !more.continuous,
      loading: more.loading,
      failed: more.error != null,
      error: more.error,
      paused: more.paused,
      // 手动翻页 turns to the next page alone; 自动接续 appends.
      onNext: next == null
          ? null
          : !more.continuous
              ? () => _openPage(next)
              : () => more.retry(first, _scrolls[_pending]!),
    );
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Runs [run] unless the session moved on since [epoch], when the user
  /// started the action (a dialog may have stayed open across a switch).
  Future<void> _mutate(
    int epoch,
    ForumFriend friend,
    Future<ForumFriendMutationResult> Function() run,
    String done,
  ) async {
    if (!_current(epoch) || _sessionChanged) return;
    setState(() {
      _busy.add(friend.uid);
      // A page on its way was read before the write: it is not appended.
      for (final more in _more.values) {
        more.cancelPending();
      }
    });
    try {
      final result = await run();
      if (!_current(epoch)) return;
      _toast(result.confirmed
          ? done
          : result.message.isEmpty
              ? '论坛没有确认这次操作'
              : result.message);
    } catch (error) {
      if (!_current(epoch)) return;
      _toast('操作失败，${forumErrorText(error)}');
    }
    if (!_current(epoch)) return;
    _busy.remove(friend.uid);
    await _reloadAll();
  }

  Future<void> _delete(ForumFriendPage page, ForumFriend friend) async {
    final epoch = widget.repository.sessionEpoch.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除好友 ${friend.name}？'),
        // Only this list changes; the other side's is untouched, whatever
        // it holds (仅接受 can leave it without you).
        content: const Text('不影响对方的好友列表'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _mutate(
      epoch,
      friend,
      () => widget.repository.deleteFriends(page, [friend]),
      '已删除好友',
    );
  }

  Future<void> _respond(
    ForumFriendPage page,
    ForumFriend friend,
    ForumFriendResponse response,
  ) async {
    final epoch = widget.repository.sessionEpoch.value;
    var refusal = '';
    if (response == ForumFriendResponse.refuse) {
      final text = await _askRefusal(friend);
      if (text == null) return;
      refusal = text;
    }
    await _mutate(
      epoch,
      friend,
      () => widget.repository.respondToFriendRequests(
        page,
        [friend],
        response,
        refusalMessage: refusal,
      ),
      switch (response) {
        ForumFriendResponse.acceptadd => '已互加好友',
        ForumFriendResponse.accept => '已接受请求',
        ForumFriendResponse.refuse => '已拒绝请求',
      },
    );
  }

  Future<String?> _askRefusal(ForumFriend friend) => showDialog<String>(
        context: context,
        builder: (context) => _RefusalDialog(name: friend.name),
      );

  void _openProfile(ForumFriend friend) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            userUrl: friend.url,
            repository: widget.repository,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
        actions: [
          IconButton(
            tooltip: '加好友验证设置',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  ForumPreferencesScreen(repository: widget.repository),
            )),
            icon: const Icon(Icons.tune_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AppContentWidth(
          maxWidth: AppWidths.list,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                child: FutureBuilder<ForumFriendPage>(
                  future: _futures[true],
                  builder: (context, snapshot) {
                    // Only a settled answer from this session counts.
                    final waiting = _sessionChanged ||
                            snapshot.connectionState != ConnectionState.done
                        ? null
                        : snapshot.data;
                    final count = waiting == null || waiting.items.isEmpty
                        ? ''
                        : waiting.pageCount > 1
                            ? ' ${waiting.items.length}+'
                            : ' ${waiting.items.length}';
                    return SubTabs<bool>(
                      tabs: [(false, '好友'), (true, '待验证$count')],
                      selected: _pending,
                      onSelected: (value) => setState(() => _pending = value),
                    );
                  },
                ),
              ),
              Expanded(
                  child: AppSwitcher(
                direction: _pending ? 1 : -1,
                scope: widget.repository.sessionEpoch.value,
                child: FutureBuilder<ForumFriendPage>(
                  key: ValueKey(_pending),
                  future: _futures[_pending],
                  // A session change hides the old account's rows at once.
                  builder: (context, snapshot) => _sessionChanged
                      ? AsyncErrorView(
                          title: '登录状态已变化',
                          message: '之前加载的好友已隐藏，重试将按当前账号重新加载。',
                          onRetry: _reloadAll,
                        )
                      : AppSwitcher(
                          scope: widget.repository.sessionEpoch.value,
                          id: snapshot.connectionState != ConnectionState.done
                              ? 'loading'
                              : snapshot.hasError
                                  ? 'error'
                                  : 'list',
                          child: Builder(builder: (context) {
                            // A replaced request never shows the previous answer.
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const ThreadListSkeleton(itemCount: 6);
                            }
                            if (snapshot.hasError) {
                              return AsyncErrorView(
                                title: _pending ? '待验证列表加载失败' : '好友列表加载失败',
                                message: forumErrorText(snapshot.error),
                                onRetry: _reloadAll,
                              );
                            }
                            final page = snapshot.data!;
                            final more = _more[_pending]!;
                            // Each row once, acted on with the page it came on.
                            final seen = <String>{};
                            final pages = [
                              for (final shown in [page, ...more.pages])
                                (
                                  shown,
                                  [
                                    for (final friend in shown.items)
                                      if (!MorePages.repeats(seen, friend.uid))
                                        friend,
                                  ]
                                ),
                            ];
                            return RefreshIndicator(
                              color: AppColors.brand,
                              onRefresh: _reloadAll,
                              child: ListView(
                                controller: _scrolls[_pending],
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                    top: AppSpace.md, bottom: AppSpace.xxl),
                                children: [
                                  // Empty as a whole only when the forum has
                                  // no other page; else per page.
                                  if (page.items.isEmpty &&
                                      page.page <= 1 &&
                                      page.pageCount <= 1)
                                    EmptyStateView(
                                      icon: _pending
                                          ? Icons.how_to_reg_outlined
                                          : Icons.people_outline,
                                      title: _pending ? '没有待验证的请求' : '还没有好友',
                                    )
                                  else
                                    for (final (i, (shown, friends))
                                        in pages.indexed) ...[
                                      if (i > 0) PageBoundary(page: shown.page),
                                      if (shown.items.isEmpty)
                                        PageEmptyNote(
                                            _pending ? '本页没有请求' : '本页没有好友')
                                      else if (friends.isEmpty)
                                        const SizedBox.shrink()
                                      else if (_pending)
                                        AppGroup(
                                          description:
                                              i > 0 ? null : '仅接受时，只有对方的列表加上你',
                                          dividerIndent: AppSpace.lg,
                                          children: [
                                            for (final friend in friends)
                                              _RequestRow(
                                                friend: friend,
                                                busy:
                                                    _busy.contains(friend.uid),
                                                onOpen: () =>
                                                    _openProfile(friend),
                                                onRespond: (response) =>
                                                    _respond(shown, friend,
                                                        response),
                                              ),
                                          ],
                                        )
                                      else
                                        AppGroup(
                                          dividerIndent: 72,
                                          children: [
                                            for (final friend in friends)
                                              _FriendRow(
                                                friend: friend,
                                                busy:
                                                    _busy.contains(friend.uid),
                                                onOpen: () =>
                                                    _openProfile(friend),
                                                onDelete: () =>
                                                    _delete(shown, friend),
                                              ),
                                          ],
                                        ),
                                    ],
                                  if (page.pageCount > 1) _footer(page, more),
                                  if (page.pageCount > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: AppSpace.md),
                                      // From the last page shown, appended
                                      // ones included.
                                      child: ForumPager(
                                        current: (more.pages.lastOrNull ?? page)
                                            .page,
                                        total: (more.pages.lastOrNull ?? page)
                                            .pageCount,
                                        onSelected: _openPage,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          })),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;
    Widget icon(BuildContext context) =>
        Icon(Icons.person_outline, color: AppColors.textMuted, size: 22);
    final avatar = url;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.inkSoft,
      child: avatar == null
          ? icon(context)
          : ClipOval(
              child: CachedForumImage(
                url: avatar,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: icon,
              ),
            ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final ForumFriend friend;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final joined = friend.joinedAt;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.xs, AppSpace.md),
        child: Row(
          children: [
            _FriendAvatar(url: friend.avatarUrl),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  if (joined != null && joined.isNotEmpty)
                    Text('加入于 $joined', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            busy
                ? const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: '删除好友 ${friend.name}',
                    onPressed: onDelete,
                    icon: Icon(Icons.person_remove_outlined,
                        color: AppColors.textMuted),
                  ),
          ],
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.friend,
    required this.busy,
    required this.onOpen,
    required this.onRespond,
  });

  final ForumFriend friend;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<ForumFriendResponse> onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = friend.verificationMessage?.trim() ?? '';
    final joined = friend.joinedAt;
    void Function()? respond(ForumFriendResponse r) =>
        busy ? null : () => onRespond(r);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Row(
              children: [
                _FriendAvatar(url: friend.avatarUrl),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(friend.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      if (joined != null && joined.isNotEmpty)
                        Text(joined, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.inkSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Text(
                message,
                semanticsLabel: '验证信息：$message',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: respond(ForumFriendResponse.acceptadd),
                child: const Text('接受并加好友'),
              ),
              OutlinedButton(
                onPressed: respond(ForumFriendResponse.accept),
                child: const Text('仅接受'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error),
                onPressed: respond(ForumFriendResponse.refuse),
                child: const Text('拒绝'),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for an optional refusal note; null when cancelled.
class _RefusalDialog extends StatefulWidget {
  const _RefusalDialog({required this.name});

  final String name;

  @override
  State<_RefusalDialog> createState() => _RefusalDialogState();
}

class _RefusalDialogState extends State<_RefusalDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Keeps 拒绝 reachable above the keyboard at large text.
      scrollable: true,
      title: Text('拒绝 ${widget.name}'),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: '拒绝理由（可选）',
          hintText: '对方会在通知中看到',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('拒绝'),
        ),
      ],
    );
  }
}

/// Asks for the optional note a user who verifies requests reads; null when
/// the sheet is dismissed.
Future<String?> showFriendRequestSheet(
  BuildContext context, {
  required String name,
  String? prompt,
  int? maxLength,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _FriendRequestSheet(name: name, prompt: prompt, maxLength: maxLength),
    );

class _FriendRequestSheet extends StatefulWidget {
  const _FriendRequestSheet({required this.name, this.prompt, this.maxLength});

  final String name;
  final String? prompt;
  final int? maxLength;

  @override
  State<_FriendRequestSheet> createState() => _FriendRequestSheetState();
}

class _FriendRequestSheetState extends State<_FriendRequestSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = widget.prompt?.trim() ?? '';
    // Scrolls so 发送请求 stays reachable above the keyboard at large text.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl,
          AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('向 ${widget.name} 发送好友请求', style: theme.textTheme.titleMedium),
          // The forum's own request prompt, when it set one.
          if (prompt.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(prompt, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpace.lg),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: widget.maxLength,
            decoration: const InputDecoration(labelText: '验证信息（可选）'),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_text.text.trim()),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('发送请求'),
          ),
        ],
      ),
    );
  }
}
